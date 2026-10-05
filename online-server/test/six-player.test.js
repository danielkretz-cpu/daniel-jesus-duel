import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import WebSocket from 'ws';
import { fileURLToPath } from 'node:url';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';

const ORIGIN = 'https://danielkretz-cpu.github.io';
let mf, base;
const opened = [];
const persistence = mkdtempSync(join(tmpdir(), 'krater-v3-test-'));
const options = { ...convertV4MiniflareOptions({ port: 0, workers: [{ name: 'kraterkompisar-online',
    modules: true, scriptPath: fileURLToPath(new URL('../src/worker.js', import.meta.url)),
    compatibilityDate: '2026-10-01', durableObjects: { ROOMS: { className: 'GameRoom', useSQLite: true } },
    bindings: { ALLOWED_ORIGIN: ORIGIN }
  }] }), resourcePersistencePath: persistence };
before(async () => {
  mf = new Miniflare(options);
  base = (await mf.ready).toString().replace('http:', 'ws:').replace(/\/$/, '');
});
after(async () => {
  for (const s of opened) s.ws.terminate();
  await mf?.dispose();
  rmSync(persistence, { recursive: true, force: true });
});
function connect(path, origin = ORIGIN, headers = {}) {
  const ws = new WebSocket(base + path, { headers: { ...(origin ? { Origin: origin } : {}), ...headers } });
  const queue = [], waiting = [];
  ws.on('message', data => {
    const text = data.toString();
    const message = text === 'pong' ? { type: 'pong' } : JSON.parse(text);
    const index = waiting.findIndex(w => w.predicate(message));
    if (index < 0) queue.push(message);
    else { const waiter = waiting.splice(index, 1)[0]; clearTimeout(waiter.timeout); waiter.resolve(message); }
  });
  ws.on('error', () => {});
  const peer = {
    ws, queue,
    next(type, predicate = () => true) {
      const match = m => m.type === type && predicate(m);
      const index = queue.findIndex(match);
      if (index >= 0) return Promise.resolve(queue.splice(index, 1)[0]);
      return new Promise((resolve, reject) => {
        const waiter = { predicate: match, resolve, timeout: null };
        waiter.timeout = setTimeout(() => { const i = waiting.indexOf(waiter); if (i >= 0) waiting.splice(i, 1); reject(new Error('Timed out waiting for ' + type)); }, 4000);
        waiting.push(waiter);
      });
    },
    send(message) { ws.send(JSON.stringify(message)); },
    async close() {
      if (ws.readyState === WebSocket.CLOSED) return;
      await new Promise(resolve => { ws.once('close', resolve); ws.close(); });
    }
  };
  opened.push(peer);
  return peer;
}
function snapshot(overrides = {}) {
  return {
    schema: 1, phase: 'aim', turn: 1, active: 0, angle: 46, power: 70,
    weapon: 0, wind: 12, move_left: 170, turn_clock: 40, settle_clock: 0,
    winner: -1, shots: 0, hits: 0,
    fighters: [
      { pos: [224, 307], vel: [0, 0], hp: 100, face: 1, ground: true },
      { pos: [1050, 325], vel: [0, 0], hp: 100, face: -1, ground: true }
    ],
    projectile: {}, terrain_version: 0, craters: [], trail: [], ...overrides
  };
}
function projectile(overrides = {}) {
  return { pos: [640, 140], vel: [250, -90], age: 0.4, weapon: 2, bounces: 0, owner: 0, target: 1, ...overrides };
}
function snapshotV2(overrides = {}) {
  return snapshot({ schema: 2, map_id: 0, freedom: [1, 1], fragments: [], ...overrides });
}
async function pair(protocol) {
  const version = protocol === undefined ? '' : '&protocol=' + protocol;
  const host = connect('/room?mode=create' + version);
  const h = await host.next('welcome');
  const guest = connect('/room?code=' + h.room + version);
  const g = await guest.next('welcome');
  await host.next('presence', m => m.guest_connected);
  return { host, guest, h, g };
}

