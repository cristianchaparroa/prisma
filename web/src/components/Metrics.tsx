import { createPublicClient, http, decodeEventLog, parseAbiItem, webSocket } from 'viem';
import { anvil } from 'viem/chains';
import { YieldMaximizerHookABI } from '../abi/YieldMaximizerHook.abi';
import { getTokenInPool, formatPoolTokenAmount, discoverPoolFromEvent, discoverPoolFromTokens, getPoolConfig } from '../config/pools';
import { getTokenInfo } from '../config/tokens';

interface HookEventConfig {
    rpcUrl: string;
    hookAddress: string;
    poolManagerAddress: string;
    universalRouterAddress: string;
}

interface TokenFees {
    address: string;
    symbol: string;
    amount: bigint;
    decimals: number;
}

interface DashboardMetrics {
    totalTVL: bigint;
    totalUsers: number;
    totalFeesCollected: bigint;
    totalCompounded: bigint;
    gasEfficiency: bigint;
    avgAPY: number;
    activeStrategies: number;
    poolDistribution: Record<string, number>;
    userPerformance: Record<string, UserPerformance>;
    systemHealth: SystemHealth;
    feesByToken: Record<string, TokenFees>; // Track fees by token address
    compoundedByToken: Record<string, TokenFees>; // Track compounded fees by token address
}

interface UserPerformance {
    totalDeposited: bigint;
    totalFeesEarned: bigint;
    totalCompounded: bigint;
    netYield: number;
    lastActivity: Date;
    gasSaved: bigint;
}

interface SystemHealth {
    averageGasPrice: bigint;
    pendingCompounds: number;
    batchEfficiency: number;
    networkCongestion: 'low' | 'medium' | 'high';
    systemUptime: number;
}

interface PoolAnalytics {
    poolId: string;
    swapVolume24h: bigint;
    feesGenerated24h: bigint;
    activeUsers: number;
    averageAPY: number;
    compoundFrequency: number;
    efficiency: number;
}

interface RealTimeEvent extends DecodedHookEvent {
    impact: 'low' | 'medium' | 'high';
    category: 'user' | 'system' | 'optimization' | 'performance';
    metrics?: any;
}

class EnhancedHookListener {
    private client;
    private wsClient;
    private readonly hookAddress: string;
    private isListening: boolean = false;
    private metrics: DashboardMetrics;
    private poolAnalytics: Map<string, PoolAnalytics> = new Map();
    private eventHistory: RealTimeEvent[] = [];
    private metricsCallbacks: ((metrics: DashboardMetrics) => void)[] = [];
    private eventCallbacks: ((event: RealTimeEvent) => void)[] = [];
    private performanceInterval?: NodeJS.Timeout;
    private activeUsers: Set<string> = new Set(); // Track users who have received fees
    private poolTracker: Map<string, {token0?: string, token1?: string, discovered: boolean}> = new Map(); // Track partial pool discoveries

    constructor(config: HookEventConfig) {
        // Use WebSocket for real-time updates
        this.wsClient = createPublicClient({
            chain: anvil,
            transport: webSocket(config.rpcUrl.replace('http', 'ws'))
        });

        this.client = createPublicClient({
            chain: anvil,
            transport: http(config.rpcUrl)
        });

        this.hookAddress = config.hookAddress;
        this.initializeMetrics();
    }

    private initializeMetrics() {
        this.metrics = {
            totalTVL: 0n,
            totalUsers: 0,
            totalFeesCollected: 0n,
            totalCompounded: 0n,
            gasEfficiency: 0n,
            avgAPY: 0,
            activeStrategies: 0,
            poolDistribution: {},
            userPerformance: {},
            systemHealth: {
                averageGasPrice: 0n,
                pendingCompounds: 0,
                batchEfficiency: 0,
                networkCongestion: 'low',
                systemUptime: 100
            },
            feesByToken: {}, // Initialize empty token fees tracking
            compoundedByToken: {} // Initialize empty compounded fees tracking
        };
    }

