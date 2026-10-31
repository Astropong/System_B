class_name Player
extends Node2D
## Personnage vu de dessus, dessiné comme un rond.
## - Flèches, ZQSD ou WASD (actions move_*, project.godot) : déplacement direct.
## - Bouton gauche maintenu : le personnage se rend vers la souris ; il
##   s'arrête dès que le bouton est relâché.
## Légère inertie : il accélère et freine en une fraction de seconde
## (ACCELERATION ; vitesse actuelle move_velocity, jointe à chaque ordre).
## Il est placé dans un vaisseau (son nœud Crew, voir get_ship ; il peut en
## changer, transfer_to) : il avance et tourne avec lui, et sa position comme
## sa cible sont exprimées dans le repère du vaisseau.
## La caméra tourne avec le vaisseau (ignore_rotation désactivé) : le vaisseau
## reste droit à l'écran, c'est l'espace autour qui tourne.
##
## Collisions : un corps circulaire (rayon radius) dans l'espace physique de
## l'équipage de son vaisseau (Ship.get_crew_space, repère du vaisseau), où il
## glisse contre les murs, les portes fermées et les autres personnages
## (_move). Le déplacement ne dépend donc ni de la place du vaisseau dans la
## scène ni de sa vitesse, sur toutes les machines.
##
## Multijoueur : le nom du nœud est l'identifiant réseau du joueur, qui fait
## autorité sur son personnage. Seul le personnage local lit les commandes et
## porte la caméra et la lumière (donc son propre brouillard de guerre).
## Le joueur n'envoie pas sa position en continu, mais ses ORDRES de
## déplacement (direction clavier, cible souris), seulement quand ils changent ;
## chaque machine simule ensuite le déplacement. Pour rattraper les écarts
## (collisions, latence), chaque ordre porte la position de départ, la position
## finale est envoyée à l'arrêt, et une correction part toutes les
## CORRECTION_INTERVAL secondes pendant un déplacement.

@export var speed: float = 300.0
@export var radius: float = 24.0
@export var color: Color = Color(0.3, 0.7, 1.0)

## Couleurs des autres joueurs (le joueur local reste bleu).
const OTHER_PLAYER_COLORS: Array[Color] = [
	Color(1.0, 0.6, 0.2),   # orange
	Color(0.4, 0.9, 0.4),   # vert
	Color(1.0, 0.45, 0.7),  # rose
	Color(1.0, 0.9, 0.3),   # jaune
	Color(0.75, 0.5, 1.0),  # violet
	Color(0.95, 0.3, 0.3),  # rouge
]

## Cible suivie à la souris : intervalle minimal (s) entre deux envois, et
## déplacement minimal (px) de la cible pour la renvoyer.
const TARGET_SEND_INTERVAL := 0.1
const TARGET_SEND_DISTANCE := 24.0
## Légère inertie : le personnage rejoint la vitesse voulue (et s'arrête) avec
## cette accélération (px/s²) ; à `speed` = 300, il démarre ou s'arrête en
## environ 0,1 s.
const ACCELERATION := 2400.0
## Intervalle (s) des corrections de position pendant un déplacement.
const CORRECTION_INTERVAL := 0.5
## Vitesse de résorption d'un écart de position (proportion par seconde).
const CORRECTION_RATE := 10.0
## Au-delà de cet écart (px), la position est corrigée d'un coup.
const CORRECTION_SNAP_DISTANCE := 96.0
## Glissements successifs au plus par pas (coin : deux murs).
const MAX_SLIDES := 4

var target: Vector2  # dans le repère du vaisseau
var has_target: bool = false
## Direction donnée au clavier (nulle sans touche enfoncée).
var input_dir := Vector2.ZERO
## Vitesse actuelle dans le repère du vaisseau (px/s) : elle rejoint la vitesse
## voulue à ACCELERATION près (inertie), et part avec chaque ordre.
var move_velocity := Vector2.ZERO

# Dernier ordre envoyé (joueur local).
var _sent_dir := Vector2.ZERO
var _sent_target := Vector2.ZERO
var _sent_has_target := false
var _time_since_order: float = 0.0
var _time_since_correction: float = 0.0
# Écart restant à résorber (autres joueurs).
var _position_error := Vector2.ZERO

# Corps dans l'espace de l'équipage du vaisseau, et paramètres des tests de
# déplacement (réutilisés).
var _body := RID()
var _shape := RID()
var _motion := PhysicsTestMotionParameters2D.new()
var _motion_result := PhysicsTestMotionResult2D.new()

static var _local: Player


