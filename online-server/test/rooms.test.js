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
const persistence = mkdtempSync(join(tmpdir(), 'krater-rooms-test-'));
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

test('public health endpoint reports protocol, with no private state', async () => {
  const response = await fetch(base.replace('ws:', 'http:') + '/health');
  assert.deepEqual(await response.json(), { ok: true, game: 'Kraterkompisar', protocol: 3, supported_protocols: [1, 2, 3], transport_revision: 1, shot_power_revision: 1 });
});

test('real sockets create/join, relay terrain state and only the correct guest turn', async () => {
  const { host, guest, h, g } = await pair();
  assert.equal(h.protocol, 1); assert.equal(g.protocol, 1);
  assert.match(h.room, /^[A-HJ-NP-Z2-9]{8}$/);
  assert.equal(h.seat, 0); assert.equal(g.seat, 1);
  assert.equal(h.host, true); assert.equal(g.host, false);
  assert.match(h.token, /^[a-f0-9]{64}$/); assert.notEqual(h.token, g.token);
  assert.equal(g.peer_connected, true);
  const s = snapshot({ turn: 2, active: 1, shots: 1, craters: [[500, 350, 57]], terrain_version: 1 });
  host.send({ type: 'state', seq: 1, commit: true, snapshot: s });
  assert.deepEqual((await guest.next('state')).snapshot, s);
  guest.send({ type: 'input', seq: 1, turn: 2, move: -1, angle_axis: 0, power_axis: 1, action: 'jump' });
  const input = await host.next('input');
  assert.equal(input.seat, 1); assert.equal(input.action, 'jump');
  guest.send({ type: 'input', seq: 2, turn: 1, move: 1, angle_axis: 0, power_axis: 0 });
  guest.send({ type: 'ping' }); await guest.next('pong');
  assert.equal(host.queue.filter(m => m.type === 'input').length, 0);
  guest.send({ type: 'state', seq: 99, snapshot: s });
  assert.equal((await guest.next('error')).code, 'forbidden');
  host.send({ type: 'input', seq: 99, turn: 2, move: 0, angle_axis: 0, power_axis: 0 });
  assert.equal((await host.next('error')).code, 'forbidden');
  await host.close(); await guest.close();
});

test('room isolation, third player rejected, invalid resume cannot steal a seat', async () => {
  const { host, guest, h } = await pair();
  const third = connect('/room?code=' + h.room);
  assert.equal((await third.next('error')).code, 'room_full');
  const intruder = connect('/room?code=' + h.room + '&token=' + 'a'.repeat(64));
  assert.equal((await intruder.next('error')).code, 'invalid_token');
  const missing = connect('/room?code=AAAAAAAA');
  assert.equal((await missing.next('error')).code, 'room_not_found');
  const other = connect('/room?mode=create');
  const o = await other.next('welcome'); assert.notEqual(o.room, h.room);
  host.send({ type: 'state', seq: 1, commit: true, snapshot: snapshot() });
  await guest.next('state');
  other.send({ type: 'ping' }); await other.next('pong');
  assert.equal(other.queue.filter(m => m.type === 'state').length, 0);
  await host.close(); await guest.close(); await other.close();
});

test('disconnect and resume preserve seat, state, input sequence, and presence', async () => {
  const { host, guest, h, g } = await pair();
  const s = snapshot({ turn: 2, active: 1 });
  host.send({ type: 'state', seq: 12, commit: true, snapshot: s }); await guest.next('state');
  guest.send({ type: 'input', seq: 8, turn: 2, move: 0, angle_axis: 0, power_axis: 0 }); await host.next('input');
  await guest.close();
  await host.next('presence', m => !m.guest_connected);
  const resumed = connect('/room?code=' + h.room + '&token=' + g.token);
  const r = await resumed.next('welcome');
  assert.equal(r.seat, 1); assert.equal(r.token, g.token); assert.equal(r.seq, 12); assert.equal(r.input_seq, 8);
  assert.deepEqual(r.snapshot, s);
  await host.next('presence', m => m.guest_connected);
  await host.close(); await resumed.next('presence', m => !m.host_connected);
  const newHost = connect('/room?code=' + h.room + '&token=' + h.token);
  const rh = await newHost.next('welcome'); assert.equal(rh.seat, 0); assert.deepEqual(rh.snapshot, s);
  await resumed.next('presence', m => m.host_connected);
  newHost.send({ type: 'state', seq: rh.seq + 1, commit: true, snapshot: s });
  assert.equal((await resumed.next('state')).seq, 13);
  await newHost.close(); await resumed.close();
});

