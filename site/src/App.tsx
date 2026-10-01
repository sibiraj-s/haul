import { useEffect } from 'react'
import { Demo } from './components/Demo'
import { Features } from './components/Features'
import { Footer } from './components/Footer'
import { Header } from './components/Header'
import { Hero } from './components/Hero'
import { Sponsor } from './components/Sponsor'

export default function App() {
  // The page renders after load, so the browser can't scroll to a #fragment by itself.
  useEffect(() => {
    const target = location.hash ? document.getElementById(decodeURIComponent(location.hash.slice(1))) : null
    target?.scrollIntoView()
  }, [])

  return (
    <div className="min-h-screen bg-bg font-sans text-text">
      <Header />
      <main>
        <Hero />
        <Demo />
        <Features />
        <Sponsor />
      </main>
      <Footer />
    </div>
  )
}
