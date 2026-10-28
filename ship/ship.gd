@tool
class_name Ship
extends Node2D
## Vaisseau : aligne ses modules enfants de gauche à droite (arrière -> avant),
## centrés sur la position du vaisseau, puis génère les murs (collisions et
## ombres) et une porte entre chaque paire de modules voisins.
## Pour changer la composition, ajoutez, supprimez ou réordonnez les modules
## enfants dans la scène.
##
## Multijoueur : chaque joueur fait avancer le vaisseau lui-même à la vitesse
## [member speed]. L'hôte fait autorité : il envoie chaque changement de vitesse
## (avec la position), et une correction de position toutes les
## MOTION_SYNC_INTERVAL secondes ; les autres résorbent l'écart en douceur.
## L'hôte applique aussi les règles d'alimentation (voir power_rules.gd)
## PowerRules.UPDATE_RATE fois par seconde, puis les règles de température
## (voir temperature_rules.gd), et envoie le résultat aux autres.

## Intervalle (s) entre deux corrections de position envoyées par l'hôte.
const MOTION_SYNC_INTERVAL := 1.0
## Vitesse de résorption d'un écart de position (proportion par seconde).
const CORRECTION_RATE := 2.0
## Au-delà de cet écart (px), la position est corrigée d'un coup.
const CORRECTION_SNAP_DISTANCE := 96.0

## Vitesse d'avancée du vaisseau vers la droite, en pixels par seconde
## (1 case = 48 px). Peut varier en cours de partie : à modifier sur l'hôte,
## qui transmet le changement aux autres joueurs.
@export var speed: float = 10.0:
	set(value):
		if value == speed:
			return
		speed = value
		if is_inside_tree() and not Engine.is_editor_hint() and is_multiplayer_authority():
			_receive_motion.rpc(position, speed)

var _arranging: bool = false
var _power_timer: float = 0.0
var _motion_timer: float = 0.0
var _position_error := Vector2.ZERO


func _ready() -> void:
	child_order_changed.connect(arrange_modules)
	arrange_modules()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	position.x += speed * delta
	if is_multiplayer_authority():
		_update_power(delta)
		_motion_timer += delta
		if _motion_timer >= MOTION_SYNC_INTERVAL:
			_motion_timer = 0.0
			_receive_position.rpc(position)
	else:
		_apply_correction(delta)


## Envoie la position et la vitesse du vaisseau à un joueur qui vient d'arriver (hôte).
func send_motion_to(peer_id: int) -> void:
	_receive_motion.rpc_id(peer_id, position, speed)


## Changement de vitesse (ou arrivée dans la partie) : envoi fiable.
@rpc("authority", "call_remote", "reliable")
func _receive_motion(new_position: Vector2, new_speed: float) -> void:
	speed = new_speed
	_correct_to(new_position)


## Correction périodique : une correction perdue est remplacée par la suivante.
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_position(new_position: Vector2) -> void:
	_correct_to(new_position)


func _correct_to(new_position: Vector2) -> void:
	_position_error = new_position - position
	if _position_error.length() > CORRECTION_SNAP_DISTANCE:
		position = new_position
		_position_error = Vector2.ZERO


func _apply_correction(delta: float) -> void:
	if _position_error == Vector2.ZERO:
		return
	var step := _position_error * minf(1.0, CORRECTION_RATE * delta)
	if step.length() < 0.01:
		step = _position_error
	position += step
	_position_error -= step


