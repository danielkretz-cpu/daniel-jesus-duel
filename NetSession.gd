extends Node
## Account-free private rooms. Seat 0 owns simulation, even after elimination.
signal changed
signal welcomed(data: Dictionary)
signal received(data: Dictionary)
signal match_started(data: Dictionary)

const PROTOCOL := 3
const MAX_PACKET := 65536
const MAX_PLAYERS := 6
# Full snapshots supersede older snapshots. Keep only a small transport backlog.
const STATE_QUEUE_BUDGET := 16384
const INBOUND_BUFFER := MAX_PACKET * 32
const ROOM_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
var server_url := ""
var socket: WebSocketPeer
var status := "idle"
var status_text := ""
var room := ""
var seat := -1
var token := "" # Private resume credential, never include in an invitation.
var host_connected := false
var guest_connected := false
var roster: Array = []
var players: Array:
	get: return roster
var capacity := 6
var started := false
var map_id := 0
var map_index: int:
	get: return map_id
var player_count: int:
	get: return roster.size()
var state_seq := 0
var input_seq := 0
var _request_path := ""
var _wait_time := 0.0
var _heartbeat := 0.0
var _pending_state: Dictionary = {}
var _incoming_state: Dictionary = {}
var coalesced_states := 0
var deferred_states := 0
var skipped_inputs := 0

func _ready() -> void:
	if FileAccess.file_exists("res://network_config.json"):
		var config = JSON.parse_string(FileAccess.get_file_as_string("res://network_config.json"))
		if config is Dictionary:
			server_url = str(config.get("server_url", "")).trim_suffix("/")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server-url="):
			server_url = arg.trim_prefix("--server-url=").trim_suffix("/")

func configured() -> bool:
	return server_url.begins_with("wss://") or server_url.begins_with("ws://127.0.0.1:") or server_url.begins_with("ws://localhost:")

static func normalize_player_name(value: String) -> String:
	var clean := ""
	for character in value:
		var code := character.unicode_at(0)
		# Unicode Cc/Cf characters, including bidi overrides, are not display names.
		if code <= 31 or (code >= 127 and code <= 159) or code in [173, 1564, 1807, 6158, 8232, 8233, 65279, 69821, 69837, 917505]:
			continue
		if (code >= 1536 and code <= 1541) or (code >= 2192 and code <= 2193) or (code >= 8203 and code <= 8207) or (code >= 8234 and code <= 8238) or (code >= 8288 and code <= 8303) or (code >= 65529 and code <= 65531) or (code >= 78896 and code <= 78911) or (code >= 113824 and code <= 113827) or (code >= 119155 and code <= 119162) or (code >= 917536 and code <= 917631):
			continue
		clean += character
	clean = clean.strip_edges()
	# Match JavaScript trim() for Unicode space separators too.
	while not clean.is_empty() and _name_edge_space(clean.unicode_at(0)):
		clean = clean.substr(1)
	while not clean.is_empty() and _name_edge_space(clean.unicode_at(clean.length() - 1)):
		clean = clean.substr(0, clean.length() - 1)
	return clean

static func _name_edge_space(code: int) -> bool:
	return code in [32, 160, 5760, 8239, 8287, 12288] or (code >= 8192 and code <= 8202)

static func valid_player_name(value: String) -> bool:
	var clean := normalize_player_name(value)
	return clean.length() >= 1 and clean.length() <= 20 and not "<" in clean and not ">" in clean

func together() -> bool:
	if status != "connected" or not started or not host_connected or roster.size() < 2:
		return false
	for player in roster:
		if bool(player.get("alive", true)) and not bool(player.connected):
			return false
	return true

func can_start() -> bool:
	if status != "connected" or seat != 0 or started or roster.size() < 2:
		return false
	for player in roster:
		if not bool(player.connected):
			return false
	return true

