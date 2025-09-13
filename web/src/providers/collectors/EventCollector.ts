import { createPublicClient, http, keccak256, toHex } from 'viem';
import { anvil } from 'viem/chains';
import YieldMaximizerABI from '../../generated/YieldMaximizerHook.abi.json';

const events = [
    'HookSwap',              // ⭐ MOST IMPORTANT - Standard V4 hook event
    'StrategyActivated',
    'StrategyDeactivated', 
    'StrategyUpdated',
    'FeesCollected',
    'FeesCompounded',
    'BatchScheduled',
    'BatchExecuted',
    'EmergencyCompound',
    'UserAddedToPool',
    'UserRemovedFromPool',
    'DebugSwapEntered',      // ⭐ CRITICAL DEBUG - Always emitted on swaps
    'DebugSwapCalculation',
    'DebugUserFeeShare', 
    'DebugSwapError',
    'DebugActiveUsers'
];

class EventCollector {
    private client;
    private readonly hookAddress;
    private readonly poolManagerAddress;
    private eventHandlers;
    private isMonitoring: boolean = false;
    private unsubscribe?: () => void;
    private eventSignatures: { [key: string]: string } = {};

    constructor(config) {
        this.client = createPublicClient({
            chain: anvil,
            transport: http(config.rpcUrl)
        });
        this.hookAddress = config.hookAddress;
        this.poolManagerAddress = config.poolManagerAddress || '0x000000000004444c5dc75cB358380D2e3dE08A90';
        this.eventHandlers = new Map();

        // Calculate event signatures from exact contract definitions
        this.calculateEventSignatures();
    }

    // Calculate event signatures + Add Uniswap V4 core events
    private calculateEventSignatures() {
        const eventSignatureMap = {
            // YieldMaximizerHook Events
            'StrategyActivated(address,bytes32)': 'StrategyActivated',
            'StrategyDeactivated(address,bytes32)': 'StrategyDeactivated',
            'StrategyUpdated(address,uint256,uint8)': 'StrategyUpdated',
            'FeesCollected(address,bytes32,uint256)': 'FeesCollected',
            'FeesCompounded(address,uint256)': 'FeesCompounded',
            'BatchScheduled(address,bytes32,uint256)': 'BatchScheduled',
            'BatchExecuted(bytes32,uint256,uint256,uint256)': 'BatchExecuted',
            'EmergencyCompound(address,bytes32,uint256)': 'EmergencyCompound',
            'UserAddedToPool(address,bytes32,uint256)': 'UserAddedToPool',
            'UserRemovedFromPool(address,bytes32)': 'UserRemovedFromPool',
            'HookSwap(bytes32,address,int128,int128,uint128,uint128)': 'HookSwap',
            'DebugSwapEntered(address,bytes32,uint256)': 'DebugSwapEntered',
            'DebugSwapCalculation(bytes32,uint256,uint256,uint256)': 'DebugSwapCalculation',
            'DebugUserFeeShare(address,bytes32,uint256,uint256,bool)': 'DebugUserFeeShare',
            'DebugSwapError(string,bytes32,address)': 'DebugSwapError',
            'DebugActiveUsers(bytes32,uint256)': 'DebugActiveUsers',

            // OFFICIAL Uniswap V4 PoolManager Events (from IPoolManager.sol)  
            'Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)': 'V4_Swap_Official',
            
            // Let's add the mystery signature we found
            'unknown_f208f491': 'Mystery_V4_Event', // Manually add until we identify it
            'ModifyLiquidity(bytes32,address,int128,int128,bytes32)': 'V4_ModifyLiquidity', 
            'Initialize(bytes32,address,uint160,int24)': 'V4_Initialize',
            
            // Standard ERC20/Token Events
            'Transfer(address,address,uint256)': 'Transfer',
            'Approval(address,address,uint256)': 'Approval',
            
            // Add more known signatures as we discover them
        };

        // Calculate keccak256 hashes for all event signatures
        Object.entries(eventSignatureMap).forEach(([signature, name]) => {
            const hash = keccak256(toHex(signature));
            this.eventSignatures[hash] = name;
        });

        console.error('Event signatures calculated:', Object.keys(this.eventSignatures).length);
        console.error('Monitoring addresses:', {
            hook: this.hookAddress,
            poolManager: this.poolManagerAddress
        });
    }

    // Enhanced event decoder with data analysis
    private decodeEventName(log): string {
        if (!log.topics || log.topics.length === 0) {
            return 'Unknown_NoTopics';
        }

        const signature = log.topics[0];
        const eventName = this.eventSignatures[signature];

        if (!eventName) {
            // Enhanced analysis for unknown events
            console.error(`🔍 UNKNOWN EVENT DETECTED:`);
            console.error(`  Signature: ${signature}`);
            console.error(`  Address: ${log.address}`);
            console.error(`  Block: ${log.blockNumber}`);
            console.error(`  Transaction: ${log.transactionHash}`);
            
            // Analyze the data payload
            this.analyzeEventData(log.data, log.topics);
            
            return `Unknown_${signature.slice(0, 10)}`;
        }

        return eventName;
    }

