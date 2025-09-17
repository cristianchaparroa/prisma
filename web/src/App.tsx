import { useEffect } from 'react'
import './App.css'
import HookEventListener from "./providers/collectors/EventCollector";
import Prisma from "./components/prisma.tsx";

function App() {

  useEffect(() => {
    // Simple EventCollector test - CONSOLE LOGS ONLY
    const testEventCollector = async () => {
      console.log('🧪 Starting EventCollector Test...')

      try {
        const listener = new HookEventListener({
          rpcUrl: 'http://127.0.0.1:8545',
          hookAddress: '0x5c795C660c9DC55420CF2385B9930708Ceef1540'
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
        <h1 className="text-5xl font-bold text-center mb-8 text-gray-100 flex items-center justify-center gap-2">
          <Prisma
              key="single-pyramid"
              color={"0x0099ff"}
              opacity={0.9}
              size={2} width={60}
              height={60} />

          Prisma
        </h1>
      </div>
    </div>
  )
}

export default App