    // Dashboard subscription methods
    onMetricsUpdate(callback: (metrics: DashboardMetrics) => void) {
        this.metricsCallbacks.push(callback);
    }

    onNewEvent(callback: (event: RealTimeEvent) => void) {
        this.eventCallbacks.push(callback);
    }

    async startRealtimeMonitoring(): Promise<void> {
        if (this.isListening) return;

        console.log('🚀 YieldMaximizer monitoring started');

        // Initialize with historical data
        await this.loadHistoricalData();

        // Start real-time event monitoring
        await this.startEventListening();

        // Start periodic metrics updates
        this.startPerformanceTracking();

        this.isListening = true;
        console.log('✅ Monitoring active!');
    }

    private async loadHistoricalData(): Promise<void> {
        try {
            const currentBlock = await this.client.getBlockNumber();
            const blockRange = 100n; // Increased to catch more historical events
            const fromBlock = currentBlock - blockRange;

            const logs = await this.client.getLogs({
                address: this.hookAddress as `0x${string}`,
                fromBlock: fromBlock,
                toBlock: currentBlock
            });

            if (logs.length > 0) {
                console.log(`📊 Found ${logs.length} historical events`);
            }

            for (const log of logs) {
                try {
                    const decoded = decodeEventLog({
                        abi: YieldMaximizerHookABI,
                        data: log.data,
                        topics: log.topics
                    });

                    const event = await this.createRealTimeEvent(
                        { ...log, eventName: decoded.eventName, args: decoded.args }
                    );

                    this.updateMetricsFromEvent(event);
                    this.eventHistory.push(event);
                } catch (error) {
                    // Skip undecodable events
                }
            }

            // Update final user count after processing all historical events
            this.metrics.totalUsers = this.activeUsers.size;
            
            if (this.eventHistory.length > 0) {
                const eventCounts = this.eventHistory.reduce((acc, event) => {
                    acc[event.name] = (acc[event.name] || 0) + 1;
                    return acc;
                }, {} as Record<string, number>);
                
                console.log(`✅ Loaded ${this.eventHistory.length} events:`, eventCounts);
                console.log(`👥 ${this.metrics.totalUsers} active users, 💰 ${this.metrics.totalFeesCollected.toString()} total fees, 🔄 ${this.metrics.totalCompounded.toString()} compounded`);
            }
            
        } catch (error) {
            console.warn('⚠️  Could not load historical data (this is OK for new deployments):', error);
            // Continue without historical data - real-time events will still work
        }
    }

    private async startEventListening(): Promise<void> {
        // Real-time event monitoring using WebSocket
        this.wsClient.watchContractEvent({
            address: this.hookAddress as `0x${string}`,
            abi: YieldMaximizerHookABI,
            onLogs: async (logs) => {
                for (const log of logs) {
                    try {
                        const event = await this.createRealTimeEvent(log);
                        this.handleRealTimeEvent(event);
                    } catch (error) {
                        console.error('Error processing real-time event:', error);
                    }
                }
            },
            onError: (error) => {
                console.error('❌ Real-time event error:', error);
                this.metrics.systemHealth.systemUptime -= 1;
                this.broadcastMetrics();
            }
        });
    }

    private async createRealTimeEvent(log: any): Promise<RealTimeEvent> {
        const [block, receipt] = await Promise.all([
            this.client.getBlock({ blockNumber: log.blockNumber }),
            this.client.getTransactionReceipt({ hash: log.transactionHash })
        ]);

        const baseEvent = {
            name: log.eventName || 'Unknown',
            signature: log.topics?.[0] || 'unknown',
            blockNumber: log.blockNumber,
            transactionHash: log.transactionHash,
            logIndex: log.logIndex,
            data: log.data,
            address: log.address,
            args: log.args || {},
            timestamp: new Date(Number(block.timestamp) * 1000),
            gasUsed: receipt.gasUsed,
            gasPrice: receipt.effectiveGasPrice,
            source: 'hook' as const
        };

        return {
            ...baseEvent,
            impact: this.calculateEventImpact(baseEvent),
            category: this.categorizeEvent(baseEvent),
            metrics: this.extractEventMetrics(baseEvent)
        };
    }