function snapshotV3(count, overrides = {}) {
  return snapshotV2({ schema: 3, target: 1,
    fighters: Array.from({ length: count }, (_, i) => ({ pos: [100 + 200 * i, 325], vel: [0, 0], hp: 100, face: i % 2 ? -1 : 1, ground: true })),
    freedom: Array(count).fill(1), ...overrides });
}
let createId = 0;
function create(extra = '') {
  return connect('/room?mode=create&protocol=3&name=V%C3%A4rd' + extra, ORIGIN, { 'CF-Connecting-IP': `test-${++createId}` });
}
async function room(count = 6, extra = '') {
  const host = create(extra), h = await host.next('welcome');
  const peers = [host], welcomes = [h];
  for (let i = 1; i < count; i++) {
    const guest = connect(`/room?code=${h.room}&protocol=3&name=Spelare%20${i}`);
    const g = await guest.next('welcome'); peers.push(guest); welcomes.push(g);
  }
  await host.next('presence', p => p.roster.length === count);
  return { host, h, peers, welcomes };
}
async function start(peers, mapId = 0) {
  peers[0].send({ type: 'start', map_id: mapId });
  const messages = await Promise.all(peers.map(p => p.next('started')));
  messages.forEach(m => { assert.equal(m.started, true); assert.equal(m.map_id, mapId); });
}
async function state(peers, seq, value) {
  peers[0].send({ type: 'state', seq, snapshot: value, commit: true });
  const messages = await Promise.all(peers.slice(1).filter(p => p.ws.readyState === WebSocket.OPEN).map(p => p.next('state', m => m.seq === seq)));
  messages.forEach(m => assert.deepEqual(m.snapshot, value));
}
function input(seq, turn = 1, target = 0) {
  return { type: 'input', seq, turn, move: 0, angle_axis: 0, power_axis: 0, target };
}
async function noInput(host, sender) {
  sender.send({ type: 'ping' }); await sender.next('pong');
  host.send({ type: 'ping' }); await host.next('pong');
  assert.equal(host.queue.filter(m => m.type === 'input').length, 0);
}
async function closeAll(peers) { await Promise.all(peers.map(p => p.close())); }

test('v3 simultaneous joins allocate exactly six private contiguous seats, with explicit host start', async () => {
  const host = create(), h = await host.next('welcome');
  assert.equal(h.protocol, 3); assert.equal(h.capacity, 6); assert.equal(h.started, false);
  assert.equal(h.roster[0].name, 'Värd'); assert.equal(h.can_start, false);
  assert.equal(h.snapshot, null); assert.ok(h.expires_at - Date.now() <= 2 * 3600_000);
  const contenders = Array.from({ length: 12 }, (_, i) => connect(`/room?code=${h.room}&protocol=3&name=G%C3%A4st${i}`));
  const results = await Promise.all(contenders.map(p => new Promise((resolve, reject) => {
    const timer = setInterval(() => {
      const m = p.queue.find(m => ['welcome', 'error'].includes(m.type));
      if (m) { clearInterval(timer); clearTimeout(timeout); resolve(m); }
    }, 5);
    const timeout = setTimeout(() => { clearInterval(timer); reject(new Error('join timed out')); }, 4000);
  })));
  assert.deepEqual(results.filter(m => m.type === 'welcome').map(m => m.seat).sort(), [1, 2, 3, 4, 5]);
  assert.equal(results.filter(m => m.code === 'room_full').length, 7);
  const roster = await host.next('presence', m => m.roster.length === 6);
  assert.equal(roster.started, false); assert.equal(roster.can_start, true);
  assert.equal(JSON.stringify(roster).includes('token'), false);
  const accepted = contenders.filter((_, i) => results[i].type === 'welcome');
  host.send({ type: 'state', seq: 1, snapshot: snapshotV3(6) });
  assert.equal((await host.next('error')).code, 'not_started');
  await start([host, ...accepted], 4);
  const late = connect(`/room?code=${h.room}&protocol=3&name=Sen`);
  assert.equal((await late.next('error')).code, 'match_started');
  await closeAll([host, ...contenders]);
});