func create_room(display_name: String = "Spelare", room_capacity: int = 6, selected_map: int = 0) -> void:
	leave()
	if not valid_player_name(display_name) or room_capacity < 2 or room_capacity > MAX_PLAYERS or selected_map < 0 or selected_map > 4:
		_fail("Välj ett namn med 1–20 tecken, 2–6 platser och en giltig karta.")
		return
	_connect("/room?mode=create&protocol=%d&name=%s&capacity=%d&map_id=%d" % [PROTOCOL, normalize_player_name(display_name).uri_encode(), room_capacity, selected_map])

func join_room(code: String, display_name: String = "Spelare") -> void:
	leave()
	var normalized := code.strip_edges().to_upper()
	if not valid_room_code(normalized):
		_fail("Rumskoden ska ha 8 bokstäver eller siffror från inbjudan.")
		return
	if not valid_player_name(display_name):
		_fail("Välj ett namn med 1–20 tecken utan vinkelparenteser.")
		return
	_connect("/room?code=%s&protocol=%d&name=%s" % [normalized.uri_encode(), PROTOCOL, normalize_player_name(display_name).uri_encode()])

func valid_room_code(value: String) -> bool:
	if value.length() != 8:
		return false
	for character in value:
		if not character in ROOM_ALPHABET:
			return false
	return true

func start_match(selected_map: int = -1) -> bool:
	if not can_start():
		return false
	var message := {"type": "start"}
	if selected_map >= 0:
		message.map_id = selected_map
	return send(message)

func set_map(selected_map: int) -> bool:
	return seat == 0 and not started and selected_map >= 0 and selected_map <= 4 and send({"type": "lobby", "map_id": selected_map})

func set_capacity(count: int) -> bool:
	return seat == 0 and not started and count >= maxi(2, player_count) and count <= MAX_PLAYERS and send({"type": "lobby", "capacity": count})

func rename_player(display_name: String) -> bool:
	return not started and valid_player_name(display_name) and send({"type": "rename", "name": normalize_player_name(display_name)})

func reconnect() -> void:
	if room.is_empty() or token.is_empty():
		return
	_close_socket()
	_connect("/room?code=" + room.uri_encode() + "&token=" + token.uri_encode() + "&protocol=%d" % PROTOCOL)

func _connect(path: String) -> void:
	if not configured():
		_fail("Onlineservern är inte aktiverad ännu. Lokal match fungerar redan.")
		return
	_request_path = path
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = INBOUND_BUFFER
	socket.outbound_buffer_size = MAX_PACKET * 2
	socket.max_queued_packets = 128
	_wait_time = 0
	_heartbeat = 0
	host_connected = false
	guest_connected = false
	status = "connecting"
	status_text = "Ansluter till rummet…"
	changed.emit()
	if socket.connect_to_url(server_url + path) != OK:
		_fail("Kunde inte ansluta. Kontrollera nätverket och försök igen.")