    private calculateEventImpact(event: any): 'low' | 'medium' | 'high' {
        switch (event.name) {
            case 'BatchExecuted':
                return event.args?.userCount > 10 ? 'high' : 'medium';
            case 'EmergencyCompound':
                return 'high';
            case 'StrategyActivated':
            case 'StrategyDeactivated':
                return 'medium';
            case 'FeesCompounded':
                return event.args?.amount > 1000 ? 'medium' : 'low';
            default:
                return 'low';
        }
    }

    private categorizeEvent(event: any): 'user' | 'system' | 'optimization' | 'performance' {
        switch (event.name) {
            case 'StrategyActivated':
            case 'StrategyDeactivated':
            case 'StrategyUpdated':
                return 'user';
            case 'BatchExecuted':
            case 'GasOptimizationMetrics':
                return 'optimization';
            case 'PerformanceSnapshot':
            case 'UserPerformanceUpdate':
                return 'performance';
            default:
                return 'system';
        }
    }

    private extractEventMetrics(event: any): any {
        const metrics: any = {};

        switch (event.name) {
            case 'FeesCollected':
                metrics.feeAmount = event.args?.amount || 0;
                metrics.user = event.args?.user;
                metrics.poolId = event.args?.poolId;
                break;
            case 'BatchExecuted':
                metrics.userCount = event.args?.userCount || 0;
                metrics.totalAmount = event.args?.totalAmount || 0;
                metrics.gasUsed = event.args?.gasUsed || 0;
                metrics.gasEfficiency = this.calculateGasEfficiency(
                    event.args?.userCount,
                    event.args?.gasUsed
                );
                break;
            case 'PerformanceSnapshot':
                metrics.tvl = event.args?.totalTVL || 0;
                metrics.users = event.args?.totalUsers || 0;
                metrics.feesCollected = event.args?.totalFeesCollected || 0;
                break;
        }

        return metrics;
    }

    private calculateGasEfficiency(userCount?: number, gasUsed?: number): number {
        if (!userCount || !gasUsed) return 0;
        const individualGas = 150000; // Estimated individual compound gas
        const expectedIndividualTotal = userCount * individualGas;
        return ((expectedIndividualTotal - gasUsed) / expectedIndividualTotal) * 100;
    }

    private handleRealTimeEvent(event: RealTimeEvent): void {
        // Only log important events
        if (['FeesCollected', 'FeesCompounded', 'BatchExecuted'].includes(event.name)) {
            console.log(`🎯 ${event.name}`, event.args);
        }
        
        // Special logging for compounding events
        if (event.name === 'FeesCompounded') {
            console.log(`🔄 COMPOUNDING EVENT RECEIVED:`, {
                user: event.args?.user,
                amount: event.args?.amount,
                blockNumber: event.blockNumber,
                transactionHash: event.transactionHash
            });
        }

        // Update metrics
        this.updateMetricsFromEvent(event);

        // Store event
        this.eventHistory.unshift(event);
        this.eventHistory = this.eventHistory.slice(0, 1000); // Keep last 1000 events

        // Update pool analytics
        this.updatePoolAnalytics(event);

        // Broadcast to subscribers
        this.broadcastEvent(event);
        this.broadcastMetrics();
    }