test('v3 Unicode names, host-only settings and reconnect reservations are validated before start', async () => {
  for (const name of ['', ' ', '\u0000\u202E', '<script>', 'A'.repeat(21), '😀'.repeat(21)]) {
    const bad = connect(`/room?mode=create&protocol=3&name=${encodeURIComponent(name)}`, ORIGIN, { 'CF-Connecting-IP': `invalid-${++createId}` });
    assert.equal((await bad.next('error')).code, 'invalid_name');
  }
  const host = connect('/room?mode=create&protocol=3&name=' + encodeURIComponent('\u2000 Åsa\u0000\u202E\u2028\u2029 😀  \u3000'), ORIGIN, { 'CF-Connecting-IP': `name-${++createId}` });
  const h = await host.next('welcome'); assert.equal(h.roster[0].name, 'Åsa 😀');
  host.send({ type: 'start' }); const notReady = await host.next('error');
  assert.equal(notReady.code, 'not_ready'); assert.equal(notReady.fatal, false);
  const guest = connect(`/room?code=${h.room}&protocol=3&name=${encodeURIComponent('😀'.repeat(20))}`), g = await guest.next('welcome');
  assert.equal([...g.roster[1].name].length, 20);
  for (const message of [{ type: 'start' }, { type: 'lobby', map_id: 2 }]) {
    guest.send(message); assert.equal((await guest.next('error')).code, 'forbidden');
  }
  guest.send({ type: 'rename', name: '  Новое\u0007 имя  ' });
  assert.equal((await host.next('presence', m => m.roster[1]?.name === 'Новое имя')).roster[1].name, 'Новое имя');
  guest.send({ type: 'rename', name: '<b>Name</b>' }); assert.equal((await guest.next('error')).code, 'invalid_name');
  host.send({ type: 'lobby', capacity: 2, map_id: 3 });
  const settings = await host.next('presence', m => m.capacity === 2); assert.equal(settings.map_id, 3);
  await guest.close(); const disconnected = await host.next('presence', m => m.roster[1]?.connected === false);
  assert.equal(disconnected.roster[1].name, 'Новое имя'); assert.equal(disconnected.can_start, false);
  host.send({ type: 'start' }); assert.equal((await host.next('error')).code, 'not_ready');
  const stranger = connect(`/room?code=${h.room}&protocol=3&name=Stranger`); assert.equal((await stranger.next('error')).code, 'room_full');
  const resumed = connect(`/room?code=${h.room}&protocol=3&token=${g.token}&name=Ignored`), r = await resumed.next('welcome');
  assert.equal(r.seat, 1); assert.equal(r.roster[1].name, 'Новое имя');
  await start([host, resumed], 3);
  resumed.send({ type: 'rename', name: 'Too late' }); assert.equal((await resumed.next('error')).code, 'match_started');
  await closeAll([host, resumed]);
});

test('v3 mixed versions never reserve a seat or replace an authenticated connection', async () => {
  const { host, h } = await room(1);
  for (const version of ['', '&protocol=1', '&protocol=2']) {
    const wrong = connect(`/room?code=${h.room}` + version);
    assert.equal((await wrong.next('error')).code, 'version_mismatch');
    const wrongResume = connect(`/room?code=${h.room}&token=${h.token}` + version);
    assert.equal((await wrongResume.next('error')).code, 'version_mismatch');
  }
  host.send({ type: 'ping' }); await host.next('pong');
  const guest = connect(`/room?code=${h.room}&protocol=3&name=Second`), g = await guest.next('welcome');
  assert.equal(g.seat, 1); assert.equal(g.roster.length, 2);
  const invalid = connect(`/room?code=${h.room}&protocol=3&token=${'a'.repeat(64)}`);
  assert.equal((await invalid.next('error')).code, 'invalid_token');
  const replacement = connect(`/room?code=${h.room}&protocol=3&token=${g.token}`), r = await replacement.next('welcome');
  assert.equal(r.seat, 1); assert.equal(r.roster.length, 2);
  await host.next('presence', p => p.guest_connected);
  await new Promise(resolve => setTimeout(resolve, 40));
  assert.notEqual(guest.ws.readyState, WebSocket.OPEN);
  replacement.send({ type: 'ping' }); await replacement.next('pong');
  await closeAll([host, replacement]);
});

