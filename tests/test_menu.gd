extends SceneTree
## Native Control tests: entry, invitations, privacy, interrupted/repeated flows and resize.
const Lobby = preload("res://OnlineLobby.gd")
const Menu = preload("res://StartMenu.gd")
const Invite = preload("res://FriendInvite.gd")
const Net = preload("res://NetSession.gd")
var checks := 0
var failures := 0
var events: Array = []
var lobby
var menu
var session

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, text: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", text)
	else:
		failures += 1
		push_error("FAIL: " + text)

func run() -> void:
	session = Net.new()
	root.add_child(session)
	session.set_process(false)
	session.server_url = "wss://example.invalid"
	lobby = Lobby.new()
	root.add_child(lobby)
	menu = Menu.new()
	root.add_child(menu)
	menu.visible = false
	lobby.visible = true
	lobby.create_requested.connect(func(player_name: String): events.append(["create", player_name]))
	lobby.join_requested.connect(func(code: String, player_name: String): events.append(["join", code, player_name]))
	lobby.leave_requested.connect(func(): events.append(["leave"]))
	lobby.start_requested.connect(func(map_id: int): events.append(["start", map_id]))
	lobby.reconnect_requested.connect(func(): events.append(["reconnect"]))
	menu.local_requested.connect(func(map_id: int): events.append(["local", map_id]))
	menu.online_requested.connect(func(map_id: int): events.append(["online", map_id]))
	await process_frame
	lobby.refresh(session)
	check(lobby.name_input.placeholder_text == "Välj ett namn" and lobby.name_input.text.is_empty(), "Name is explicitly chosen; no personal name or role assumed")
	check(not "JESUS" in lobby.join_button.text and not "DANIEL" in lobby.create_button.text, "Create and join actions do not assign avatar roles")
	lobby._submit_create()
	check(events.is_empty() and "namn" in lobby.message.text, "Blank name gives actionable error without creating room")
	lobby.name_input.text = "<script>"
	lobby._submit_create()
	check(events.is_empty(), "Markup name rejected before connection")
	lobby.name_input.text = "Åsa 🦊"
	lobby._submit_create()
	lobby._submit_create()
	check(events == [["create", "Åsa 🦊"]], "Unicode name creates room exactly once despite repeated tap")
	session.status = "error"
	session.status_text = "Servern svarade inte. Försök igen."
	lobby.refresh(session)
	check(not lobby.create_button.disabled and lobby.name_input.text == "Åsa 🦊", "Connection failure preserves name and allows retry")
	events.clear()
	lobby.request_leave()
	check(events == [["leave"]] and not lobby.confirm_panel.visible, "Back before joining requires no destructive-room confirmation")
	events.clear()
	session.status = "idle"
	session.status_text = ""
	lobby.refresh(session)
	check(lobby.open_invite("https://danielkretz-cpu.github.io/daniel-jesus-duel/?room=abcd2345&token=PRIVATE"), "Room invitation opens with valid lowercase code")
	check(events.is_empty() and lobby.code.text == "ABCD2345" and not lobby.create_button.visible, "Invite prefills room and skips create without autojoining or sharing name")
	lobby._submit_join()
	lobby._submit_join()
	check(events == [["join", "ABCD2345", "Åsa 🦊"]], "Explicit join sends chosen name once")
	events.clear()
	session.status = "error"
	lobby.refresh(session)
	lobby.code.text = "ABCD!!!!"
	lobby._submit_join()
	check(events.is_empty() and "8" in lobby.message.text, "Invalid room code stays editable and explains format")
	lobby.code.text = "https://danielkretz-cpu.github.io/daniel-jesus-duel/?room=ABCD2345"
	lobby._submit_join()
	check(events == [["join", "ABCD2345", "Åsa 🦊"]], "Pasted full invitation URL is accepted by direct join")
	check(Invite.share_url("abcd2345") == Invite.PUBLIC_URL + "?room=ABCD2345", "Share URL canonicalizes code and has only one public query parameter")
	check(Invite.share_url("ABCD2345&token=SECRET").is_empty(), "Share builder rejects data that could inject a resume credential")
	check(Invite.room_from_url("https://example.test/?room=%41BCD2345#token=SECRET") == "ABCD2345", "Percent-encoded room parses without reading fragment secrets")
	check(Invite.room_from_url("https://example.test/#room=ABCD2345") == "ABCD2345", "Hash invitation fallback parses")
	check(Invite.room_from_url("https://example.test/?room=ABCD2345&room=EFGH6789").is_empty(), "Ambiguous duplicate room parameters are rejected")
	check(Invite.room_from_url("https://example.test/?room=%3Cscript%3E").is_empty(), "Malicious invite input never becomes a displayed room")
	check(Invite.room_from_input("  abcd2345  ") == "ABCD2345", "Direct code accepts friendly whitespace and lowercase")
	check(Invite.room_from_url("https://example.test/?room=ABCD2345%26token%3DSECRET").is_empty(), "Encoded query-injection room is rejected")
	setup_room(1)
	lobby.refresh(session)
	check(lobby.room_content.visible and not lobby.entry.visible and lobby.start_button.disabled, "Creating host enters waiting room and cannot start alone")
	check(lobby.room_label.text == "RUM  ABCD2345" and not "SECRET" in lobby.invite_link.text, "Room display and invitation never expose session token")
	setup_room(6)
	lobby.refresh(session)
	check(lobby._roster_labels.size() == 6 and "6/6" in lobby.roster_heading.text, "Six-player lobby exposes all six seats")
	check("Åsa 🦊" in lobby._roster_labels[0].text and "Zoë" in lobby._roster_labels[5].text, "Roster uses chosen Unicode names")
	check(not lobby.start_button.disabled and not lobby.map_picker.disabled, "Host may select map and start a full connected room")
	lobby.set_map(3)
	events.clear()
	lobby._submit_start()
	lobby._submit_start()
	check(events == [["start", 3]], "Start requires a separate explicit action and repeat tap cannot restart")
	session.roster[4].connected = false
	lobby.refresh(session)
	check(lobby.start_button.disabled and "frånkopplad" in lobby._roster_labels[4].text, "Disconnected reserved seat is clear and blocks start")
	check(lobby.connection_help.visible and "Återanslut" in lobby.connection_help.text and "skapa ett nytt" in lobby.connection_help.text, "Host sees both reconnect and fresh-room recovery for a departed reserved seat")
	session.seat = 5
	lobby.refresh(session)
	check(not lobby.start_button.visible and lobby.map_picker.disabled and "du" in lobby._roster_labels[5].text, "Guest sees own name but cannot start or change arena")
	events.clear()
	lobby.request_leave()
	check(events.is_empty() and lobby.confirm_panel.visible, "Leaving a reserved room asks for confirmation")
	lobby.cancel_leave()
	check(events.is_empty() and not lobby.confirm_panel.visible, "Cancelling leave returns to the same room without network action")
	lobby.request_leave()
	lobby._confirm_leave()
	lobby._confirm_leave()
	check(events == [["leave"]], "Confirmed leave emits only once even after repeated click")
	lobby.refresh(session)
	lobby._complete_share("fallback")
	check(lobby.invite_link.visible and lobby.invite_link.text == Invite.share_url(session.room) and "Markera" in lobby.share_message.text, "Denied clipboard reveals selectable safe link and room-code fallback")
	lobby._complete_share("cancelled")
	check("avbröts" in lobby.share_message.text and not lobby.copy_button.disabled, "Cancelled native sharing keeps room intact and copy usable")
	lobby._complete_share("copied")
	check("kopierad" in lobby.share_message.text, "Copy success has clear next step")
	session.status = "disconnected"
	lobby.refresh(session)
	events.clear()
	lobby._reconnect()
	lobby._reconnect()
	check(lobby.reconnect_button.visible and events == [["reconnect"]], "Disconnected player can request resume only once")
	setup_room(6)
	lobby.refresh(session)
	lobby.request_leave()
	lobby.request_leave()
	check(not lobby.is_confirming_leave(), "Escape again cancels leave rather than trapping the confirmation")
	for view in [Vector2(430, 932), Vector2(852, 393), Vector2(320, 568), Vector2(1180, 812), Vector2(393, 852), Vector2(1280, 800), Vector2(568, 320)]:
		lobby.layout(view)
		menu.layout(view)
		await process_frame
		await process_frame
		check(lobby.box.position.x >= 0 and lobby.box.position.y >= 0 and lobby.box.get_rect().end.x <= view.x + 1 and lobby.box.get_rect().end.y <= view.y + 1, "Lobby card remains inside %dx%d after rotation" % [view.x, view.y])
		check(lobby.back_button.get_global_rect().end.y <= view.y + 1 and lobby.back_button.get_global_rect().size.y >= 44, "Back stays reachable and finger-sized at %dx%d" % [view.x, view.y])
		check(lobby.start_button.get_global_rect().end.y <= view.y + 1 and lobby.start_button.get_global_rect().size.y >= 44, "Host start stays reachable and finger-sized at %dx%d" % [view.x, view.y])
		check(menu.box.get_rect().end.x <= view.x + 1 and menu.box.get_rect().end.y <= view.y + 1, "Start menu resizes without stale portrait minimum at %dx%d" % [view.x, view.y])
		check(menu.local_button.get_global_rect().end.y <= menu.box.get_rect().end.y - 8 and menu.online_button.get_global_rect().position.y >= menu.box.position.y, "Both local and online choices are visible without scrolling at %dx%d" % [view.x, view.y])
		check(lobby.scroll.size.y > 0, "Room content can scroll in %dx%d" % [view.x, view.y])
	menu.visible = true
	menu.set_map(4)
	events.clear()
	menu._activate(false)
	menu._activate(false)
	check(events == [["local", 4]], "Local entry uses selected arena and ignores double tap")
	menu.visible = false
	menu.visible = true
	menu._activate(true)
	check(events == [["local", 4], ["online", 4]], "Returning to menu enables online entry again")
	lobby.queue_free()
	menu.queue_free()
	session.queue_free()
	await process_frame
	await run_game_integration()
	print("RESULT: %d menu checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func setup_room(count: int) -> void:
	session.room = "ABCD2345"
	session.token = "SECRET_RESUME_TOKEN"
	session.seat = 0
	session.status = "connected"
	session.status_text = "Bjud in vänner och starta när alla är redo."
	session.started = false
	session.roster.clear()
	var names := ["Åsa 🦊", "Sam", "Alex", "Robin", "Kim", "Zoë"]
	for n in range(count):
		session.roster.append({"seat": n, "name": names[n], "connected": true})

func run_game_integration() -> void:
	var game = load("res://Main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.net.set_process(false)
	game.sound_on = false
	await process_frame
	check(game.start_menu.visible and not game.lobby.visible, "Shipping scene starts in the new menu")
	game.start_menu.set_map(2)
	game.start_menu._activate(false)
	check(game.phase == "aim" and game.map_id == 2 and not game.start_menu.visible, "Local menu signal starts the selected arena and hides menu immediately")
	game.turn = 5
	game.shots = 3
	game.fighters[0].hp = 59
	game.carve(Vector2(650, 380), 24)
	var local_snapshot: Dictionary = game.network_snapshot().duplicate(true)
	game._pointer(game.buttons.help.get_center(), 98, true)
	check(game.help_open and game.network_snapshot() == local_snapshot, "Opening local help preserves nondefault turn, health, shots and craters")
	game._pointer(game.buttons.close_help.get_center(), 98, true)
	check(not game.help_open and game.network_snapshot() == local_snapshot, "Closing local help never starts a fresh match")
	game._restart_action()
	game._process(0)
	game.start_menu._activate(true)
	check(game.online and game.lobby.visible and not game.start_menu.visible, "Online menu signal opens lobby without starting a match")
	game.lobby.open_invite("ABCD2345")
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_SPACE
	var before_menu_shots: int = game.shots
	game._input(key)
	check(game.phase == "title" and game.shots == before_menu_shots and game.net.room.is_empty(), "Gameplay keyboard cannot bypass the visible invitation menu")
	game.lobby.request_leave()
	check(not game.online and game.start_menu.visible and not game.lobby.visible, "Entry Back returns to the shipping start menu")
	game._open_online()
	game.net.room = "ABCD2345"
	game.net.token = "PRIVATE_TEST_TOKEN"
	game.net.seat = 0
	game.net.status = "connected"
	game.net.host_connected = true
	game.net.guest_connected = true
	game.net.started = false
	game.net.roster = [{"seat": 0, "name": "Åsa", "connected": true}, {"seat": 1, "name": "Zoë", "connected": true}]
	game._network_changed()
	check(game.phase == "title" and not game._online_started and game.lobby.visible, "Two connected players remain in lobby until explicit host start")
	game.net.started = true
	game._network_changed()
	check(game.phase == "aim" and game._online_started and not game.lobby.visible, "Server-approved start transitions into the actual game")
	check(game.fighters[0].name == "Åsa" and game.fighters[1].name == "Zoë", "Chosen lobby names become actual fighter names")
	game.turn = 7
	game.shots = 4
	game.fighters[0].hp = 63
	game.carve(Vector2(650, 380), 28)
	var preserved_snapshot: Dictionary = game.network_snapshot().duplicate(true)
	game.pointers[77] = "right"
	game._refresh_held()
	game._restart_action()
	var released := InputEventScreenTouch.new()
	released.index = 77
	released.pressed = false
	game._input(released)
	check(game.lobby.visible and game.lobby.is_confirming_leave() and game.phase == "aim", "Active match restart opens confirmation without discarding the game")
	game._refresh_network_overlay()
	check(game.lobby.visible and game.lobby.is_confirming_leave(), "Incoming network refresh cannot dismiss an unanswered leave confirmation")
	game.lobby.cancel_leave()
	check(not game.lobby.visible and game.online and game.phase == "aim", "Stanna immediately resumes host game without needing a network event")
	check(game.pointers.is_empty() and game.held.is_empty(), "A movement touch released behind confirmation cannot remain held after cancel")
	check(game.network_snapshot() == preserved_snapshot, "Cancelled leave preserves the full match including nondefault turn, health, shots and craters")
	var previous_x: float = game.fighters[0].pos.x
	game._physics_process(0.1)
	check(is_equal_approx(previous_x, float(game.fighters[0].pos.x)), "Cancelling leave never moves the fighter without a finger still down")
	game._restart_action()
	key.physical_keycode = KEY_ESCAPE
	game._input(key)
	check(not game.lobby.visible and game.online, "Escape cancels active-match leave confirmation")
	game._restart_action()
	game.lobby._confirm_leave()
	check(not game.online and game.start_menu.visible and game.net.token.is_empty(), "Confirmed leave clears credential and returns to start")
	game.queue_free()
	await process_frame
