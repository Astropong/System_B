class_name Piloting
extends Control
## Mode pilotage du joueur local, lancé par le volant de la fenêtre du module
## de pilotage (ModulePilotage.build_interface → Piloting.enter).
##
## En TRANSITION_TIME secondes, la caméra du joueur s'éloigne (zoom divisé par
## ZOOM_FACTOR), vise LOOK_AHEAD cases devant le centre du vaisseau et cesse
## de tourner avec lui :
## l'espace reste fixe à l'écran, c'est le vaisseau qui tourne. Pendant tout le
## mode (transitions comprises), les vaisseaux sont montrés en vue « coque »
## (Ship.hull_view : silhouettes blanches au lieu des salles). La souris
## commande alors le vaisseau (pas le clavier) ; le personnage reste immobile.
## Le clic droit quitte le mode (même transition en sens inverse).
## Statistiques du vaisseau à gauche de l'écran (pour l'instant : vitesse en km/h).
##
## Commandes (envoyées à l'hôte par Ship.request_controls, qui fait autorité) :
## bouton gauche maintenu : direction du centre de l'écran vers la souris
## (montrée par un trait). Le vaisseau pousse dans cette direction, par les
## réacteurs dont la tuyère est sur le bord opposé (voir Ship), et tourne son
## avant vers elle. Bouton relâché : plus de poussée, et les réacteurs annulent
## la rotation (stabilisation).
## Sans poussée, le vaisseau garde sa vitesse (inertie).
## Si aucun module de pilotage n'atteint son alimentation minimale
## (Ship.is_helm_powered), les commandes sont sans effet : rien n'est envoyé
## (l'hôte annule aussi les commandes), le vaisseau garde son mouvement et un
## avertissement remplace l'indication.
## Rien n'empêche deux joueurs de piloter en même temps : la dernière demande
## l'emporte.

## Rapport entre le zoom du joueur et celui du mode pilotage.
const ZOOM_FACTOR := 20.0
## Durée (s) du passage d'une vue à l'autre.
const TRANSITION_TIME := 0.5
## Rotation vers la souris : la vitesse de rotation visée permet de s'arrêter
## pile sur la cible en freinant à BRAKING_MARGIN × l'accélération maximale ;
## l'écart à cette vitesse est rattrapé en TURN_RESPONSE secondes.
const BRAKING_MARGIN := 0.8
const TURN_RESPONSE := 0.5
## La commande de rotation est arrondie (moins d'envois) en précision
## relative : TURN_STEPS_PER_DOUBLING valeurs possibles chaque fois qu'elle
## double (≈ 19 % d'écart au plus entre deux). Un pas fixe la mettrait à zéro
## quand les réacteurs sont puissants (petite commande = forte accélération),
## et le vaisseau ne pourrait plus arrêter une rotation lente. En dessous de
## TURN_MIN_COMMAND, pas de commande.
const TURN_STEPS_PER_DOUBLING := 4.0
const TURN_MIN_COMMAND := 0.00001
## Intervalle minimal (s) entre deux demandes de commandes.
const SEND_INTERVAL := 0.1
## Distance (px d'écran) au centre de l'écran en dessous de laquelle la souris
## est ignorée.
const MOUSE_DEAD_ZONE := 32.0
## La direction de poussée est arrondie à THRUST_ANGLE_STEP degrés (moins d'envois).
const THRUST_ANGLE_STEP := 5.0
## Trait vers la souris (voir _draw).
const AIM_LINE_COLOR := Color(1, 1, 1, 0.25)
const AIM_RADIUS := 8.0
## Point visé par la caméra : à LOOK_AHEAD cases devant le centre du vaisseau
## (0 pour le moment : vaisseau au centre de l'écran).
const LOOK_AHEAD := 0.0
const HINT_TEXT := "Pilotage : clic gauche maintenu pour diriger le vaisseau vers la souris   |   clic droit : quitter"
const UNPOWERED_TEXT := "Pilotage hors service : alimentation insuffisante   |   clic droit : quitter"
const UNPOWERED_COLOR := Color(1.0, 0.35, 0.3)
## Statistiques du vaisseau, à gauche de l'écran pendant le pilotage : marge
## au bord (px) et textes (valeurs insérées après traduction).
const STATS_MARGIN := 24.0
const SPEED_TEXT := "Vitesse : %d km/h"

