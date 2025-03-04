import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';
import react from '@vitejs/plugin-react';

export default defineConfig({
    server: {
        host: "0.0.0.0",
        port: 5173,
        origin: "http://localhost:5173",
        cors: true,
        hmr: {
            host: "localhost",
            port: 5173,
            protocol: "ws"
        }
    },
    plugins: [
        laravel({
            input: 'resources/js/app.jsx',
            refresh: true,
        }),
        react(),
    ],
});
