class_name ModuleWindow
extends Control
## Fenêtre d'un module, ouverte par le joueur local depuis la zone
## d'interaction du module (Module.get_interaction_rect) avec l'action
## « interact » (Espace ou clic droit), refermée par la même action.
##
## À gauche : levier marche / arrêt et curseur de l'alimentation cible
## (selon Module.can_be_switched_off et Module.adjustable_power), décidés par
## l'hôte (Module.request_switch, Module.request_target_power).
## Au centre : les éléments propres au module (Module.build_interface).
## Sur le côté : ses statistiques (état, consommation, températures), mises à
## jour en continu. Tant que la fenêtre est ouverte, le personnage ne se
## déplace pas (voir Player._read_input).
## Une indication s'affiche en bas de l'écran quand le joueur est dans une zone.

## Vrai tant qu'une fenêtre de module est ouverte (lu par le joueur local).
static var is_open: bool = false

const WINDOW_SIZE := Vector2(760, 420)
const STATS_WIDTH := 240.0
const TITLE_FONT_SIZE := 26
const STAT_FONT_SIZE := 18
const INTACT_COLOR := Color(0.4, 0.95, 0.5)
const BROKEN_COLOR := Color(1.0, 0.35, 0.3)
const PROMPT_TEXT := "Espace / clic droit : utiliser %s"
const PANEL_COLOR := Color(0.09, 0.1, 0.13, 0.96)
const PANEL_BORDER_COLOR := Color(0.55, 0.58, 0.65)

## Commandes, à gauche du centre : levier marche / arrêt (si
## Module.can_be_switched_off), curseur d'alimentation cible en dessous (si
## Module.adjustable_power).
const CONTROLS_WIDTH := 110.0
const LEVER_SIZE := Vector2(56, 96)
const LEVER_ON_COLOR := Color(0.3, 0.9, 0.4)
const LEVER_OFF_COLOR := Color(0.95, 0.25, 0.2)
const LEVER_PLATE_COLOR := Color(0.23, 0.25, 0.3)
const LEVER_SLOT_COLOR := Color(0.05, 0.05, 0.07)
## Intervalle minimal (s) entre deux cibles envoyées pendant un glissement.
const SLIDER_SEND_INTERVAL := 0.1
## Curseur : largeur du rail (noir), manette carrée, repère « 100% » à droite
## (trait de SLIDER_MARK_LENGTH px ; un clic sur le texte règle l'optimum).
const SLIDER_TRACK_WIDTH := 8
const SLIDER_TRACK_COLOR := Color.BLACK
const SLIDER_GRABBER_SIZE := 20
const SLIDER_GRABBER_COLOR := Color(0.85, 0.88, 0.95)
const SLIDER_GRABBER_HIGHLIGHT := Color.WHITE
const SLIDER_GRABBER_BORDER := Color(0.3, 0.32, 0.38)
const SLIDER_MARK_LENGTH := 12.0
const SLIDER_MARK_FONT_SIZE := 14

@export var ship: Ship

var _module: Module
var _panel: PanelContainer
var _title: Label
var _content: VBoxContainer
var _state_label: Label
var _power_label: Label
var _machine_label: Label
var _room_label: Label
var _prompt: Label
var _controls: VBoxContainer
var _controls_separator: VSeparator
var _lever: Control
var _lever_label: Label
var _slider: VSlider
var _slider_box: VBoxContainer
var _slider_label: Label
var _slider_area: Control
var _optimal_button: Button
var _slider_dragging: bool = false
var _time_since_send: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_panel.hide()
	_prompt.hide()


## is_open est statique : à remettre à faux si la scène est rechargée (hôte
## parti) fenêtre ouverte, sinon le nouveau personnage resterait immobile.
func _exit_tree() -> void:
	if _module != null:
		close()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or event.is_echo() or Piloting.is_active():
		return
	if _module != null:
		close()
		get_viewport().set_input_as_handled()
		return
	var module := _get_module_in_reach()
	if module != null:
		open(module)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Mode pilotage (lancé depuis le volant) : fenêtre fermée, pas d'indication.
	if Piloting.is_active():
		if _module != null:
			close()
		_prompt.hide()
		return
	if _module != null:
		_update_stats()
		_update_controls(delta)
		return
	var module := _get_module_in_reach()
	_prompt.visible = module != null
	if module != null:
		_prompt.text = tr(PROMPT_TEXT) % module.get_type_name()


## Ouvre la fenêtre de [param module].
func open(module: Module) -> void:
	_module = module
	is_open = true
	_title.text = module.get_type_name()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	module.build_interface(_content)
	_lever.visible = module.can_be_switched_off
	_lever_label.visible = module.can_be_switched_off
	_slider_box.visible = module.adjustable_power
	_controls.visible = module.can_be_switched_off or module.adjustable_power
	_controls_separator.visible = _controls.visible
	_slider_dragging = false
	_slider.min_value = module.get_min_power()
	_slider.max_value = module.get_max_power()
	_layout_slider()
	_update_stats()
	_update_controls(0.0)
	_prompt.hide()
	_panel.show()


