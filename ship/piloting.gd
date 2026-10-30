class_name Piloting
extends Control
## Mode pilotage du joueur local, lancé par le volant de la fenêtre du module
## de pilotage (ModulePilotage.build_interface → Piloting.enter).
##
## En TRANSITION_TIME secondes, la caméra du joueur s'éloigne (zoom divisé par
## ZOOM_FACTOR), vise LOOK_AHEAD cases devant le centre du vaisseau et cesse
## de tourner avec lui :
## l'espace reste fixe à l'écran, c'est le vaisseau qui tourne. Le clavier
## (flèches, ZQSD, WASD) et le bouton gauche maintenu dirigent alors le
## vaisseau au lieu du personnage, immobile ; le clic droit quitte le mode
## (même transition en sens inverse).
##
## Diriger : le vaisseau tourne vers la direction voulue (touches, ou du
## centre du vaisseau vers la souris) et avance d'autant plus vite qu'il y est
## aligné ; sans commande, il s'arrête. Les vitesses sont demandées à l'hôte
## (Ship.request_motion), qui fait autorité sur le vaisseau.
## Si aucun module de pilotage n'atteint son alimentation minimale
## (Ship.is_helm_powered), les commandes sont sans effet : rien n'est envoyé
## (l'hôte refuse aussi), le vaisseau garde son mouvement et un avertissement
## remplace l'indication.
## Rien n'empêche deux joueurs de piloter en même temps : la dernière demande
## l'emporte.

## Rapport entre le zoom du joueur et celui du mode pilotage.
const ZOOM_FACTOR := 20.0
## Durée (s) du passage d'une vue à l'autre.
const TRANSITION_TIME := 0.5
## Vitesse de rotation demandée par degré d'écart avec la direction voulue (°/s).
const STEER_GAIN := 2.0
## Écart (°) en dessous duquel le vaisseau ne tourne plus.
const STEER_DEAD_ZONE := 1.0
## La vitesse d'avancée est arrondie à un SPEED_STEPS-ième de Ship.max_speed.
const SPEED_STEPS := 10
## Intervalle minimal (s) entre deux demandes de vitesses.
const SEND_INTERVAL := 0.1
## Distance (px) au centre du vaisseau en dessous de laquelle la souris est ignorée.
const MOUSE_DEAD_ZONE := Module.CELL_SIZE * 4.0
## Point visé par la caméra : à LOOK_AHEAD cases devant le centre du vaisseau.
const LOOK_AHEAD := 64.0
const HINT_TEXT := "Pilotage : flèches, ZQSD, WASD ou clic gauche maintenu pour diriger le vaisseau   |   clic droit : quitter"
const UNPOWERED_TEXT := "Pilotage hors service : alimentation insuffisante   |   clic droit : quitter"
const UNPOWERED_COLOR := Color(1.0, 0.35, 0.3)

enum State { OFF, ENTERING, ACTIVE, LEAVING }

static var _instance: Piloting

@export var ship: Ship

var _state: State = State.OFF
## Avancement de la transition : 0 = vue du joueur, 1 = vue de pilotage.
var _progress: float = 0.0
var _camera: Camera2D
var _base_zoom := Vector2.ONE
## Tours entiers (rad) retirés de l'orientation du vaisseau pour que la caméra
## ne refasse pas tous les tours accumulés (angles non repliés).
var _turns: float = 0.0
## Le bouton gauche qui a cliqué le volant doit être relâché avant de diriger.
var _mouse_armed: bool = false
var _sent_speed: float = -1.0
var _sent_angular_speed: float = 0.0
var _time_since_send: float = 0.0
var _hint: Label


## Vrai pendant le mode pilotage, transitions comprises : le personnage local
## ne bouge pas et la fenêtre de module ne s'ouvre pas.
static func is_active() -> bool:
	return _instance != null and _instance._state != State.OFF


## Passe le joueur local en mode pilotage.
static func enter() -> void:
	if _instance != null:
		_instance._enter()


func _enter_tree() -> void:
	_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint = Label.new()
	_hint.text = HINT_TEXT
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_bottom = -24
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", ModuleWindow.STAT_FONT_SIZE)
	_hint.hide()
	add_child(_hint)


func _enter() -> void:
	if _state != State.OFF or ship == null or multiplayer.multiplayer_peer == null:
		return
	var player := ship.get_node_or_null("Crew/%d" % multiplayer.get_unique_id())
	if player == null:
		return
	_camera = player.get_node("Camera2D")
	_base_zoom = _camera.zoom
	_turns = roundf(ship.rotation / TAU) * TAU
	_mouse_armed = false
	_sent_speed = -1.0  # force le premier envoi
	_time_since_send = SEND_INTERVAL
	_state = State.ENTERING
	_hint.show()