    // Analyze mysterious event data
    private analyzeEventData(data: string, topics: string[]): void {
        console.error(`  Data length: ${data.length}`);
        console.error(`  Topics count: ${topics.length}`);
        console.error(`  Raw data: ${data}`);
        
        if (data.length > 2) {
            try {
                const dataWithoutPrefix = data.slice(2);
                const chunks = [];
                for (let i = 0; i < dataWithoutPrefix.length; i += 64) {
                    chunks.push('0x' + dataWithoutPrefix.slice(i, i + 64));
                }
                console.error(`  Data chunks:`, chunks);
                
                chunks.forEach((chunk, i) => {
                    const asNumber = BigInt(chunk);
                    const asAddress = '0x' + chunk.slice(26);
                    console.error(`    Chunk ${i}: ${chunk} -> BigInt: ${asNumber} | Address: ${asAddress}`);
                });
            } catch (e) {
                console.error(`  Failed to decode data:`, e);
            }
        }
    }

    // Monitor all hook events - COMPLETE IMPLEMENTATION
    async startEventMonitoring(): Promise<void> {
        // Check if already monitoring
        if (this.isMonitoring) {
            console.warn('⚠️ Event monitoring is already active');
            return;
        }

        console.error('🚀 Starting YieldMaximizer Event Monitoring...');
        console.error(`📍 Hook Address: ${this.hookAddress}`);
        console.error(`🎯 Monitoring ${events.length} event types`);

        // Log computed event signatures for debugging
        console.error('📊 Event signatures computed:');
        // Object.entries(this.eventSignatures).forEach(([sig, name]) => {
        //     if (events.includes(name)) {
        //         console.error(`  ${name}: ${sig}`);
        //     }
        // });

        try {
            // Test connection first
            const currentBlock = await this.client.getBlockNumber();
            console.error(`📦 Connected! Current block: ${currentBlock}`);

            // Monitor ALL events from ALL addresses (not just hook and pool manager)
            this.unsubscribe = this.client.watchEvent({
                onLogs: (logs) => {
                    console.error(`📡 Received ${logs.length} total events`);
                    // Process ALL events to see everything
                    this.processEvents(logs);
                },
                onError: (error) => {
                    console.error('❌ Event subscription error:', error);
                    this.isMonitoring = false;
                }
            });

            // Mark as monitoring
            this.isMonitoring = true;
            console.error('✅ Event monitoring started successfully!');

        } catch (error) {
            console.error('❌ Failed to start event monitoring:', error);
            this.isMonitoring = false;
            throw error;
        }
    }

    async processEvents(logs) {
        if (!logs || logs.length === 0) {
            return;
        }

        console.error(`🔄 Processing ${logs.length} event logs...`);

        for (const log of logs) {
            try {
                // Check if this event is from our contracts
                const isFromHook = log.address?.toLowerCase() === this.hookAddress.toLowerCase();
                const isFromPoolManager = log.address?.toLowerCase() === this.poolManagerAddress.toLowerCase();

                // Use manual decoding since ABI isn't working
                const eventName = this.decodeEventName(log);

                // Transform raw log into structured event data
                const event = {
                    type: eventName,
                    data: log.args || log.data || {},
                    blockNumber: log.blockNumber || 0n,
                    transactionHash: log.transactionHash || '0x',
                    timestamp: Date.now(),
                    logIndex: log.logIndex || 0,
                    address: log.address || '0x',
                    isFromHook: isFromHook,
                    isFromPoolManager: isFromPoolManager,
                    rawSignature: log.topics?.[0] || 'no-signature'
                };

                // Log ALL events (don't skip any)
                if (isFromHook) {
                    console.error(`✅ Hook event: ${eventName} from ${event.address}`);
                } else if (isFromPoolManager) {
                    console.error(`🔷 PoolManager event: ${eventName} from ${event.address}`);
                } else {
                    console.error(`🔍 Other contract event: ${eventName} from ${event.address}`);
                }
                
                // Process ALL events, don't skip any

                // Process each event individually
                await this.handleEvent(event);

            } catch (error) {
                console.error('❌ Error processing individual event log:', error, log);
                // Continue processing other events even if one fails
            }
        }

        console.error(`✅ Completed processing ${logs.length} events`);
    }

    async handleEvent(event) {
        try {
            // Log the event for debugging
            // Use JSON.stringify for better readability
            console.error(`📡 [${new Date(event.timestamp).toLocaleTimeString()}] ${event.type}:`);
            console.error('Event Details:', JSON.stringify({
                block: Number(event.blockNumber),
                tx: event.transactionHash?.slice(0, 16) + '...',
                address: event.address,
                signature: event.rawSignature,
                data: event.data
            }, null, 2));

            // Notify registered event handlers for this specific event type
            const handlers = this.eventHandlers.get(event.type);
            if (handlers) {
                for (const handler of handlers) {
                    try {
                        await handler(event);
                    } catch (error) {
                        console.error(`❌ Error in event handler for ${event.type}:`, error);
                    }
                }
            }

            // Notify global handlers (registered for all events with '*')
            const globalHandlers = this.eventHandlers.get('*');
            if (globalHandlers) {
                for (const handler of globalHandlers) {
                    try {
                        await handler(event);
                    } catch (error) {
                        console.error('❌ Error in global event handler:', error);
                    }
                }
            }

        } catch (error) {
            console.error('❌ Error handling event:', error, event);
        }
    }

    // Register event handler for specific event type - COMPLETE IMPLEMENTATION
    onEvent(eventType, handler) {
        // Create handler set if it doesn't exist
        if (!this.eventHandlers.has(eventType)) {
            this.eventHandlers.set(eventType, new Set());
        }

        // Add the handler to the set
        this.eventHandlers.get(eventType).add(handler);

        console.log(`📝 Event handler registered for: ${eventType}`);
    }
}

export default EventCollector;
