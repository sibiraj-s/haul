import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { Footer } from './components/Footer'
import { Header } from './components/Header'
import './index.css'

// The privacy policy and terms are written into their HTML, so they read the same without
// JavaScript (store reviewers and link checkers often don't run it); this only adds the
// site's header and footer around them.
for (const [id, element] of [
  ['header', <Header home="../" />],
  ['footer', <Footer home="../" />],
] as const) {
  createRoot(document.getElementById(id)!).render(<StrictMode>{element}</StrictMode>)
}
