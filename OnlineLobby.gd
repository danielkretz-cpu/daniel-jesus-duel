extends Control
## Native, keyboard-friendly lobby. Room invitations never contain a resume token.
signal create_requested(display_name: String)
signal join_requested(code: String, display_name: String)
signal leave_requested
signal leave_cancelled
signal reconnect_requested
signal start_requested(map_index: int)
signal map_changed(map_index: int)
signal copy_requested # Compatibility only; sharing is handled inside this view.
const UI = preload("res://MenuUI.gd")
const Invite = preload("res://FriendInvite.gd")
const Maps = preload("res://MapThemes.gd")
const Session = preload("res://NetSession.gd")
var box: PanelContainer
var column: VBoxContainer
var heading: Label
var message: Label
var code: LineEdit
var name_input: LineEdit
var create_button: Button
var join_button: Button
var reconnect_button: Button
var copy_button: Button
var share_button: Button
var back_button: Button
var start_button: Button
var room_label: Label
var invite_link: LineEdit
var share_message: Label
var roster_heading: Label
var connection_help: Label
var map_picker: OptionButton
var connected := false
var selected_map := 0
var entry: VBoxContainer
var room_content: VBoxContainer
var roster: VBoxContainer
var invite_hint: Label
var confirm_panel: VBoxContainer
var confirm_button: Button
var cancel_button: Button
var scroll: ScrollContainer
var invite_actions: GridContainer
var _roster_labels: Array[Label] = []
var _view := Vector2(1280, 800)
var _session
var _room := ""
var _has_room := false
var _started := false
var _pending := false
var _leaving := false
var _invite_mode := false
var _share_pending := false
var _share_result_key := ""
var _share_elapsed := 0.0
var _last_status := "idle"

func _ready() -> void:
	theme = UI.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.065, 0.11, 0.89)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	box = PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.style(UI.PANEL, 22, Color("4c627e")))
	add_child(box)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	box.add_child(column)
	heading = UI.label(column, "Spela med vänner", 28)
	heading.add_theme_font_override("font", load("res://assets/Bold.ttf"))
	message = UI.label(column, "2–6 spelare, varsin skärm. Alla väljer sitt eget namn.", 15, UI.MUTED)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	entry = VBoxContainer.new()
	entry.add_theme_constant_override("separation", 10)
	body.add_child(entry)
	UI.label(entry, "Ditt namn", 15)
	name_input = UI.field(entry, "Välj ett namn", 20)
	name_input.text_changed.connect(func(_value: String): _clear_entry_error())
	name_input.text_submitted.connect(func(_value: String):
		if _invite_mode:
			_submit_join()
		else:
			create_button.grab_focus())
	UI.label(entry, "1–20 tecken. Syns för dem som är med i rummet.", 13, UI.MUTED)
	create_button = UI.button(entry, "Skapa ett rum", true)
	create_button.pressed.connect(_submit_create)
	invite_hint = UI.label(entry, "Har du en inbjudan? Klistra in länken eller rumskoden.", 14, UI.MUTED)
	code = UI.field(entry, "Rumskod eller länk")
	code.text_submitted.connect(func(_value: String): _submit_join())
	code.text_changed.connect(func(_value: String): _clear_entry_error())
	join_button = UI.button(entry, "Gå med i rummet")
	join_button.pressed.connect(_submit_join)
	room_content = VBoxContainer.new()
	room_content.add_theme_constant_override("separation", 10)
	body.add_child(room_content)
	room_label = UI.label(room_content, "", 25, UI.MINT)
	var invite_row := GridContainer.new()
	invite_actions = invite_row
	invite_row.columns = 2
	invite_row.add_theme_constant_override("h_separation", 8)
	invite_row.add_theme_constant_override("v_separation", 8)
	room_content.add_child(invite_row)
	share_button = UI.button(invite_row, "Bjud in vänner", true)
	share_button.pressed.connect(func(): _share_invite(true))
	copy_button = UI.button(invite_row, "Kopiera länk")
	copy_button.pressed.connect(func(): _share_invite(false))
	invite_link = UI.field(room_content, "")
	invite_link.editable = false
	invite_link.visible = false
	invite_link.tooltip_text = "Markera och kopiera hela länken. Bara rumskoden delas."
	share_message = UI.label(room_content, "Dela länken eller de 8 tecknen i rumskoden.", 13, UI.MUTED)
	roster_heading = UI.label(room_content, "Spelare · 0/6", 17)
	roster = VBoxContainer.new()
	roster.add_theme_constant_override("separation", 5)
	room_content.add_child(roster)
	for n in range(6):
		var row := UI.label(roster, "%d  ·  Ledig plats" % [n + 1], 15, UI.MUTED)
		row.custom_minimum_size.y = 27
		_roster_labels.append(row)
	connection_help = UI.label(room_content, "", 14, UI.GOLD)
	connection_help.visible = false
	UI.label(room_content, "Bana · värden väljer", 14, UI.MUTED)
	map_picker = OptionButton.new()
	map_picker.custom_minimum_size.y = 48
	map_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_picker.clip_text = true
	for n in range(Maps.count()):
		map_picker.add_item(Maps.title(n), n)
	map_picker.item_selected.connect(func(index: int):
		selected_map = index
		map_changed.emit(index))
	room_content.add_child(map_picker)
	reconnect_button = UI.button(body, "Återanslut till rummet", true)
	reconnect_button.pressed.connect(_reconnect)
	confirm_panel = VBoxContainer.new()
	confirm_panel.add_theme_constant_override("separation", 8)
	column.add_child(confirm_panel)
	UI.label(confirm_panel, "Lämna rummet? Du kan inte få tillbaka din plats med bara rumskoden.", 14, UI.GOLD)
	var confirm_row := HBoxContainer.new()
	confirm_row.add_theme_constant_override("separation", 8)
	confirm_panel.add_child(confirm_row)
	cancel_button = UI.button(confirm_row, "Stanna", true)
	cancel_button.pressed.connect(cancel_leave)
	confirm_button = UI.button(confirm_row, "Lämna")
	confirm_button.pressed.connect(_confirm_leave)
	start_button = UI.button(column, "Starta matchen", true)
	start_button.pressed.connect(_submit_start)
	back_button = UI.button(column, "Tillbaka")
	back_button.pressed.connect(request_leave)
	room_content.visible = false
	reconnect_button.visible = false
	start_button.visible = false
	confirm_panel.visible = false
	visible = false
	layout(_view)