    private updateMetricsFromEvent(event: RealTimeEvent): void {
        const previousTVL = this.metrics.totalTVL;
        
        switch (event.name) {
            case 'FeesCollected':
                const feeAmount = BigInt(event.args?.amount || 0);
                const previousTotal = this.metrics.totalFeesCollected;
                this.metrics.totalFeesCollected += feeAmount;
                
                // Extract token information from enhanced event
                const user = event.args?.user;
                const token = event.args?.token;
                const isToken0 = event.args?.isToken0;
                const poolId = event.args?.poolId;

                // Dynamic pool discovery
                this.discoverPoolFromFeesEvent(poolId, token, isToken0);
                
                // Track fees by token
                if (token && token !== '0x0000000000000000000000000000000000000000') {
                    const tokenInfo = getTokenInfo(token);
                    if (tokenInfo) {
                        if (!this.metrics.feesByToken[token]) {
                            this.metrics.feesByToken[token] = {
                                address: token,
                                symbol: tokenInfo.symbol,
                                amount: 0n,
                                decimals: tokenInfo.decimals
                            };
                        }
                        this.metrics.feesByToken[token].amount += feeAmount;
                    }
                }
                
                // Track active users based on fee collection
                if (user && !this.activeUsers.has(user)) {
                    this.activeUsers.add(user);
                    this.metrics.totalUsers = this.activeUsers.size;
                    console.log(`👤 New user active (${this.metrics.totalUsers} total)`);
                }
                
                // Format amount for context
                const poolTokenInfo = poolId ? getTokenInPool(poolId, isToken0) : null;
                const formattedAmount = poolId && poolTokenInfo ? 
                    formatPoolTokenAmount(feeAmount, poolId, isToken0) : 
                    `${feeAmount.toString()} tokens`;
                
                this.updateUserPerformance(user, {
                    totalFeesEarned: feeAmount
                });
                
                // Store enhanced token context for dashboard use
                event.tokenContext = {
                    address: token,
                    isToken0: isToken0,
                    poolId: poolId,
                    formattedAmount: formattedAmount
                };
                break;

            case 'FeesCompounded':
                const compoundedAmount = BigInt(event.args?.amount || 0);
                const previousCompounded = this.metrics.totalCompounded;
                this.metrics.totalCompounded += compoundedAmount;
                // Compounding adds liquidity back to the pool, so it increases TVL
                this.metrics.totalTVL += compoundedAmount;
                
                // Track compounded fees by token (similar to fee collection)
                const compoundToken = event.args?.token;
                const compoundIsToken0 = event.args?.isToken0;
                let tokenSymbol = 'tokens';
                
                if (compoundToken && compoundToken !== '0x0000000000000000000000000000000000000000') {
                    const tokenInfo = getTokenInfo(compoundToken);
                    if (tokenInfo) {
                        tokenSymbol = tokenInfo.symbol;
                        if (!this.metrics.compoundedByToken[compoundToken]) {
                            this.metrics.compoundedByToken[compoundToken] = {
                                address: compoundToken,
                                symbol: tokenInfo.symbol,
                                amount: 0n,
                                decimals: tokenInfo.decimals
                            };
                        }
                        this.metrics.compoundedByToken[compoundToken].amount += compoundedAmount;
                    }
                }
                
                console.log(`🔄 FeesCompounded: ${compoundedAmount.toString()} ${tokenSymbol} (Total: ${previousCompounded.toString()} → ${this.metrics.totalCompounded.toString()})`);
                
                this.updateUserPerformance(event.args?.user, {
                    totalCompounded: compoundedAmount
                });
                break;

            case 'LiquidityAdded':
                const addedAmount = BigInt(event.args?.amount || 0);
                this.metrics.totalTVL += addedAmount;
                break;

            case 'LiquidityRemoved':
                const removedAmount = BigInt(event.args?.amount || 0);
                this.metrics.totalTVL = this.metrics.totalTVL > removedAmount 
                    ? this.metrics.totalTVL - removedAmount 
                    : 0n;
                break;

            case 'StrategyActivated':
                // Note: totalUsers is now tracked via FeesCollected events
                // Only track strategy activations separately
                this.metrics.activeStrategies++;
                
                // If user already collected fees, they're already counted
                // If not, they'll be counted when they first receive fees
                const strategyUser = event.args?.user;
                if (strategyUser && !this.activeUsers.has(strategyUser)) {
                    console.log('👤 User activated strategy before collecting fees:', strategyUser);
                }
                break;

            case 'StrategyDeactivated':
                this.metrics.activeStrategies = Math.max(0, this.metrics.activeStrategies - 1);
                break;

            case 'BatchExecuted':
                const gasUsed = BigInt(event.args?.gasUsed || 0);
                const userCount = event.args?.userCount || 1;
                const individualGas = BigInt(150000 * userCount);
                const gasSaved = individualGas - gasUsed;
                this.metrics.gasEfficiency += gasSaved;

                this.metrics.systemHealth.batchEfficiency =
                    Number(gasSaved * 100n / individualGas);
                break;

            case 'PerformanceSnapshot':
                // PerformanceSnapshot can override with authoritative data
                this.metrics.totalTVL = BigInt(event.args?.totalTVL || 0);
                break;
        }

        // Log TVL changes
        if (this.metrics.totalTVL !== previousTVL) {
            console.log(`📊 TVL Update: ${event.name} - ${previousTVL.toString()} → ${this.metrics.totalTVL.toString()} (+${(this.metrics.totalTVL - previousTVL).toString()})`);
        }

        // Update system health
        this.updateSystemHealth(event);

        // Calculate APY
        this.calculateAPY();
    }