func close() -> void:
	_module = null
	is_open = false
	_panel.hide()


## Module dont la zone d'interaction contient le personnage local, ou null.
func _get_module_in_reach() -> Module:
	if ship == null or multiplayer.multiplayer_peer == null:
		return null
	var player := ship.get_node_or_null("Crew/%d" % multiplayer.get_unique_id()) as Node2D
	if player == null:
		return null
	# Joueurs et modules sont tous dans le repère du vaisseau.
	for module in ship.get_modules():
		if module.get_interaction_rect().has_point(player.position - module.position):
			return module
	return null


func _update_stats() -> void:
	var intact := _module.is_intact()
	_state_label.text = "Intact" if intact else "Cassé"
	_state_label.add_theme_color_override("font_color", INTACT_COLOR if intact else BROKEN_COLOR)
	_power_label.text = "%d W / %d W" % [roundi(_module.power_supplied), roundi(_module.get_ideal_power())]
	_machine_label.text = "%d °C" % roundi(_module.machine_temperature)
	_room_label.text = "%d °C" % roundi(_module.room_temperature)


## Levier et curseur suivent l'état décidé par l'hôte, sauf le curseur tant
## qu'il est tenu : sa valeur part alors au plus toutes les
## SLIDER_SEND_INTERVAL s, et une dernière fois au relâchement.
func _update_controls(delta: float) -> void:
	_lever.queue_redraw()
	_lever_label.text = tr("Marche") if _module.is_on else tr("Arrêt")
	if _slider_dragging:
		_time_since_send += delta
		if _time_since_send >= SLIDER_SEND_INTERVAL and not is_equal_approx(_slider.value, _module.target_power):
			_time_since_send = 0.0
			_module.request_target_power(_slider.value)
	else:
		_slider.set_value_no_signal(_module.get_power_cap())
	_slider_label.text = "%d W" % roundi(_slider.value)


func _on_lever_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_module.request_switch(not _module.is_on)
		_lever.accept_event()


func _on_slider_drag_ended(_value_changed: bool) -> void:
	_slider_dragging = false
	if _module != null:
		_module.request_target_power(_slider.value)


## Clic sur « 100% » : manette à l'alimentation optimale.
func _on_optimal_pressed() -> void:
	if _module == null:
		return
	_slider.set_value_no_signal(_module.get_ideal_power())
	_module.request_target_power(_module.get_ideal_power())


## Place le curseur dans sa zone, et le texte « 100% » à droite, à la hauteur
## de l'alimentation optimale.
func _layout_slider() -> void:
	var area := _slider_area.size
	var width := float(SLIDER_GRABBER_SIZE)
	_slider.position = Vector2(roundf(area.x * 0.35 - width / 2.0), 0.0)
	_slider.size = Vector2(width, area.y)
	var y := _get_optimal_y()
	_optimal_button.reset_size()
	_optimal_button.position = Vector2(_slider.position.x + width + SLIDER_MARK_LENGTH + 2.0,
			roundf(y - _optimal_button.size.y / 2.0))
	_slider_area.queue_redraw()


## Ordonnée (px, dans la zone du curseur) du centre de la manette à
## l'alimentation optimale ; même calcul que le dessin de VSlider.
func _get_optimal_y() -> float:
	if _module == null or _slider.max_value <= _slider.min_value:
		return 0.0
	var ratio := inverse_lerp(_slider.min_value, _slider.max_value, _module.get_ideal_power())
	var height := _slider.size.y
	var grabber := float(SLIDER_GRABBER_SIZE)
	return height - ratio * (height - grabber) - grabber / 2.0


## Trait du repère « 100% », à droite du rail.
func _draw_optimal_mark() -> void:
	if _module == null:
		return
	var x := _slider.position.x + _slider.size.x / 2.0 + SLIDER_TRACK_WIDTH / 2.0 + 2.0
	var y := _get_optimal_y()
	_slider_area.draw_line(Vector2(x, y), Vector2(_slider.position.x + _slider.size.x + SLIDER_MARK_LENGTH, y),
			PANEL_BORDER_COLOR, 2.0)


