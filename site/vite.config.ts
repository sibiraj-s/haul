import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  // Relative asset paths, so the build works at github.io/haul/ or any other base path.
  base: './',
  build: {
    rollupOptions: {
      // The docs are a page of their own, served at /docs/.
      input: { main: 'index.html', docs: 'docs/index.html' },
    },
  },
})