    private updateUserPerformance(userAddress: string, updates: Partial<UserPerformance>): void {
        if (!userAddress) return;

        const current = this.metrics.userPerformance[userAddress] || {
            totalDeposited: 0n,
            totalFeesEarned: 0n,
            totalCompounded: 0n,
            netYield: 0,
            lastActivity: new Date(),
            gasSaved: 0n
        };

        this.metrics.userPerformance[userAddress] = {
            ...current,
            ...updates,
            lastActivity: new Date()
        };

        // Calculate net yield
        const user = this.metrics.userPerformance[userAddress];
        if (user.totalFeesEarned > 0n) {
            user.netYield = Number(user.totalCompounded * 10000n / user.totalFeesEarned) / 100;
        }
    }

    private updateSystemHealth(event: RealTimeEvent): void {
        // Update average gas price
        if (event.gasPrice) {
            this.metrics.systemHealth.averageGasPrice = event.gasPrice;
        }

        // Determine network congestion
        const gasPrice = Number(event.gasPrice || 0n);
        if (gasPrice > 100e9) { // 100 gwei
            this.metrics.systemHealth.networkCongestion = 'high';
        } else if (gasPrice > 50e9) { // 50 gwei
            this.metrics.systemHealth.networkCongestion = 'medium';
        } else {
            this.metrics.systemHealth.networkCongestion = 'low';
        }
    }

    private updatePoolAnalytics(event: RealTimeEvent): void {
        const poolId = event.args?.poolId;
        if (!poolId) return;

        const existing = this.poolAnalytics.get(poolId) || {
            poolId,
            swapVolume24h: 0n,
            feesGenerated24h: 0n,
            activeUsers: 0,
            averageAPY: 0,
            compoundFrequency: 0,
            efficiency: 0
        };

        switch (event.name) {
            case 'FeesCollected':
                existing.feesGenerated24h += BigInt(event.args?.amount || 0);
                break;
            case 'FeesCompounded':
                existing.compoundFrequency++;
                break;
            case 'StrategyActivated':
                existing.activeUsers++;
                break;
        }

        this.poolAnalytics.set(poolId, existing);
    }

    private calculateAPY(): void {
        if (this.metrics.totalFeesCollected > 0n) {
            const annualizedCompounded = this.metrics.totalCompounded * 365n;
            this.metrics.avgAPY = Number(annualizedCompounded * 100n / this.metrics.totalFeesCollected);
        }
    }

    private startPerformanceTracking(): void {
        this.performanceInterval = setInterval(() => {
            this.emitPerformanceSnapshot();
            this.cleanupOldData();
        }, 30000); // Every 30 seconds
    }

    private emitPerformanceSnapshot(): void {
        // This would trigger the contract to emit PerformanceSnapshot events
        // In a real implementation, you'd call the contract method
        console.log('📸 Performance snapshot triggered');
    }

    private cleanupOldData(): void {
        const oneDayAgo = Date.now() - 24 * 60 * 60 * 1000;
        this.eventHistory = this.eventHistory.filter(
            event => event.timestamp && event.timestamp.getTime() > oneDayAgo
        );
    }

    private broadcastEvent(event: RealTimeEvent): void {
        this.eventCallbacks.forEach(callback => {
            try {
                callback(event);
            } catch (error) {
                console.error('Error in event callback:', error);
            }
        });
    }