func set_map(value: int) -> void:
	selected_map = clampi(value, 0, Maps.count() - 1)
	if map_picker != null:
		map_picker.select(selected_map)

func open_invite(value: String) -> bool:
	var room_code := Invite.room_from_input(value)
	if room_code.is_empty():
		return false
	code.text = room_code
	_invite_mode = true
	create_button.visible = false
	invite_hint.text = "Du är inbjuden. Välj ditt namn och gå med."
	heading.text = "Du är inbjuden!"
	join_button.add_theme_stylebox_override("normal", UI.style(UI.GOLD, 12))
	join_button.add_theme_color_override("font_color", UI.INK)
	# Prefill only. Never connect, save, or disclose a player's name on page load.
	return true

func clear_invite() -> void:
	_invite_mode = false
	code.text = ""
	create_button.visible = true
	invite_hint.text = "Har du en inbjudan? Klistra in länken eller rumskoden."
	join_button.remove_theme_stylebox_override("normal")
	join_button.remove_theme_color_override("font_color")

func refresh(session) -> void:
	_session = session
	connected = session.status == "connected"
	var was_room := _has_room
	_has_room = not session.room.is_empty()
	_room = session.room
	_started = session.started
	_last_status = session.status
	var busy: bool = session.status == "connecting" or connected
	if session.status in ["error", "disconnected", "idle", "connected"]:
		_pending = false
	if not _has_room and was_room:
		cancel_leave(false)
		_share_pending = false
		invite_link.visible = false
		share_message.text = "Dela länken eller de 8 tecknen i rumskoden."
	entry.visible = not _has_room
	room_content.visible = _has_room
	create_button.visible = not _invite_mode
	create_button.disabled = busy or not session.configured()
	join_button.disabled = busy or not session.configured()
	name_input.editable = not busy
	code.editable = not busy
	heading.text = ("Ditt rum" if session.seat == 0 else "Väntrum") if _has_room else ("Du är inbjuden!" if _invite_mode else "Spela med vänner")
	if _started:
		heading.text = "Matchen är pausad"
	message.text = session.status_text if not session.status_text.is_empty() else ("2–6 spelare, varsin skärm. Alla väljer sitt eget namn." if session.configured() else "Onlineservern är inte tillgänglig. Du kan spela lokal duell under tiden.")
	message.add_theme_color_override("font_color", UI.GOLD if session.status in ["error", "disconnected"] else UI.MUTED)
	room_label.text = "RUM  %s" % _room
	invite_link.text = Invite.share_url(_room)
	invite_actions.visible = not _started
	share_button.disabled = _share_pending or _started
	copy_button.disabled = _share_pending or _started
	if _started:
		invite_link.visible = false
		share_message.text = "Matchen har startat. Befintliga spelare återansluter från sin öppna spelflik."
	reconnect_button.visible = _has_room and session.status == "disconnected"
	reconnect_button.disabled = session.status == "connecting"
	start_button.visible = _has_room and not _started and session.seat == 0 and not _leaving
	start_button.disabled = not session.can_start()
	start_button.text = "Starta matchen · %d spelare" % session.player_count if session.can_start() else ("Vänta på minst 2 spelare" if session.player_count < 2 else "Vänta tills alla är anslutna")
	back_button.text = "Lämna rummet" if _has_room else ("Avbryt anslutning" if session.status == "connecting" else "Tillbaka")
	back_button.visible = not _leaving
	map_picker.disabled = session.seat != 0 or _started or not connected
	set_map(session.map_id if _has_room else selected_map)
	_update_roster(session.roster, session.seat, session.capacity)
	var waiting_for_someone := false
	for player in session.roster:
		if not bool(player.get("connected", false)):
			waiting_for_someone = true
	connection_help.visible = _has_room and not _started and (waiting_for_someone or not connected)
	if not connected:
		connection_help.text = "Tryck på Återanslut i den här öppna spelfliken. Om fliken har stängts behöver värden skapa ett nytt rum."
	elif waiting_for_someone:
		var who := "du" if session.seat == 0 else "värden"
		connection_help.text = "Be frånkopplade vänner trycka på Återanslut i sina öppna spelflikar. Om någon inte kommer tillbaka behöver %s lämna rummet och skapa ett nytt." % who
	_fit_box.call_deferred()

