class_name Player
extends CharacterBody2D
## Personnage vu de dessus, dessiné comme un rond.
## - Flèches du clavier : déplacement direct.
## - Clic gauche (ou bouton maintenu) : le personnage se rend vers la souris.
## Il est placé dans le vaisseau (nœud Ship/Crew) : il avance et tourne avec
## lui, et sa position comme sa cible sont exprimées dans le repère du vaisseau.
## La caméra tourne avec le vaisseau (ignore_rotation désactivé) : le vaisseau
## reste droit à l'écran, c'est l'espace autour qui tourne.
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
## Intervalle (s) des corrections de position pendant un déplacement.
const CORRECTION_INTERVAL := 0.5
## Vitesse de résorption d'un écart de position (proportion par seconde).
const CORRECTION_RATE := 10.0
## Au-delà de cet écart (px), la position est corrigée d'un coup.
const CORRECTION_SNAP_DISTANCE := 96.0

var target: Vector2  # dans le repère du vaisseau
var has_target: bool = false
## Direction donnée au clavier (nulle sans touche enfoncée).
var input_dir := Vector2.ZERO

# Dernier ordre envoyé (joueur local).
var _sent_dir := Vector2.ZERO
var _sent_target := Vector2.ZERO
var _sent_has_target := false
var _time_since_order: float = 0.0
var _time_since_correction: float = 0.0
# Écart restant à résorber (autres joueurs).
var _position_error := Vector2.ZERO


func _enter_tree() -> void:
	var peer_id := name.to_int()
	if peer_id > 0:
		set_multiplayer_authority(peer_id)


func _ready() -> void:
	target = position
	var is_local := is_multiplayer_authority()
	$Camera2D.enabled = is_local
	$VisionLight.enabled = is_local
	if is_local:
		$Camera2D.make_current()
	else:
		# Une couleur différente par joueur distant.
		color = OTHER_PLAYER_COLORS[name.to_int() % OTHER_PLAYER_COLORS.size()]


func _physics_process(delta: float) -> void:
	var is_local := is_multiplayer_authority()
	if is_local:
		_read_input()

	velocity = _compute_velocity(delta)
	move_and_slide()

	if is_local:
		_send_updates(delta)
		queue_redraw()
	else:
		_apply_correction(delta)


func _read_input() -> void:
	# Fenêtre de module ouverte : le personnage reste immobile.
	if ModuleWindow.is_open:
		input_dir = Vector2.ZERO
		has_target = false
		return

	# Souris : tant que le bouton gauche est enfoncé, la cible suit le curseur.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		target = _global_to_parent(get_global_mouse_position())
		has_target = true

	# Clavier : les actions ui_* sont déjà associées aux flèches.
	input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir != Vector2.ZERO:
		has_target = false  # le clavier annule la cible de la souris


## Vitesse selon l'ordre en cours ; identique sur toutes les machines.
## Les ordres (direction des flèches, cible) sont dans le repère du vaisseau,
## qui est aussi celui de l'écran puisque la caméra tourne avec lui ;
## move_and_slide applique la vitesse dans le repère du monde : on la tourne
## donc de l'orientation du vaisseau (synchronisée entre les joueurs).
func _compute_velocity(delta: float) -> Vector2:
	var ship_rotation := _get_ship_rotation()
	if input_dir != Vector2.ZERO:
		return input_dir.rotated(ship_rotation) * speed
	if has_target:
		var to_target := target - position
		if to_target.length() <= speed * delta:
			has_target = false
			return (to_target / delta).rotated(ship_rotation)  # dernier petit pas pile sur la cible
		return to_target.normalized().rotated(ship_rotation) * speed
	return Vector2.ZERO


## Orientation (radians) du repère du personnage, c'est-à-dire du vaisseau.
func _get_ship_rotation() -> float:
	var parent := get_parent() as Node2D
	return parent.global_rotation if parent else 0.0


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
	_receive_order.rpc(position, input_dir, target, has_target)


## Envoie l'état du personnage à un joueur qui vient d'arriver (hôte).
## L'hôte connaît l'état de tous les personnages, puisqu'il les simule.
func send_state_to(peer_id: int) -> void:
	_receive_state_from_host.rpc_id(peer_id, position, input_dir, target, has_target)


@rpc("authority", "call_remote", "reliable")
func _receive_order(from: Vector2, dir: Vector2, new_target: Vector2, new_has_target: bool) -> void:
	_apply_order(from, dir, new_target, new_has_target)


## Correction périodique : une correction perdue est remplacée par la suivante.
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_correction(at: Vector2) -> void:
	_correct_to(at)


## L'hôte n'a pas autorité sur ce personnage : on vérifie l'expéditeur.
@rpc("any_peer", "call_remote", "reliable")
func _receive_state_from_host(at: Vector2, dir: Vector2, new_target: Vector2, new_has_target: bool) -> void:
	if multiplayer.get_remote_sender_id() == 1 and not is_multiplayer_authority():
		_apply_order(at, dir, new_target, new_has_target)


func _apply_order(from: Vector2, dir: Vector2, new_target: Vector2, new_has_target: bool) -> void:
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
