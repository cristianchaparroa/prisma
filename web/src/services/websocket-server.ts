import WebSocket from 'ws';
import EnhancedHookListener from '../components/Metrics';
import type { DashboardMetrics, RealTimeEvent } from '../components/Metrics';

interface WebSocketMessage {
    type: string;
    data?: any;
    address?: string;
    timeframe?: '1h' | '24h' | '7d';
}

class DashboardWebSocketServer {
    private wss: WebSocket.Server;
    private hookListener: EnhancedHookListener;
    private clients: Set<WebSocket> = new Set();

    constructor(port: number, hookConfig: any) {
        this.wss = new WebSocket.Server({ port });
        this.hookListener = new EnhancedHookListener(hookConfig);
        
        this.setupWebSocketHandlers();
        this.setupHookListeners();
    }

    private setupWebSocketHandlers() {
        this.wss.on('connection', (ws) => {
            console.log('🔌 New dashboard client connected');
            this.clients.add(ws);
            
            // Send initial data
            ws.send(JSON.stringify({
                type: 'initial_metrics',
                data: this.hookListener.getMetrics()
            }));
            
            ws.on('close', () => {
                console.log('📱 Dashboard client disconnected');
                this.clients.delete(ws);
            });
            
            ws.on('message', (message) => {
                try {
                    const parsedMessage: WebSocketMessage = JSON.parse(message.toString());
                    this.handleClientMessage(ws, parsedMessage);
                } catch (error) {
                    console.error('❌ Error parsing client message:', error);
                }
            });
            
            ws.on('error', (error) => {
                console.error('❌ WebSocket client error:', error);
                this.clients.delete(ws);
            });
        });
    }

    private setupHookListeners() {
        this.hookListener.onMetricsUpdate((metrics: DashboardMetrics) => {
            this.broadcast({
                type: 'metrics_update',
                data: metrics
            });
        });

        this.hookListener.onNewEvent((event: RealTimeEvent) => {
            this.broadcast({
                type: 'new_event',
                data: event
            });
        });
    }

    private handleClientMessage(ws: WebSocket, message: WebSocketMessage) {
        try {
            switch (message.type) {
                case 'get_user_performance':
                    if (message.address) {
                        const userPerf = this.hookListener.getUserPerformance(message.address);
                        ws.send(JSON.stringify({
                            type: 'user_performance',
                            data: userPerf
                        }));
                    }
                    break;
                    
                case 'get_pool_analytics':
                    const poolAnalytics = this.hookListener.getPoolAnalytics();
                    ws.send(JSON.stringify({
                        type: 'pool_analytics',
                        data: poolAnalytics
                    }));
                    break;
                    
                case 'get_gas_savings':
                    const timeframe = message.timeframe || '24h';
                    const gasSavings = this.hookListener.calculateGasSavings(timeframe);
                    ws.send(JSON.stringify({
                        type: 'gas_savings',
                        data: gasSavings.toString()
                    }));
                    break;
                    
                case 'get_recent_events':
                    const limit = message.data?.limit || 50;
                    const events = this.hookListener.getRecentEvents(limit);
                    ws.send(JSON.stringify({
                        type: 'recent_events',
                        data: events
                    }));
                    break;
                    
                case 'get_system_efficiency':
                    const efficiency = this.hookListener.getSystemEfficiencyScore();
                    ws.send(JSON.stringify({
                        type: 'system_efficiency',
                        data: efficiency
                    }));
                    break;
                    
                case 'ping':
                    ws.send(JSON.stringify({
                        type: 'pong',
                        data: { timestamp: Date.now() }
                    }));
                    break;
                    
                default:
                    console.warn(`⚠️  Unknown message type: ${message.type}`);
            }
        } catch (error) {
            console.error('❌ Error handling client message:', error);
            ws.send(JSON.stringify({
                type: 'error',
                data: { message: 'Internal server error' }
            }));
        }
    }

    private broadcast(message: any) {
        const data = JSON.stringify(message);
        let activeClients = 0;
        
        this.clients.forEach(client => {
            if (client.readyState === WebSocket.OPEN) {
                try {
                    client.send(data);
                    activeClients++;
                } catch (error) {
                    console.error('❌ Error broadcasting to client:', error);
                    this.clients.delete(client);
                }
            } else {
                this.clients.delete(client);
            }
        });
        
        if (activeClients > 0) {
            console.log(`📡 Broadcasted ${message.type} to ${activeClients} clients`);
        }
    }

    async start() {
        try {
            await this.hookListener.startRealtimeMonitoring();
            console.log(`🚀 Dashboard WebSocket server started on port ${this.wss.options.port}`);
            console.log('🎯 Ready to accept dashboard connections');
            
            // Setup periodic health checks
            setInterval(() => {
                this.broadcast({
                    type: 'heartbeat',
                    data: { 
                        timestamp: Date.now(),
                        connectedClients: this.clients.size 
                    }
                });
            }, 30000); // Every 30 seconds
            
        } catch (error) {
            console.error('❌ Failed to start WebSocket server:', error);
            throw error;
        }
    }

    async stop() {
        console.log('🛑 Shutting down WebSocket server...');
        
        // Close all client connections
        this.clients.forEach(client => {
            if (client.readyState === WebSocket.OPEN) {
                client.close();
            }
        });
        
        // Stop hook listener
        await this.hookListener.stop();
        
        // Close WebSocket server
        this.wss.close();
        
        console.log('✅ WebSocket server stopped');
    }
    
    getStatus() {
        return {
            connectedClients: this.clients.size,
            isListening: this.hookListener ? true : false,
            serverState: this.wss.readyState
        };
    }
}

export default DashboardWebSocketServer;
export type { WebSocketMessage };