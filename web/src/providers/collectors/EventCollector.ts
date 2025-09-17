import { createPublicClient, http, decodeEventLog } from 'viem';
import { anvil } from 'viem/chains';
import { YieldMaximizerHookABI } from '../../abi/YieldMaximizerHook.abi';

interface HookEventConfig {
    rpcUrl: string;
    hookAddress: string;
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
}

class YieldMaximizerEventCollector {
    private client;
    private readonly hookAddress: string;
    private isListening: boolean = false;
    private unsubscribe?: () => void;
    private events: DecodedHookEvent[] = [];

    constructor(config: HookEventConfig) {
        this.client = createPublicClient({
            chain: anvil,
            transport: http(config.rpcUrl)
        });
        this.hookAddress = config.hookAddress;

        console.log(`YieldMaximizer Event Collector initialized for: ${this.hookAddress}`);
    }

    async startListening(): Promise<void> {
        if (this.isListening) {
            console.warn('Already listening to events');
            return;
        }

        console.log('Starting YieldMaximizer event listener...');

        try {
            const currentBlock = await this.client.getBlockNumber();
            console.log(`Connected! Current block: ${currentBlock}`);

            this.unsubscribe = this.client.watchContractEvent({
                address: this.hookAddress as `0x${string}`,
                abi: YieldMaximizerHookABI,
                onLogs: (logs) => {
                    console.log(`\n📡 Received ${logs.length} YieldMaximizer events`);
                    this.processEvents(logs);
                },
                onError: (error) => {
                    console.error('❌ Event subscription error:', error);
                    this.isListening = false;
                }
            });

            this.isListening = true;
            console.log('✅ YieldMaximizer event listener started!\n');

        } catch (error) {
            console.error('❌ Failed to start listener:', error);
            throw error;
        }
    }

    private async processEvents(logs: any[]): Promise<void> {
        for (const log of logs) {
            try {
                const decodedEvent = await this.decodeEvent(log);
                this.handleEvent(decodedEvent);
                this.events.push(decodedEvent);
            } catch (error) {
                console.error('Error processing event:', error, log);
            }
        }
    }

    private async decodeEvent(log: any): Promise<DecodedHookEvent> {
        const block = await this.client.getBlock({ blockNumber: log.blockNumber });
        
        return {
            name: log.eventName,
            signature: log.topics?.[0] || 'unknown',
            blockNumber: log.blockNumber,
            transactionHash: log.transactionHash,
            logIndex: log.logIndex,
            data: log.data,
            address: log.address,
            args: log.args,
            timestamp: new Date(Number(block.timestamp) * 1000)
        };
    }

    private handleEvent(event: DecodedHookEvent): void {
        console.log(`🎯 ${event.name} Event`);
        console.log(`   📦 Block: ${event.blockNumber} | 🕒 ${event.timestamp?.toLocaleString()}`);
        console.log(`   📄 Tx: ${event.transactionHash.slice(0, 20)}...`);

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
                console.log(`   📊 Args:`, event.args);
        }
        console.log('');
    }

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
        console.log(`   Debug: ${s}`);
    }

    // Utility methods
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

                    const block = await this.client.getBlock({ blockNumber: log.blockNumber });
                    
                    events.push({
                        name: decoded.eventName,
                        signature: log.topics[0],
                        blockNumber: log.blockNumber,
                        transactionHash: log.transactionHash,
                        logIndex: log.logIndex,
                        data: log.data,
                        address: log.address,
                        args: decoded.args,
                        timestamp: new Date(Number(block.timestamp) * 1000)
                    });
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

    async stopListening(): Promise<void> {
        if (this.unsubscribe) {
            this.unsubscribe();
            this.isListening = false;
            console.log('✅ Stopped listening to YieldMaximizer events');
        }
    }

    isCurrentlyListening(): boolean {
        return this.isListening;
    }

    clearEvents(): void {
        this.events = [];
        console.log('🧹 Event history cleared');
    }

    // Statistics
    getEventStats(): {
        total: number;
        byType: Record<string, number>;
        totalUsers: number;
        totalPools: number;
    } {
        const byType: Record<string, number> = {};
        const users = new Set<string>();
        const pools = new Set<string>();

        this.events.forEach(event => {
            byType[event.name] = (byType[event.name] || 0) + 1;
            
            if (event.args?.user) {
                users.add(event.args.user.toLowerCase());
            }
            if (event.args?.poolId) {
                pools.add(event.args.poolId);
            }
        });

        return {
            total: this.events.length,
            byType,
            totalUsers: users.size,
            totalPools: pools.size
        };
    }
}

export default YieldMaximizerEventCollector;
