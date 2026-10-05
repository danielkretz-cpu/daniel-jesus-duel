// Kraterkompisar: small, private rooms for two to six players. The host runs game physics.
// No accounts, analytics, chat, public room listing, or third-party calls.
import { DurableObject } from 'cloudflare:workers';

const PROTOCOL = 3;
const SUPPORTED_PROTOCOLS = [1, 2, 3];
const MAX_MESSAGE = 65_536;
const ROOM_TTL = 2 * 60 * 60 * 1000;
const ROOM_CODE = /^[A-HJ-NP-Z2-9]{8}$/;
const TOKEN = /^[a-f0-9]{64}$/;
const encoder = new TextEncoder();
const createBuckets = new Map(); // Best-effort edge protection; free-plan quotas remain the hard cap.

function randomHex(bytes = 32) {
  return [...crypto.getRandomValues(new Uint8Array(bytes))].map(n => n.toString(16).padStart(2, '0')).join('');
}
function randomCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return [...crypto.getRandomValues(new Uint8Array(8))].map(n => alphabet[n & 31]).join('');
}
async function tokenHash(token) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(token)))].map(n => n.toString(16).padStart(2, '0')).join('');
}
function socketError(code, message) {
  const pair = new WebSocketPair();
  pair[1].accept();
  pair[1].send(JSON.stringify({ type: 'error', code, message, fatal: true }));
  pair[1].close(1008, code);
  return new Response(null, { status: 101, webSocket: pair[0] });
}
function allowedOrigin(request, env) {
  const origin = request.headers.get('Origin');
  // Native Godot clients have no Origin. Origin is CSWSH protection, not authentication.
  if (!origin) return true;
  if (origin === env.ALLOWED_ORIGIN) return true;
  const host = new URL(request.url).hostname;
  return ['localhost', '127.0.0.1'].includes(host) && /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
}
function createAllowed(request) {
  const now = Date.now();
  // IPs exist only in this short-lived bounded map, never in room storage/logs.
  const key = request.headers.get('CF-Connecting-IP') || 'local';
  const old = createBuckets.get(key);
  if (old && now - old.at < 60_000) {
    old.n++;
    return old.n <= 10;
  }
  if (createBuckets.size >= 1024) createBuckets.clear();
  createBuckets.set(key, { at: now, n: 1 });
  return true;
}
function integer(value, min, max) { return Number.isSafeInteger(value) && value >= min && value <= max; }
function number(value, min, max) { return typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max; }
function vector(value, limit = 10000) { return Array.isArray(value) && value.length === 2 && value.every(n => number(n, -limit, limit)); }
function record(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function requestedProtocol(url) {
  const values = url.searchParams.getAll('protocol');
  // Only a missing parameter implies legacy v1. Reject ambiguous/unknown values.
  if (!values.length) return 1;
  return values.length === 1 && ['1', '2', '3'].includes(values[0]) ? Number(values[0]) : null;
}
function versionMismatch() {
  return socketError('version_mismatch', 'Spelversionerna passar inte ihop. Uppdatera spelet och skapa ett nytt rum.');
}
// Names are plain text; never HTML. Count Unicode code points, not UTF-16 units.
function cleanName(value) {
  if (typeof value !== 'string' || value.length > 200) return null;
  const name = value.replace(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu, '').trim();
  return [...name].length >= 1 && [...name].length <= 20 && !/[<>]/u.test(name) ? name : null;
}
function validV3Projectile(p, count, fragment = false) {
  if (!record(p)) return false;
  if (!fragment && !Object.keys(p).length) return true;
  return vector(p.pos) && vector(p.vel) && number(p.age, 0, 10)
    && integer(p.weapon, fragment ? 4 : 0, fragment ? 4 : 3)
    && integer(p.bounces, 0, 4) && integer(p.owner, 0, count - 1)
    && integer(p.target, 0, count - 1) && p.target !== p.owner;
}
function validV2Projectile(p, fragment = false) {
  if (!record(p)) return false;
  if (!fragment && !Object.keys(p).length) return true;
  return vector(p.pos) && vector(p.vel) && number(p.age, 0, 10)
    && integer(p.weapon, fragment ? 4 : 0, fragment ? 4 : 3)
    && integer(p.bounces, 0, 4) && integer(p.owner, 0, 1) && integer(p.target, 0, 1)
    && p.target === 1 - p.owner;
}
function validSnapshot(s, protocol, count = 2) {
  if (!record(s) || s.schema !== protocol) return false;
  if (!['title', 'aim', 'flying', 'settle', 'over'].includes(s.phase)) return false;
  if (s.paused !== undefined && typeof s.paused !== 'boolean') return false;
  if (!integer(count, 2, 6) || (protocol !== 3 && count !== 2)) return false;
  if (!integer(s.turn, 1, 10000) || !integer(s.active, 0, count - 1) || !integer(s.winner, -1, count - 1)) return false;
  if (!number(s.angle, 5, 85) || !number(s.power, 12, 100) || !integer(s.weapon, 0, protocol >= 2 ? 3 : 1)) return false;
  if (!number(s.wind, -100, 100) || !number(s.move_left, 0, 170.01) || !number(s.turn_clock, -10, 40.1) || !number(s.settle_clock, -20, 10)) return false;
  if (!integer(s.shots, 0, 10000) || !integer(s.hits, 0, 20000)) return false;
  if (!Array.isArray(s.fighters) || s.fighters.length !== count) return false;
  for (const f of s.fighters) {
    if (!f || !vector(f.pos) || !vector(f.vel) || !integer(f.hp, 0, 100) || ![-1, 1].includes(f.face) || typeof f.ground !== 'boolean') return false;
  }
  if (!Array.isArray(s.craters) || s.craters.length > 500 || s.terrain_version !== s.craters.length) return false;
  for (const c of s.craters) {
    if (!Array.isArray(c) || c.length !== 3 || !number(c[0], -200, 1500) || !number(c[1], -1500, 1000) || !number(c[2], 1, 100)) return false;
  }
  if (!Array.isArray(s.trail) || s.trail.length > 32 || !s.trail.every(v => vector(v))) return false;
  if (protocol === 3) {
    // Leave room for the resume credential and full roster in a welcome packet.
    if (encoder.encode(JSON.stringify(s)).length > MAX_MESSAGE - 4096) return false;
    if (!integer(s.map_id, 0, 4) || s.phase === 'title') return false;
    if (!Array.isArray(s.freedom) || s.freedom.length !== count || !s.freedom.every(n => integer(n, 0, 1))) return false;
    if (!integer(s.target, 0, count - 1) || s.target === s.active) return false;
    if (s.phase === 'aim' && (s.fighters[s.active].hp === 0 || s.fighters[s.target].hp === 0)) return false;
    const survivors = s.fighters.flatMap((f, seat) => f.hp > 0 ? [seat] : []);
    if (s.phase === 'over') {
      if (survivors.length > 1 || s.winner !== (survivors[0] ?? -1)) return false;
    } else if (s.winner !== -1) return false;
    if (!Array.isArray(s.fragments) || s.fragments.length > 5 || !s.fragments.every(p => validV3Projectile(p, count, true))) return false;
    return validV3Projectile(s.projectile, count);
  }
  if (protocol === 2) {
    if (!integer(s.map_id, 0, 4)) return false;
    if (!Array.isArray(s.freedom) || s.freedom.length !== 2 || !s.freedom.every(n => integer(n, 0, 1))) return false;
    if (!Array.isArray(s.fragments) || s.fragments.length > 5 || !s.fragments.every(p => validV2Projectile(p, true))) return false;
    return validV2Projectile(s.projectile);
  }
  // Legacy schema 1 keeps its existing projectile validation and weapon bounds.
  if (!s.projectile || typeof s.projectile !== 'object' || Array.isArray(s.projectile)) return false;
  if (Object.keys(s.projectile).length) {
    const p = s.projectile;
    if (!vector(p.pos) || !vector(p.vel) || !number(p.age, 0, 10) || !integer(p.weapon, 0, 1) || !integer(p.bounces, 0, 4)) return false;
  }
  return true;
}
function validInput(m, protocol = 1) {
  if (!integer(m.seq, 0, Number.MAX_SAFE_INTEGER) || !integer(m.turn, 1, 10000)) return false;
  if (![-1, 0, 1].includes(m.move) || ![-1, 0, 1].includes(m.angle_axis) || ![-1, 0, 1].includes(m.power_axis)) return false;
  if (m.aim !== undefined && (!Array.isArray(m.aim) || m.aim.length !== 2 || ![-1, 1].includes(m.aim[0]) || !number(m.aim[1], 5, 85))) return false;
  if (m.action !== undefined && !(protocol === 3 ? ['jump', 'fire', 'weapon', 'target'] : ['jump', 'fire', 'weapon']).includes(m.action)) return false;
  return true;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/health') {
      return Response.json({ ok: true, game: 'Kraterkompisar', protocol: PROTOCOL, supported_protocols: SUPPORTED_PROTOCOLS }, { headers: { 'Cache-Control': 'no-store' } });
    }
    if (url.pathname !== '/room') return new Response('Not found', { status: 404 });
    if (request.method !== 'GET' || request.headers.get('Upgrade')?.toLowerCase() !== 'websocket') return new Response('WebSocket required', { status: 426 });
    if (!allowedOrigin(request, env)) return new Response('Origin not allowed', { status: 403 });
    const protocol = requestedProtocol(url);
    if (protocol === null) return versionMismatch();
    const creating = url.searchParams.get('mode') === 'create';
    if (creating && !createAllowed(request)) return socketError('rate_limited', 'Vänta en minut innan du skapar fler rum.');
    const code = creating ? randomCode() : (url.searchParams.get('code') || '').toUpperCase();
    if (!ROOM_CODE.test(code)) return socketError('room_not_found', 'Kontrollera rumskoden.');
    // Never trust a client-supplied internal header. DO receives a clean routing URL.
    const internal = new URL('https://room/room');
    internal.searchParams.set('code', code);
    internal.searchParams.set('protocol', String(protocol));
    if (creating) internal.searchParams.set('mode', 'create');
    for (const key of ['token', 'name', 'capacity', 'map_id']) {
      if (url.searchParams.getAll(key).length > 1) return socketError('bad_message', 'Upprepad inställning.');
      if (url.searchParams.has(key)) internal.searchParams.set(key, url.searchParams.get(key));
    }
    try {
      return await env.ROOMS.get(env.ROOMS.idFromName(code)).fetch(new Request(internal, { headers: { Upgrade: 'websocket' } }));
    } catch {
      return socketError('server_unavailable', 'Servern är tillfälligt upptagen. Försök igen senare.');
    }
  }
};