test('malformed, oversized, spoofed-origin and excessive traffic are rejected', async () => {
  const host = connect('/room?mode=create'); await host.next('welcome');
  host.send({ type: 'state', seq: 1, snapshot: snapshot({ craters: [[0, 0, 100000]], terrain_version: 1 }) });
  assert.equal((await host.next('error')).code, 'bad_message');
  host.ws.send('x'.repeat(65537));
  assert.equal((await host.next('error')).code, 'bad_message');
  const blocked = connect('/room?mode=create', 'https://evil.example');
  const status = await new Promise(resolve => blocked.ws.once('unexpected-response', (_req, response) => { resolve(response.statusCode); response.destroy(); }));
  assert.equal(status, 403);
  const spam = connect('/room?mode=create'); await spam.next('welcome');
  for (let i = 0; i < 200; i++) spam.send({ type: 'ping' });
  assert.equal((await spam.next('error')).code, 'rate_limited');
});

test('exactly one seat is issued under simultaneous joins', async () => {
  const host = connect('/room?mode=create'), h = await host.next('welcome');
  const guests = Array.from({length: 12}, () => connect('/room?code=' + h.room));
  await Promise.all(guests.map(p => new Promise(resolve => {
    const timer = setInterval(() => { if (p.queue.some(m => ['welcome','error'].includes(m.type))) {clearInterval(timer); resolve();} },10);
    setTimeout(() => {clearInterval(timer); resolve();},2000);
  })));
  const messages = guests.flatMap(p => p.queue.filter(m => ['welcome','error'].includes(m.type)));
  assert.equal(messages.filter(m => m.type === 'welcome').length,1);
  assert.equal(messages.filter(m => m.code === 'room_full').length,11);
  assert.equal(messages.find(m => m.type === 'welcome').seat,1);
  assert.equal(messages.some(m => JSON.stringify(m).includes(h.token)),false);
  await host.close(); await Promise.all(guests.map(p => p.close()));
});
test('live resume replaces only own socket and old close leaves presence intact', async () => {
  const {host,guest,h,g} = await pair();
  const resumed = connect('/room?code=' + h.room + '&token=' + g.token);
  const r = await resumed.next('welcome'); assert.equal(r.seat,1);
  await new Promise(resolve => setTimeout(resolve,100));
  assert.notEqual(guest.ws.readyState, WebSocket.OPEN);
  host.send({type:'state',seq:1,commit:true,snapshot:snapshot({turn:2,active:1})});
  await resumed.next('state');
  resumed.send({type:'input',seq:1,turn:2,move:1,angle_axis:0,power_axis:0});
  const input=await host.next('input');assert.equal(input.seat,1);
  assert.equal(host.queue.filter(m => m.type === 'presence').at(-1).guest_connected,true);
  assert.equal(r.token.includes(h.token),false);
  await host.close();await resumed.close();
});


test('guest controls stop while host snapshot is paused', async () => {
  const { host, guest } = await pair();
  host.send({ type: 'state', seq: 1, commit: true, snapshot: snapshot({ turn: 2, active: 1, paused: true }) });
  await guest.next('state');
  guest.send({ type: 'input', seq: 1, turn: 2, move: 1, angle_axis: 0, power_axis: 0 });
  guest.send({ type: 'ping' }); await guest.next('pong');
  assert.equal(host.queue.filter(m => m.type === 'input').length, 0);
  host.send({ type: 'state', seq: 2, commit: true, snapshot: snapshot({ turn: 2, active: 1, paused: false }) });
  await guest.next('state');
  guest.send({ type: 'input', seq: 2, turn: 2, move: 1, angle_axis: 0, power_axis: 0 });
  assert.equal((await host.next('input')).seq, 2);
  await host.close(); await guest.close();
});

test('closed room survives complete runtime disposal with roles, latest state and input sequence', async () => {
 const {host,guest,h,g} = await pair();
 const state = snapshot({turn:2,active:1,craters:[[510,351,57]],terrain_version:1});
 host.send({type:'state',seq:37,commit:true,snapshot:state});await guest.next('state');
 guest.send({type:'input',seq:81,turn:2,move:0,angle_axis:0,power_axis:0});await host.next('input');
 await guest.close();await host.next('presence',m=>!m.guest_connected);
 await host.close();
 await mf.dispose();
 mf = new Miniflare(options);
 base = (await mf.ready).toString().replace('http:','ws:').replace(/\/$/,'');
 const host2 = connect('/room?code='+h.room+'&token='+h.token);
 const hr = await host2.next('welcome');
 assert.equal(hr.seat,0);assert.equal(hr.seq,37);assert.equal(hr.input_seq,81);assert.deepEqual(hr.snapshot,state);
 const guest2 = connect('/room?code='+h.room+'&token='+g.token);
 const gr = await guest2.next('welcome');
 assert.equal(gr.seat,1);assert.equal(gr.seq,37);assert.equal(gr.input_seq,81);assert.deepEqual(gr.snapshot,state);
 await host2.next('presence',m=>m.guest_connected);
 guest2.send({type:'input',seq:82,turn:2,move:1,angle_axis:0,power_axis:0});
 assert.equal((await host2.next('input')).seq,82);
 await guest2.close();await host2.close();
});

