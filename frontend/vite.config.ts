import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
export default defineConfig({
  plugins: [vue()],
  // 显式绑定 IPv4 回环地址：默认 localhost 在部分机器上只解析到 ::1，
  // 会导致健康检查与 /api 代理偶发连不上。
  server: { host: '127.0.0.1', port: 3000, proxy: { '/api': 'http://127.0.0.1:8000' } }
})