test('v3 broadcasts all six states, gates each authenticated active seat and sanitizes target input', async () => {
  const { host, peers } = await room(); await start(peers);
  for (let seat = 1; seat <= 5; seat++) {
    await state(peers, seat, snapshotV3(6, { active: seat, target: 0, turn: seat }));
    peers[seat].send({ ...input(1, seat), seat: (seat % 5) + 1, owner: 99, hp: 1000 });
    const m = await host.next('input');
    assert.equal(m.seat, seat); assert.equal(m.target, 0); assert.equal(m.owner, undefined); assert.equal(m.hp, undefined);
    peers[seat].send(input(1, seat)); await noInput(host, peers[seat]); // Per-seat duplicate.
    const wrongSeat = seat === 5 ? 1 : seat + 1;
    peers[wrongSeat].send(input(999, seat)); await noInput(host, peers[wrongSeat]);
  }
  for (const target of [-1, 6, 5, '0', null, {}, 1.5]) {
    peers[5].send(input(2, 5, target)); assert.equal((await peers[5].next('error')).code, 'bad_message');
  }
  const dead = snapshotV3(6, { active: 5, target: 0, turn: 5 }); dead.fighters[3].hp = 0;
  await state(peers, 7, dead);
  peers[5].send(input(2, 5, 3)); assert.equal((await peers[5].next('error')).code, 'bad_message');
  peers[5].send({ ...input(2, 5, 2), action: 'fire' });
  assert.equal((await host.next('input')).target, 2);
  peers[3].send({ type: 'state', seq: 80, snapshot: dead }); assert.equal((await peers[3].next('error')).code, 'forbidden');
  host.send(input(80, 5)); assert.equal((await host.next('error')).code, 'forbidden');
  await closeAll(peers);
});

test('v3 validates exact roster length, bounded inventory/projectiles and living aim/winner consistency', async () => {
  const { host, peers } = await room(); await start(peers);
  await state(peers, 1, snapshotV3(6));
  const invalid = [
    snapshotV3(2), snapshotV3(7), snapshotV3(6, { schema: 2 }),
    snapshotV3(6, { padding: 'x'.repeat(62_000) }),
    snapshotV3(6, { freedom: [1, 1] }), snapshotV3(6, { freedom: [1, 1, 1, 1, 1, 2] }),
    snapshotV3(6, { active: 6 }), snapshotV3(6, { target: 6 }), snapshotV3(6, { target: 0 }),
    snapshotV3(6, { target: '1' }), snapshotV3(6, { phase: 'title' }), snapshotV3(6, { winner: 1 }),
    snapshotV3(6, { phase: 'over', winner: 0 }), snapshotV3(6, { map_id: 4 }),
    snapshotV3(6, { projectile: projectile({ owner: 5, target: 5 }) }),
    snapshotV3(6, { projectile: projectile({ owner: 6, target: 0 }) }),
    snapshotV3(6, { fragments: [projectile({ weapon: 4, owner: 5, target: -1 })] }),
    snapshotV3(6, { fragments: Array(6).fill(projectile({ weapon: 4 })) })
  ];
  const deadAim = snapshotV3(6); deadAim.fighters[0].hp = 0; invalid.push(deadAim);
  const deadTarget = snapshotV3(6); deadTarget.fighters[1].hp = 0; invalid.push(deadTarget);
  const badHealth = snapshotV3(6); badHealth.fighters[4].hp = 101; invalid.push(badHealth);
  for (let i = 0; i < invalid.length; i++) {
    host.send({ type: 'state', seq: i + 2, snapshot: invalid[i] });
    assert.equal((await host.next('error')).code, 'bad_message', 'invalid case ' + i);
  }
  const settle = snapshotV3(6, { phase: 'settle', active: 5, target: 4, freedom: [0, 1, 0, 1, 1, 0],
    projectile: projectile({ weapon: 3, owner: 5, target: 4 }),
    fragments: [projectile({ weapon: 4, owner: 5, target: 4 })] });
  settle.fighters[5].hp = 0; settle.fighters[4].hp = 0;
  await state(peers, 90, settle);
  const won = snapshotV3(6, { phase: 'over', winner: 4 });
  won.fighters.forEach((f, seat) => { f.hp = seat === 4 ? 51 : 0; });
  await state(peers, 91, won);
  const drawn = snapshotV3(6, { phase: 'over', winner: -1 }); drawn.fighters.forEach(f => { f.hp = 0; });
  await state(peers, 92, drawn);
  await closeAll(peers);
});