test('v2 negotiation rejects mismatched joins and resumes before consuming or replacing seats', async () => {
  const host = connect('/room?mode=create&protocol=2');
  const h = await host.next('welcome'); assert.equal(h.protocol, 2);
  for (const version of ['', '&protocol=1']) {
    const wrong = connect('/room?code=' + h.room + version);
    assert.equal((await wrong.next('error')).code, 'version_mismatch');
  }
  const guest = connect('/room?code=' + h.room + '&protocol=2');
  const g = await guest.next('welcome'); assert.equal(g.protocol, 2); assert.equal(g.seat, 1);
  await host.next('presence', m => m.guest_connected);
  for (const token of [h.token, g.token]) {
    const wrong = connect('/room?code=' + h.room + '&token=' + token);
    assert.equal((await wrong.next('error')).code, 'version_mismatch');
  }
  host.send({ type: 'state', seq: 1, snapshot: snapshotV2() }); await guest.next('state');
  assert.equal(host.ws.readyState, WebSocket.OPEN); assert.equal(guest.ws.readyState, WebSocket.OPEN);
  await host.close(); await guest.close();

  // A caller-controlled header cannot convert a legacy request into protocol 2.
  const legacy = connect('/room?mode=create', ORIGIN, { 'X-Protocol': '2', 'X-Room-Protocol': '2' });
  const l = await legacy.next('welcome'); assert.equal(l.protocol, 1);
  const wrong = connect('/room?code=' + l.room + '&protocol=2');
  assert.equal((await wrong.next('error')).code, 'version_mismatch');
  const legacyGuest = connect('/room?code=' + l.room + '&protocol=1');
  assert.equal((await legacyGuest.next('welcome')).seat, 1);
  await legacy.close(); await legacyGuest.close();
});

test('unknown, malformed and duplicate protocol parameters are rejected explicitly', async () => {
  for (const version of ['0', '4', '-1', '2.0', '02', 'NaN', 'Infinity', '', 'true', '2&protocol=1', '2&protocol=2']) {
    const bad = connect('/room?mode=create&protocol=' + version);
    assert.equal((await bad.next('error')).code, 'version_mismatch', version);
  }
});

test('v2 relays complete maps, inventories, projectiles and fragments with unchanged host authority', async () => {
  const { host, guest, h, g } = await pair(2);
  assert.equal(h.protocol, 2); assert.equal(g.protocol, 2);
  for (let map = 0; map <= 4; map++) {
    const s = snapshotV2({ map_id: map, weapon: Math.min(map, 3), freedom: [map % 2, 0],
      phase: 'flying', projectile: projectile({ weapon: Math.min(map, 3), owner: map % 2, target: 1 - map % 2 }),
      fragments: Array.from({ length: 5 }, (_, i) => projectile({ weapon: 4, age: i, bounces: i, owner: i % 2, target: 1 - i % 2 })),
      craters: [[400 + map, 350, 57]], terrain_version: 1, trail: [[600, 150], [640, 140]] });
    host.send({ type: 'state', seq: map + 1, commit: true, snapshot: s });
    assert.deepEqual((await guest.next('state')).snapshot, s);
  }
  guest.send({ type: 'state', seq: 99, snapshot: snapshotV2() });
  assert.equal((await guest.next('error')).code, 'forbidden');
  host.send({ type: 'state', seq: 6, snapshot: snapshotV2({ turn: 2, active: 1, freedom: [0, 0] }) });
  await guest.next('state');
  guest.send({ type: 'input', seq: 1, turn: 2, move: 0, angle_axis: 0, power_axis: 0, action: 'weapon' });
  assert.equal((await host.next('input')).action, 'weapon');
  await host.close(); await guest.close();
});

