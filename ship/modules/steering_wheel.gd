class_name SteeringWheel
extends Control
## Volant cliquable de la fenêtre du module de pilotage (voir
## ModulePilotage.build_interface) : au survol de la souris, il prend la
## couleur HOVER_COLOR et grossit légèrement ; un clic gauche émet [signal pressed].

## Émis au clic gauche sur le volant.
signal pressed

## Diamètre du volant (px).
const WHEEL_SIZE := 140.0
const RIM_WIDTH := 12.0
const HUB_RADIUS := 16.0
const SPOKE_WIDTH := 8.0
const COLOR := Color(0.7, 0.74, 0.82)
const HOVER_COLOR := ModulePilotage.ACCENT
## Agrandissement au survol, et durée de la transition (s).
const HOVER_SCALE := 1.08
const HOVER_TIME := 0.1

var _hovered: bool = false
# Agrandissement appliqué au dessin (la propriété scale serait remise à 1 par
# le conteneur parent).
var _hover_scale: float = 1.0
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(WHEEL_SIZE, WHEEL_SIZE) * HOVER_SCALE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()


func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	queue_redraw()
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(value: float) -> void:
		_hover_scale = value
		queue_redraw(), _hover_scale, HOVER_SCALE if hovered else 1.0, HOVER_TIME)


## Jante, trois rayons et moyeu, agrandis de _hover_scale autour du centre.
func _draw() -> void:
	var color := HOVER_COLOR if _hovered else COLOR
	var center := size / 2.0
	draw_set_transform(center * (1.0 - _hover_scale), 0.0, Vector2.ONE * _hover_scale)
	var radius := WHEEL_SIZE / 2.0 - RIM_WIDTH / 2.0
	draw_arc(center, radius, 0.0, TAU, 64, color, RIM_WIDTH, true)
	for angle in [PI / 2.0, PI / 2.0 + TAU / 3.0, PI / 2.0 - TAU / 3.0]:
		draw_line(center, center + Vector2.from_angle(angle) * radius, color, SPOKE_WIDTH, true)
	draw_circle(center, HUB_RADIUS, color)
	draw_circle(center, HUB_RADIUS * 0.5, color.darkened(0.5))
