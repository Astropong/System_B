@tool
class_name Door
extends Node2D
## Porte coulissante entre deux modules.
## Elle s'ouvre quand un personnage s'en approche, reste ouverte tant qu'il
## est dans son passage, puis se referme [member open_duration] secondes
## après qu'il l'a franchie. Fermée, elle bloque le passage et la vue.
##
## Multijoueur : seul l'hôte décide d'ouvrir ou de fermer, puis applique
## le changement chez tous les joueurs (RPC _apply_state).

## Temps (s) pendant lequel la porte reste ouverte après le passage.
@export var open_duration: float = 3.0
## Longueur de la porte (px), réglée par le vaisseau.
@export var length: float = Module.DOOR_SIZE

const THICKNESS := 14.0
## Profondeur (px) de la zone de détection, de chaque côté de la porte.
const DETECTION_DEPTH := 60.0
## Durée (s) de l'animation d'ouverture / fermeture.
const ANIMATION_TIME := 0.25

const PANEL_COLOR := Color(0.72, 0.46, 0.2)
const LAMP_OPEN := Color(0.3, 1.0, 0.4)
const LAMP_CLOSED := Color(1.0, 0.25, 0.2)

var is_open: bool = false

var _amount: float = 0.0:  # 0 = fermée, 1 = ouverte (pour l'animation)
	set(value):
		_amount = value
		queue_redraw()
var _bodies_near: int = 0
var _collision: CollisionShape2D
var _occluder: LightOccluder2D
var _timer: Timer
var _tween: Tween


func _ready() -> void:
	# Battant physique : bloque le passage quand la porte est fermée.
	var body := StaticBody2D.new()
	_collision = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(THICKNESS, length)
	_collision.shape = shape
	body.add_child(_collision)
	add_child(body)

	# Ombre : bloque la vue quand la porte est fermée.
	_occluder = LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.closed = false
	poly.polygon = PackedVector2Array([Vector2(0, -length / 2.0), Vector2(0, length / 2.0)])
	_occluder.occluder = poly
	add_child(_occluder)

	# Zone de détection des personnages, de part et d'autre de la porte.
	var area := Area2D.new()
	var area_shape := CollisionShape2D.new()
	var area_rect := RectangleShape2D.new()
	area_rect.size = Vector2(DETECTION_DEPTH * 2.0, length)
	area_shape.shape = area_rect
	area.add_child(area_shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	_timer = Timer.new()
	_timer.one_shot = true
	add_child(_timer)
	_timer.timeout.connect(_on_timer_timeout)


## Ouvre la porte chez tous les joueurs (à appeler sur l'hôte).
func open() -> void:
	if not is_open:
		_apply_state.rpc(true)


## Ferme la porte chez tous les joueurs (à appeler sur l'hôte).
func close() -> void:
	if is_open:
		_apply_state.rpc(false)


## Envoie l'état actuel de la porte à un joueur qui vient d'arriver.
func sync_to(peer_id: int) -> void:
	_apply_state.rpc_id(peer_id, is_open)


@rpc("authority", "call_local", "reliable")
func _apply_state(open_state: bool) -> void:
	if open_state == is_open:
		return
	is_open = open_state
	_collision.set_deferred("disabled", open_state)
	_occluder.visible = not open_state
	_animate_to(1.0 if open_state else 0.0)


func _animate_to(value: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_amount", value, ANIMATION_TIME)


func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
	if body is CharacterBody2D:
		_bodies_near += 1
		_timer.stop()
		open()


func _on_body_exited(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
	if body is CharacterBody2D:
		_bodies_near = maxi(_bodies_near - 1, 0)
		if _bodies_near == 0:
			_timer.start(open_duration)


func _on_timer_timeout() -> void:
	if _bodies_near == 0:
		close()


func _draw() -> void:
	# Deux battants qui se rétractent dans les murs en s'ouvrant.
	var half := length / 2.0
	var panel_len := half * (1.0 - _amount)
	var x := -THICKNESS / 2.0
	for r in [Rect2(x, -half, THICKNESS, panel_len), Rect2(x, half - panel_len, THICKNESS, panel_len)]:
		if r.size.y > 0.5:
			draw_rect(r, PANEL_COLOR)
			draw_rect(r, PANEL_COLOR.darkened(0.45), false, 2.0)
	# Voyants sur le chambranle.
	var lamp := LAMP_OPEN if is_open else LAMP_CLOSED
	draw_circle(Vector2(0, -half - 12), 4, lamp)
	draw_circle(Vector2(0, half + 12), 4, lamp)
