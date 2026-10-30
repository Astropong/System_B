@tool
class_name ModuleReacteur
extends Module
## Réacteur : propulsion du vaisseau.
##
## Sa tuyère est sur le côté [member nozzle_side] (bord extérieur du
## vaisseau) ; il pousse le vaisseau dans le sens opposé, de MAX_THRUST
## newtons à l'alimentation optimale, proportionnellement à l'alimentation
## fournie (150 % → 1,5 × MAX_THRUST), s'il est opérationnel (voir
## is_operational). Le vaisseau l'utilise pour avancer quand la direction
## voulue est opposée à sa tuyère, et pour tourner (voir Ship).

const ACCENT := Color(1.0, 0.5, 0.15)
## Poussée à l'alimentation optimale (N).
const MAX_THRUST := 20000.0
## Tuyère dessinée hors du mur : longueur et largeurs (cases).
const NOZZLE_LENGTH := 1.5
const NOZZLE_INNER_WIDTH := 4.0
const NOZZLE_OUTER_WIDTH := 6.0
const NOZZLE_COLOR := Color(0.32, 0.34, 0.4)

## Flamme à la sortie de la tuyère quand le réacteur participe au mouvement
## (voir flame_level) : longueur à pleine poussée (cases), couleurs, vacillement.
const FLAME_LENGTH := 12.0
const FLAME_OUTER_COLOR := Color(1.0, 0.45, 0.1, 0.85)
const FLAME_INNER_COLOR := Color(1.0, 0.9, 0.55, 0.95)
const FLAME_FLICKER := 0.15
## En dessous de cette part de poussée, pas de flamme (triangle trop plat).
const FLAME_MIN_LEVEL := 0.02

## Côté de la tuyère (SIDE_LEFT : à l'arrière, pousse vers l'avant).
@export var nozzle_side: Side = SIDE_LEFT:
	set(value):
		nozzle_side = value
		queue_redraw()

## Part de sa poussée que le réacteur fournit en ce moment (0 à 1), réglée
## par le vaisseau à chaque pas physique (Ship._apply_forces) :
## commande la flamme.
var flame_level: float = 0.0:
	set(value):
		flame_level = value
		if _flame:
			_flame.visible = value >= FLAME_MIN_LEVEL

var _flame: Node2D


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.REACTEUR


func get_ideal_power() -> float:
	return 100.0


func get_possible_failures() -> Array[StringName]:
	return []


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	# Flamme dessinée par un nœud enfant : pas teintée par l'éclairage de la
	# salle (self_modulate), et redessinée seule pour vaciller.
	_flame = Node2D.new()
	_flame.name = "Flame"
	_flame.visible = false
	_flame.draw.connect(_draw_flame)
	add_child(_flame)


func _process(delta: float) -> void:
	super._process(delta)
	if _flame and _flame.visible:
		_flame.queue_redraw()


## Vrai si le réacteur est allumé et atteint son alimentation minimale.
func is_operational() -> bool:
	return is_on and power_supplied >= get_min_power()


## Poussée actuelle (N) : proportionnelle à l'alimentation, nulle s'il n'est
## pas opérationnel.
func get_thrust() -> float:
	if not is_operational():
		return 0.0
	return MAX_THRUST * power_supplied / get_ideal_power()


## Sens de la poussée dans le repère du vaisseau : opposé à la tuyère.
func get_thrust_direction() -> Vector2:
	match nozzle_side:
		SIDE_LEFT:
			return Vector2.RIGHT
		SIDE_RIGHT:
			return Vector2.LEFT
		SIDE_TOP:
			return Vector2.DOWN
		_:
			return Vector2.UP


func _draw_details(rect: Rect2) -> void:
	# Quatre réservoirs de refroidissement, cœur du réacteur au sol.
	var half := QUADRANT_SIZE / 2.0
	for q in QUADRANTS:
		_draw_round_furniture(cell_point(q.x + half, q.y + half), CELL_SIZE * 1.3, ACCENT)
		draw_circle(cell_point(q.x + half, q.y + half), CELL_SIZE * 0.35, ACCENT)
	var c := rect.get_center()
	var emblem := emblem_color(ACCENT)
	draw_arc(c, CELL_SIZE * 2.4, 0.0, TAU, 64, emblem, 6.0)
	draw_arc(c, CELL_SIZE * 1.5, 0.0, TAU, 64, emblem, 4.0)
	draw_circle(c, CELL_SIZE * 0.7, emblem)
	_draw_nozzle(rect)


## Base de la tuyère (milieu du mur [member nozzle_side], côté extérieur).
func _nozzle_base() -> Vector2:
	var outward := -get_thrust_direction()
	var size := get_pixel_size()
	var base := size / 2.0 + outward * (absf(outward.x) * size.x + absf(outward.y) * size.y) / 2.0
	return base + outward * WALL_THICKNESS / 2.0


## Tuyère évasée, hors de la salle, au milieu du mur [member nozzle_side].
func _draw_nozzle(_rect: Rect2) -> void:
	var outward := -get_thrust_direction()
	var along := Vector2(-outward.y, outward.x)
	var base := _nozzle_base()
	var tip := base + outward * NOZZLE_LENGTH * CELL_SIZE
	var inner := along * NOZZLE_INNER_WIDTH * CELL_SIZE / 2.0
	var outer := along * NOZZLE_OUTER_WIDTH * CELL_SIZE / 2.0
	var shape := PackedVector2Array([base - inner, base + inner, tip + outer, tip - outer])
	draw_colored_polygon(shape, NOZZLE_COLOR)
	shape.append(shape[0])
	draw_polyline(shape, ACCENT, FURNITURE_OUTLINE)


## Flamme à la sortie de la tuyère, d'autant plus longue que flame_level est
## grand, avec un léger vacillement.
func _draw_flame() -> void:
	var outward := -get_thrust_direction()
	var along := Vector2(-outward.y, outward.x)
	var start := _nozzle_base() + outward * NOZZLE_LENGTH * CELL_SIZE
	var length := FLAME_LENGTH * CELL_SIZE * flame_level * randf_range(1.0 - FLAME_FLICKER, 1.0 + FLAME_FLICKER)
	var half_width := NOZZLE_OUTER_WIDTH * CELL_SIZE / 2.0 * 0.85
	_flame.draw_colored_polygon(PackedVector2Array([
		start - along * half_width, start + along * half_width, start + outward * length,
	]), FLAME_OUTER_COLOR)
	_flame.draw_colored_polygon(PackedVector2Array([
		start - along * half_width * 0.5, start + along * half_width * 0.5, start + outward * length * 0.6,
	]), FLAME_INNER_COLOR)