enum State { OFF, ENTERING, ACTIVE, LEAVING }

static var _instance: Piloting

## Vaisseau piloté : celui du personnage local à l'entrée dans le mode.
var ship: Ship

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
var _sent_thrust := Vector2.ZERO
var _sent_turn: float = 0.0
## Faux pour forcer le prochain envoi (entrée, retour de l'alimentation).
var _sent_valid: bool = false
var _time_since_send: float = 0.0
var _hint: Label
var _stats: VBoxContainer
var _speed_label: Label
## Vrai pendant que le bouton gauche dirige le vaisseau (trait affiché).
var _aiming: bool = false


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
	Ship.hull_view = false


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
	_create_stats()


## Colonne de statistiques, centrée verticalement à gauche de l'écran. Les
## textes sont composés (valeur insérée) : traduits par _update_stats.
func _create_stats() -> void:
	_stats = VBoxContainer.new()
	_stats.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_stats.grow_vertical = Control.GROW_DIRECTION_BOTH
	_stats.offset_left = STATS_MARGIN
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats.hide()
	add_child(_stats)
	_speed_label = Label.new()
	_speed_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_speed_label.add_theme_font_size_override("font_size", ModuleWindow.STAT_FONT_SIZE)
	_stats.add_child(_speed_label)


## Vitesse du vaisseau (centre de masse) en km/h : 1 m = PIXELS_PER_METER px.
func _update_stats() -> void:
	var kmh := ship.velocity.length() / Ship.PIXELS_PER_METER * 3.6
	_speed_label.text = tr(SPEED_TEXT) % roundi(kmh)


func _process(_delta: float) -> void:
	var shown := _state == State.ENTERING or _state == State.ACTIVE
	_stats.visible = shown
	if shown:
		_update_stats()


func _enter() -> void:
	var player := Player.get_local()
	if _state != State.OFF or player == null:
		return
	ship = player.get_ship()
	_camera = player.get_node("Camera2D")
	_base_zoom = _camera.zoom
	_turns = roundf(ship.space_rotation / TAU) * TAU
	_mouse_armed = false
	_sent_valid = false
	_time_since_send = SEND_INTERVAL
	_state = State.ENTERING
	_hint.show()
	Ship.hull_view = true


func _leave() -> void:
	_state = State.LEAVING
	_hint.hide()
	queue_redraw()  # efface le trait
	# Les tours faits pendant le pilotage ne sont pas à refaire en sens inverse.
	var turns := roundf(ship.space_rotation / TAU) * TAU
	if turns != _turns:
		_turns = turns
		_apply_camera()
		_camera.reset_physics_interpolation()
	# Plus de poussée ni de rotation commandée : le vaisseau continue sur sa lancée.
	if ship.is_helm_powered() and (not _sent_valid or _sent_thrust != Vector2.ZERO or _sent_turn != 0.0):
		_send(Vector2.ZERO, 0.0)


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
		Ship.hull_view = false
		return
	# Personnage passé dans un autre vaisseau : fin immédiate du mode.
	var player := _camera.get_parent() as Player
	if not is_instance_valid(ship) or player.get_ship() != ship:
		_state = State.OFF
		_progress = 0.0
		_aiming = false
		_hint.hide()
		queue_redraw()
		_apply_camera()
		_camera.reset_physics_interpolation()
		Ship.hull_view = false
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
		Ship.hull_view = false


## Caméra entre la vue du joueur (progress 0) et celle du pilotage (1). Elle
## reste enfant du personnage, sans rotation propre dans le vaisseau : pour
## viser devant le vaisseau et annuler sa rotation, on la décale de
## -position du personnage (le centre du vaisseau est son origine) plus
## LOOK_AHEAD cases vers l'avant (sa droite), et on la tourne de
## -orientation du vaisseau dans l'espace (l'espace, placé par Fleet autour
## du vaisseau ancré, tourne d'autant dans la scène : il reste fixe à l'écran).
func _apply_camera() -> void:
	var weight := smoothstep(0.0, 1.0, _progress)
	var player := _camera.get_parent() as Node2D
	_camera.position = (Vector2(LOOK_AHEAD * Module.CELL_SIZE, 0.0) - player.position) * weight
	_camera.rotation = -(ship.space_rotation - _turns) * weight
	_camera.zoom = _base_zoom.lerp(_base_zoom / ZOOM_FACTOR, weight)


