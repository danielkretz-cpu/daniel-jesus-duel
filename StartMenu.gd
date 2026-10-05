extends Control
## A simple front door: choose a local two-player duel or invite up to six friends.
signal local_requested(map_index: int)
signal online_requested(map_index: int)
signal map_changed(map_index: int)
const UI = preload("res://MenuUI.gd")
const Maps = preload("res://MapThemes.gd")
var box: PanelContainer
var column: VBoxContainer
var heading: Label
var map_picker: OptionButton
var local_button: Button
var online_button: Button
var selected_map := 0
var _action_pending := false
var _view := Vector2(1280, 800)
var _decorative: Array[Control] = []

func _ready() -> void:
	theme = UI.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.065, 0.11, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	box = PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.style(UI.PANEL, 22, Color("4c627e")))
	add_child(box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 13)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var eyebrow := UI.label(column, "VÄNNER · KRATRAR · EN TUR TILL", 13, UI.MINT)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_decorative.append(eyebrow)
	heading = UI.label(column, "Kraterkompisar", 36)
	heading.add_theme_font_override("font", load("res://assets/Bold.ttf"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := UI.label(column, "Sikta, skjut och bli sist kvar på ön.", 17, UI.MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_decorative.append(subtitle)
	online_button = UI.button(column, "Spela online · 2–6 vänner", true)
	online_button.custom_minimum_size.y = 58
	online_button.pressed.connect(func(): _activate(true))
	var online_note := UI.label(column, "Varsin mobil eller dator. Bjud in med en länk.", 14, UI.MUTED)
	online_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_decorative.append(online_note)
	column.add_child(HSeparator.new())
	UI.label(column, "Bana för lokal duell", 14, UI.MUTED)
	map_picker = OptionButton.new()
	map_picker.custom_minimum_size.y = 48
	map_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_picker.clip_text = true
	for n in range(Maps.count()):
		map_picker.add_item(Maps.title(n), n)
	map_picker.select(selected_map)
	map_picker.item_selected.connect(func(index: int):
		selected_map = index
		map_changed.emit(index))
	column.add_child(map_picker)
	local_button = UI.button(column, "Lokal duell · samma skärm")
	local_button.pressed.connect(func(): _activate(false))
	var footer := UI.label(column, "Två spelare turas om. Inga konton behövs.", 13, UI.MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_decorative.append(footer)
	visibility_changed.connect(func():
		if visible:
			_action_pending = false
			local_button.disabled = false
			online_button.disabled = false)
	layout(_view)

func _activate(is_online: bool) -> void:
	if _action_pending or not visible:
		return
	_action_pending = true
	local_button.disabled = true
	online_button.disabled = true
	if is_online:
		online_requested.emit(selected_map)
	else:
		local_requested.emit(selected_map)

func set_map(value: int) -> void:
	selected_map = clampi(value, 0, Maps.count() - 1)
	if map_picker != null:
		map_picker.select(selected_map)

func layout(view: Vector2) -> void:
	_view = view
	position = Vector2.ZERO
	scale = Vector2.ONE
	size = view
	if box == null:
		return
	var margin := 12.0 if view.x < 600 else 24.0
	var width := minf(560, view.x - margin * 2)
	var height := minf(540, view.y - margin * 2)
	box.position = Vector2((view.x - width) * 0.5, (view.y - height) * 0.5)
	box.custom_minimum_size = Vector2.ZERO
	box.size = Vector2(width, height)
	var compact := view.y < 500
	for decoration in _decorative:
		decoration.visible = not compact
	column.add_theme_constant_override("separation", 8 if compact else 13)
	heading.add_theme_font_size_override("font_size", 28 if compact else (29 if view.x < 390 else 36))
	_fit_box.call_deferred()

func _fit_box() -> void:
	# Containers settle deferred after orientation/font changes, then shrink safely.
	if box != null:
		box.size = Vector2(minf(560, _view.x - (24 if _view.x < 600 else 48)), minf(540, _view.y - (24 if _view.x < 600 else 48)))
