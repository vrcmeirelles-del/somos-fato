/// <reference types="vitest" />
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Build estático servido pelo servidor local (127.0.0.1). Sem publicação.
export default defineConfig({
  plugins: [react()],
  build: { outDir: 'dist', sourcemap: false, assetsInlineLimit: 0 },
  test: { environment: 'jsdom' },
});
