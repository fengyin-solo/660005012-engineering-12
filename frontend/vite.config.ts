import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
export default defineConfig({
  plugins: [vue()],
  server: {
    host: '127.0.0.1',
    port: 3000,
    strictPort: true, // 端口被占用时直接失败，而不是静默跳到 3001
    proxy: { '/api': 'http://127.0.0.1:8000' }
  }
})