func _leave() -> void:
	_state = State.LEAVING
	_hint.hide()
	# Les tours faits pendant le pilotage ne sont pas à refaire en sens inverse.
	var turns := roundf(ship.rotation / TAU) * TAU
	if turns != _turns:
		_turns = turns
		_apply_camera()
		_camera.reset_physics_interpolation()
	if ship.is_helm_powered() and (_sent_speed != 0.0 or _sent_angular_speed != 0.0):
		_send(0.0, 0.0)


func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_RIGHT:
		return
	if _state == State.ENTERING or _state == State.ACTIVE:
		_leave()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _state == State.OFF:
		return
	if not is_instance_valid(_camera):
		_state = State.OFF
		_hint.hide()
		return
	match _state:
		State.ENTERING:
			_progress = minf(_progress + delta / TRANSITION_TIME, 1.0)
			if _progress >= 1.0:
				_state = State.ACTIVE
		State.LEAVING:
			_progress = maxf(_progress - delta / TRANSITION_TIME, 0.0)
	if _state == State.ENTERING or _state == State.ACTIVE:
		_steer(delta)
	_apply_camera()
	if _state == State.LEAVING and _progress <= 0.0:
		_state = State.OFF


## Caméra entre la vue du joueur (progress 0) et celle du pilotage (1). Elle
## reste enfant du personnage, sans rotation propre dans le vaisseau : pour
## viser devant le vaisseau et annuler sa rotation, on la décale de
## -position du personnage (le centre du vaisseau est son origine) plus
## LOOK_AHEAD cases vers l'avant (sa droite), et on la tourne de
## -orientation du vaisseau.
func _apply_camera() -> void:
	var weight := smoothstep(0.0, 1.0, _progress)
	var player := _camera.get_parent() as Node2D
	_camera.position = (Vector2(LOOK_AHEAD * Module.CELL_SIZE, 0.0) - player.position) * weight
	_camera.rotation = -(ship.rotation - _turns) * weight
	_camera.zoom = _base_zoom.lerp(_base_zoom / ZOOM_FACTOR, weight)


## Direction voulue (clavier, sinon souris) → vitesses demandées à l'hôte ;
## rien sans alimentation du pilotage.
func _steer(delta: float) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mouse_armed = true
	var powered := ship.is_helm_powered()
	_show_hint(powered)
	if not powered:
		_sent_speed = -1.0  # renvoi forcé au retour de l'alimentation
		return
	var direction := Vector2.ZERO
	var keys := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if keys != Vector2.ZERO:
		# Directions de l'écran, ramenées dans le monde.
		direction = keys.rotated(_camera.global_rotation)
	elif _mouse_armed and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var to_mouse := ship.get_global_mouse_position() - ship.global_position
		if to_mouse.length() > MOUSE_DEAD_ZONE:
			direction = to_mouse

	var new_speed := 0.0
	var new_angular_speed := 0.0
	if direction != Vector2.ZERO:
		var error := rad_to_deg(angle_difference(ship.rotation, direction.angle()))
		if absf(error) > STEER_DEAD_ZONE:
			new_angular_speed = clampf(roundf(error * STEER_GAIN), -ship.max_angular_speed, ship.max_angular_speed)
		var alignment := clampf(cos(deg_to_rad(error)), 0.0, 1.0)
		new_speed = ship.max_speed * roundf(alignment * SPEED_STEPS) / SPEED_STEPS

	_time_since_send += delta
	if (new_speed != _sent_speed or new_angular_speed != _sent_angular_speed) \
			and _time_since_send >= SEND_INTERVAL:
		_send(new_speed, new_angular_speed)


## Indication des commandes, ou avertissement si le pilotage n'est pas alimenté.
func _show_hint(powered: bool) -> void:
	_hint.text = HINT_TEXT if powered else UNPOWERED_TEXT
	if powered:
		_hint.remove_theme_color_override("font_color")
	else:
		_hint.add_theme_color_override("font_color", UNPOWERED_COLOR)


func _send(new_speed: float, new_angular_speed: float) -> void:
	_sent_speed = new_speed
	_sent_angular_speed = new_angular_speed
	_time_since_send = 0.0
	ship.request_motion(new_speed, new_angular_speed)
