import { useEffect, useState } from 'react'
import './App.css'
import Prisma from "./components/prisma.tsx";
import YieldMaximizerDashboard from "./components/Dashboard";
import EnhancedHookListener from "./components/Metrics";

function App() {
  const [hookListener, setHookListener] = useState<EnhancedHookListener | null>(null);
  const [serverStatus, setServerStatus] = useState<'starting' | 'running' | 'error' | 'stopped'>('stopped');

  useEffect(() => {
    // Initialize Enhanced Hook Listener directly in the browser
    const initializeHookListener = async () => {
      console.log('🚀 Initializing YieldMaximizer Hook Listener...')
      setServerStatus('starting');

      try {
        const listener = new EnhancedHookListener({
          rpcUrl: 'http://127.0.0.1:8545',
          hookAddress: '0xf9Ce2CDc991DF6Ded7201003554864936D909540',
          poolManagerAddress: '0x000000000004444c5dc75cB358380D2e3dE08A90',
          universalRouterAddress: '0x66a9893cc07d91d95644aedd05d03f95e1dba8af',
        });

        // Start the hook listener
        await listener.startRealtimeMonitoring();
        setHookListener(listener);
        setServerStatus('running');

        console.log('✅ YieldMaximizer Hook Listener started successfully');

      } catch (error) {
        console.error('❌ Failed to start Hook Listener:', error);
        setServerStatus('error');
      }
    }

    // Start the listener
    initializeHookListener();

    // Cleanup on unmount
    return () => {
      if (hookListener) {
        console.log('🛑 Shutting down Hook Listener...');
        hookListener.stop();
        setServerStatus('stopped');
      }
    };
  }, []);

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-gray-900 text-white py-4">
        <div className="container mx-auto px-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <Prisma
                key="single-pyramid"
                color={"0x0099ff"}
                opacity={0.9}
                size={2}
                width={40}
                height={40}
              />
              <h1 className="text-2xl font-bold">Prisma - YieldMaximizer</h1>
            </div>

            {/* Listener Status */}
            <div className={`flex items-center space-x-2 px-3 py-2 rounded-lg text-sm font-medium ${
              serverStatus === 'running' ? 'bg-green-100 text-green-800' :
              serverStatus === 'starting' ? 'bg-yellow-100 text-yellow-800' :
              serverStatus === 'error' ? 'bg-red-100 text-red-800' :
              'bg-gray-100 text-gray-800'
            }`}>
              <div className={`h-2 w-2 rounded-full ${
                serverStatus === 'running' ? 'bg-green-500' :
                serverStatus === 'starting' ? 'bg-yellow-500' :
                serverStatus === 'error' ? 'bg-red-500' :
                'bg-gray-500'
              }`}></div>
              <span>
                Listener: {
                  serverStatus === 'running' ? 'Active' :
                  serverStatus === 'starting' ? 'Starting...' :
                  serverStatus === 'error' ? 'Error' :
                  'Stopped'
                }
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Dashboard */}
      {serverStatus === 'running' ? (
        <YieldMaximizerDashboard hookListener={hookListener} />
      ) : serverStatus === 'starting' ? (
        <div className="flex items-center justify-center min-h-screen">
          <div className="text-center">
            <div className="animate-spin rounded-full h-32 w-32 border-b-2 border-blue-600 mx-auto mb-4"></div>
            <h2 className="text-xl font-semibold text-gray-900 mb-2">Starting YieldMaximizer</h2>
            <p className="text-gray-600">Connecting to blockchain and initializing real-time monitoring...</p>
          </div>
        </div>
      ) : serverStatus === 'error' ? (
        <div className="flex items-center justify-center min-h-screen">
          <div className="text-center">
            <div className="bg-red-100 rounded-full p-3 mx-auto mb-4 w-16 h-16 flex items-center justify-center">
              <span className="text-red-600 text-2xl">⚠️</span>
            </div>
            <h2 className="text-xl font-semibold text-red-900 mb-2">Listener Error</h2>
            <p className="text-red-600">Failed to start blockchain event listener. Check console for details.</p>
            <button
              onClick={() => window.location.reload()}
              className="mt-4 px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700"
            >
              Retry
            </button>
          </div>
        </div>
      ) : (
        <div className="flex items-center justify-center min-h-screen">
          <div className="text-center">
            <h2 className="text-xl font-semibold text-gray-900 mb-2">Listener Stopped</h2>
            <p className="text-gray-600">Blockchain event listener is not running.</p>
          </div>
        </div>
      )}
    </div>
  )
}

export default App
