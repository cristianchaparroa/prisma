import { useState, useEffect, useCallback, useRef } from 'react';
import type { DashboardMetrics, RealTimeEvent, UserPerformance, PoolAnalytics } from '../components/Metrics';

interface WebSocketMessage {
    type: string;
    data?: any;
}

interface UseYieldMaximizerDataReturn {
    metrics: DashboardMetrics | null;
    events: RealTimeEvent[];
    isConnected: boolean;
    connectionStatus: 'connecting' | 'connected' | 'disconnected' | 'error';
    requestUserPerformance: (address: string) => void;
    requestPoolAnalytics: () => void;
    requestGasSavings: (timeframe: '1h' | '24h' | '7d') => void;
    requestRecentEvents: (limit?: number) => void;
    requestSystemEfficiency: () => void;
    userPerformance: UserPerformance | null;
    poolAnalytics: PoolAnalytics[];
    gasSavings: string;
    systemEfficiency: number;
}

export const useYieldMaximizerData = (
    wsUrl: string = 'ws://localhost:8080'
): UseYieldMaximizerDataReturn => {
    const [ws, setWs] = useState<WebSocket | null>(null);
    const [metrics, setMetrics] = useState<DashboardMetrics | null>(null);
    const [events, setEvents] = useState<RealTimeEvent[]>([]);
    const [connectionStatus, setConnectionStatus] = useState<'connecting' | 'connected' | 'disconnected' | 'error'>('disconnected');
    const [userPerformance, setUserPerformance] = useState<UserPerformance | null>(null);
    const [poolAnalytics, setPoolAnalytics] = useState<PoolAnalytics[]>([]);
    const [gasSavings, setGasSavings] = useState<string>('0');
    const [systemEfficiency, setSystemEfficiency] = useState<number>(0);
    
    const reconnectTimeoutRef = useRef<NodeJS.Timeout>();
    const reconnectAttemptsRef = useRef<number>(0);
    const maxReconnectAttempts = 5;
    const reconnectDelay = 3000;

    const connectWebSocket = useCallback(() => {
        if (ws && (ws.readyState === WebSocket.CONNECTING || ws.readyState === WebSocket.OPEN)) {
            return;
        }

        console.log('🔌 Connecting to YieldMaximizer data stream...');
        setConnectionStatus('connecting');
        
        const websocket = new WebSocket(wsUrl);
        
        websocket.onopen = () => {
            console.log('✅ Connected to YieldMaximizer data stream');
            setConnectionStatus('connected');
            setWs(websocket);
            reconnectAttemptsRef.current = 0;
            
            // Clear any existing reconnect timeout
            if (reconnectTimeoutRef.current) {
                clearTimeout(reconnectTimeoutRef.current);
            }
        };
        
        websocket.onmessage = (event) => {
            try {
                const message: WebSocketMessage = JSON.parse(event.data);
                handleMessage(message);
            } catch (error) {
                console.error('❌ Error parsing WebSocket message:', error);
            }
        };
        
        websocket.onclose = (event) => {
            console.log('📱 Disconnected from data stream', event.code, event.reason);
            setConnectionStatus('disconnected');
            setWs(null);
            
            // Attempt to reconnect if not intentionally closed
            if (event.code !== 1000 && reconnectAttemptsRef.current < maxReconnectAttempts) {
                reconnectAttemptsRef.current++;
                console.log(`🔄 Attempting to reconnect (${reconnectAttemptsRef.current}/${maxReconnectAttempts})...`);
                
                reconnectTimeoutRef.current = setTimeout(() => {
                    connectWebSocket();
                }, reconnectDelay);
            }
        };
        
        websocket.onerror = (error) => {
            console.error('❌ WebSocket error:', error);
            setConnectionStatus('error');
        };
        
        return websocket;
    }, [wsUrl, ws]);

    useEffect(() => {
        const websocket = connectWebSocket();
        
        return () => {
            if (reconnectTimeoutRef.current) {
                clearTimeout(reconnectTimeoutRef.current);
            }
            if (websocket) {
                websocket.close(1000, 'Component unmounting');
            }
        };
    }, [connectWebSocket]);

    const handleMessage = useCallback((message: WebSocketMessage) => {
        switch (message.type) {
            case 'initial_metrics':
            case 'metrics_update':
                setMetrics(message.data);
                console.log('📊 Received metrics update:', message.data);
                break;
                
            case 'new_event':
                setEvents(prev => {
                    const newEvents = [message.data, ...prev].slice(0, 100);
                    console.log('🎯 New event:', message.data.name, message.data.impact);
                    return newEvents;
                });
                break;
                
            case 'user_performance':
                setUserPerformance(message.data);
                console.log('👤 User performance:', message.data);
                break;
                
            case 'pool_analytics':
                setPoolAnalytics(message.data || []);
                console.log('🏊 Pool analytics:', message.data);
                break;
                
            case 'gas_savings':
                setGasSavings(message.data || '0');
                console.log('⛽ Gas savings:', message.data);
                break;
                
            case 'recent_events':
                setEvents(message.data || []);
                console.log('📋 Recent events:', message.data?.length);
                break;
                
            case 'system_efficiency':
                setSystemEfficiency(message.data || 0);
                console.log('📈 System efficiency:', message.data);
                break;
                
            case 'heartbeat':
                console.log('💗 Heartbeat received');
                break;
                
            case 'pong':
                console.log('🏓 Pong received');
                break;
                
            case 'error':
                console.error('❌ Server error:', message.data);
                break;
                
            default:
                console.warn('⚠️  Unknown message type:', message.type);
        }
    }, []);

    const sendMessage = useCallback((message: any) => {
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify(message));
            return true;
        } else {
            console.warn('⚠️  WebSocket not connected, cannot send message:', message);
            return false;
        }
    }, [ws]);

    const requestUserPerformance = useCallback((address: string) => {
        sendMessage({
            type: 'get_user_performance',
            address
        });
    }, [sendMessage]);

    const requestPoolAnalytics = useCallback(() => {
        sendMessage({
            type: 'get_pool_analytics'
        });
    }, [sendMessage]);

    const requestGasSavings = useCallback((timeframe: '1h' | '24h' | '7d') => {
        sendMessage({
            type: 'get_gas_savings',
            timeframe
        });
    }, [sendMessage]);

    const requestRecentEvents = useCallback((limit: number = 50) => {
        sendMessage({
            type: 'get_recent_events',
            data: { limit }
        });
    }, [sendMessage]);

    const requestSystemEfficiency = useCallback(() => {
        sendMessage({
            type: 'get_system_efficiency'
        });
    }, [sendMessage]);

    // Ping server periodically to keep connection alive
    useEffect(() => {
        if (connectionStatus === 'connected') {
            const pingInterval = setInterval(() => {
                sendMessage({ type: 'ping' });
            }, 30000); // Ping every 30 seconds

            return () => clearInterval(pingInterval);
        }
    }, [connectionStatus, sendMessage]);

    // Request initial data when connected
    useEffect(() => {
        if (connectionStatus === 'connected') {
            console.log('🚀 Connection established, requesting initial data...');
            
            // Wait a bit for the server to send initial metrics
            setTimeout(() => {
                requestRecentEvents(50);
                requestPoolAnalytics();
                requestSystemEfficiency();
                requestGasSavings('24h');
            }, 1000);
        }
    }, [connectionStatus, requestRecentEvents, requestPoolAnalytics, requestSystemEfficiency, requestGasSavings]);

    return {
        metrics,
        events,
        isConnected: connectionStatus === 'connected',
        connectionStatus,
        requestUserPerformance,
        requestPoolAnalytics,
        requestGasSavings,
        requestRecentEvents,
        requestSystemEfficiency,
        userPerformance,
        poolAnalytics,
        gasSavings,
        systemEfficiency
    };
};