test('v3 pauses for disconnected living players or host but not eliminated guests', async () => {
  const { host, h, peers, welcomes } = await room(); await start(peers);
  await state(peers, 1, snapshotV3(6, { active: 1, target: 2 }));
  await peers[5].close(); const missing = await host.next('presence', p => p.roster[5]?.connected === false);
  assert.equal(missing.playable, false); assert.equal(missing.roster[5].alive, true);
  peers[1].send(input(1, 1, 2)); await noInput(host, peers[1]);
  const resumed = connect(`/room?code=${h.room}&protocol=3&token=${welcomes[5].token}`); await resumed.next('welcome'); peers[5] = resumed;
  await host.next('presence', p => p.roster[5]?.connected === true);
  peers[1].send(input(1, 1, 2)); assert.equal((await host.next('input')).seat, 1);
  const eliminated = snapshotV3(6, { active: 1, target: 2 }); eliminated.fighters[5].hp = 0;
  await state(peers, 2, eliminated); await peers[5].close();
  const absentDead = await host.next('presence', p => p.roster[5]?.connected === false);
  assert.equal(absentDead.playable, true); assert.equal(absentDead.roster[5].alive, false);
  peers[1].send(input(2, 1, 2)); assert.equal((await host.next('input')).seq, 2);
  eliminated.fighters[0].hp = 0; await state(peers, 3, eliminated);
  await host.close(); const hostGone = await peers[1].next('presence', p => !p.host_connected);
  assert.equal(hostGone.playable, false);
  const host2 = connect(`/room?code=${h.room}&protocol=3&token=${h.token}`), hr = await host2.next('welcome');
  assert.equal(hr.seat, 0); assert.equal(hr.roster[0].alive, false); assert.equal(hr.playable, true);
  peers[1].send(input(3, 1, 2)); assert.equal((await host2.next('input')).seat, 1);
  peers[0] = host2; await closeAll(peers);
});

test('v3 six names, roles, per-seat input sequence, fragments and map persist through full SQLite restart', async () => {
  const { host, h, peers, welcomes } = await room(); await start(peers, 4);
  for (let seat = 1; seat < 6; seat++) {
    await state(peers, seat, snapshotV3(6, { active: seat, target: 0, turn: seat, map_id: 4 }));
    peers[seat].send(input(70 + seat, seat)); await host.next('input');
  }
  const saved = snapshotV3(6, { phase: 'flying', active: 5, target: 4, turn: 5, map_id: 4,
    freedom: [0, 1, 0, 1, 1, 0], craters: [[510, 351, 57]], terrain_version: 1,
    projectile: projectile({ weapon: 3, owner: 5, target: 4 }),
    fragments: [projectile({ weapon: 4, owner: 5, target: 2 }), projectile({ weapon: 4, owner: 5, target: 4 })] });
  await state(peers, 37, saved); await closeAll(peers);
  await mf.dispose(); mf = new Miniflare(options); base = (await mf.ready).toString().replace('http:', 'ws:').replace(/\/$/, '');
  const resumed = [];
  for (let seat = 0; seat < 6; seat++) {
    const peer = connect(`/room?code=${h.room}&protocol=3&token=${welcomes[seat].token}`), r = await peer.next('welcome');
    resumed.push(peer); assert.equal(r.seat, seat); assert.equal(r.protocol, 3); assert.equal(r.started, true);
    assert.equal(r.map_id, 4); assert.equal(r.capacity, 6); assert.equal(r.seq, 37);
    assert.equal(r.input_seq, seat ? 70 + seat : 0); assert.deepEqual(r.snapshot, saved);
    assert.deepEqual(r.roster.map(p => p.name), ['Värd', 'Spelare 1', 'Spelare 2', 'Spelare 3', 'Spelare 4', 'Spelare 5']);
  }
  const p = await resumed[0].next('presence', p => p.roster.every(s => s.connected)); assert.equal(p.playable, true);
  await state(resumed, 38, { ...saved, phase: 'aim', projectile: {}, fragments: [] });
  resumed[5].send(input(75, 5, 4)); await noInput(resumed[0], resumed[5]);
  resumed[5].send(input(76, 5, 4)); assert.equal((await resumed[0].next('input')).seq, 76);
  await closeAll(resumed);
});

test('v3 lobby settings and reserved names survive full restart before host starts', async () => {
  const { h, peers, welcomes } = await room(3, '&capacity=4&map_id=2');
  await closeAll(peers);
  await mf.dispose(); mf = new Miniflare(options); base = (await mf.ready).toString().replace('http:', 'ws:').replace(/\/$/, '');
  const resumed = [];
  for (let seat = 0; seat < 3; seat++) {
    const peer = connect(`/room?code=${h.room}&protocol=3&token=${welcomes[seat].token}`), r = await peer.next('welcome');
    resumed.push(peer); assert.equal(r.started, false); assert.equal(r.snapshot, null); assert.equal(r.map_id, 2); assert.equal(r.capacity, 4);
    assert.equal(r.roster.length, 3); assert.equal(r.roster[seat].name, welcomes[seat].roster[seat].name);
  }
  await start(resumed, 2); await state(resumed, 1, snapshotV3(3, { map_id: 2 }));
  await closeAll(resumed);
});

