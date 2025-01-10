import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
    plugins: [
        laravel({
            input: 'resources/js/app.tsx',
        }),
        react(),
    ],
    // resolve: {
    //     alias: {
    //         '@': path.resolve(__dirname, 'resources/js'),
    //     },
    // },
    base: '/build/',
    build: {
        outDir: 'public/build',
        emptyOutDir: true,
        // rollupOptions: {
        //     output: {
        //         manualChunks(id) {
        //             if (id.includes('node_modules')) {
        //                 return 'vendor';
        //             }
        //         },
        //     },
        // },
    },
});