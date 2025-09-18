import { useEffect } from 'react'
import './App.css'
import Prisma from "./components/prisma.tsx";
import HookListener from "./providers/collectors/HookEventListener.ts";

function App() {

  useEffect(() => {
    // Simple EventCollector test - CONSOLE LOGS ONLY
    const testEventCollector = async () => {
      console.log('🧪 Starting EventCollector Test...')

      try {
        const listener = new HookListener({
          rpcUrl: 'http://127.0.0.1:8545',
          hookAddress: '0x868c4b561869e1Fc1f8F0A50F3a12496C3C5D540',
          poolManagerAddress: '0x000000000004444c5dc75cB358380D2e3dE08A90',
          universalRouterAddress: '0x66a9893cc07d91d95644aedd05d03f95e1dba8af',
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
