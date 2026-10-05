extends Node
## Small, account-free, room relay client. Simulation authority stays with seat 0.
signal changed
signal welcomed(data: Dictionary)
signal received(data: Dictionary)

const PROTOCOL := 2
const MAX_PACKET := 65536
var server_url := ""
var socket: WebSocketPeer
var status := "idle"
var status_text := ""
var room := ""
var seat := -1
var token := ""
var host_connected := false
var guest_connected := false
var state_seq := 0
var input_seq := 0
var _request_path := ""
var _opened := false
var _wait_time := 0.0
var _heartbeat := 0.0

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

func together() -> bool:
	return status == "connected" and host_connected and guest_connected

func create_room() -> void:
	leave()
	_connect("/room?mode=create&protocol=%d" % PROTOCOL)

func join_room(code: String) -> void:
	leave()
	var normalized := code.strip_edges().to_upper()
	if not valid_room_code(normalized):
		_fail("Rumskoden ska ha 8 bokstäver eller siffror.")
		return
	_connect("/room?code=" + normalized.uri_encode() + "&protocol=%d" % PROTOCOL)

func valid_room_code(value: String) -> bool:
	if value.length() != 8:
		return false
	for character in value:
		if not character in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789":
			return false
	return true

func reconnect() -> void:
	if room.is_empty() or token.is_empty():
		return
	_close_socket()
	_connect("/room?code=" + room.uri_encode() + "&token=" + token.uri_encode() + "&protocol=%d" % PROTOCOL)

func _connect(path: String) -> void:
	if not configured():
		_fail("Onlineservern är inte aktiverad ännu. Lokal duell fungerar redan.")
		return
	_request_path = path
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = MAX_PACKET * 2
	socket.outbound_buffer_size = MAX_PACKET * 2
	socket.max_queued_packets = 128
	_opened = false
	_wait_time = 0
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
	if ready == WebSocketPeer.STATE_OPEN:
		_opened = true
		while socket != null and socket.get_available_packet_count() > 0:
			var packet := socket.get_packet()
			if packet.size() > MAX_PACKET or not socket.was_string_packet():
				_fail("Servern skickade ett ogiltigt meddelande.")
				return
			var data = JSON.parse_string(packet.get_string_from_utf8())
			if not data is Dictionary:
				_fail("Servern skickade ett ogiltigt meddelande.")
				return
			_handle(data)
		_heartbeat += delta
		if _heartbeat > 15 and status == "connected":
			_heartbeat = 0
			send({"type": "ping"})
	elif ready == WebSocketPeer.STATE_CLOSED:
		if status not in ["error", "idle", "disconnected"]:
			_fail("Anslutningen bröts. Matchen är pausad. Tryck Återanslut." if not token.is_empty() else "Kunde inte nå onlineservern. Försök igen.")
	if status == "connecting":
		_wait_time += delta
		if _wait_time > 12:
			_fail("Servern svarade inte. Kontrollera nätverket och försök igen.")

func _handle(data: Dictionary) -> void:
	match str(data.get("type", "")):
		"welcome":
			if int(data.get("protocol", 0)) != PROTOCOL or int(data.get("seat", -1)) not in [0, 1]:
				_fail("Spelversionerna stämmer inte överens. Ladda om sidan.")
				return
			room = str(data.get("room", ""))
			token = str(data.get("token", ""))
			seat = int(data.seat)
			state_seq = int(data.get("seq", 0))
			input_seq = maxi(input_seq, int(data.get("input_seq", 0)))
			host_connected = seat == 0 or bool(data.get("peer_connected", false))
			guest_connected = seat == 1 or bool(data.get("peer_connected", false))
			status = "connected"
			status_text = "Ni är anslutna!" if together() else "Väntar på den andra spelaren…"
			welcomed.emit(data)
			changed.emit()
		"presence":
			host_connected = bool(data.get("host_connected", false))
			guest_connected = bool(data.get("guest_connected", false))
			status_text = "Ni är anslutna!" if together() else "Den andra spelaren är frånkopplad. Matchen är pausad."
			changed.emit()
		"error":
			var messages := {"version_mismatch": "Spelversionerna stämmer inte överens. Båda behöver ladda om sidan och skapa ett nytt rum.", "room_not_found": "Rummet finns inte längre. Kontrollera koden eller skapa ett nytt.", "room_full": "Rummet är fullt. Bara två spelare får plats.", "invalid_token": "Rummet kan inte återanslutas. Skapa ett nytt rum.", "rate_limited": "Servern är upptagen. Vänta en stund och försök igen.", "room_expired": "Rummet har stängts. Skapa ett nytt rum.", "bad_message": "Spelet och servern kunde inte förstå varandra. Ladda om sidan."}
			_fail(str(messages.get(str(data.get("code", "")), "Anslutningen misslyckades. Försök igen.")))
		"state", "input":
			received.emit(data)

func send(data: Dictionary) -> bool:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var encoded := JSON.stringify(data, "", true, true)
	if encoded.to_utf8_buffer().size() > MAX_PACKET:
		_fail("Matchen är för stor för servern. Starta en ny duell.")
		return false
	return socket.send_text(encoded) == OK

func send_input(input: Dictionary, turn_number: int) -> bool:
	if seat != 1 or not together():
		return false
	input_seq += 1
	var message := input.duplicate(true)
	message.type = "input"
	message.seq = input_seq
	message.turn = turn_number
	return send(message)

func send_state(snapshot: Dictionary, commit: bool) -> bool:
	if seat != 0 or status != "connected":
		return false
	state_seq += 1
	snapshot.seq = state_seq
	return send({"type": "state", "seq": state_seq, "commit": commit, "snapshot": snapshot})

func _fail(message: String) -> void:
	status = "disconnected" if not token.is_empty() else "error"
	status_text = message
	host_connected = false
	guest_connected = false
	_close_socket()
	changed.emit()

func _close_socket() -> void:
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
	state_seq = 0
	input_seq = 0
	changed.emit()
