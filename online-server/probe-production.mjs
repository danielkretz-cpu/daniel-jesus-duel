// Explicitly invoked post-deploy probe. Never run against production in npm test.
// One ephemeral synthetic room; no account data or credentials are logged.
import WebSocket from 'ws';
import assert from 'node:assert/strict';
import { setTimeout as sleep } from 'node:timers/promises';
const endpoint = process.env.PROBE_URL;
if (!endpoint || !/^wss?:\/\//.test(endpoint)) throw new Error('Set PROBE_URL to the explicitly authorized relay endpoint');
const health = await fetch(endpoint.replace(/^ws/, 'http') + '/health').then(r => r.json());
assert.equal(health.transport_revision, 1, 'New transport revision must be deployed');
console.log('PASS: configured endpoint identifies transport revision 1');
const sockets = [];
function connect(path) {
  const ws = new WebSocket(endpoint + path, { headers: { Origin: 'https://danielkretz-cpu.github.io' } });
  sockets.push(ws);
  const queue = [];
  ws.on('message', data => queue.push(JSON.parse(data.toString())));
  ws.on('error', () => {});
  return { ws, send: m => ws.send(JSON.stringify(m)), async next(type, predicate = () => true) {
    const deadline = Date.now() + 10_000;
    while (Date.now() < deadline) {
      const failure = queue.find(m => m.type === 'error');
      if (failure) throw new Error(`Relay rejection: ${failure.code}`);
      const i = queue.findIndex(m => m.type === type && predicate(m));
      if (i >= 0) return queue.splice(i, 1)[0];
      if (ws.readyState === WebSocket.CLOSED) throw new Error('Socket closed before ' + type);
      await sleep(10);
    }
    throw new Error('Timed out waiting for ' + type);
  } };
}
try {
  const host = connect('/room?mode=create&protocol=3&capacity=2&name=Transport%20probe');
  const welcome = await host.next('welcome');
  const guest = connect(`/room?protocol=3&code=${welcome.room}&name=Synthetic%20guest`);
  const guestWelcome = await guest.next('welcome');
  await host.next('presence', m => m.roster.length === 2 && m.can_start);
  host.send({ type: 'start', map_id: 0 });
  await Promise.all([host.next('started'), guest.next('started')]);
  const snapshot = { schema: 3, phase: 'aim', turn: 1, active: 0, target: 1, map_id: 0,
    angle: 46, power: 70, weapon: 0, wind: 0, move_left: 170, turn_clock: 40, settle_clock: 0,
    winner: -1, shots: 0, hits: 0, freedom: [1, 1], paused: false,
    fighters: [{ pos: [224, 307], vel: [0, 0], hp: 100, face: 1, ground: true },
      { pos: [1050, 325], vel: [0, 0], hp: 100, face: -1, ground: true }],
    projectile: {}, fragments: [], trail: [], terrain_version: 500,
    craters: Array.from({ length: 500 }, (_, i) => [i * 2, 350, 35]) };
  const start = Date.now();
  for (let seq = 1; seq <= 60; seq++) host.send({ type: 'state', seq, snapshot });
  const latest = await guest.next('state', m => m.seq === 60);
  assert.deepEqual(latest.snapshot, snapshot);
  host.send({ type: 'ping' }); await host.next('pong');
  console.log(`PASS: 60-state / 500-crater delayed-delivery burst reaches current state; host stays connected (${Date.now() - start} ms)`);
  await sleep(1100); // Refill the bounded rate budget before another short batch.
  guest.ws.pause();
  for (let seq = 61; seq <= 80; seq++) host.send({ type: 'state', seq, snapshot });
  await sleep(500);
  guest.ws.resume();
  assert.deepEqual((await guest.next('state', m => m.seq === 80)).snapshot, snapshot);
  console.log('PASS: paused receiver resumes and obtains latest exact state');
  // Token stays in memory and is used only with the authorized relay endpoint.
  await new Promise(resolve => { guest.ws.once('close', resolve); guest.ws.close(); });
  await host.next('presence', m => m.roster[1]?.connected === false);
  const resumed = connect(`/room?protocol=3&code=${welcome.room}&token=${guestWelcome.token}`);
  const restored = await resumed.next('welcome');
  assert.equal(restored.seat, 1); assert.equal(restored.seq, 80);
  assert.deepEqual(restored.snapshot, snapshot);
  console.log('PASS: synthetic guest reconnect restores its seat and latest snapshot');
} finally {
  await Promise.all(sockets.map(ws => new Promise(resolve => {
    if (ws.readyState === WebSocket.CLOSED) return resolve();
    ws.once('close', resolve);
    ws.close();
    setTimeout(() => { ws.terminate(); resolve(); }, 1500).unref();
  })));
}