test('v2 bounds and object validation reject malformed state without changing the accepted snapshot', async () => {
  const { host, guest, h, g } = await pair(2);
  const good = snapshotV2({ map_id: 4, weapon: 3, freedom: [0, 1], projectile: projectile({ age: 10, bounces: 4 }) });
  host.send({ type: 'state', seq: 1, snapshot: good }); await guest.next('state');
  const invalid = [];
  const cases = (field, values) => values.forEach(value => invalid.push([field + '=' + JSON.stringify(value), snapshotV2({ [field]: value })]));
  cases('schema', [1, 3, '2', null]);
  cases('map_id', [undefined, -1, 5, 0.5, '1', null]);
  cases('freedom', [undefined, null, {}, [], [1], [1, 1, 1], [-1, 0], [0, 2], [0.5, 0], ['1', 0], [true, 0]]);
  cases('weapon', [-1, 4, 0.5, '1', null]);
  cases('projectile', [null, [], 'projectile', 1, true, { pos: [0, 0] }]);
  cases('fragments', [undefined, null, {}, 'fragments', Array.from({ length: 6 }, () => projectile({ weapon: 4 })), [{}], [null], [[]], [true]]);
  for (const [field, values] of Object.entries({
    owner: [undefined, -1, 2, 0.5, '0', null], target: [undefined, -1, 2, 0.5, '1', null],
    bounces: [-1, 5, 0.5, '1'], age: [-1, 10.01, null, '1'],
    pos: [[10001, 0], [0], [0, 0, 0], ['0', 0], null], vel: [[0, -10001], {}, null]
  })) {
    for (const value of values) {
      invalid.push(['projectile.' + field, snapshotV2({ projectile: projectile({ [field]: value }) })]);
      invalid.push(['fragment.' + field, snapshotV2({ fragments: [projectile({ weapon: 4, [field]: value })] })]);
    }
  }
  for (const weapon of [-1, 4, 1.5, '2']) invalid.push(['projectile.weapon', snapshotV2({ projectile: projectile({ weapon }) })]);
  for (const weapon of [-1, 0, 1, 2, 3, 5, 4.5, '4']) invalid.push(['fragment.weapon', snapshotV2({ fragments: [projectile({ weapon })] })]);
  for (const owner of [0, 1]) {
    invalid.push(['projectile self-target', snapshotV2({ projectile: projectile({ owner, target: owner }) })]);
    invalid.push(['fragment self-target', snapshotV2({ fragments: [projectile({ weapon: 4, owner, target: owner })] })]);
  }
  for (const value of [null, [], 'snapshot', 1, true]) invalid.push(['snapshot object', value]);
  for (const value of [null, [], true, 'fighter']) invalid.push(['fighter object', snapshotV2({ fighters: [value, good.fighters[1]] })]);
  for (let i = 0; i < invalid.length; i++) {
    if (i % 30 === 0) await new Promise(resolve => setTimeout(resolve, 1050));
    const [label, state] = invalid[i];
    host.send({ type: 'state', seq: i + 2, snapshot: state });
    assert.equal((await host.next('error')).code, 'bad_message', label);
  }
  await guest.close(); await host.next('presence', m => !m.guest_connected);
  const resumed = connect('/room?code=' + h.room + '&token=' + g.token + '&protocol=2');
  const r = await resumed.next('welcome');
  assert.equal(r.seq, 1); assert.deepEqual(r.snapshot, good);
  await host.close(); await resumed.close();
});

test('explicit v1 clients keep schema 1 projectile rules and reject expanded weapons or schema 2', async () => {
  const { host, guest, h } = await pair(1); assert.equal(h.protocol, 1);
  const legacyProjectile = { pos: [400, 200], vel: [200, -30], age: 0.5, weapon: 1, bounces: 4 };
  const state = snapshot({ projectile: legacyProjectile, weapon: 1 });
  host.send({ type: 'state', seq: 1, snapshot: state });
  assert.deepEqual((await guest.next('state')).snapshot, state);
  for (const bad of [snapshotV2(), snapshot({ weapon: 2 }), snapshot({ projectile: { ...legacyProjectile, weapon: 2 } })]) {
    host.send({ type: 'state', seq: 2, snapshot: bad });
    assert.equal((await host.next('error')).code, 'bad_message');
  }
  await host.close(); await guest.close();
});