## Entrée dans un vaisseau (création ou changement) : son corps rejoint
## l'espace de l'équipage de ce vaisseau.
func _enter_tree() -> void:
	var peer_id := name.to_int()
	if peer_id > 0:
		set_multiplayer_authority(peer_id)
	var ship := get_ship()
	if ship == null:
		return
	if not _body.is_valid():
		_shape = PhysicsServer2D.circle_shape_create()
		PhysicsServer2D.shape_set_data(_shape, radius)
		_body = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(_body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(_body, _shape)
	PhysicsServer2D.body_set_space(_body, ship.get_crew_space())
	_place_body()


## Hors de l'arbre, le corps quitte l'espace (le vaisseau peut le libérer).
func _exit_tree() -> void:
	if _body.is_valid():
		PhysicsServer2D.body_set_space(_body, RID())


## Destruction : vient avant la sortie de l'arbre (_exit_tree ne doit plus
## toucher au corps libéré).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _body.is_valid():
		PhysicsServer2D.free_rid(_body)
		PhysicsServer2D.free_rid(_shape)
		_body = RID()
		_shape = RID()


## Corps placé à la position du personnage (les autres le heurtent là).
func _place_body() -> void:
	PhysicsServer2D.body_set_state(_body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, position))


## Déplace le personnage de [param wanted] × [param delta] (repère du
## vaisseau) en glissant contre ce qu'il heurte ; renvoie la vitesse après
## glissement (l'élan ne traverse pas un mur).
func _move(wanted: Vector2, delta: float) -> Vector2:
	var from := Transform2D(0.0, position)
	var motion := wanted * delta
	var result_velocity := wanted
	for i in MAX_SLIDES:
		_motion.from = from
		_motion.motion = motion
		if not PhysicsServer2D.body_test_motion(_body, _motion, _motion_result):
			from.origin += motion
			break
		from.origin += _motion_result.get_travel()
		var normal := _motion_result.get_collision_normal()
		motion = _motion_result.get_remainder().slide(normal)
		result_velocity = result_velocity.slide(normal)
		if motion.is_zero_approx():
			break
	position = from.origin
	return result_velocity


## Personnage du joueur local, ou null (pas encore créé, serveur dédié).
static func get_local() -> Player:
	return _local if is_instance_valid(_local) else null


## Vaisseau à bord duquel se trouve le personnage (parent de son nœud Crew).
func get_ship() -> Ship:
	var crew := get_parent()
	return crew.get_parent() as Ship if crew else null


## Passe dans le vaisseau [param ship], à la place [param at] (repère de ce
## vaisseau), sans ordre en cours. Joueur local : ce vaisseau devient le
## vaisseau ancré (fixe à l'écran, voir Ship.anchored).
func transfer_to(ship: Ship, at: Vector2) -> void:
	reparent(ship.get_node("Crew"), false)
	position = at
	target = at
	has_target = false
	input_dir = Vector2.ZERO
	move_velocity = Vector2.ZERO
	_position_error = Vector2.ZERO
	_place_body()
	reset_physics_interpolation()
	if is_multiplayer_authority():
		ship.make_anchor()
		$Camera2D.make_current()
		$Camera2D.reset_physics_interpolation()


func _ready() -> void:
	target = position
	var is_local := is_multiplayer_authority()
	$Camera2D.enabled = is_local
	$VisionLight.enabled = is_local
	if is_local:
		_local = self
		get_ship().make_anchor()
		$Camera2D.make_current()
	else:
		# Une couleur différente par joueur distant.
		color = OTHER_PLAYER_COLORS[name.to_int() % OTHER_PLAYER_COLORS.size()]


func _physics_process(delta: float) -> void:
	var is_local := is_multiplayer_authority()
	if is_local:
		_read_input()

	var slid := _move(_compute_velocity(delta), delta)
	# Vitesse après glissement contre les murs : l'élan ne traverse pas un mur.
	if move_velocity != Vector2.ZERO:
		move_velocity = slid

	if is_local:
		_send_updates(delta)
		queue_redraw()
	else:
		_apply_correction(delta)
	_place_body()


func _read_input() -> void:
	# Fenêtre de module ouverte ou mode pilotage : le personnage reste immobile.
	if ModuleWindow.is_open or Piloting.is_active():
		input_dir = Vector2.ZERO
		has_target = false
		return

	# Souris : tant que le bouton gauche est enfoncé, la cible suit le curseur ;
	# relâché, le personnage s'arrête aussitôt.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		target = _global_to_parent(get_global_mouse_position())
		has_target = true
	else:
		has_target = false

	# Clavier : flèches, ZQSD et WASD (touches selon leur lettre, pas leur place).
	input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir != Vector2.ZERO:
		has_target = false  # le clavier annule la cible de la souris


