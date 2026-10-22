import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  // Relative asset paths, so the build works at github.io/haul/ or any other base path.
  base: './',
  build: {
    rollupOptions: {
      // The docs, privacy policy and terms are pages of their own, served at /docs/ and so on.
      input: {
        main: 'index.html',
        docs: 'docs/index.html',
        privacy: 'privacy/index.html',
        terms: 'terms/index.html',
      },
    },
  },
})
