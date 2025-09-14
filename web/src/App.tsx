import { useEffect } from 'react'
import EventCollector from './providers/collectors/EventCollector'
import './App.css'
import AnvilSwapComponent from "./components/swap.tsx";

function App() {

  useEffect(() => {
    // Simple EventCollector test - CONSOLE LOGS ONLY
    const testEventCollector = async () => {
      console.log('🧪 Starting EventCollector Test...')

      try {
        // Fetch current hook address from config file
        console.log('📡 Fetching current hook address...')
        const configResponse = await fetch('/config.json')
        const config = await configResponse.json()

        console.log('✅ Loaded config:', config)

        // Create EventCollector instance with dynamic config
        const eventCollector = new EventCollector(config)

        // Register a simple event handler for testing
        eventCollector.onEvent('BatchExecuted', (event) => {
          console.log('✅ BatchExecuted event received:', event)
        })

        // Register handler for FeesCollected
        eventCollector.onEvent('FeesCollected', (event) => {
          console.log('💰 FeesCollected event received:', event)
        })

        // Register handler for all events
        eventCollector.onEvent('*', (event) => {
          console.log('📡 Any event received:', event.type, event.data)
        })

        // Start monitoring
        await eventCollector.startEventMonitoring()

        console.log('🎯 EventCollector test setup complete - waiting for events...')
        console.log('💡 Run your simulation to generate events!')

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
        <AnvilSwapComponent />
      </div>
    </div>
  )
}

export default App
