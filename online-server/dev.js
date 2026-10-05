// Account-free local testing only: uses the same workerd runtime and Worker code.
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { fileURLToPath } from 'node:url';
const mf = new Miniflare(convertV4MiniflareOptions({
  host: '127.0.0.1', port: Number(process.env.PORT || 8787),
  workers: [{
    name: 'kraterkompisar-online', modules: true,
    scriptPath: fileURLToPath(new URL('./src/worker.js', import.meta.url)),
    compatibilityDate: '2026-10-01', durableObjects: { ROOMS: { className: 'GameRoom', useSQLite: true } },
    bindings: { ALLOWED_ORIGIN: 'https://danielkretz-cpu.github.io' }
  }]
}));
console.log('Kraterkompisar local server:', (await mf.ready).toString());
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => { await mf.dispose(); process.exit(0); });