export class GameRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx = ctx;
    this.room = null;
    this.lastPersist = 0;
    this.ctx.blockConcurrencyWhile(async () => {
      this.room = await this.ctx.storage.get('room') || null;
    });
    // A text heartbeat can be answered without waking the room.
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'));
  }

  async fetch(request) {
    // Seat allocation and token checks must be atomic across simultaneous joins.
    return this.ctx.blockConcurrencyWhile(() => this.connect(request));
  }

  async connect(request) {
    const url = new URL(request.url);
    const protocol = requestedProtocol(url);
    if (protocol === null) return versionMismatch();
    const creating = url.searchParams.get('mode') === 'create';
    if (this.room && Date.now() >= this.room.expires_at) {
      await this.expire();
      return socketError('room_expired', 'Rummet har stängts. Skapa ett nytt.');
    }
    // Old persisted rooms have no protocol field and remain strictly v1.
    // Check before allocating a guest seat or replacing any authenticated socket.
    if (this.room && protocol !== (this.room.protocol ?? 1)) return versionMismatch();
    const named = protocol === 3;
    let token = url.searchParams.get('token') || '';
    const name = named && (creating || !token) ? cleanName(url.searchParams.get('name') ?? 'Spelare') : null;
    if (named && (creating || !token) && !name) return socketError('invalid_name', 'Välj ett namn med 1–20 tecken utan vinkelparenteser.');
    let seat;
    if (creating) {
      if (this.room) return socketError('room_exists', 'Prova att skapa ett nytt rum.');
      const capacity = named ? Number(url.searchParams.get('capacity') ?? 6) : 2;
      const mapId = named ? Number(url.searchParams.get('map_id') ?? 0) : 0;
      if (!integer(capacity, 2, 6) || !integer(mapId, 0, 4)) return socketError('bad_message', 'Ogiltiga rumsinställningar.');
      token = randomHex();
      this.room = {
        code: url.searchParams.get('code'), protocol, expires_at: Date.now() + ROOM_TTL,
        token_hashes: named ? [await tokenHash(token)] : [await tokenHash(token), null],
        ...(named ? { names: [name], capacity, map_id: mapId, started: false, input_seqs: [0] } : {}),
        seq: 0, input_seq: 0, snapshot: null
      };
      seat = 0;
      await this.ctx.storage.setAlarm(this.room.expires_at);
      await this.persist();
    } else {
      if (!this.room) return socketError('room_not_found', 'Rummet finns inte längre. Kontrollera koden.');
      if (token) {
        if (!TOKEN.test(token)) return socketError('invalid_token', 'Kunde inte återansluta till din plats.');
        const hash = await tokenHash(token);
        seat = this.room.token_hashes.indexOf(hash);
        if (seat < 0) return socketError('invalid_token', 'Kunde inte återansluta till din plats.');
      } else {
        if (named && this.room.started) return socketError('match_started', 'Matchen har redan startat. Be värden skapa ett nytt rum.');
        seat = named ? this.room.token_hashes.length : 1;
        if (named ? seat >= this.room.capacity : this.room.token_hashes[1]) return socketError('room_full', 'Rummet är fullt.');
        token = randomHex();
        this.room.token_hashes[seat] = await tokenHash(token);
        if (named) { this.room.names.push(name); this.room.input_seqs.push(0); }
        await this.persist();
      }
    }
    // Replace only a socket authenticated to this exact seat. Old close callbacks
    // must not be able to remove the newly connected socket or its presence.
    for (const old of this.sockets(seat)) old.close(4001, 'Reconnected');
    const pair = new WebSocketPair();
    const server = pair[1];
    this.ctx.acceptWebSocket(server, [String(seat)]);
    server.serializeAttachment({ seat, n: 0, window: Date.now() });
    const presence = this.presence();
    server.send(JSON.stringify({
      type: 'welcome', protocol: this.room.protocol ?? 1, room: this.room.code, seat, host: seat === 0,
      token, peer_connected: seat === 0 ? presence.guest_connected : presence.host_connected,
      ...presence, seq: this.room.seq, input_seq: named ? this.room.input_seqs[seat] : this.room.input_seq, snapshot: this.room.snapshot,
      expires_at: this.room.expires_at
    }));
    this.broadcast({ type: 'presence', ...presence });
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  sockets(seat) {
    const sockets = seat === undefined ? this.ctx.getWebSockets() : this.ctx.getWebSockets(String(seat));
    return sockets.filter(ws => ws.readyState === 1);
  }
  presence() {
    const base = { host_connected: this.sockets(0).length > 0, guest_connected: this.sockets(1).length > 0 };
    if (this.room?.protocol !== 3) return base;
    const roster = this.room.names.map((name, seat) => ({ seat, name, connected: this.sockets(seat).length > 0,
      alive: (this.room.snapshot?.fighters[seat]?.hp ?? 100) > 0 }));
    return { ...base, roster, capacity: this.room.capacity, map_id: this.room.map_id,
      started: this.room.started, player_count: roster.length,
      all_connected: roster.every(p => p.connected),
      can_start: !this.room.started && roster.length >= 2 && roster.every(p => p.connected),
      playable: this.room.started && base.host_connected && roster.every(p => !p.alive || p.connected) };
  }
  broadcast(message, seat) {
    const data = JSON.stringify(message);
    for (const ws of this.sockets(seat)) { try { ws.send(data); } catch { /* close callback updates presence */ } }
  }
  reject(ws, code, message, close = false) {
    try { ws.send(JSON.stringify({ type: 'error', code, message, ...(this.room?.protocol === 3 ? { fatal: close } : {}) })); if (close) ws.close(1008, code); } catch { /* already closed */ }
  }
  async persist() {
    if (this.room) { await this.ctx.storage.put('room', this.room); this.lastPersist = Date.now(); }
  }

  async webSocketMessage(ws, raw) {
    if (!this.room || Date.now() >= this.room.expires_at) {
      await this.expire();
      return;
    }
    if (typeof raw !== 'string' || encoder.encode(raw).length > MAX_MESSAGE) return this.reject(ws, 'bad_message', 'Meddelandet är för stort.', true);
    const auth = ws.deserializeAttachment();
    if (!auth || !integer(auth.seat, 0, this.room.protocol === 3 ? this.room.names.length - 1 : 1) || ws.readyState !== 1) return;
    const now = Date.now();
    if (now - auth.window >= 1000) { auth.window = now; auth.n = 0; auth.lobby_n = 0; }
    if (++auth.n > 40) return this.reject(ws, 'rate_limited', 'För många meddelanden.', true);
    ws.serializeAttachment(auth);
    let m;
    try { m = JSON.parse(raw); } catch { return this.reject(ws, 'bad_message', 'Ogiltigt meddelande.', true); }
    if (!m || typeof m !== 'object' || Array.isArray(m)) return this.reject(ws, 'bad_message', 'Ogiltigt meddelande.', true);
    if (m.type === 'ping') { ws.send(JSON.stringify({ type: 'pong' })); return; }
    if (this.room.protocol === 3 && ['start', 'lobby', 'rename'].includes(m.type)) {
      if (m.type !== 'rename' && auth.seat !== 0) return this.reject(ws, 'forbidden', 'Bara värden kan ändra rummet.');
      if (this.room.started) return this.reject(ws, 'match_started', 'Matchen har redan startat.');
      auth.lobby_n = (auth.lobby_n || 0) + 1;
      ws.serializeAttachment(auth);
      if (auth.lobby_n > 4) return this.reject(ws, 'rate_limited', 'Vänta en sekund innan du ändrar rummet igen.');
      if (m.type === 'rename') {
        const name = cleanName(m.name);
        if (!name) return this.reject(ws, 'invalid_name', 'Välj ett namn med 1–20 tecken utan vinkelparenteser.');
        this.room.names[auth.seat] = name;
      } else {
        if (m.map_id !== undefined && !integer(m.map_id, 0, 4)) return this.reject(ws, 'bad_message', 'Ogiltig karta.');
        if (m.capacity !== undefined && (!integer(m.capacity, 2, 6) || m.capacity < this.room.names.length)) return this.reject(ws, 'bad_message', 'Ogiltigt antal platser.');
        if (m.type === 'start' && !this.presence().can_start) return this.reject(ws, 'not_ready', 'Minst två spelare måste vara anslutna och alla reserverade platser tillbaka.');
        if (m.map_id !== undefined) this.room.map_id = m.map_id;
        if (m.capacity !== undefined) this.room.capacity = m.capacity;
        if (m.type === 'start') this.room.started = true;
      }
      await this.persist();
      this.broadcast({ type: m.type === 'start' ? 'started' : 'presence', ...this.presence() });
      return;
    }
    if (m.type === 'state') {
      if (auth.seat !== 0) return this.reject(ws, 'forbidden', 'Bara värden kan ändra matchen.');
      if (this.room.protocol === 3 && !this.room.started) return this.reject(ws, 'not_started', 'Starta matchen i lobbyn först.');
      if (!integer(m.seq, 1, Number.MAX_SAFE_INTEGER) || !validSnapshot(m.snapshot, this.room.protocol ?? 1, this.room.protocol === 3 ? this.room.names.length : 2) || (this.room.protocol === 3 && m.snapshot.map_id !== this.room.map_id)) return this.reject(ws, 'bad_message', 'Ogiltigt matchläge.');
      if (m.seq <= this.room.seq) return; // Duplicate/stale packets are idempotent.
      const firstSnapshot = this.room.snapshot === null;
      const pauseChanged = this.room.snapshot?.paused !== m.snapshot.paused;
      this.room.seq = m.seq;
      this.room.snapshot = m.snapshot;
      // Every accepted snapshot is complete. Persist at most four times/second,
      // normally once/second, plus major game events. No continuous alarm loop.
      if (firstSnapshot || pauseChanged || now - this.lastPersist >= 1000 || (m.commit === true && now - this.lastPersist >= 250)) await this.persist();
      const message = { type: 'state', seq: m.seq, commit: m.commit === true, snapshot: m.snapshot };
      if (this.room.protocol === 3) {
        for (let seat = 1; seat < this.room.names.length; seat++) this.broadcast(message, seat);
      } else this.broadcast(message, 1);
      return;
    }
    if (m.type === 'input') {
      const named = this.room.protocol === 3;
      if (auth.seat === 0) return this.reject(ws, 'forbidden', 'Ogiltig spelarplats.');
      if (!validInput(m, this.room.protocol ?? 1) || (named && m.target !== undefined && (!integer(m.target, 0, this.room.names.length - 1) || m.target === auth.seat))) return this.reject(ws, 'bad_message', 'Ogiltig kontroll.');
      const lastSeq = named ? this.room.input_seqs[auth.seat] : this.room.input_seq;
      if (m.seq <= lastSeq) return;
      const s = this.room.snapshot;
      if (!this.presence().host_connected || (named && !this.presence().playable) || !s || s.paused === true || s.phase !== 'aim' || s.active !== auth.seat || s.turn !== m.turn) return;
      if (named && (s.fighters[auth.seat].hp <= 0 || (m.target !== undefined && s.fighters[m.target].hp <= 0))) return this.reject(ws, 'bad_message', 'Välj en spelare som är kvar i matchen.');
      if (named) this.room.input_seqs[auth.seat] = m.seq;
      else this.room.input_seq = m.seq;
      this.broadcast({ type: 'input', seat: auth.seat, seq: m.seq, turn: m.turn, move: m.move, angle_axis: m.angle_axis, power_axis: m.power_axis, ...(m.aim ? { aim: m.aim } : {}), ...(m.action ? { action: m.action } : {}), ...(named && m.target !== undefined ? { target: m.target } : {}) }, 0);
      return;
    }
    this.reject(ws, 'bad_message', 'Okänd meddelandetyp.');
  }

  async webSocketClose(ws, code, reason, wasClean) {
    try { ws.close(code === 1005 ? 1000 : code, reason); } catch { /* already closed */ }
    // Save current simulation before a possible hibernation or reconnect.
    await this.persist();
    this.broadcast({ type: 'presence', ...this.presence() });
  }
  async webSocketError(ws) {
    try { ws.close(1011, 'Connection error'); } catch { /* already closed */ }
    await this.persist();
    this.broadcast({ type: 'presence', ...this.presence() });
  }
  async expire() {
    this.broadcast({ type: 'error', code: 'room_expired', message: 'Rummet har stängts efter två timmar. Skapa ett nytt.' });
    for (const ws of this.sockets()) ws.close(4000, 'Room expired');
    this.room = null;
    await this.ctx.storage.deleteAll();
  }
  async alarm() { await this.expire(); }
}
