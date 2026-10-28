@tool
class_name Ship
extends Node2D
## Vaisseau : place ses modules enfants sur une grille en cases (voir
## [member Module.grid_position] ; l'avant est à droite), centrée sur la
## position du vaisseau, puis génère les murs (collisions et ombres) et une
## porte entre chaque paire de modules qui partagent un mur.
## Pour changer la composition, ajoutez ou supprimez des modules enfants dans
## la scène et réglez leur position dans la grille.
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
## Longueur minimale (cases) d'un mur partagé pour y placer une porte.
const MIN_SHARED_WALL := 4

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


## Place les modules selon leur [member Module.grid_position] (en cases),
## l'ensemble étant centré sur l'origine du vaisseau, puis relie par une porte
## chaque paire de modules qui partagent un mur assez long, et reconstruit
## les murs.
func arrange_modules() -> void:
	if _arranging or not is_inside_tree():
		return
	_arranging = true

	var modules := get_modules()
	var bounds := Rect2i()
	for i in modules.size():
		var r := Rect2i(modules[i].grid_position, modules[i].get_size())
		bounds = r if i == 0 else bounds.merge(r)
	var origin := -Vector2(bounds.position) * Module.CELL_SIZE - Vector2(bounds.size) * Module.CELL_SIZE / 2.0
	for m in modules:
		m.position = origin + Vector2(m.grid_position) * Module.CELL_SIZE
		m.doorways = []
		m.neighbors = []

	var doors := []
	for i in modules.size():
		for j in range(i + 1, modules.size()):
			var door := _connect(modules[i], modules[j])
			if not door.is_empty():
				doors.append(door)

	_build_structure(modules, doors)
	_arranging = false


## Relie [param a] et [param b] s'ils partagent un mur d'au moins
## MIN_SHARED_WALL cases : ouverture au milieu de la partie commune.
## Renvoie la porte à créer [position dans le vaisseau, horizontale ?],
## ou un tableau vide.
func _connect(a: Module, b: Module) -> Array:
	var ra := Rect2i(a.grid_position, a.get_size())
	var rb := Rect2i(b.grid_position, b.get_size())
	# Mur vertical commun (b à droite de a, ou l'inverse).
	for pair in [[a, ra, b, rb], [b, rb, a, ra]]:
		var left: Module = pair[0]
		var lr: Rect2i = pair[1]
		var right: Module = pair[2]
		var rr: Rect2i = pair[3]
		if lr.end.x == rr.position.x:
			var top := maxi(lr.position.y, rr.position.y)
			var bottom := mini(lr.end.y, rr.end.y)
			if bottom - top >= MIN_SHARED_WALL:
				var center := (top + bottom) * Module.CELL_SIZE / 2.0
				left.doorways.append([SIDE_RIGHT, center - lr.position.y * Module.CELL_SIZE])
				right.doorways.append([SIDE_LEFT, center - rr.position.y * Module.CELL_SIZE])
				_add_neighbors(left, right)
				return [right.position + Vector2(0, center - rr.position.y * Module.CELL_SIZE), false]
	# Mur horizontal commun (b sous a, ou l'inverse).
	for pair in [[a, ra, b, rb], [b, rb, a, ra]]:
		var upper: Module = pair[0]
		var ur: Rect2i = pair[1]
		var lower: Module = pair[2]
		var lwr: Rect2i = pair[3]
		if ur.end.y == lwr.position.y:
			var left_x := maxi(ur.position.x, lwr.position.x)
			var right_x := mini(ur.end.x, lwr.end.x)
			if right_x - left_x >= MIN_SHARED_WALL:
				var center := (left_x + right_x) * Module.CELL_SIZE / 2.0
				upper.doorways.append([SIDE_BOTTOM, center - ur.position.x * Module.CELL_SIZE])
				lower.doorways.append([SIDE_TOP, center - lwr.position.x * Module.CELL_SIZE])
				_add_neighbors(upper, lower)
				return [lower.position + Vector2(center - lwr.position.x * Module.CELL_SIZE, 0), true]
	return []


func _add_neighbors(a: Module, b: Module) -> void:
	a.neighbors.append(b)
	b.neighbors.append(a)


## Nœud (non sauvegardé) qui contient les murs, les ombres et les portes générés.
func _get_structure() -> Node2D:
	var structure := get_node_or_null("Structure") as Node2D
	if structure == null:
		structure = Node2D.new()
		structure.name = "Structure"
		add_child(structure)
	return structure


## Construit les collisions et les ombres des murs, et les portes
## ([param doors] : liste de [position, horizontale ?]).
func _build_structure(modules: Array[Module], doors: Array) -> void:
	var structure := _get_structure()
	for child in structure.get_children():
		structure.remove_child(child)
		child.queue_free()

	var walls := StaticBody2D.new()
	walls.name = "Walls"
	structure.add_child(walls)
	for line in _merge_wall_lines(modules):
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
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

	for i in doors.size():
		var door := Door.new()
		door.name = "Door%d" % i
		door.position = doors[i][0]
		# La porte est dessinée verticalement : pivotée dans un mur horizontal.
		if doors[i][1]:
			door.rotation = PI / 2.0
		structure.add_child(door)


## Murs de tous les modules, en coordonnées du vaisseau, fusionnés : une
## cloison partagée (même de longueurs différentes de chaque côté) ne donne
## qu'une série de segments sans chevauchement.
func _merge_wall_lines(modules: Array[Module]) -> Array:
	# Intervalles groupés par droite : clé [horizontale ?, coordonnée fixe].
	var by_line := {}
	for m in modules:
		for line in m.get_wall_lines():
			var a: Vector2 = (m.position + line[0]).round()
			var b: Vector2 = (m.position + line[1]).round()
			var horizontal := is_equal_approx(a.y, b.y)
			var key := [horizontal, a.y if horizontal else a.x]
			var span := Vector2(minf(a.x, b.x), maxf(a.x, b.x)) if horizontal \
					else Vector2(minf(a.y, b.y), maxf(a.y, b.y))
			if not by_line.has(key):
				by_line[key] = []
			by_line[key].append(span)

	var result := []
	for key in by_line:
		var spans: Array = by_line[key]
		spans.sort_custom(func(s1: Vector2, s2: Vector2) -> bool: return s1.x < s2.x)
		var current: Vector2 = spans[0]
		for k in range(1, spans.size() + 1):
			if k < spans.size() and spans[k].x <= current.y:
				current.y = maxf(current.y, spans[k].y)
				continue
			if key[0]:
				result.append([Vector2(current.x, key[1]), Vector2(current.y, key[1])])
			else:
				result.append([Vector2(key[1], current.x), Vector2(key[1], current.y)])
			if k < spans.size():
				current = spans[k]
	return result