## Bouton gauche maintenu → poussée et rotation vers la souris, demandées à
## l'hôte ; relâché → stabilisation seule ; rien sans alimentation du pilotage.
func _steer(delta: float) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_mouse_armed = true
	var powered := ship.is_helm_powered()
	_show_hint(powered)
	if not powered:
		_sent_valid = false  # renvoi forcé au retour de l'alimentation
		if _aiming:
			_aiming = false
			queue_redraw()
		return

	var thrust := Vector2.ZERO
	var target_error := 0.0  # écart (°) entre l'avant et la direction voulue
	_aiming = false
	if _mouse_armed and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# Direction du centre de l'écran vers la souris : mesurée depuis le
		# vaisseau, elle bougerait avec la caméra, qui vise devant lui et
		# tourne donc avec lui (le vaisseau courrait après sa cible).
		var to_mouse := get_viewport().get_mouse_position() - get_viewport_rect().size / 2.0
		if to_mouse.length() > MOUSE_DEAD_ZONE:
			_aiming = true
			# Direction de l'écran ramenée dans la scène (rotation de la caméra),
			# puis dans l'espace (orientation du vaisseau dans l'espace moins
			# celle de son nœud, nulle s'il est ancré), arrondie (moins d'envois).
			var to_space := _camera.global_rotation - ship.global_rotation + ship.space_rotation
			var angle := snappedf(to_mouse.rotated(to_space).angle(), deg_to_rad(THRUST_ANGLE_STEP))
			thrust = Vector2.from_angle(angle)
			target_error = rad_to_deg(angle_difference(ship.space_rotation, angle))
	var turn := _turn_command(target_error)
	queue_redraw()

	_time_since_send += delta
	if (not _sent_valid or thrust != _sent_thrust or turn != _sent_turn) \
			and _time_since_send >= SEND_INTERVAL:
		_send(thrust, turn)


## Trait vers la souris pendant le pilotage, comme la cible du personnage :
## du centre de l'écran (point d'où se mesure la direction) au cercle.
func _draw() -> void:
	if not _aiming or _state == State.OFF or _state == State.LEAVING:
		return
	var mouse := get_viewport().get_mouse_position()
	draw_line(get_viewport_rect().size / 2.0, mouse, AIM_LINE_COLOR, 1.0)
	draw_arc(mouse, AIM_RADIUS, 0.0, TAU, 24, Color.WHITE, 2.0)


## Commande de rotation (-1 à 1) pour annuler l'écart [param error] (°) à la
## cible, en arrivant dessus à vitesse nulle ; écart nul : stabilisation.
## Les réacteurs ne font pas forcément tourner autant dans les deux sens : le
## freinage se calcule avec l'accélération du sens opposé à l'écart, la
## correction avec celle du sens demandé (rien si aucun réacteur ne le peut).
func _turn_command(error: float) -> float:
	var braking := ship.get_max_angular_acceleration(-signf(error))  # °/s²
	var wanted_speed := signf(error) * sqrt(2.0 * BRAKING_MARGIN * braking * absf(error))
	var gap := wanted_speed - ship.angular_speed
	var acceleration := ship.get_max_angular_acceleration(signf(gap))
	if acceleration <= 0.0:
		return 0.0
	var command := gap / (acceleration * TURN_RESPONSE)
	command = clampf(command, -1.0, 1.0)
	if absf(command) < TURN_MIN_COMMAND:
		return 0.0
	var doublings := roundf(log(absf(command)) / log(2.0) * TURN_STEPS_PER_DOUBLING) / TURN_STEPS_PER_DOUBLING
	return signf(command) * minf(pow(2.0, doublings), 1.0)


## Indication des commandes, ou avertissement si le pilotage n'est pas alimenté.
func _show_hint(powered: bool) -> void:
	_hint.text = HINT_TEXT if powered else UNPOWERED_TEXT
	if powered:
		_hint.remove_theme_color_override("font_color")
	else:
		_hint.add_theme_color_override("font_color", UNPOWERED_COLOR)


func _send(thrust: Vector2, turn: float) -> void:
	_sent_thrust = thrust
	_sent_turn = turn
	_sent_valid = true
	_time_since_send = 0.0
	ship.request_controls(thrust, turn)
