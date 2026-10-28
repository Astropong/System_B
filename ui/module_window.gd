class_name ModuleWindow
extends Control
## Fenêtre d'un module, ouverte par le joueur local depuis la zone
## d'interaction du module (Module.get_interaction_rect) avec l'action
## « interact » (Espace ou clic droit), refermée par la même action.
##
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


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_panel.hide()
	_prompt.hide()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or event.is_echo():
		return
	if _module != null:
		close()
		get_viewport().set_input_as_handled()
		return
	var module := _get_module_in_reach()
	if module != null:
		open(module)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _module != null:
		_update_stats()
		return
	var module := _get_module_in_reach()
	_prompt.visible = module != null
	if module != null:
		_prompt.text = PROMPT_TEXT % module.get_type_name()


## Ouvre la fenêtre de [param module].
func open(module: Module) -> void:
	_module = module
	is_open = true
	_title.text = module.get_type_name()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	module.build_interface(_content)
	_update_stats()
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
