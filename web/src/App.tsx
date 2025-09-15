import { useEffect } from 'react'
import './App.css'
import HookEventListener from "./providers/collectors/EventCollector";

function App() {

  useEffect(() => {
    // Simple EventCollector test - CONSOLE LOGS ONLY
    const testEventCollector = async () => {
      console.log('🧪 Starting EventCollector Test...')

      try {
        const listener = new HookEventListener({
          rpcUrl: 'http://127.0.0.1:8545',
          hookAddress: '0x50D1b723B364dD8f41B5b394DE9a8870Bb49D540'
        });

        // Start listening
        await listener.startListening();



      } catch (error) {
        console.error('❌ EventCollector test failed:', error)
      }
    }

    // Run the test
    testEventCollector()
  }, [])

  return (
    <div className="min-h-screen bg-gray-900 text-white">
      <div className="container mx-auto py-8">
        <h1 className="text-2xl font-bold text-center mb-8 text-gray-100">YieldMaximizer EventCollector Test</h1>
      </div>
    </div>
  )
}

export default App