func _update_roster(players: Array, own_seat: int, capacity: int) -> void:
	roster_heading.text = "Spelare · %d/%d" % [players.size(), capacity]
	for n in range(_roster_labels.size()):
		var row := _roster_labels[n]
		row.visible = n < capacity
		var player := {}
		for candidate in players:
			if int(candidate.get("seat", -1)) == n:
				player = candidate
				break
		if player.is_empty():
			row.text = "%d  ·  Ledig plats" % [n + 1]
			row.add_theme_color_override("font_color", UI.MUTED)
		else:
			var suffix := " · du" if n == own_seat else ""
			if n == 0:
				suffix += " · värd"
			var present: bool = player.get("connected", false)
			row.text = "%s  %s%s · %s" % ["●" if present else "○", str(player.get("name", "Spelare")), suffix, "ansluten" if present else "frånkopplad"]
			row.add_theme_color_override("font_color", UI.CREAM if present else UI.GOLD)

func _valid_name() -> String:
	var player_name := Session.normalize_player_name(name_input.text)
	if not Session.valid_player_name(player_name):
		_show_error("Välj ett namn med 1–20 tecken, utan <, > eller kontrolltecken.")
		name_input.grab_focus()
		return ""
	name_input.text = player_name
	return player_name

func _submit_create() -> void:
	if _pending or create_button.disabled or _has_room:
		return
	var player_name := _valid_name()
	if player_name.is_empty():
		return
	_lock_request()
	create_requested.emit(player_name)

func _submit_join() -> void:
	if _pending or join_button.disabled or _has_room:
		return
	var player_name := _valid_name()
	if player_name.is_empty():
		return
	var room_code := Invite.room_from_input(code.text)
	if room_code.is_empty():
		_show_error("Rumskoden har 8 bokstäver eller siffror. Du kan också klistra in hela inbjudningslänken.")
		code.grab_focus()
		return
	code.text = room_code
	_lock_request()
	join_requested.emit(room_code, player_name)

func _lock_request() -> void:
	_pending = true
	create_button.disabled = true
	join_button.disabled = true
	name_input.release_focus()
	code.release_focus()

func _submit_start() -> void:
	if _pending or start_button.disabled or _started or _leaving:
		return
	_pending = true
	start_button.disabled = true
	start_button.text = "Startar matchen…"
	start_requested.emit(selected_map)

func _reconnect() -> void:
	if _pending or reconnect_button.disabled:
		return
	_pending = true
	reconnect_button.disabled = true
	reconnect_requested.emit()

func request_leave() -> void:
	if _leaving:
		cancel_leave()
		return
	if _has_room:
		_leaving = true
		confirm_panel.visible = true
		back_button.visible = false
		start_button.visible = false
		cancel_button.grab_focus()
	else:
		_finish_leave()

func is_confirming_leave() -> bool:
	return _leaving

