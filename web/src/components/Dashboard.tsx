import React, { useState, useEffect, useRef, useMemo } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, AreaChart, Area, BarChart, Bar, PieChart, Pie, Cell } from 'recharts';
import { Activity, TrendingUp, Users, DollarSign, Zap, Settings, AlertCircle, Gauge } from 'lucide-react';
import EnhancedHookListener from './Metrics';
import type { DashboardMetrics, RealTimeEvent } from './Metrics';
import { formatTokenAmount, getTokenInfo } from '../config/tokens';
import { getPoolDescription, formatPoolTokenAmount } from '../config/pools';

interface YieldMaximizerDashboardProps {
    hookListener: EnhancedHookListener | null;
}

const YieldMaximizerDashboard: React.FC<YieldMaximizerDashboardProps> = ({ hookListener }) => {
    const [metrics, setMetrics] = useState<DashboardMetrics | null>(null);
    const [events, setEvents] = useState<RealTimeEvent[]>([]);
    const [isConnected, setIsConnected] = useState(false);
    const [poolDistribution, setPoolDistribution] = useState<Array<{name: string, value: number, color: string}>>([]);
    const [lastUpdateTime, setLastUpdateTime] = useState(Date.now());
    const [error, setError] = useState<string | null>(null);

    const [currentBlock, setCurrentBlock] = useState(0);
    const [timeSeriesData, setTimeSeriesData] = useState<any[]>([]);
    const [gasOptimization, setGasOptimization] = useState<any[]>([]);
    const [recentActivity, setRecentActivity] = useState<any[]>([]);

    // Convert real metrics to dashboard format with proper number handling - use useMemo to ensure updates
    const systemMetrics = React.useMemo(() => {
        const result = metrics ? {
            totalTVL: Number(metrics.totalTVL),
            totalUsers: metrics.totalUsers,
            totalFeesCollected: Number(metrics.totalFeesCollected),
            totalCompounded: Number(metrics.totalCompounded),
            gasEfficiency: Number(metrics.gasEfficiency),
            avgAPY: metrics.avgAPY
        } : {
            totalTVL: 0,
            totalUsers: 0,
            totalFeesCollected: 0,
            totalCompounded: 0,
            gasEfficiency: 0,
            avgAPY: 0
        };
        
        console.log('💰 SystemMetrics computed:', result);
        return result;
    }, [metrics, lastUpdateTime]);

    // Format fees by token - shows breakdown by token type
    const formatFeesByToken = (metrics: DashboardMetrics | null): string => {
        // Reduced logging - only when we have multiple tokens
        if (metrics?.feesByToken && Object.keys(metrics.feesByToken).length > 1) {
            console.log('💰 Multi-token fees:', Object.keys(metrics.feesByToken).map(addr => 
                metrics.feesByToken[addr]?.symbol || 'UNKNOWN'
            ));
        }

        if (!metrics || !metrics.feesByToken || Object.keys(metrics.feesByToken).length === 0) {
            return formatSmartTokenAmount(metrics ? Number(metrics.totalFeesCollected) : 0);
        }

        const tokenFees = Object.values(metrics.feesByToken)
            .map(tokenFee => {
                const amount = Number(tokenFee.amount) / Math.pow(10, tokenFee.decimals);
                const formatted = amount < 0.000001 ? 
                    amount.toExponential(3) : 
                    amount.toFixed(6);
                return `${formatted} ${tokenFee.symbol}`;
            })
            .join(' + ');

        // Only log when fees are actually present
        if (tokenFees && tokenFees !== "0.00") {
            console.log('💰 Fee breakdown:', tokenFees);
        }
        return tokenFees || "0.00";
    };

    // Format compounded fees by token - shows breakdown by token type
    const formatCompoundedByToken = (metrics: DashboardMetrics | null): string => {
        // Reduced logging - only when we have multiple tokens
        if (metrics?.compoundedByToken && Object.keys(metrics.compoundedByToken).length > 1) {
            console.log('🔄 Multi-token compounded:', Object.keys(metrics.compoundedByToken).map(addr => 
                metrics.compoundedByToken[addr]?.symbol || 'UNKNOWN'
            ));
        }

        if (!metrics || !metrics.compoundedByToken || Object.keys(metrics.compoundedByToken).length === 0) {
            return formatSmartTokenAmount(metrics ? Number(metrics.totalCompounded) : 0);
        }

        const compoundedTokens = Object.values(metrics.compoundedByToken)
            .map(tokenCompounded => {
                const amount = Number(tokenCompounded.amount) / Math.pow(10, tokenCompounded.decimals);
                const formatted = amount < 0.000001 ? 
                    amount.toExponential(3) : 
                    amount.toFixed(6);
                return `${formatted} ${tokenCompounded.symbol}`;
            })
            .join(' + ');

        // Only log when compounded fees are actually present
        if (compoundedTokens && compoundedTokens !== "0.00") {
            console.log('🔄 Compounded breakdown:', compoundedTokens);
        }
        return compoundedTokens || "0.00";
    };

    // Smart token formatter - detects token based on amount and context
    const formatSmartTokenAmount = (amount: number, tokenAddress?: string) => {
        if (amount === 0) return "0.00";
        
        // Try to detect token from events if no address provided
        if (!tokenAddress && events.length > 0) {
            // Look at recent events to infer token type
            const recentEvent = events[0];
            // For now, assume it's a stablecoin based on small amounts
            if (amount < 1000000) { // Less than 1M suggests 6-decimal token like USDC
                return `${(amount / 1e6).toFixed(6)} USDC`;
            } else if (amount > 1e15) { // Large numbers suggest 18-decimal token like DAI
                return `${(amount / 1e18).toFixed(6)} DAI`;
            }
        }
        
        // If we have a token address, use proper formatting
        if (tokenAddress) {
            return formatTokenAmount(amount, tokenAddress);
        }
        
        // Fallback: try to guess based on amount magnitude
        if (amount < 1000000) {
            // Likely USDC (6 decimals)
            return `${(amount / 1e6).toFixed(6)} USDC`;
        } else if (amount > 1e15) {
            // Likely DAI (18 decimals) 
            return `${(amount / 1e18).toFixed(6)} DAI`;
        } else {
            // Medium range - could be USDT (6 decimals) or other
            return `${(amount / 1e6).toFixed(6)} tokens`;
        }
    };

    // Essential dashboard metrics logging (reduced frequency)
    if (systemMetrics.totalUsers > 0 && systemMetrics.totalFeesCollected > 0) {
        console.log('📊 Dashboard Summary:', {
            users: systemMetrics.totalUsers,
            events: events.length,
            connected: isConnected
        });
    }

    // Subscribe to hook listener events and metrics
    useEffect(() => {
        if (!hookListener) return;

        try {
            setIsConnected(true);
            setError(null);

            // Get initial data
            const initialMetrics = hookListener.getMetrics();
            const initialEvents = hookListener.getRecentEvents(50);
            const poolAnalytics = hookListener.getPoolAnalytics();
            
            console.log('🚀 Initial setup - Metrics:', initialMetrics);
            console.log('🚀 Initial setup - Events:', initialEvents.length);
            
            setMetrics(initialMetrics);
            setEvents(initialEvents);
            updatePoolDistribution(poolAnalytics, initialEvents);

        // Subscribe to updates
        const handleMetricsUpdate = (newMetrics: DashboardMetrics) => {
            console.log('📊 Metrics updated:', newMetrics);
            setMetrics(newMetrics);
            setLastUpdateTime(Date.now());
        };

        const handleNewEvent = (newEvent: RealTimeEvent) => {
            console.log('🎯 New event received:', newEvent.name, newEvent.args);
            setEvents(prev => {
                const updatedEvents = [newEvent, ...prev].slice(0, 100);
                // Update pool distribution when new events come in
                const currentPoolAnalytics = hookListener.getPoolAnalytics();
                updatePoolDistribution(currentPoolAnalytics, updatedEvents);
                return updatedEvents;
            });
            
            // Force metrics refresh when new event comes in
            const refreshedMetrics = hookListener.getMetrics();
            console.log('🔄 Refreshed metrics after event:', refreshedMetrics);
            setMetrics(refreshedMetrics);
            setLastUpdateTime(Date.now());
        };

        hookListener.onMetricsUpdate(handleMetricsUpdate);
        hookListener.onNewEvent(handleNewEvent);

        // Set up periodic refresh to ensure UI stays updated
        const refreshInterval = setInterval(() => {
            const currentMetrics = hookListener.getMetrics();
            console.log('🔄 Periodic refresh:', currentMetrics);
            setMetrics(currentMetrics);
            setLastUpdateTime(Date.now());
        }, 2000); // Refresh every 2 seconds

            return () => {
                setIsConnected(false);
                clearInterval(refreshInterval);
            };
        } catch (error) {
            console.error('❌ Error in dashboard setup:', error);
            setError(error instanceof Error ? error.message : 'Unknown error occurred');
            setIsConnected(false);
        }
    }, [hookListener]);

    // Update current block based on real events
    useEffect(() => {
        if (events.length > 0) {
            const latestBlock = Math.max(...events.map(e => Number(e.blockNumber) || 0));
            setCurrentBlock(latestBlock);
        }
    }, [events]);

    // Helper function to get event description
    const getEventDescription = (event: any) => {
        if (!event.args) return event.name;
        
        switch (event.name) {
            case 'FeesCollected':
                const feeAmount = Number(event.args.amount || 0);
                const tokenAddress = event.args.token || event.tokenContext?.address;
                const tokenDisplay = tokenAddress ? 
                    formatTokenAmount(feeAmount, tokenAddress) : 
                    formatSmartTokenAmount(feeAmount);
                return `${event.args.user?.slice(0, 6)}...${event.args.user?.slice(-4)} earned ${tokenDisplay} fees`;
            case 'FeesCompounded':
                const compoundAmount = Number(event.args.amount || 0);
                return `${event.args.user?.slice(0, 6)}...${event.args.user?.slice(-4)} compounded ${formatSmartTokenAmount(compoundAmount)}`;
            case 'BatchExecuted':
                return `Batch of ${event.args.userCount || 0} compounds executed, saved ${event.args.gasUsed || 0} gas`;
            case 'StrategyActivated':
                return `${event.args.user?.slice(0, 6)}...${event.args.user?.slice(-4)} activated auto-compounding strategy`;
            case 'LiquidityAdded':
                const liquidityAmount = Number(event.args.amount || 0);
                return `${event.args.user?.slice(0, 6)}...${event.args.user?.slice(-4)} added ${formatSmartTokenAmount(liquidityAmount)} liquidity`;
            default:
                return event.name;
        }
    };

    // Convert real events to dashboard format
    useEffect(() => {
        if (events.length > 0) {
            const dashboardEvents = events.slice(0, 20).map(event => ({
                id: event.transactionHash || Date.now(),
                type: event.name,
                description: getEventDescription(event),
                timestamp: event.timestamp,
                importance: event.impact
            }));
            setRecentActivity(dashboardEvents);
        }
    }, [events]);

    // Update time series data based on real metrics (using gwei for better visibility)
    useEffect(() => {
        try {
            if (metrics) {
                const now = new Date();
                const newDataPoint = {
                    time: now.toLocaleTimeString(),
                    timestamp: now.getTime(),
                    tvl: Number(metrics.totalTVL) / 1e9, // Convert to gwei
                    fees: Number(metrics.totalFeesCollected) / 1e9, // Convert to gwei  
                    compounds: Number(metrics.totalCompounded) / 1e9, // Convert to gwei
                    users: metrics.totalUsers,
                    apy: metrics.avgAPY
                };
                
                setTimeSeriesData(prev => {
                    try {
                        const updated = [...prev, newDataPoint].slice(-20);
                        console.log('📈 Time series updated:', updated[updated.length - 1]);
                        return updated;
                    } catch (arrayError) {
                        console.warn('Warning: Error updating time series:', arrayError);
                        return [newDataPoint];
                    }
                });
            }
        } catch (error) {
            console.error('❌ Error in time series update:', error);
        }
    }, [metrics]);

    // Update gas optimization data based on real events
    useEffect(() => {
        const batchEvents = events.filter(e => e.name === 'BatchExecuted');
        if (batchEvents.length > 0) {
            const gasData = batchEvents.slice(-10).map(event => ({
                time: new Date(event.timestamp).toLocaleTimeString(),
                individual: event.args?.userCount ? event.args.userCount * 150000 : 150000,
                batch: Number(event.gasUsed) || 50000,
                savings: event.metrics?.gasEfficiency || 0
            }));
            setGasOptimization(gasData);
        }
    }, [events]);

    const updatePoolDistribution = (poolAnalytics: any[], events: RealTimeEvent[]) => {
        try {
            const poolColors = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042', '#8884D8', '#82CA9D'];
            
            // Always use events-based distribution since it reflects actual activity
            const poolEventCounts: Record<string, number> = {};
            const poolActivityData: Record<string, { fees: bigint, users: Set<string> }> = {};
            
            events.forEach(event => {
                try {
                    const poolId = event.args?.poolId;
                    if (poolId && typeof poolId === 'string') {
                        const poolKey = poolId.slice(0, 8) + '...';
                        poolEventCounts[poolKey] = (poolEventCounts[poolKey] || 0) + 1;
                        
                        // Track more detailed activity
                        if (!poolActivityData[poolKey]) {
                            poolActivityData[poolKey] = { fees: 0n, users: new Set() };
                        }
                        
                        if (event.name === 'FeesCollected' && event.args.amount) {
                            const amount = typeof event.args.amount === 'bigint' ? event.args.amount : BigInt(event.args.amount);
                            poolActivityData[poolKey].fees += amount;
                        }
                        
                        if (event.args.user) {
                            poolActivityData[poolKey].users.add(event.args.user);
                        }
                    }
                } catch (eventError) {
                    console.warn('Warning: Error processing event for pool distribution:', eventError);
                }
            });
        
        console.log('🔍 Pool Activity Summary:');
        console.log('Pool event counts:', poolEventCounts);
        console.log('Pool activity data:', Object.entries(poolActivityData).map(([pool, data]) => ({
            pool,
            eventCount: poolEventCounts[pool],
            totalFees: data.fees.toString(),
            uniqueUsers: data.users.size
        })));
        
        const totalEvents = Object.values(poolEventCounts).reduce((sum, count) => sum + count, 0);
        
        if (totalEvents > 0) {
            const distribution = Object.entries(poolEventCounts).map(([poolId, count], index) => {
                const activityData = poolActivityData[poolId];
                const userCount = activityData ? activityData.users.size : 0;
                const feesInEth = activityData ? Number(activityData.fees) / 1e18 : 0;
                const percentage = Math.round((count / totalEvents) * 100);
                
                // Create a more descriptive name
                const poolName = Object.keys(poolEventCounts).length === 1 
                    ? `Pool ${poolId} (Active)` 
                    : `Pool ${poolId}`;
                
                return {
                    name: poolName,
                    value: percentage,
                    color: poolColors[index % poolColors.length],
                    tooltip: `${count} events (${percentage}%), ${userCount} users, ${feesInEth.toFixed(6)} ETH fees`
                };
            });
            
            console.log('✅ Distribution from events:', distribution);
            setPoolDistribution(distribution);
        } else {
            console.log('ℹ️ No pool activity found, using default');
            setPoolDistribution(getDefaultPoolDistribution());
        }
        } catch (error) {
            console.error('❌ Error updating pool distribution:', error);
            setPoolDistribution(getDefaultPoolDistribution());
        }
    };

    const getDefaultPoolDistribution = () => [
        { name: 'No Active Pools', value: 100, color: '#9CA3AF' }
    ];



    const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042', '#8884D8'];

    const StatCard = ({ icon: Icon, title, value, subtitle, trend, color = "blue" }) => (
        <div className="bg-white rounded-lg shadow-lg p-6 border-l-4 border-blue-500">
            <div className="flex items-center justify-between">
                <div>
                    <p className="text-sm font-medium text-gray-600">{title}</p>
                    <p className="text-2xl font-bold text-gray-900">{value}</p>
                    {subtitle && <p className="text-sm text-gray-500">{subtitle}</p>}
                </div>
                <div className={`p-3 rounded-full bg-${color}-100`}>
                    <Icon className={`h-6 w-6 text-${color}-600`} />
                </div>
            </div>
            {trend && (
                <div className="mt-2 flex items-center">
                    <TrendingUp className="h-4 w-4 text-green-500" />
                    <span className="text-sm text-green-600 ml-1">{trend}</span>
                </div>
            )}
        </div>
    );

    // Handle error state
    if (error) {
        return (
            <div className="min-h-screen bg-gray-50 p-6 flex items-center justify-center">
                <div className="bg-white rounded-lg shadow-lg p-8 max-w-md">
                    <div className="flex items-center mb-4">
                        <AlertCircle className="h-8 w-8 text-red-500 mr-3" />
                        <h2 className="text-xl font-bold text-gray-900">Dashboard Error</h2>
                    </div>
                    <p className="text-gray-600 mb-4">{error}</p>
                    <button 
                        onClick={() => {
                            setError(null);
                            window.location.reload();
                        }}
                        className="bg-blue-500 text-white px-4 py-2 rounded hover:bg-blue-600"
                    >
                        Reload Dashboard
                    </button>
                </div>
            </div>
        );
    }

    return (
        <div key={`dashboard-${lastUpdateTime}`} className="min-h-screen bg-gray-50 p-6">
            {/* Header */}
            <div className="mb-8">
                <div className="flex items-center justify-between">
                    <div>
                        <h1 className="text-3xl font-bold text-gray-900">YieldMaximizer Dashboard</h1>
                        <p className="text-gray-600">Real-time monitoring of auto-compounding strategies</p>
                    </div>
                    <div className="flex items-center space-x-4">
                        <div className={`flex items-center space-x-2 px-3 py-2 rounded-lg ${
                            isConnected ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'
                        }`}>
                            <div className={`h-2 w-2 rounded-full ${
                                isConnected ? 'bg-green-500' : 'bg-gray-500'
                            }`}></div>
                            <span className="text-sm font-medium">
                                {isConnected ? `Connected - Block ${currentBlock}` : 'Disconnected'}
                            </span>
                        </div>
                    </div>
                </div>
            </div>

            {/* Key Metrics - Only What Matters for Swappers */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-8">
                <StatCard
                    icon={DollarSign}
                    title="Total Fees Earned"
                    value={formatFeesByToken(metrics)}
                    subtitle="From swapping activity"
                    color="green"
                />
                <StatCard
                    icon={TrendingUp}
                    title="Fees Compounded"
                    value={formatCompoundedByToken(metrics)}
                    subtitle="Auto-reinvested"
                    color="blue"
                />
                <StatCard
                    icon={Users}
                    title="Active Swappers"
                    value={systemMetrics.totalUsers.toLocaleString()}
                    subtitle="Using auto-compound"
                    color="purple"
                />
            </div>

            {/* Essential Charts */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
                {/* Fee Collection vs Compounding */}
                <div className="bg-white rounded-lg shadow-lg p-6">
                    <h3 className="text-lg font-semibold text-gray-900 mb-4">Fee Collection vs Auto-Compounding</h3>
                    <ResponsiveContainer width="100%" height={350}>
                        <AreaChart data={timeSeriesData} margin={{ top: 5, right: 30, left: 20, bottom: 5 }}>
                            <defs>
                                <linearGradient id="colorFees" x1="0" y1="0" x2="0" y2="1">
                                    <stop offset="5%" stopColor="#3B82F6" stopOpacity={0.8}/>
                                    <stop offset="95%" stopColor="#3B82F6" stopOpacity={0.2}/>
                                </linearGradient>
                                <linearGradient id="colorCompounds" x1="0" y1="0" x2="0" y2="1">
                                    <stop offset="5%" stopColor="#10B981" stopOpacity={0.8}/>
                                    <stop offset="95%" stopColor="#10B981" stopOpacity={0.2}/>
                                </linearGradient>
                            </defs>
                            <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                            <XAxis dataKey="time" tick={{fontSize: 12}} />
                            <YAxis tick={{fontSize: 12}} />
                            <Tooltip formatter={(value, name) => {
                                const gweiValue = Number(value);
                                const formattedValue = gweiValue.toFixed(2) + ' gwei';
                                return [formattedValue, name === 'fees' ? 'Fees Collected' : 'Fees Compounded'];
                            }} />
                            <Legend />
                            <Area 
                                type="monotone" 
                                dataKey="fees" 
                                stackId="1" 
                                stroke="#3B82F6" 
                                fill="url(#colorFees)" 
                                name="Fees Collected"
                                isAnimationActive={false}
                            />
                            <Area 
                                type="monotone" 
                                dataKey="compounds" 
                                stackId="1" 
                                stroke="#10B981" 
                                fill="url(#colorCompounds)" 
                                name="Fees Compounded"
                                isAnimationActive={false}
                            />
                        </AreaChart>
                    </ResponsiveContainer>
                </div>

                {/* Compounding Efficiency */}
                <div className="bg-white rounded-lg shadow-lg p-6">
                    <h3 className="text-lg font-semibold text-gray-900 mb-4">Auto-Compound Efficiency</h3>
                    <div className="space-y-6">
                        {/* Efficiency Percentage */}
                        <div key={`efficiency-${lastUpdateTime}`}>
                            <div className="flex justify-between items-center mb-2">
                                <span className="text-sm font-medium text-gray-700">Compounding Rate</span>
                                <span className="text-sm font-semibold text-gray-900">
                                    {systemMetrics.totalFeesCollected > 0 
                                        ? Math.round((systemMetrics.totalCompounded / systemMetrics.totalFeesCollected) * 100)
                                        : 0}%
                                </span>
                            </div>
                            <div className="w-full bg-gray-200 rounded-full h-3">
                                <div 
                                    className="bg-green-500 h-3 rounded-full"
                                    style={{ 
                                        width: `${systemMetrics.totalFeesCollected > 0 
                                            ? Math.min(100, (systemMetrics.totalCompounded / systemMetrics.totalFeesCollected) * 100)
                                            : 0}%` 
                                    }}
                                ></div>
                            </div>
                        </div>

                        {/* Key Stats */}
                        <div className="grid grid-cols-2 gap-4">
                            <div key={`fees-${lastUpdateTime}`} className="bg-blue-50 rounded-lg p-4">
                                <div className="text-lg font-bold text-blue-600">
                                    {formatFeesByToken(metrics)}
                                </div>
                                <div className="text-sm text-blue-800">Fees Collected</div>
                            </div>
                            <div key={`compounds-${lastUpdateTime}`} className="bg-green-50 rounded-lg p-4">
                                <div className="text-lg font-bold text-green-600">
                                    {formatCompoundedByToken(metrics)}
                                </div>
                                <div className="text-sm text-green-800">Auto-Compounded</div>
                            </div>
                        </div>

                        {/* Status */}
                        <div className="flex items-center justify-center p-4 bg-gray-50 rounded-lg">
                            <div className="flex items-center space-x-2">
                                <div className={`h-3 w-3 rounded-full ${systemMetrics.totalUsers > 0 ? 'bg-green-500' : 'bg-gray-400'}`}></div>
                                <span className="text-sm font-medium text-gray-700">
                                    {systemMetrics.totalUsers > 0 
                                        ? `${systemMetrics.totalUsers} swappers using auto-compound`
                                        : 'No active auto-compound users'
                                    }
                                </span>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            {/* How It Helps Swappers */}
            <div className="bg-white rounded-lg shadow-lg p-6">
                <h3 className="text-lg font-semibold text-gray-900 mb-4">YieldMaximizer Impact</h3>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div className="text-center">
                        <div className="text-3xl font-bold text-blue-600 mb-2">
                            {systemMetrics.totalUsers}
                        </div>
                        <div className="text-sm text-gray-600">Swappers earning fees automatically</div>
                    </div>
                    <div className="text-center">
                        <div className="text-3xl font-bold text-green-600 mb-2">
                            {systemMetrics.totalFeesCollected > 0 
                                ? Math.round((systemMetrics.totalCompounded / systemMetrics.totalFeesCollected) * 100)
                                : 0}%
                        </div>
                        <div className="text-sm text-gray-600">Of fees automatically compounded</div>
                    </div>
                    <div className="text-center">
                        <div className="text-3xl font-bold text-purple-600 mb-2">
                            {formatSmartTokenAmount(systemMetrics.totalFeesCollected - systemMetrics.totalCompounded)}
                        </div>
                        <div className="text-sm text-gray-600">pending compounding</div>
                        <div className="text-xs text-gray-500 mt-1">
                            (Total: {formatFeesByToken(metrics)})
                        </div>
                    </div>
                </div>
                
                <div className="mt-6 p-4 bg-gray-50 rounded-lg">
                    <p className="text-sm text-gray-700 text-center">
                        <strong>How it helps:</strong> Swappers earn fees from their trading activity, which are automatically compounded back into more liquidity positions, growing their earnings over time without manual intervention.
                    </p>
                </div>
            </div>

            {/* Simple Status */}
            <div className="mt-8 bg-white rounded-lg shadow-lg p-4">
                <div className="flex items-center justify-center">
                    <div className="text-sm text-gray-600">
                        YieldMaximizer Status: <span className="text-green-600 font-medium">
                            {systemMetrics.totalUsers > 0 ? 'Active' : 'Waiting for users'}
                        </span>
                        <span className="ml-4 text-xs text-gray-500">
                            Last updated: {new Date().toLocaleTimeString()}
                        </span>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default YieldMaximizerDashboard;
