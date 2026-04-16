import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const DEFAULT_WEB_PORT = 4174;
const DEFAULT_API_PORT = 4310;

export default defineConfig({
  plugins: [react()],
  server: {
    host: "127.0.0.1",
    port: DEFAULT_WEB_PORT,
    proxy: {
      "/api": {
        target: `http://127.0.0.1:${DEFAULT_API_PORT}`,
        changeOrigin: true
      }
    }
  }
});