test('v3 payload and lobby write rates remain bounded and errors preserve valid seats', async () => {
  const { host, h, peers } = await room(2);
  for (let i = 0; i < 4; i++) {
    host.send({ type: 'lobby', map_id: i }); await host.next('presence', p => p.map_id === i);
  }
  host.send({ type: 'lobby', map_id: 4 });
  const limited = await host.next('error'); assert.equal(limited.code, 'rate_limited'); assert.equal(limited.fatal, false);
  host.send({ type: 'ping' }); await host.next('pong');
  peers[1].ws.send('x'.repeat(65_537));
  const tooBig = await peers[1].next('error'); assert.equal(tooBig.code, 'bad_message'); assert.equal(tooBig.fatal, true);
  const preserved = await host.next('presence', p => p.roster[1]?.connected === false);
  assert.equal(preserved.roster.length, 2); assert.equal(preserved.map_id, 3);
  const stranger = connect(`/room?code=${h.room}&protocol=3&name=Third`), t = await stranger.next('welcome');
  assert.equal(t.seat, 2); assert.equal(t.roster[1].connected, false);
  await closeAll([host, stranger]);
});

test('v3 expires and removes persisted names, seats and match state using the room alarm', async () => {
  await mf.dispose();
  const fixture = `import { DurableObject } from 'cloudflare:workers';
    export default { fetch(request, env) { return env.ROOMS.get(env.ROOMS.idFromName('EXPRY222')).fetch(request); } };
    export class GameRoom extends DurableObject {
      async fetch(request) { const room = await request.json(); await this.ctx.storage.put('room', room);
        await this.ctx.storage.setAlarm(room.expires_at); return new Response('seeded'); }
      async alarm() {}
    }`;
  mf = new Miniflare({ ...convertV4MiniflareOptions({ port: 0, workers: [{ name: 'kraterkompisar-online', modules: true,
    script: fixture, compatibilityDate: '2026-10-01', durableObjects: { ROOMS: { className: 'GameRoom', useSQLite: true } },
    bindings: { ALLOWED_ORIGIN: ORIGIN } }] }), resourcePersistencePath: persistence });
  const token = 'c'.repeat(64);
  const seeded = await fetch((await mf.ready).toString(), { method: 'POST', body: JSON.stringify({
    code: 'EXPRY222', protocol: 3, expires_at: Date.now() + 2000,
    token_hashes: [createHash('sha256').update(token).digest('hex')], names: ['Temporary'],
    capacity: 6, map_id: 0, started: false, input_seqs: [0], seq: 0, input_seq: 0, snapshot: null
  }) }); assert.equal(await seeded.text(), 'seeded');
  await mf.dispose(); mf = new Miniflare(options); base = (await mf.ready).toString().replace('http:', 'ws:').replace(/\/$/, '');
  const host = connect(`/room?code=EXPRY222&protocol=3&token=${token}`);
  const h = await host.next('welcome'); assert.equal(h.roster[0].name, 'Temporary');
  assert.equal((await host.next('error')).code, 'room_expired');
  const old = connect(`/room?code=EXPRY222&protocol=3&token=${token}`);
  assert.equal((await old.next('error')).code, 'room_not_found');
});

test('v3 delayed delivery burst stays connected, relays latest state and retains rate protection', async () => {
  const { host, peers } = await room(6);
  await start(peers);
  // 5 seconds of ordinary 10Hz states delivered together by a stalled uplink.
  const value = snapshotV3(6, { craters: Array.from({ length: 500 }, (_, i) => [i * 2, 350, 35]), terrain_version: 500 });
  for (let seq = 1; seq <= 50; seq++) host.send({ type: 'state', seq, snapshot: value });
  await Promise.all(peers.slice(1).map(p => p.next('state', m => m.seq === 50)));
  host.send({ type: 'ping' }); await host.next('pong');
  assert.equal(host.ws.readyState, WebSocket.OPEN);
  assert.equal(host.queue.some(m => m.type === 'error'), false);
  // Abuse is still bounded rather than disabling the limiter to mask stalls.
  for (let i = 0; i < 200; i++) host.send({ type: 'ping' });
  const error = await host.next('error');
  assert.equal(error.code, 'rate_limited'); assert.equal(error.fatal, true);
  await closeAll(peers);
});

