@tool
class_name Ship
extends Node2D
## Vaisseau : aligne ses modules enfants de gauche à droite (arrière -> avant),
## centrés sur la position du vaisseau, puis génère les murs (collisions et
## ombres) et une porte entre chaque paire de modules voisins.
## Pour changer la composition, ajoutez, supprimez ou réordonnez les modules
## enfants dans la scène.
##
## Multijoueur : seul l'hôte fait avancer le vaisseau ; sa position est
## transmise aux autres joueurs par le nœud ShipSync.
## L'hôte applique aussi les règles d'alimentation (voir power_rules.gd)
## PowerRules.UPDATE_RATE fois par seconde et envoie le résultat aux autres.

## Vitesse d'avancée du vaisseau vers la droite, en pixels par seconde
## (1 case = 48 px).
@export var speed: float = 10.0

var _arranging: bool = false
var _power_timer: float = 0.0


func _ready() -> void:
	child_order_changed.connect(arrange_modules)
	arrange_modules()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_multiplayer_authority():
		return
	position.x += speed * delta
	_update_power(delta)


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

	# Un seul petit message pour tous les modules.
	var values := PackedFloat32Array()
	for m in modules:
		values.append(m.power_supplied)
	_receive_power.rpc(values)


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_power(values: PackedFloat32Array) -> void:
	var modules := get_modules()
	for i in mini(values.size(), modules.size()):
		modules[i].power_supplied = values[i]


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

	# Murs : une forme de collision et une ombre par segment.
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	structure.add_child(walls)
	for m in modules:
		for line in m.get_wall_lines():
			var a: Vector2 = m.position + line[0]
			var b: Vector2 = m.position + line[1]

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
