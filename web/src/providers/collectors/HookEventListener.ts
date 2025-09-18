import { createPublicClient, http, decodeEventLog, parseAbiItem } from 'viem';
import { anvil } from 'viem/chains';
import { YieldMaximizerHookABI } from '../../abi/YieldMaximizerHook.abi';

interface HookEventConfig {
    rpcUrl: string;
    hookAddress: string;
    poolManagerAddress?: string;
    universalRouterAddress?: string;
}

interface DecodedHookEvent {
    name: string;
    signature: string;
    blockNumber: bigint;
    transactionHash: string;
    logIndex: number;
    data: any;
    address: string;
    args: any;
    timestamp?: Date;
    gasUsed?: bigint;
    gasPrice?: bigint;
    source: 'hook' | 'pool-manager' | 'universal-router' | 'permit2';
}

interface SwapStats {
    totalSwaps: number;
    successfulSwaps: number;
    failedSwaps: number;
    totalVolume: bigint;
    averageGasUsed: bigint;
    uniqueUsers: Set<string>;
    poolActivity: Record<string, number>;
}

class HookListener {
    private client;
    private readonly hookAddress: string;
    private readonly poolManagerAddress?: string;
    private readonly universalRouterAddress?: string;
    private isListening: boolean = false;
    private unsubscribeHook?: () => void;
    private unsubscribePoolManager?: () => void;
    private unsubscribeUniversalRouter?: () => void;
    private events: DecodedHookEvent[] = [];
    private swapStats: SwapStats = {
        totalSwaps: 0,
        successfulSwaps: 0,
        failedSwaps: 0,
        totalVolume: 0n,
        averageGasUsed: 0n,
        uniqueUsers: new Set(),
        poolActivity: {}
    };

    constructor(config: HookEventConfig) {
        this.client = createPublicClient({
            chain: anvil,
            transport: http(config.rpcUrl)
        });
        this.hookAddress = config.hookAddress;
        this.poolManagerAddress = config.poolManagerAddress;
        this.universalRouterAddress = config.universalRouterAddress;

        console.log(`Comprehensive YieldMaximizer Event Listener initialized`);
        console.log(`Hook Address: ${this.hookAddress}`);
        if (config.poolManagerAddress) console.log(`PoolManager Address: ${config.poolManagerAddress}`);
        if (config.universalRouterAddress) console.log(`UniversalRouter Address: ${config.universalRouterAddress}`);
    }

    async startListening(): Promise<void> {
        if (this.isListening) {
            console.warn('Already listening to events');
            return;
        }

        console.log('Starting comprehensive event listener...');

        try {
            const currentBlock = await this.client.getBlockNumber();
            console.log(`Connected! Current block: ${currentBlock}`);

            // Listen to YieldMaximizer Hook events
            this.unsubscribeHook = this.client.watchContractEvent({
                address: this.hookAddress as `0x${string}`,
                abi: YieldMaximizerHookABI,
                onLogs: (logs) => {
                    console.log(`\n📡 Received ${logs.length} YieldMaximizer Hook events`);
                    this.processEvents(logs, 'hook');
                },
                onError: (error) => {
                    console.error('❌ Hook event subscription error:', error);
                }
            });

            // Listen to PoolManager events if address provided
            if (this.poolManagerAddress) {
                this.unsubscribePoolManager = this.client.watchEvent({
                    address: this.poolManagerAddress as `0x${string}`,
                    onLogs: (logs) => {
                        console.log(`\n🏊 Received ${logs.length} PoolManager events`);
                        this.processPoolManagerEvents(logs);
                    },
                    onError: (error) => {
                        console.error('❌ PoolManager event subscription error:', error);
                    }
                });
            }

            // Listen to UniversalRouter events if address provided
            if (this.universalRouterAddress) {
                this.unsubscribeUniversalRouter = this.client.watchEvent({
                    address: this.universalRouterAddress as `0x${string}`,
                    onLogs: (logs) => {
                        console.log(`\n🔄 Received ${logs.length} UniversalRouter events`);
                        this.processUniversalRouterEvents(logs);
                    },
                    onError: (error) => {
                        console.error('❌ UniversalRouter event subscription error:', error);
                    }
                });
            }

            this.isListening = true;
            console.log('✅ Comprehensive event listener started!\n');

            // Display initial stats
            this.displayStats();

        } catch (error) {
            console.error('❌ Failed to start listener:', error);
            throw error;
        }
    }

    private async processEvents(logs: any[], source: 'hook' | 'pool-manager' | 'universal-router' = 'hook'): Promise<void> {
        for (const log of logs) {
            try {
                const decodedEvent = await this.decodeEvent(log, source);
                this.handleEvent(decodedEvent);
                this.events.push(decodedEvent);
                this.updateStats(decodedEvent);
            } catch (error) {
                console.error('Error processing event:', error, log);
            }
        }
    }

