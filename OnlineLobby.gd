extends Control
## Native text entry keeps room codes usable on touch devices and with a keyboard.
signal create_requested
signal join_requested(code: String)
signal leave_requested
signal reconnect_requested
signal copy_requested
var box: PanelContainer
var message: Label
var code: LineEdit
var create_button: Button
var join_button: Button
var reconnect_button: Button
var copy_button: Button
var back_button: Button
var room_label: Label
var connected := false
var heading: Label
var column: VBoxContainer
var _box_width := 676.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	box = PanelContainer.new()
	add_child(box)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1f2237")
	style.border_color = Color("756789")
	style.set_border_width_all(2)
	style.set_corner_radius_all(24)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	box.add_theme_stylebox_override("panel", style)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	box.add_child(column)
	var title := Label.new()
	heading = title
	title.text = "SPELA PÅ VARSIN SKÄRM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("f9c95e"))
	title.add_theme_font_size_override("font_size", 25)
	column.add_child(title)
	message = Label.new()
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(590, 50)
	message.add_theme_font_size_override("font_size", 18)
	column.add_child(message)
	room_label = Label.new()
	room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_label.add_theme_font_size_override("font_size", 30)
	room_label.add_theme_color_override("font_color", Color("91d2b0"))
	column.add_child(room_label)
	create_button = _button(column, "SKAPA RUM · DU ÄR DANIEL")
	create_button.pressed.connect(func(): create_requested.emit())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	code = LineEdit.new()
	code.placeholder_text = "RUMSKOD"
	code.max_length = 8
	code.custom_minimum_size = Vector2(272, 58)
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.add_theme_font_size_override("font_size", 24)
	code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.text_changed.connect(func(value: String):
		var caret := code.caret_column
		code.text = value.to_upper()
		code.caret_column = caret)
	code.text_submitted.connect(func(_value: String):
		if not join_button.disabled:
			join_requested.emit(code.text))
	row.add_child(code)
	join_button = _button(row, "GÅ MED · JESUS")
	join_button.pressed.connect(func(): join_requested.emit(code.text))
	copy_button = _button(column, "KOPIERA RUMSKOD")
	copy_button.pressed.connect(func(): copy_requested.emit())
	reconnect_button = _button(column, "ÅTERANSLUT")
	reconnect_button.pressed.connect(func(): reconnect_requested.emit())
	back_button = _button(column, "TILLBAKA TILL START")
	back_button.pressed.connect(func(): leave_requested.emit())
	visible = false

func _button(parent: Control, text: String) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 54
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_font_size_override("font_size", 20)
	parent.add_child(result)
	return result

func place(origin: Vector2, factor: float, top: float, tall: bool) -> void:
	position = origin
	scale = Vector2.ONE * factor
	size = Vector2(1280, 2200 if tall else 800)
	box.position = Vector2(80 if tall else 302, top + 5)
	_box_width = 1120.0 if tall else 676.0
	column.add_theme_constant_override("separation", 20 if tall else 12)
	heading.add_theme_font_size_override("font_size", 42 if tall else 25)
	message.add_theme_font_size_override("font_size", 32 if tall else 18)
	message.custom_minimum_size = Vector2(1010 if tall else 590, 100 if tall else 50)
	room_label.add_theme_font_size_override("font_size", 42 if tall else 30)
	for button in [create_button, join_button, copy_button, reconnect_button, back_button]:
		button.custom_minimum_size.y = 132 if tall else 54
		button.add_theme_font_size_override("font_size", 32 if tall else 20)
	code.custom_minimum_size = Vector2(420 if tall else 272, 132 if tall else 58)
	code.add_theme_font_size_override("font_size", 42 if tall else 24)
	# Font/minimum-size changes propagate through nested Containers deferred.
	# Shrinking before they propagate retains the old portrait minimum forever.
	box.custom_minimum_size = Vector2(_box_width, 0)
	_fit_box.call_deferred()

func _fit_box() -> void:
	box.reset_size()

func refresh(session) -> void:
	connected = session.status == "connected"
	var busy: bool = session.status == "connecting" or connected
	var has_room: bool = not session.room.is_empty()
	message.text = session.status_text if not session.status_text.is_empty() else ("Skapa ett privat rum och dela koden. Inga spelarkonton behövs." if session.configured() else "Onlineservern är inte aktiverad ännu. Du kan spela lokal duell tills den är klar.")
	room_label.text = "%s · DU ÄR %s" % [session.room, "DANIEL" if session.seat == 0 else "JESUS"] if has_room else ""
	room_label.visible = has_room
	create_button.visible = not has_room
	create_button.disabled = busy or not session.configured()
	code.get_parent().visible = not has_room
	code.editable = not busy
	join_button.disabled = busy or not session.configured()
	copy_button.visible = has_room
	reconnect_button.visible = has_room and session.status == "disconnected"
	back_button.text = "LÄMNA RUMMET" if has_room else "TILLBAKA TILL START"

	_fit_box.call_deferred()
