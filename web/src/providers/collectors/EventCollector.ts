import { createPublicClient, http, keccak256, toHex } from 'viem';
import { anvil } from 'viem/chains';

interface HookEventConfig {
    rpcUrl: string;
    hookAddress: string;
}

interface HookEvent {
    name: string;
    signature: string;
    blockNumber: bigint;
    transactionHash: string;
    data: any;
    address: string;
}

class HookEventListener {
    private client;
    private readonly hookAddress: string;
    private isListening: boolean = false;
    private unsubscribe?: () => void;

    // Your hook's key events (based on your logs showing "_afterSwap")
    private readonly hookEvents = [
        'event HookSwap(bytes32 indexed poolId, address indexed user, int128 amount0Delta, int128 amount1Delta)',
        'event DebugSwapEntered(address indexed user, bytes32 indexed poolId)',
        'event FeesCollected(address indexed user, bytes32 indexed poolId, uint256 amount)',
        'event FeesCompounded(address indexed user, uint256 amount)'
    ];

    constructor(config: HookEventConfig) {
        this.client = createPublicClient({
            chain: anvil,
            transport: http(config.rpcUrl)
        });
        this.hookAddress = config.hookAddress;

        console.log(`🎯 Hook Event Listener initialized for: ${this.hookAddress}`);
    }

    // Start listening to hook events
    async startListening(): Promise<void> {
        if (this.isListening) {
            console.warn('⚠️ Already listening to events');
            return;
        }

        console.log('🚀 Starting hook event listener...');

        try {
            // Test connection
            const currentBlock = await this.client.getBlockNumber();
            console.log(`📦 Connected! Current block: ${currentBlock}`);

            // Watch for events from your hook address only
            this.unsubscribe = this.client.watchContractEvent({
                address: this.hookAddress as `0x${string}`,
                // Watch all events by not specifying specific events
                onLogs: (logs) => {
                    console.log(`📡 Received ${logs.length} hook events`);
                    this.processHookEvents(logs);
                },
                onError: (error) => {
                    console.error('❌ Event subscription error:', error);
                    this.isListening = false;
                }
            });

            this.isListening = true;
            console.log('✅ Hook event listener started!');

        } catch (error) {
            console.error('❌ Failed to start listener:', error);
            throw error;
        }
    }

    // Process hook events
    private processHookEvents(logs: any[]): void {
        for (const log of logs) {
            try {
                const event = this.decodeEvent(log);
                this.handleHookEvent(event);
            } catch (error) {
                console.error('❌ Error processing event:', error);
            }
        }
    }

    // Decode event data
    private decodeEvent(log: any): HookEvent {
        // Based on your logs, we know the main event is "_afterSwap"
        // Topic: 0x56f074d292557f2e3c567d982816e0fb5b72100ff196892f8fbd23b8a9073679
        const eventName = this.getEventName(log.topics?.[0]);

        return {
            name: eventName,
            signature: log.topics?.[0] || 'unknown',
            blockNumber: log.blockNumber,
            transactionHash: log.transactionHash,
            data: log.data,
            address: log.address
        };
    }

    // Get event name from signature
    private getEventName(signature: string): string {
        // Your known event from the logs
        if (signature === '0x56f074d292557f2e3c567d982816e0fb5b72100ff196892f8fbd23b8a9073679') {
            return 'AfterSwap';
        }

        // Add more as you discover them
        const knownEvents: Record<string, string> = {
            [keccak256(toHex('HookSwap(bytes32,address,int128,int128)'))]: 'HookSwap',
            [keccak256(toHex('FeesCollected(address,bytes32,uint256)'))]: 'FeesCollected',
            [keccak256(toHex('DebugSwapEntered(address,bytes32)'))]: 'DebugSwapEntered'
        };

        return knownEvents[signature] || `Unknown_${signature.slice(0, 10)}`;
    }

    // Handle individual hook events
    private handleHookEvent(event: HookEvent): void {
        console.log(`🎉 Hook Event: ${event.name}`);
        console.log(`   Block: ${event.blockNumber}`);
        console.log(`   Tx: ${event.transactionHash.slice(0, 16)}...`);

        // Decode the data based on your logs showing "_afterSwap"
        if (event.data && event.data !== '0x') {
            try {
                // Your event data shows: "_afterSwap" as a string
                const decoded = this.decodeStringData(event.data);
                console.log(`   Data: ${decoded}`);
            } catch (e) {
                console.log(`   Raw Data: ${event.data}`);
            }
        }

        // Handle specific events
        switch (event.name) {
            case 'AfterSwap':
                this.onAfterSwap(event);
                break;
            case 'HookSwap':
                this.onHookSwap(event);
                break;
            case 'FeesCollected':
                this.onFeesCollected(event);
                break;
            default:
                console.log(`   Unknown event: ${event.name}`);
        }
    }

    // Decode string data (like "_afterSwap" from your logs)
    private decodeStringData(data: string): string {
        try {
            // Remove 0x prefix
            const hex = data.slice(2);
            // Skip first 64 chars (offset) and next 64 chars (length)
            const stringHex = hex.slice(128);
            // Convert hex to string
            return Buffer.from(stringHex, 'hex').toString('utf8').replace(/\0/g, '');
        } catch (e) {
            return 'Failed to decode';
        }
    }

    // Event handlers
    private onAfterSwap(event: HookEvent): void {
        console.log('✅ afterSwap hook executed successfully!');
    }

    private onHookSwap(event: HookEvent): void {
        console.log('💱 Swap processed through hook');
    }

    private onFeesCollected(event: HookEvent): void {
        console.log('💰 Fees collected by hook');
    }

    // Stop listening
    async stopListening(): Promise<void> {
        if (this.unsubscribe) {
            this.unsubscribe();
            this.isListening = false;
            console.log('🛑 Stopped listening to hook events');
        }
    }

    // Get listening status
    isCurrentlyListening(): boolean {
        return this.isListening;
    }
}

export default HookEventListener;

// Usage example:
/*
const listener = new HookEventListener({
  rpcUrl: 'http://127.0.0.1:8545',
  hookAddress: '0x50D1b723B364dD8f41B5b394DE9a8870Bb49D540'
});

// Start listening
await listener.startListening();

// Run your swaps...

// Stop when done
await listener.stopListening();
*/