    private broadcastMetrics(): void {
        // Broadcast metrics silently
        this.metricsCallbacks.forEach(callback => {
            try {
                callback(this.metrics);
            } catch (error) {
                console.error('Error in metrics callback:', error);
            }
        });
    }

    // Dynamic pool discovery from fees events
    private discoverPoolFromFeesEvent(poolId: string, tokenAddress: string, isToken0: boolean): void {
        if (!poolId || !tokenAddress) return;

        // Track this token for the pool
        const currentTracker = this.poolTracker.get(poolId) || { discovered: false };
        
        if (isToken0) {
            currentTracker.token0 = tokenAddress;
        } else {
            currentTracker.token1 = tokenAddress;
        }

        // If we have both tokens and haven't discovered this pool yet, create the pool config
        if (currentTracker.token0 && currentTracker.token1 && !currentTracker.discovered) {
            const discoveredPool = discoverPoolFromTokens(poolId, currentTracker.token0, currentTracker.token1);
            if (discoveredPool) {
                currentTracker.discovered = true;
                console.log(`✅ Pool discovered: ${discoveredPool.description}`);
            }
        } else if (!getPoolConfig(poolId)) {
            // Try discovery with current known token
            discoverPoolFromEvent(poolId, tokenAddress, isToken0);
        }

        this.poolTracker.set(poolId, currentTracker);
    }

    // Public API methods for dashboard
    getMetrics(): DashboardMetrics {
        return { ...this.metrics };
    }

    getPoolAnalytics(): PoolAnalytics[] {
        return Array.from(this.poolAnalytics.values());
    }

    getRecentEvents(limit: number = 50): RealTimeEvent[] {
        return this.eventHistory.slice(0, limit);
    }

    getEventsByCategory(category: string): RealTimeEvent[] {
        return this.eventHistory.filter(event => event.category === category);
    }

    getUserPerformance(userAddress: string): UserPerformance | null {
        return this.metrics.userPerformance[userAddress] || null;
    }

    getTopPerformers(limit: number = 10): Array<{address: string, performance: UserPerformance}> {
        return Object.entries(this.metrics.userPerformance)
            .sort(([,a], [,b]) => b.netYield - a.netYield)
            .slice(0, limit)
            .map(([address, performance]) => ({ address, performance }));
    }

    // Advanced analytics
    calculateGasSavings(timeframe: '1h' | '24h' | '7d' = '24h'): bigint {
        const now = Date.now();
        const timeframes = {
            '1h': 60 * 60 * 1000,
            '24h': 24 * 60 * 60 * 1000,
            '7d': 7 * 24 * 60 * 60 * 1000
        };

        const cutoff = now - timeframes[timeframe];
        const relevantEvents = this.eventHistory.filter(
            event => event.timestamp && event.timestamp.getTime() > cutoff &&
                event.name === 'BatchExecuted'
        );

        return relevantEvents.reduce((total, event) => {
            const userCount = BigInt(event.args?.userCount || 0);
            const gasUsed = BigInt(event.args?.gasUsed || 0);
            const individualGas = userCount * 150000n;
            return total + (individualGas - gasUsed);
        }, 0n);
    }

    getSystemEfficiencyScore(): number {
        const batchEvents = this.eventHistory.filter(e => e.name === 'BatchExecuted');
        if (batchEvents.length === 0) return 0;

        const totalEfficiency = batchEvents.reduce((sum, event) => {
            return sum + (event.metrics?.gasEfficiency || 0);
        }, 0);

        return totalEfficiency / batchEvents.length;
    }

    async stop(): Promise<void> {
        this.isListening = false;

        if (this.performanceInterval) {
            clearInterval(this.performanceInterval);
        }

        console.log('✅ Enhanced monitoring stopped');
        console.log(`📊 Final metrics: ${this.eventHistory.length} events processed`);
    }
}

export default EnhancedHookListener;
export type { DashboardMetrics, UserPerformance, SystemHealth, RealTimeEvent, PoolAnalytics };