## Vitesse selon l'ordre en cours ; identique sur toutes les machines.
## Tout est dans le repère du vaisseau (ordres, position, vitesse renvoyée),
## qui est aussi celui de l'écran puisque la caméra tourne avec lui.
## Inertie : move_velocity rejoint la vitesse voulue à ACCELERATION près ; vers
## une cible, la vitesse voulue baisse assez tôt pour s'arrêter dessus.
func _compute_velocity(delta: float) -> Vector2:
	var wanted := Vector2.ZERO
	if input_dir != Vector2.ZERO:
		wanted = input_dir * speed
	elif has_target:
		var to_target := target - position
		var distance := to_target.length()
		if distance <= maxf(move_velocity.length(), ACCELERATION * delta) * delta:
			# Dernier petit pas pile sur la cible.
			has_target = false
			move_velocity = Vector2.ZERO
			return to_target / delta
		wanted = to_target / distance * minf(speed, sqrt(2.0 * ACCELERATION * distance))
	move_velocity = move_velocity.move_toward(wanted, ACCELERATION * delta)
	return move_velocity


## Joueur local : envoie l'ordre quand il change (dont l'arrêt), et des
## corrections de position pendant le déplacement.
func _send_updates(delta: float) -> void:
	_time_since_order += delta
	_time_since_correction += delta
	if input_dir != _sent_dir or has_target != _sent_has_target:
		_send_order()
	elif has_target and _time_since_order >= TARGET_SEND_INTERVAL \
			and target.distance_to(_sent_target) >= TARGET_SEND_DISTANCE:
		_send_order()
	elif (input_dir != Vector2.ZERO or has_target) and _time_since_correction >= CORRECTION_INTERVAL:
		_time_since_correction = 0.0
		_receive_correction.rpc(position)


func _send_order() -> void:
	_sent_dir = input_dir
	_sent_target = target
	_sent_has_target = has_target
	_time_since_order = 0.0
	_time_since_correction = 0.0
	_receive_order.rpc(position, move_velocity, input_dir, target, has_target)


## Envoie l'état du personnage à un joueur qui vient d'arriver (hôte).
## L'hôte connaît l'état de tous les personnages, puisqu'il les simule.
func send_state_to(peer_id: int) -> void:
	_receive_state_from_host.rpc_id(peer_id, position, move_velocity, input_dir, target, has_target)


@rpc("authority", "call_remote", "reliable")
func _receive_order(from: Vector2, new_velocity: Vector2, dir: Vector2, new_target: Vector2,
		new_has_target: bool) -> void:
	_apply_order(from, new_velocity, dir, new_target, new_has_target)


## Correction périodique : une correction perdue est remplacée par la suivante.
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_correction(at: Vector2) -> void:
	_correct_to(at)


## L'hôte n'a pas autorité sur ce personnage : on vérifie l'expéditeur.
@rpc("any_peer", "call_remote", "reliable")
func _receive_state_from_host(at: Vector2, new_velocity: Vector2, dir: Vector2, new_target: Vector2,
		new_has_target: bool) -> void:
	if multiplayer.get_remote_sender_id() == 1 and not is_multiplayer_authority():
		_apply_order(at, new_velocity, dir, new_target, new_has_target)


func _apply_order(from: Vector2, new_velocity: Vector2, dir: Vector2, new_target: Vector2,
		new_has_target: bool) -> void:
	move_velocity = new_velocity
	input_dir = dir
	target = new_target
	has_target = new_has_target
	_correct_to(from)


func _correct_to(at: Vector2) -> void:
	_position_error = at - position
	if _position_error.length() > CORRECTION_SNAP_DISTANCE:
		position = at
		_position_error = Vector2.ZERO
		reset_physics_interpolation()  # saut : pas d'interpolation


func _apply_correction(delta: float) -> void:
	if _position_error == Vector2.ZERO:
		return
	var step := _position_error * minf(1.0, CORRECTION_RATE * delta)
	if step.length() < 0.1:
		step = _position_error
	position += step
	_position_error -= step


func _global_to_parent(point: Vector2) -> Vector2:
	var parent := get_parent() as Node2D
	return parent.to_local(point) if parent else point


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, color.darkened(0.4), 3.0)
	# La cible n'est montrée qu'à son propre joueur.
	if has_target and is_multiplayer_authority():
		# Le personnage n'est ni tourné ni agrandi dans le vaisseau : son repère
		# local a l'orientation du vaisseau, comme la cible.
		var t := target - position
		draw_arc(t, 8.0, 0.0, TAU, 24, Color.WHITE, 2.0)
		draw_line(Vector2.ZERO, t, Color(1, 1, 1, 0.25), 1.0)