## Alimentation : mise à jour à intervalle fixe (hôte uniquement).
func _update_power(delta: float) -> void:
	var step := 1.0 / PowerRules.UPDATE_RATE
	_power_timer += delta
	if _power_timer < step:
		return
	var modules := get_modules()
	while _power_timer >= step:
		_power_timer -= step
		PowerRules.update(modules, step)
		TemperatureRules.update(modules, step)

	# Un seul petit message pour tous les modules.
	var power := PackedFloat32Array()
	var room_temperatures := PackedFloat32Array()
	var machine_temperatures := PackedFloat32Array()
	for m in modules:
		power.append(m.power_supplied)
		room_temperatures.append(m.room_temperature)
		machine_temperatures.append(m.machine_temperature)
	_receive_modules_state.rpc(power, room_temperatures, machine_temperatures)


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_modules_state(power: PackedFloat32Array, room_temperatures: PackedFloat32Array,
		machine_temperatures: PackedFloat32Array) -> void:
	var modules := get_modules()
	for i in mini(power.size(), modules.size()):
		modules[i].power_supplied = power[i]
	for i in mini(room_temperatures.size(), modules.size()):
		modules[i].room_temperature = room_temperatures[i]
	for i in mini(machine_temperatures.size(), modules.size()):
		modules[i].machine_temperature = machine_temperatures[i]


func get_modules() -> Array[Module]:
	var result: Array[Module] = []
	for child in get_children():
		if child is Module:
			result.append(child)
	return result


## Position d'apparition du n-ième joueur : au centre du premier couloir,
## en décalant chaque joueur verticalement.
func get_spawn_position(index: int) -> Vector2:
	var center := Vector2.ZERO
	for m in get_modules():
		if m is ModuleCouloir:
			center = m.position + m.get_pixel_size() / 2.0
			break
	return center + Vector2(0, (index % 5 - 2) * 64)


## Envoie l'état de toutes les portes à un joueur qui vient d'arriver (hôte).
func send_door_states(peer_id: int) -> void:
	for child in _get_structure().get_children():
		if child is Door:
			child.sync_to(peer_id)


func arrange_modules() -> void:
	if _arranging or not is_inside_tree():
		return
	_arranging = true

	var modules := get_modules()
	var total_width := 0.0
	for m in modules:
		total_width += m.get_pixel_size().x

	var x := -total_width / 2.0
	for i in modules.size():
		var m := modules[i]
		var size := m.get_pixel_size()
		m.position = Vector2(x, -size.y / 2.0)
		# Ouverture uniquement entre deux modules voisins.
		m.door_left = i > 0
		m.door_right = i < modules.size() - 1
		x += size.x

	_build_structure(modules)
	_arranging = false


## Nœud (non sauvegardé) qui contient les murs, les ombres et les portes générés.
func _get_structure() -> Node2D:
	var structure := get_node_or_null("Structure") as Node2D
	if structure == null:
		structure = Node2D.new()
		structure.name = "Structure"
		add_child(structure)
	return structure


func _build_structure(modules: Array[Module]) -> void:
	var structure := _get_structure()
	for child in structure.get_children():
		structure.remove_child(child)
		child.queue_free()

	# Murs : une forme de collision et une ombre par segment. La cloison entre
	# deux modules voisins figure dans les murs des deux : on ne la crée qu'une fois.
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	structure.add_child(walls)
	var built := {}
	for m in modules:
		for line in m.get_wall_lines():
			var a: Vector2 = (m.position + line[0]).round()
			var b: Vector2 = (m.position + line[1]).round()
			var key := [a, b] if a < b else [b, a]
			if built.has(key):
				continue
			built[key] = true

			var shape := RectangleShape2D.new()
			shape.size = Vector2(
					maxf(absf(b.x - a.x), Module.WALL_THICKNESS),
					maxf(absf(b.y - a.y), Module.WALL_THICKNESS))
			var collision := CollisionShape2D.new()
			collision.shape = shape
			collision.position = (a + b) / 2.0
			walls.add_child(collision)

			var occluder := LightOccluder2D.new()
			var poly := OccluderPolygon2D.new()
			poly.closed = false
			poly.polygon = PackedVector2Array([a, b])
			occluder.occluder = poly
			structure.add_child(occluder)

	# Une porte au milieu de chaque cloison entre deux modules.
	for i in range(1, modules.size()):
		var m := modules[i]
		var door := Door.new()
		door.name = "Door%d" % i
		door.position = m.position + Vector2(0, m.get_pixel_size().y / 2.0)
		structure.add_child(door)