func _process(delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	var ready := socket.get_ready_state()
	# A server rejection can send its final JSON packet and close in one poll.
	# Drain any packets first, including those queued while the peer is closing.
	while socket != null and socket.get_available_packet_count() > 0:
		var packet := socket.get_packet()
		if packet.size() > MAX_PACKET or not socket.was_string_packet():
			_fail("Servern skickade ett ogiltigt meddelande.")
			return
		var data = JSON.parse_string(packet.get_string_from_utf8())
		if not data is Dictionary:
			_fail("Servern skickade ett ogiltigt meddelande.")
			return
		_queue_received(data)
	_flush_received_state()
	if socket == null:
		return
	if ready == WebSocketPeer.STATE_OPEN:
		_flush_pending_state()
		_heartbeat += delta
		if _heartbeat > 15 and status == "connected":
			_heartbeat = 0
			send({"type": "ping"})
	elif ready == WebSocketPeer.STATE_CLOSED:
		if status not in ["error", "idle", "disconnected"]:
			# Native WebSocketPeer may discard the final payload on immediate close,
			# but preserves the server's policy-error code in the close reason.
			var reason := socket.get_close_reason()
			if socket.get_close_code() == 1008 and reason in ["version_mismatch", "room_not_found", "room_full", "match_started", "invalid_name", "not_ready", "not_started", "invalid_token", "rate_limited", "room_expired", "bad_message"]:
				_handle({"type": "error", "code": reason})
			else:
				_fail("Anslutningen bröts. Din plats är sparad. Tryck Återanslut." if not token.is_empty() else "Kunde inte nå onlineservern. Försök igen.")
	if status == "connecting":
		_wait_time += delta
		if _wait_time > 12:
			_fail("Servern svarade inte. Kontrollera nätverket och försök igen.")

# Coalesce only adjacent complete state messages. Input actions, welcome, errors
# and presence are ordering barriers and are never dropped or reordered.
func _queue_received(data: Dictionary) -> void:
	if data.get("type") == "state" and _wire_integer(data.get("seq"), 1, 9007199254740991) and data.get("snapshot") is Dictionary:
		if not _incoming_state.is_empty():
			coalesced_states += 1
		if _incoming_state.is_empty() or data.seq > _incoming_state.seq:
			_incoming_state = data
		return
	_flush_received_state()
	_handle(data)

func _flush_received_state() -> void:
	if _incoming_state.is_empty():
		return
	var latest := _incoming_state
	_incoming_state = {}
	_handle(latest)

func _flush_pending_state() -> void:
	if _pending_state.is_empty() or socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if socket.get_current_outbound_buffered_amount() > STATE_QUEUE_BUDGET:
		return
	var latest := _pending_state
	_pending_state = {}
	if not send(latest) and socket != null:
		_pending_state = latest

static func _wire_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum

func _read_presence(data: Dictionary) -> bool:
	var incoming = data.get("roster")
	if not incoming is Array or incoming.is_empty() or incoming.size() > MAX_PLAYERS:
		return false
	var index := 0
	for player in incoming:
		if not player is Dictionary or not _wire_integer(player.get("seat"), index, index) or not player.get("name") is String or not valid_player_name(player.name) or player.name != normalize_player_name(player.name) or not player.get("connected") is bool or not player.get("alive") is bool:
			return false
		index += 1
	if not _wire_integer(data.get("capacity"), maxi(2, incoming.size()), MAX_PLAYERS) or not data.get("started") is bool or not _wire_integer(data.get("map_id"), 0, 4):
		return false
	if bool(data.started) and incoming.size() < 2:
		return false
	roster = incoming.duplicate(true)
	capacity = int(data.capacity)
	started = bool(data.started)
	map_id = int(data.map_id)
	host_connected = bool(roster[0].connected)
	guest_connected = roster.size() > 1 and bool(roster[1].connected)
	return true

func _update_health(snapshot: Dictionary) -> void:
	var fighters = snapshot.get("fighters")
	if not fighters is Array or fighters.size() != roster.size():
		return
	for i in range(roster.size()):
		if not fighters[i] is Dictionary or not _wire_integer(fighters[i].get("hp"), 0, 100):
			return
	for i in range(roster.size()):
		roster[i].alive = int(fighters[i].hp) > 0

func accept_snapshot(snapshot: Dictionary) -> void:
	# Called only after Game accepted the complete, current snapshot.
	_update_health(snapshot)
	_refresh_status()

func _refresh_status() -> void:
	if not started:
		status_text = "%d av %d platser fyllda. Värden startar när alla är här." % [player_count, capacity]
	elif together():
		status_text = "Alla spelare som är kvar är anslutna."
	else:
		var missing := PackedStringArray()
		for player in roster:
			if not bool(player.connected) and (int(player.seat) == 0 or bool(player.get("alive", true))):
				missing.append(str(player.name))
		status_text = "Matchen är pausad. Väntar på " + ", ".join(missing) + "."

func _handle(data: Dictionary) -> void:
	match str(data.get("type", "")):
		"welcome":
			if not _wire_integer(data.get("protocol"), PROTOCOL, PROTOCOL) or not _read_presence(data) or not _wire_integer(data.get("seat"), 0, roster.size() - 1) or not _wire_integer(data.get("seq"), 0, 9007199254740991) or not _wire_integer(data.get("input_seq"), 0, 9007199254740991):
				_fail("Spelversionerna stämmer inte överens. Ladda om sidan.")
				return
			room = str(data.get("room", ""))
			token = str(data.get("token", ""))
			seat = int(data.seat)
			state_seq = int(data.get("seq", 0))
			input_seq = maxi(input_seq, int(data.get("input_seq", 0)))
			status = "connected"
			_refresh_status()
			welcomed.emit(data)
			changed.emit()
		"presence", "started":
			if not _read_presence(data):
				_fail("Servern skickade en ogiltig spelarlista.")
				return
			_refresh_status()
			if data.type == "started":
				match_started.emit(data)
			changed.emit()
		"error":
			var messages := {"version_mismatch": "Spelversionerna stämmer inte överens. Alla behöver ladda om sidan och skapa ett nytt rum.", "room_not_found": "Rummet finns inte längre. Kontrollera koden eller skapa ett nytt.", "room_full": "Rummet är fullt. Be värden skapa ett nytt rum.", "match_started": "Matchen har redan startat. Nya spelare kan vara med i nästa rum.", "invalid_name": "Välj ett namn med 1–20 tecken utan vinkelparenteser.", "not_ready": "Minst två spelare behövs. Alla i lobbyn måste vara anslutna.", "not_started": "Värden behöver starta matchen först.", "invalid_token": "Rummet kan inte återanslutas. Skapa ett nytt rum.", "rate_limited": "Servern är upptagen. Vänta en stund och försök igen.", "room_expired": "Rummet har stängts efter två timmar. Skapa ett nytt rum.", "bad_message": "Spelet och servern kunde inte förstå varandra. Ladda om sidan."}
			var message := str(messages.get(str(data.get("code", "")), "Anslutningen misslyckades. Försök igen."))
			if bool(data.get("fatal", true)):
				_fail(message)
			else:
				status_text = message
				changed.emit()
		"state", "input":
			received.emit(data)

func send(data: Dictionary) -> bool:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var encoded := JSON.stringify(data, "", true, true)
	if encoded.to_utf8_buffer().size() > MAX_PACKET:
		_fail("Matchen är för stor för servern. Starta en ny match.")
		return false
	return socket.send_text(encoded) == OK

func send_input(input: Dictionary, turn_number: int) -> bool:
	if seat <= 0 or not together():
		return false
	# Periodic held controls supersede each other; never build a stale-input
	# backlog on a stalled uplink. Explicit button actions retain their order.
	if not input.has("action") and socket != null and socket.get_current_outbound_buffered_amount() > 4096:
		skipped_inputs += 1
		return false
	input_seq += 1
	var message := input.duplicate(true)
	message.type = "input"
	message.seq = input_seq
	message.turn = turn_number
	return send(message)

func send_state(snapshot: Dictionary, commit: bool) -> bool:
	if seat != 0 or status != "connected" or not started:
		return false
	state_seq += 1
	snapshot.seq = state_seq
	_update_health(snapshot)
	_refresh_status()
	# Retain the newest complete snapshot instead of appending seconds of stale
	# history to TCP/browser bufferedAmount on a slow connection. Preserve commit.
	var important := commit or bool(_pending_state.get("commit", false))
	_pending_state = {"type": "state", "seq": state_seq, "commit": important, "snapshot": snapshot}
	if socket != null and socket.get_current_outbound_buffered_amount() > STATE_QUEUE_BUDGET:
		deferred_states += 1
	_flush_pending_state()
	return socket != null

func _fail(message: String) -> void:
	status = "disconnected" if not token.is_empty() else "error"
	status_text = message
	host_connected = false
	guest_connected = false
	_close_socket()
	changed.emit()

func _close_socket() -> void:
	_pending_state = {}
	_incoming_state = {}
	if socket != null:
		socket.close(1000, "Leaving room")
		socket = null

func leave() -> void:
	_close_socket()
	status = "idle"
	status_text = ""
	room = ""
	token = ""
	seat = -1
	host_connected = false
	guest_connected = false
	roster = []
	capacity = 6
	started = false
	map_id = 0
	state_seq = 0
	input_seq = 0
	changed.emit()