    private async processPoolManagerEvents(logs: any[]): Promise<void> {
        for (const log of logs) {
            try {
                // Try to decode common PoolManager events
                const commonEvents = [
                    'event Initialize(bytes32 indexed id, address indexed currency0, address indexed currency1, uint24 fee, int24 tickSpacing, address hooks, uint160 sqrtPriceX96, int24 tick)',
                    'event ModifyLiquidity(bytes32 indexed id, address indexed sender, int24 tickLower, int24 tickUpper, int256 liquidityDelta, bytes32 salt)',
                    'event Swap(bytes32 indexed id, address indexed sender, int128 amount0, int128 amount1, uint160 sqrtPriceX96, uint128 liquidity, int24 tick, uint24 fee)'
                ];

                let decoded = null;
                for (const eventAbi of commonEvents) {
                    try {
                        decoded = decodeEventLog({
                            abi: [parseAbiItem(eventAbi)],
                            data: log.data,
                            topics: log.topics
                        });
                        break;
                    } catch {
                        continue;
                    }
                }

                if (decoded) {
                    const event = await this.decodeEvent({ ...log, eventName: decoded.eventName, args: decoded.args }, 'pool-manager');
                    this.handlePoolManagerEvent(event);
                    this.events.push(event);
                }
            } catch (error) {
                // Silently continue - not all events will be decodable
            }
        }
    }

    private async processUniversalRouterEvents(logs: any[]): Promise<void> {
        // Process UniversalRouter events - mainly for swap tracking
        for (const log of logs) {
            try {
                const event = await this.decodeEvent(log, 'universal-router');
                this.handleUniversalRouterEvent(event);
                this.events.push(event);
            } catch (error) {
                // Silently continue
            }
        }
    }

    private async decodeEvent(log: any, source: string): Promise<DecodedHookEvent> {
        const [block, receipt] = await Promise.all([
            this.client.getBlock({ blockNumber: log.blockNumber }),
            this.client.getTransactionReceipt({ hash: log.transactionHash })
        ]);

        return {
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
            source: source as any
        };
    }

    private handleEvent(event: DecodedHookEvent): void {
        console.log(`🎯 ${event.name} Event (${event.source.toUpperCase()})`);
        console.log(`   📦 Block: ${event.blockNumber} | 🕒 ${event.timestamp?.toLocaleString()}`);
        console.log(`   📄 Tx: ${event.transactionHash.slice(0, 20)}...`);
        console.log(`   ⛽ Gas: ${event.gasUsed} @ ${event.gasPrice} wei`);

        switch (event.name) {
            case 'StrategyActivated':
                this.handleStrategyActivated(event);
                break;
            case 'StrategyDeactivated':
                this.handleStrategyDeactivated(event);
                break;
            case 'StrategyUpdated':
                this.handleStrategyUpdated(event);
                break;
            case 'FeesCollected':
                this.handleFeesCollected(event);
                break;
            case 'FeesCompounded':
                this.handleFeesCompounded(event);
                break;
            case 'BatchScheduled':
                this.handleBatchScheduled(event);
                break;
            case 'BatchExecuted':
                this.handleBatchExecuted(event);
                break;
            case 'EmergencyCompound':
                this.handleEmergencyCompound(event);
                break;
            case 'UserAddedToPool':
                this.handleUserAddedToPool(event);
                break;
            case 'UserRemovedFromPool':
                this.handleUserRemovedFromPool(event);
                break;
            case 'DebugEvent':
                this.handleDebugEvent(event);
                break;
            default:
                console.log(`   ❓ Unknown event type: ${event.name}`);
                if (event.args && Object.keys(event.args).length > 0) {
                    console.log(`   📊 Args:`, event.args);
                }
        }
        console.log('');
    }

    private handlePoolManagerEvent(event: DecodedHookEvent): void {
        console.log(`🏊 ${event.name} (PoolManager)`);
        console.log(`   📦 Block: ${event.blockNumber} | 🕒 ${event.timestamp?.toLocaleString()}`);
        console.log(`   📄 Tx: ${event.transactionHash.slice(0, 20)}...`);

        switch (event.name) {
            case 'Initialize':
                const { id, currency0, currency1, fee } = event.args;
                console.log(`   🆔 Pool ID: ${id}`);
                console.log(`   💱 Pair: ${currency0} / ${currency1}`);
                console.log(`   💰 Fee: ${fee} bps`);
                break;
            case 'ModifyLiquidity':
                const { sender, liquidityDelta } = event.args;
                console.log(`   👤 User: ${sender}`);
                console.log(`   📈 Liquidity Delta: ${liquidityDelta}`);
                break;
            case 'Swap':
                const { amount0, amount1, sqrtPriceX96 } = event.args;
                console.log(`   💱 Amount0: ${amount0}, Amount1: ${amount1}`);
                console.log(`   💲 Price: ${sqrtPriceX96}`);
                this.swapStats.totalSwaps++;
                this.swapStats.successfulSwaps++;
                break;
        }
        console.log('');
    }