test('v2 complete snapshot, fixed protocol and roles survive reconnect and complete runtime disposal', async () => {
  const { host, guest, h, g } = await pair(2);
  const state = snapshotV2({ turn: 2, active: 1, map_id: 4, weapon: 3, freedom: [0, 1],
    projectile: projectile({ weapon: 3, owner: 1, target: 0 }),
    fragments: [projectile({ weapon: 4, owner: 1, target: 0, bounces: 4 })],
    craters: [[510, 351, 57]], terrain_version: 1, trail: [[400, 200]], paused: false });
  host.send({ type: 'state', seq: 37, commit: true, snapshot: state }); await guest.next('state');
  guest.send({ type: 'input', seq: 81, turn: 2, move: 0, angle_axis: 0, power_axis: 0 }); await host.next('input');
  await guest.close(); await host.next('presence', m => !m.guest_connected);
  const resumed = connect('/room?code=' + h.room + '&token=' + g.token + '&protocol=2');
  const r = await resumed.next('welcome'); assert.deepEqual(r.snapshot, state); assert.equal(r.input_seq, 81);
  await resumed.close(); await host.next('presence', m => !m.guest_connected); await host.close();
  await mf.dispose(); mf = new Miniflare(options);
  base = (await mf.ready).toString().replace('http:', 'ws:').replace(/\/$/, '');
  const wrong = connect('/room?code=' + h.room + '&token=' + h.token);
  assert.equal((await wrong.next('error')).code, 'version_mismatch');
  const host2 = connect('/room?code=' + h.room + '&token=' + h.token + '&protocol=2');
  const hr = await host2.next('welcome');
  assert.equal(hr.protocol, 2); assert.equal(hr.seat, 0); assert.equal(hr.seq, 37); assert.equal(hr.input_seq, 81); assert.deepEqual(hr.snapshot, state);
  const guest2 = connect('/room?code=' + h.room + '&token=' + g.token + '&protocol=2');
  const gr = await guest2.next('welcome'); assert.equal(gr.protocol, 2); assert.equal(gr.seat, 1); assert.deepEqual(gr.snapshot, state);
  await host2.next('presence', m => m.guest_connected);
  guest2.send({ type: 'input', seq: 82, turn: 2, move: 1, angle_axis: 0, power_axis: 0 });
  assert.equal((await host2.next('input')).seq, 82);
  await guest2.close(); await host2.close();
});

test('rooms stored before version negotiation remain v1 after upgrading the runtime', async () => {
  // Seed the exact old storage shape in a separate runtime. No test-only route or
  // storage mutation hook is added to the production Worker.
  await mf.dispose();
  const fixture = `import { DurableObject } from 'cloudflare:workers';
    export default { fetch(request, env) { return env.ROOMS.get(env.ROOMS.idFromName('LEGACY22')).fetch(request); } };
    export class GameRoom extends DurableObject {
      async fetch(request) { const room = await request.json(); await this.ctx.storage.put('room', room);
        await this.ctx.storage.setAlarm(room.expires_at); return new Response('seeded'); }
      async alarm() {}
    }`;
  mf = new Miniflare({ ...convertV4MiniflareOptions({ port: 0, workers: [{ name: 'kraterkompisar-online',
    modules: true, script: fixture, compatibilityDate: '2026-10-01',
    durableObjects: { ROOMS: { className: 'GameRoom', useSQLite: true } }, bindings: { ALLOWED_ORIGIN: ORIGIN }
  }] }), resourcePersistencePath: persistence });
  const token = 'b'.repeat(64), state = snapshot({ turn: 2, active: 1, weapon: 1 });
  const seeded = await fetch((await mf.ready).toString(), { method: 'POST', body: JSON.stringify({
    code: 'LEGACY22', expires_at: Date.now() + 3600000,
    token_hashes: [createHash('sha256').update(token).digest('hex'), null], seq: 7, input_seq: 3, snapshot: state
  }) });
  assert.equal(await seeded.text(), 'seeded');
  await mf.dispose(); mf = new Miniflare(options);
  base = (await mf.ready).toString().replace('http:', 'ws:').replace(/\/$/, '');
  const wrong = connect('/room?code=LEGACY22&protocol=2');
  assert.equal((await wrong.next('error')).code, 'version_mismatch');
  const host = connect('/room?code=LEGACY22&token=' + token);
  const h = await host.next('welcome');
  assert.equal(h.protocol, 1); assert.equal(h.seat, 0); assert.equal(h.seq, 7); assert.equal(h.input_seq, 3); assert.deepEqual(h.snapshot, state);
  const guest = connect('/room?code=LEGACY22&protocol=1');
  const g = await guest.next('welcome'); assert.equal(g.protocol, 1); assert.equal(g.seat, 1); assert.deepEqual(g.snapshot, state);
  await host.next('presence', m => m.guest_connected);
  host.send({ type: 'state', seq: 8, snapshot: state }); assert.deepEqual((await guest.next('state')).snapshot, state);
  host.send({ type: 'state', seq: 9, snapshot: snapshotV2() }); assert.equal((await host.next('error')).code, 'bad_message');
  await host.close(); await guest.close();
});