test('release fire preserves exact optional power and legacy input shape across all protocols', async () => {
  for (const protocol of [1, 2, 3]) {
    let peers;
    if (protocol === 3) {
      ({ peers } = await room(2));
      await start(peers);
    } else {
      const { host, guest } = await pair(protocol);
      peers = [host, guest];
    }
    const [host, guest] = peers;
    const value = protocol === 3 ? snapshotV3(2, { active: 1, target: 0 })
      : protocol === 2 ? snapshotV2({ active: 1 }) : snapshot({ active: 1 });
    await state(peers, 1, value);
    let seq = 0;
    for (const shotPower of [undefined, 12, 57.375, 100]) {
      const sent = { type: 'input', seq: ++seq, turn: 1, move: 0, angle_axis: 0, power_axis: 0, action: 'fire',
        ...(shotPower === undefined ? {} : { shot_power: shotPower }) };
      // Role spoofing and unknown fields must never widen the whitelist.
      guest.send({ ...sent, seat: 0, owner: 0, power: 999, injected: true });
      assert.deepEqual(await host.next('input'), { ...sent, seat: 1 });
    }
    await closeAll(peers);
  }
});

test('v3 release power rejects wrong types, nonfinite values, bounds and non-fire injection', async () => {
  const { host, peers } = await room(2);
  const guest = peers[1];
  await start(peers);
  await state(peers, 1, snapshotV3(2, { active: 1, target: 0 }));
  const fire = { ...input(1), action: 'fire' };
  for (const shotPower of [null, '70', true, false, [], {}, 0, 11.999, 100.001, -1, NaN, Infinity, -Infinity]) {
    // JSON encodes NaN/Infinity as null, which must not be treated as absence.
    guest.send({ ...fire, shot_power: shotPower });
    const error = await guest.next('error');
    assert.equal(error.code, 'bad_message', String(shotPower));
    assert.equal(error.fatal, false);
  }
  // Valid JSON numeric overflow reaches validation as +/-Infinity.
  for (const rawNumber of ['1e400', '-1e400']) {
    guest.ws.send(JSON.stringify({ ...fire, shot_power: 'OVERFLOW' }).replace('"OVERFLOW"', rawNumber));
    assert.equal((await guest.next('error')).code, 'bad_message');
  }
  for (const action of [undefined, 'jump', 'weapon', 'target']) {
    guest.send({ ...input(1), ...(action ? { action } : {}), shot_power: 70 });
    assert.equal((await guest.next('error')).code, 'bad_message');
  }
  await noInput(host, guest);
  // Invalid controls neither consume the sequence nor disconnect the guest.
  guest.send({ ...fire, shot_power: 63.125 });
  assert.deepEqual(await host.next('input'), { ...fire, seat: 1, shot_power: 63.125 });
  await closeAll(peers);
});

test('literal NaN release power is rejected as invalid JSON and never forwarded', async () => {
  const { host, peers } = await room(2);
  await start(peers);
  await state(peers, 1, snapshotV3(2, { active: 1, target: 0 }));
  peers[1].ws.send(JSON.stringify({ ...input(1), action: 'fire', shot_power: 'NAN' }).replace('"NAN"', 'NaN'));
  const error = await peers[1].next('error');
  assert.equal(error.code, 'bad_message'); assert.equal(error.fatal, true);
  host.send({ type: 'ping' }); await host.next('pong');
  assert.equal(host.queue.some(m => m.type === 'input'), false);
  await closeAll(peers);
});

test('v3 optional charge capability survives full snapshot relay and guest reconnect', async () => {
  const { h, peers, welcomes } = await room(2);
  await start(peers);
  // Old hosts omit the capability; their unchanged snapshot remains valid.
  await state(peers, 1, snapshotV3(2));
  const charged = snapshotV3(2, { charge_controls: 1 });
  await state(peers, 2, charged);
  await peers[1].close();
  const resumed = connect(`/room?code=${h.room}&protocol=3&token=${welcomes[1].token}`);
  const welcome = await resumed.next('welcome');
  assert.equal(welcome.protocol, 3);
  assert.deepEqual(welcome.snapshot, charged);
  await closeAll([peers[0], resumed]);
});