    private handleUniversalRouterEvent(event: DecodedHookEvent): void {
        console.log(`🔄 UniversalRouter Event`);
        console.log(`   📦 Block: ${event.blockNumber} | 🕒 ${event.timestamp?.toLocaleString()}`);
        console.log(`   📄 Tx: ${event.transactionHash.slice(0, 20)}...`);
        console.log('');
    }

    private updateStats(event: DecodedHookEvent): void {
        if (event.args?.user) {
            this.swapStats.uniqueUsers.add(event.args.user.toLowerCase());
        }

        if (event.args?.poolId) {
            const poolId = event.args.poolId;
            this.swapStats.poolActivity[poolId] = (this.swapStats.poolActivity[poolId] || 0) + 1;
        }

        if (event.gasUsed) {
            const currentAvg = this.swapStats.averageGasUsed;
            const totalEvents = this.events.length;
            this.swapStats.averageGasUsed = (currentAvg * BigInt(totalEvents - 1) + event.gasUsed) / BigInt(totalEvents);
        }
    }

    // Event handlers (same as your original implementation)
    private handleStrategyActivated(event: DecodedHookEvent): void {
        const { user, poolId } = event.args;
        console.log(`   👤 User: ${user}`);
        console.log(`   🏊 Pool: ${poolId}`);
        console.log(`   ✅ User activated auto-compounding strategy`);
    }

    private handleStrategyDeactivated(event: DecodedHookEvent): void {
        const { user, poolId } = event.args;
        console.log(`   👤 User: ${user}`);
        console.log(`   🏊 Pool: ${poolId}`);
        console.log(`   ❌ User deactivated auto-compounding strategy`);
    }

    private handleStrategyUpdated(event: DecodedHookEvent): void {
        const { user, gasThreshold, riskLevel } = event.args;
        console.log(`   👤 User: ${user}`);
        console.log(`   ⛽ Gas Threshold: ${gasThreshold} wei`);
        console.log(`   📊 Risk Level: ${riskLevel}/10`);
        console.log(`   🔄 Strategy parameters updated`);
    }

    private handleFeesCollected(event: DecodedHookEvent): void {
        const { user, poolId, amount } = event.args;
        console.log(`   👤 User: ${user}`);
        console.log(`   🏊 Pool: ${poolId}`);
        console.log(`   💰 Amount: ${amount} wei`);
        console.log(`   📈 Fees collected for auto-compounding`);
    }

    private handleFeesCompounded(event: DecodedHookEvent): void {
        const { user, amount } = event.args;
        console.log(`   👤 User: ${user}`);
        console.log(`   💰 Amount: ${amount} wei`);
        console.log(`   🔄 Fees successfully compounded into liquidity`);
    }

    private handleBatchScheduled(event: DecodedHookEvent): void {
        const { user, poolId, amount } = event.args;
        console.log(`   👤 User: ${user}`);
        console.log(`   🏊 Pool: ${poolId}`);
        console.log(`   💰 Amount: ${amount} wei`);
        console.log(`   ⏰ Compound scheduled for batch execution`);
    }

    private handleBatchExecuted(event: DecodedHookEvent): void {
        const { poolId, userCount, totalAmount, gasUsed } = event.args;
        console.log(`   🏊 Pool: ${poolId}`);
        console.log(`   👥 Users: ${userCount}`);
        console.log(`   💰 Total Amount: ${totalAmount} wei`);
        console.log(`   ⛽ Gas Used: ${gasUsed}`);
        console.log(`   🚀 Batch compound executed successfully`);
    }

    private handleEmergencyCompound(event: DecodedHookEvent): void {
        const { user, poolId, amount } = event.args;
        console.log(`   👤 User: ${user}`);
        console.log(`   🏊 Pool: ${poolId}`);
        console.log(`   💰 Amount: ${amount} wei`);
        console.log(`   🚨 Emergency compound executed (bypassed normal conditions)`);
    }

    private handleUserAddedToPool(event: DecodedHookEvent): void {
        const { user, poolId, liquidityAmount } = event.args;
        console.log(`   👤 User: ${user}`);
        console.log(`   🏊 Pool: ${poolId}`);
        console.log(`   💧 Liquidity: ${liquidityAmount} units`);
        console.log(`   ➕ User added to active liquidity providers`);
    }

    private handleUserRemovedFromPool(event: DecodedHookEvent): void {
        const { user, poolId } = event.args;
        console.log(`   👤 User: ${user}`);
        console.log(`   🏊 Pool: ${poolId}`);
        console.log(`   ➖ User removed from active liquidity providers`);
    }