## Manette carrée du curseur (texture), cerclée de SLIDER_GRABBER_BORDER.
static func _make_grabber_texture(color: Color) -> ImageTexture:
	var image := Image.create_empty(SLIDER_GRABBER_SIZE, SLIDER_GRABBER_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(SLIDER_GRABBER_BORDER)
	image.fill_rect(Rect2i(2, 2, SLIDER_GRABBER_SIZE - 4, SLIDER_GRABBER_SIZE - 4), color)
	return ImageTexture.create_from_image(image)


## Manche vers le haut si le module est allumé, vers le bas s'il est éteint.
func _draw_lever() -> void:
	if _module == null:
		return
	var rect := Rect2(Vector2.ZERO, _lever.size)
	var center := rect.get_center()
	var color := LEVER_ON_COLOR if _module.is_on else LEVER_OFF_COLOR
	_lever.draw_rect(rect, LEVER_PLATE_COLOR)
	_lever.draw_rect(rect, PANEL_BORDER_COLOR, false, 2.0)
	var travel := rect.size.y * 0.32
	_lever.draw_line(center + Vector2(0, -travel), center + Vector2(0, travel), LEVER_SLOT_COLOR, 8.0)
	var knob := center + Vector2(0, -travel if _module.is_on else travel)
	_lever.draw_line(center, knob, PANEL_BORDER_COLOR, 5.0)
	_lever.draw_circle(knob, 11.0, color)
	_lever.draw_arc(knob, 11.0, 0.0, TAU, 32, color.darkened(0.4), 2.0)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = WINDOW_SIZE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = PANEL_BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	margin.add_child(columns)

	# Gauche : levier marche / arrêt, puis curseur de l'alimentation cible.
	_controls = VBoxContainer.new()
	_controls.custom_minimum_size.x = CONTROLS_WIDTH
	_controls.add_theme_constant_override("separation", 6)
	columns.add_child(_controls)
	_lever = Control.new()
	_lever.custom_minimum_size = LEVER_SIZE
	_lever.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_lever.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_lever.draw.connect(_draw_lever)
	_lever.gui_input.connect(_on_lever_input)
	_controls.add_child(_lever)
	_lever_label = Label.new()
	_lever_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls.add_child(_lever_label)
	_slider_box = VBoxContainer.new()
	_slider_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_controls.add_child(_slider_box)
	_slider_box.add_child(HSeparator.new())
	var slider_caption := Label.new()
	slider_caption.text = "Alimentation cible"
	slider_caption.modulate = Color(1, 1, 1, 0.6)
	slider_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slider_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_slider_box.add_child(slider_caption)
	# Zone du curseur : placement manuel (voir _layout_slider), pour aligner
	# le repère « 100% » sur la manette.
	_slider_area = Control.new()
	_slider_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slider_area.resized.connect(_layout_slider)
	_slider_area.draw.connect(_draw_optimal_mark)
	_slider_box.add_child(_slider_area)
	_slider = VSlider.new()
	_slider.step = 1.0
	_slider.focus_mode = Control.FOCUS_NONE
	# Rail noir sur toute la course, manette carrée.
	var track := StyleBoxFlat.new()
	track.bg_color = SLIDER_TRACK_COLOR
	track.content_margin_left = SLIDER_TRACK_WIDTH / 2.0
	track.content_margin_right = SLIDER_TRACK_WIDTH / 2.0
	for style_name in ["slider", "grabber_area", "grabber_area_highlight"]:
		_slider.add_theme_stylebox_override(style_name, track)
	_slider.add_theme_icon_override("grabber", _make_grabber_texture(SLIDER_GRABBER_COLOR))
	_slider.add_theme_icon_override("grabber_highlight", _make_grabber_texture(SLIDER_GRABBER_HIGHLIGHT))
	_slider.drag_started.connect(func() -> void:
		_slider_dragging = true
		_time_since_send = SLIDER_SEND_INTERVAL)
	_slider.drag_ended.connect(_on_slider_drag_ended)
	_slider_area.add_child(_slider)
	_optimal_button = Button.new()
	_optimal_button.text = "100%"
	_optimal_button.flat = true
	_optimal_button.focus_mode = Control.FOCUS_NONE
	_optimal_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_optimal_button.add_theme_font_size_override("font_size", SLIDER_MARK_FONT_SIZE)
	_optimal_button.add_theme_constant_override("h_separation", 0)
	for style_name in ["normal", "hover", "pressed", "focus"]:
		_optimal_button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	_optimal_button.pressed.connect(_on_optimal_pressed)
	_slider_area.add_child(_optimal_button)
	_slider_label = Label.new()
	_slider_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slider_label.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
	_slider_box.add_child(_slider_label)
	_controls_separator = VSeparator.new()
	columns.add_child(_controls_separator)

	# Centre : titre et éléments propres au module.
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 16)
	columns.add_child(main)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.add_child(_title)
	main.add_child(HSeparator.new())
	_content = VBoxContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_child(_content)

	columns.add_child(VSeparator.new())

	# Côté : statistiques.
	var stats := VBoxContainer.new()
	stats.custom_minimum_size.x = STATS_WIDTH
	stats.add_theme_constant_override("separation", 6)
	columns.add_child(stats)
	_state_label = _add_stat(stats, "État")
	_power_label = _add_stat(stats, "Consommation")
	_machine_label = _add_stat(stats, "Température de la machine")
	_room_label = _add_stat(stats, "Température de la pièce")

	# Indication en bas de l'écran.
	_prompt = Label.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.offset_bottom = -24
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
	add_child(_prompt)


## Ajoute à [param parent] une statistique (titre grisé puis valeur) ;
## renvoie le libellé de la valeur.
func _add_stat(parent: Container, title: String) -> Label:
	var caption := Label.new()
	caption.text = title
	caption.modulate = Color(1, 1, 1, 0.6)
	parent.add_child(caption)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
	parent.add_child(value)
	parent.add_child(Control.new())  # petit espace
	return value
