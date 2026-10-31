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
##
## Battant : forme placée dans l'espace physique de l'équipage du vaisseau
## (Ship.get_crew_space, repère du vaisseau), désactivée quand la porte est
## ouverte.
## Détection (hôte, à chaque pas physique, _count_bodies_near) : position des
## personnages de l'équipage comparée à la zone de la porte, dans le repère du
## vaisseau. Pas d'Area2D : elle serait dans le monde, où le vaisseau bouge.

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
# Battant dans l'espace de l'équipage : corps et forme (invalides dans l'éditeur).
var _body := RID()
var _shape := RID()
var _occluder: LightOccluder2D
var _timer: Timer
var _tween: Tween


func _ready() -> void:
	# Battant physique : bloque le passage quand la porte est fermée. La porte
	# est dans Structure, à l'origine du vaisseau : sa transformation est
	# déjà dans le repère du vaisseau.
	var ship := _get_ship()
	if ship and not Engine.is_editor_hint():
		_shape = PhysicsServer2D.rectangle_shape_create()
		PhysicsServer2D.shape_set_data(_shape, Vector2(THICKNESS, length) / 2.0)
		_body = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(_body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(_body, _shape)
		PhysicsServer2D.body_set_state(_body, PhysicsServer2D.BODY_STATE_TRANSFORM, transform)
		PhysicsServer2D.body_set_space(_body, ship.get_crew_space())

	# Ombre : bloque la vue quand la porte est fermée.
	_occluder = LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.closed = false
	poly.polygon = PackedVector2Array([Vector2(0, -length / 2.0), Vector2(0, length / 2.0)])
	_occluder.occluder = poly
	add_child(_occluder)

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
	if _body.is_valid():
		PhysicsServer2D.body_set_shape_disabled(_body, 0, open_state)
	_occluder.visible = not open_state
	_animate_to(1.0 if open_state else 0.0)


func _animate_to(value: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_amount", value, ANIMATION_TIME)


## Hôte : ouvre dès qu'un personnage arrive dans la zone, lance la fermeture
## différée quand le dernier en sort.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not multiplayer.is_server():
		return
	var near := _count_bodies_near()
	if near > 0 and _bodies_near == 0:
		_timer.stop()
		open()
	elif near == 0 and _bodies_near > 0:
		_timer.start(open_duration)
	_bodies_near = near


## Personnages (enfants de Crew dans le vaisseau) qui touchent la zone de
## détection : DETECTION_DEPTH de chaque côté de la porte, sur sa longueur,
## agrandie du rayon du personnage.
func _count_bodies_near() -> int:
	var ship := _get_ship()
	var crew := ship.get_node_or_null("Crew") if ship else null
	if crew == null:
		return 0
	var zone := Rect2(-DETECTION_DEPTH, -length / 2.0, DETECTION_DEPTH * 2.0, length)
	var inverse := transform.affine_inverse()  # repère du vaisseau → porte
	var count := 0
	for body in crew.get_children():
		if body is Player and zone.grow(body.radius).has_point(inverse * body.position):
			count += 1
	return count


## Hors de l'arbre, le battant quitte l'espace de l'équipage : le vaisseau,
## qui sort de l'arbre après ses enfants, peut ensuite libérer cet espace.
func _exit_tree() -> void:
	if _body.is_valid():
		PhysicsServer2D.body_set_space(_body, RID())


func _enter_tree() -> void:
	var ship := _get_ship()
	if _body.is_valid() and ship:
		PhysicsServer2D.body_set_space(_body, ship.get_crew_space())


## Vaisseau de la porte (elle est dans son nœud Structure).
func _get_ship() -> Ship:
	var structure := get_parent()
	return structure.get_parent() as Ship if structure else null


## Destruction : vient avant la sortie de l'arbre (_exit_tree ne doit plus
## toucher au corps libéré).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _body.is_valid():
		PhysicsServer2D.free_rid(_body)
		PhysicsServer2D.free_rid(_shape)
		_body = RID()
		_shape = RID()


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