func cancel_leave(notify_game: bool = true) -> void:
	_leaving = false
	confirm_panel.visible = false
	back_button.visible = true
	if _session != null:
		start_button.visible = _has_room and not _started and _session.seat == 0
	if notify_game:
		leave_cancelled.emit()

func _confirm_leave() -> void:
	if not _leaving:
		return
	_leaving = false
	_finish_leave()

func _finish_leave() -> void:
	_pending = false
	_share_pending = false
	confirm_panel.visible = false
	clear_invite()
	leave_requested.emit()

func _clear_entry_error() -> void:
	if _last_status not in ["error", "disconnected"]:
		message.text = "2–6 spelare, varsin skärm. Alla väljer sitt eget namn."
		message.add_theme_color_override("font_color", UI.MUTED)

func _show_error(value: String) -> void:
	message.text = value
	message.add_theme_color_override("font_color", UI.GOLD)

func _share_invite(use_share_sheet: bool) -> void:
	if _share_pending or not _has_room:
		return
	var link := Invite.share_url(_room)
	if link.is_empty():
		return
	_share_pending = true
	_share_elapsed = 0
	share_button.disabled = true
	copy_button.disabled = true
	invite_link.text = link
	if OS.has_feature("web"):
		# This executes directly from a button press. JS promises report back by key.
		_share_result_key = "kraterInvite" + str(get_instance_id()) + "_" + str(Time.get_ticks_msec())
		var script := """(function() {
		const key = %s;
		const url = %s;
		window[key] = 'pending';
		const finish = value => { window[key] = value; };
		const copy = () => {
			if (!navigator.clipboard || !window.isSecureContext) { finish('fallback'); return; }
			navigator.clipboard.writeText(url).then(() => finish('copied')).catch(() => finish('fallback'));
		};
		if (%s && navigator.share) {
			navigator.share({title:'Kraterkompisar', text:'Häng med i mitt rum!', url}).then(() => finish('shared')).catch(e => {
				if (e && e.name === 'AbortError') finish('cancelled'); else copy();
			});
		} else copy();
	})()""" % [JSON.stringify(_share_result_key), JSON.stringify(link), "true" if use_share_sheet else "false"]
		JavaScriptBridge.eval(script)
	else:
		DisplayServer.clipboard_set(link)
		_complete_share("copied" if DisplayServer.clipboard_get() == link else "fallback")

func _process(delta: float) -> void:
	if not _share_pending or not OS.has_feature("web"):
		return
	_share_elapsed += delta
	var result = JavaScriptBridge.eval("window[%s] || 'pending'" % JSON.stringify(_share_result_key))
	if result is String and result != "pending":
		JavaScriptBridge.eval("delete window[%s]" % JSON.stringify(_share_result_key))
		_complete_share(result)
	elif _share_elapsed > 45:
		_complete_share("fallback")

func _complete_share(result: String) -> void:
	_share_pending = false
	share_button.disabled = _started
	copy_button.disabled = _started
	match result:
		"copied":
			share_message.text = "Länken är kopierad. Klistra in den till dina vänner."
		"shared":
			share_message.text = "Inbjudan är delad. Vänta här medan dina vänner går med."
		"cancelled":
			share_message.text = "Delningen avbröts. Du kan också dela rumskoden ovan."
		_:
			invite_link.visible = true
			share_message.text = "Kopiering tilläts inte. Markera länken och kopiera, eller dela rumskoden ovan."
			invite_link.grab_focus()
			invite_link.select_all()

func layout(view: Vector2) -> void:
	_view = view
	position = Vector2.ZERO
	scale = Vector2.ONE
	size = view
	if box == null:
		return
	invite_actions.columns = 1 if view.x < 380 else 2
	var margin := 10.0 if view.x < 600 or view.y < 450 else 24.0
	var width := minf(620, view.x - margin * 2)
	var height := minf(850, view.y - margin * 2)
	box.custom_minimum_size = Vector2.ZERO
	box.position = Vector2((view.x - width) * 0.5, (view.y - height) * 0.5)
	box.size = Vector2(width, height)
	heading.add_theme_font_size_override("font_size", 23 if view.y < 450 else 28)
	column.add_theme_constant_override("separation", 6 if view.y < 450 else 10)
	_fit_box.call_deferred()

func place(_origin: Vector2, _factor: float, _top: float, _tall: bool) -> void:
	# Legacy entry point. New callers pass the actual viewport to layout(view).
	layout(get_viewport_rect().size)

func _fit_box() -> void:
	if box == null:
		return
	var margin := 10.0 if _view.x < 600 or _view.y < 450 else 24.0
	box.size = Vector2(minf(620, _view.x - margin * 2), minf(850, _view.y - margin * 2))