    private handleDebugEvent(event: DecodedHookEvent): void {
        const { s } = event.args;
        console.log(`   🐛 Debug: ${s}`);
    }

    // Enhanced utility methods
    async getEventHistory(fromBlock?: bigint, toBlock?: bigint): Promise<DecodedHookEvent[]> {
        try {
            const logs = await this.client.getLogs({
                address: this.hookAddress as `0x${string}`,
                fromBlock: fromBlock || 'earliest',
                toBlock: toBlock || 'latest'
            });

            const events: DecodedHookEvent[] = [];
            for (const log of logs) {
                try {
                    const decoded = decodeEventLog({
                        abi: YieldMaximizerHookABI,
                        data: log.data,
                        topics: log.topics
                    });

                    const event = await this.decodeEvent({ ...log, eventName: decoded.eventName, args: decoded.args }, 'hook');
                    events.push(event);
                } catch (decodeError) {
                    console.warn('Failed to decode event:', decodeError);
                }
            }

            return events.sort((a, b) => Number(a.blockNumber - b.blockNumber));
        } catch (error) {
            console.error('Failed to get event history:', error);
            return [];
        }
    }

    displayStats(): void {
        console.log('\n📊 YieldMaximizer Statistics');
        console.log('================================');
        console.log(`Total Events: ${this.events.length}`);
        console.log(`Unique Users: ${this.swapStats.uniqueUsers.size}`);
        console.log(`Total Swaps: ${this.swapStats.totalSwaps}`);
        console.log(`Successful Swaps: ${this.swapStats.successfulSwaps}`);
        console.log(`Average Gas Used: ${this.swapStats.averageGasUsed}`);
        console.log(`Active Pools: ${Object.keys(this.swapStats.poolActivity).length}`);

        if (Object.keys(this.swapStats.poolActivity).length > 0) {
            console.log('\nPool Activity:');
            Object.entries(this.swapStats.poolActivity).forEach(([poolId, count]) => {
                console.log(`  ${poolId.slice(0, 10)}...: ${count} events`);
            });
        }
        console.log('================================\n');
    }

    getCollectedEvents(): DecodedHookEvent[] {
        return [...this.events];
    }

    getEventsByType(eventName: string): DecodedHookEvent[] {
        return this.events.filter(event => event.name === eventName);
    }

    getEventsByUser(userAddress: string): DecodedHookEvent[] {
        return this.events.filter(event =>
            event.args?.user?.toLowerCase() === userAddress.toLowerCase()
        );
    }

    getEventsByPool(poolId: string): DecodedHookEvent[] {
        return this.events.filter(event =>
            event.args?.poolId === poolId
        );
    }

    getEventsBySource(source: 'hook' | 'pool-manager' | 'universal-router'): DecodedHookEvent[] {
        return this.events.filter(event => event.source === source);
    }

    async stopListening(): Promise<void> {
        if (this.unsubscribeHook) {
            this.unsubscribeHook();
        }
        if (this.unsubscribePoolManager) {
            this.unsubscribePoolManager();
        }
        if (this.unsubscribeUniversalRouter) {
            this.unsubscribeUniversalRouter();
        }

        this.isListening = false;
        console.log('✅ Stopped listening to all events');

        // Final stats
        this.displayStats();
    }

    isCurrentlyListening(): boolean {
        return this.isListening;
    }

    clearEvents(): void {
        this.events = [];
        this.swapStats = {
            totalSwaps: 0,
            successfulSwaps: 0,
            failedSwaps: 0,
            totalVolume: 0n,
            averageGasUsed: 0n,
            uniqueUsers: new Set(),
            poolActivity: {}
        };
        console.log('🧹 Event history and stats cleared');
    }

    getSwapStats(): SwapStats {
        return {
            ...this.swapStats,
            uniqueUsers: new Set(this.swapStats.uniqueUsers) // Return a copy
        };
    }

    // Advanced filtering
    getEventsByTimeRange(startTime: Date, endTime: Date): DecodedHookEvent[] {
        return this.events.filter(event =>
            event.timestamp &&
            event.timestamp >= startTime &&
            event.timestamp <= endTime
        );
    }

    getHighGasEvents(threshold: bigint = 100000n): DecodedHookEvent[] {
        return this.events.filter(event =>
            event.gasUsed && event.gasUsed > threshold
        );
    }

    exportToJSON(): string {
        return JSON.stringify({
            events: this.events,
            stats: this.getSwapStats(),
            timestamp: new Date().toISOString()
        }, (key, value) => {
            // Handle BigInt serialization
            if (typeof value === 'bigint') {
                return value.toString();
            }
            // Handle Set serialization
            if (value instanceof Set) {
                return Array.from(value);
            }
            return value;
        }, 2);
    }
}

export default HookListener;
