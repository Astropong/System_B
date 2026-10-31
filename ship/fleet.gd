class_name Fleet
extends Node2D
## Tous les vaisseaux de la partie sont ses enfants : celui de départ des
## joueurs (« Ship », dans la scène) et ceux créés et retirés en cours de
## partie par l'hôte (spawn_ship, remove_ship). Le MultiplayerSpawner enfant
## recrée ces derniers chez tous les joueurs, y compris ceux qui arrivent plus
## tard ; leur mouvement et leurs modules sont ensuite synchronisés comme
## ceux de tous les vaisseaux (groupe Ship.GROUP, voir Network).
##
## Un vaisseau est décrit par un dictionnaire (voir spawn_ship), seul envoyé
## sur le réseau : le nœud est construit par _create_ship sur chaque machine.
##
## Ce nœud est le repère de l'espace : ses enfants y ont leurs coordonnées.
## Le vaisseau ancré (celui du joueur local, voir Ship.anchored) ignore ce
## repère et reste fixe dans la scène : ce nœud est donc placé à chaque image
## à l'inverse de la place de ce vaisseau dans l'espace, interpolée comme le
## reste de l'image (d'où l'interpolation physique coupée sur ce nœud).

## Script de chaque type de module, pour construire un vaisseau à partir de
## sa description.
const MODULE_SCRIPTS := {
	Module.ModuleType.PILOTAGE: preload("res://ship/modules/module_pilotage.gd"),
	Module.ModuleType.INFIRMERIE: preload("res://ship/modules/module_infirmerie.gd"),
	Module.ModuleType.REACTEUR: preload("res://ship/modules/module_reacteur.gd"),
	Module.ModuleType.COULOIR: preload("res://ship/modules/module_couloir.gd"),
	Module.ModuleType.RADAR: preload("res://ship/modules/module_radar.gd"),
	Module.ModuleType.GENERATEUR: preload("res://ship/modules/module_generateur.gd"),
	Module.ModuleType.OXYGENE: preload("res://ship/modules/module_oxygene.gd"),
	Module.ModuleType.MAINTENANCE: preload("res://ship/modules/module_maintenance.gd"),
	Module.ModuleType.TELECOMMUNICATION: preload("res://ship/modules/module_telecommunication.gd"),
	Module.ModuleType.LABORATOIRE: preload("res://ship/modules/module_laboratoire.gd"),
	Module.ModuleType.CONSTRUCTION: preload("res://ship/modules/module_construction.gd"),
	Module.ModuleType.TOURELLES: preload("res://ship/modules/module_tourelles.gd"),
}

## Propriétés de module qu'une description peut régler (en plus du type et
## de la place dans la grille).
const MODULE_PROPERTIES: Array[StringName] = [&"nozzle_side", &"size_cells"]

## Vaisseaux créés au début de la partie (immobiles), autour de celui des
## joueurs. Modules : [type, place dans la grille (cases), propriétés].
const STARTING_SHIPS := [
	{"position": Vector2(7000, -2500), "modules": [
		[Module.ModuleType.RADAR, Vector2i(0, 0), {}],
		[Module.ModuleType.OXYGENE, Vector2i(16, 0), {}],
		[Module.ModuleType.TOURELLES, Vector2i(0, 16), {}],
		[Module.ModuleType.GENERATEUR, Vector2i(16, 16), {}],
	]},
	{"position": Vector2(-5500, 4500), "modules": [
		[Module.ModuleType.REACTEUR, Vector2i(0, 0), {}],
		[Module.ModuleType.LABORATOIRE, Vector2i(16, 0), {}],
		[Module.ModuleType.INFIRMERIE, Vector2i(32, 0), {}],
		[Module.ModuleType.MAINTENANCE, Vector2i(48, 0), {}],
	]},
	{"position": Vector2(2500, -7500), "modules": [
		[Module.ModuleType.CONSTRUCTION, Vector2i(0, 0), {}],
		[Module.ModuleType.TELECOMMUNICATION, Vector2i(0, 16), {}],
		[Module.ModuleType.PILOTAGE, Vector2i(0, 32), {}],
		[Module.ModuleType.RADAR, Vector2i(16, 32), {}],
	]},
	{"position": Vector2(-7000, -3500), "modules": [
		[Module.ModuleType.GENERATEUR, Vector2i(0, 0), {}],
		[Module.ModuleType.INFIRMERIE, Vector2i(0, 16), {}],
		[Module.ModuleType.TOURELLES, Vector2i(0, 32), {}],
		[Module.ModuleType.REACTEUR, Vector2i(0, 48), {"nozzle_side": SIDE_BOTTOM}],
	]},
	{"position": Vector2(5000, 6500), "modules": [
		[Module.ModuleType.OXYGENE, Vector2i(0, 0), {}],
		[Module.ModuleType.MAINTENANCE, Vector2i(16, 0), {}],
		[Module.ModuleType.LABORATOIRE, Vector2i(32, 0), {}],
		[Module.ModuleType.CONSTRUCTION, Vector2i(16, 16), {}],
	]},
]

@onready var _spawner: MultiplayerSpawner = $ShipSpawner

# Numéro du prochain vaisseau créé (hôte), pour des noms de nœuds uniques.
var _next_number: int = 1


func _ready() -> void:
	_spawner.spawn_function = _create_ship
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## L'espace autour du vaisseau ancré : l'inverse de sa place dans l'espace.
## Réaffecté seulement s'il change : sinon tous les nœuds de tous les autres
## vaisseaux seraient recalculés à chaque image.
func _process(_delta: float) -> void:
	var anchor := Ship.anchor
	var space := anchor.get_interpolated_space_transform().affine_inverse() if anchor else Transform2D.IDENTITY
	if space != transform:
		transform = space


## Crée les vaisseaux de départ (hôte, à la création de la partie).
func spawn_starting_ships() -> void:
	for data in STARTING_SHIPS:
		spawn_ship(data)


## Crée un vaisseau chez tous les joueurs (hôte uniquement) et le renvoie.
## [param data] : "position" (espace, px), "modules" (liste de [type
## Module.ModuleType, place dans la grille Vector2i, propriétés Dictionary]),
## et au choix "rotation" (radians), "velocity" (px/s), "angular_speed" (°/s).
## L'état de ses modules est à envoyer ensuite (Ship.send_module_states).
func spawn_ship(data: Dictionary) -> Ship:
	var description := data.duplicate()
	description["name"] = "Vaisseau%d" % _next_number
	_next_number += 1
	return _spawner.spawn(description) as Ship


## Retire un vaisseau créé par spawn_ship chez tous les joueurs (hôte
## uniquement). Refusé (faux) s'il a un équipage : les personnages à bord
## disparaîtraient (les faire d'abord changer de vaisseau).
func remove_ship(ship: Ship) -> bool:
	if ship.get_parent() != self or ship.get_node("Crew").get_child_count() > 0:
		return false
	ship.queue_free()
	return true


## Construit le vaisseau décrit par [param data] (sur chaque machine, appelé
## par le MultiplayerSpawner).
func _create_ship(data: Dictionary) -> Node:
	var ship := Ship.new()
	ship.name = data["name"]
	ship.position = data.get("position", Vector2.ZERO)
	ship.rotation = data.get("rotation", 0.0)
	ship.velocity = data.get("velocity", Vector2.ZERO)
	ship.angular_speed = data.get("angular_speed", 0.0)
	var counts := {}
	for entry in data.get("modules", []):
		var script: GDScript = MODULE_SCRIPTS.get(entry[0])
		if script == null:
			push_warning("Type de module inconnu : %s" % str(entry[0]))
			continue
		var module: Module = script.new()
		# Nom unique par type : Radar, Radar2...
		var type_name: String = script.get_global_name().trim_prefix("Module")
		counts[type_name] = counts.get(type_name, 0) + 1
		module.name = type_name if counts[type_name] == 1 else "%s%d" % [type_name, counts[type_name]]
		module.grid_position = entry[1]
		var properties: Dictionary = entry[2] if entry.size() > 2 else {}
		for property in properties:
			if StringName(property) in MODULE_PROPERTIES and property in module:
				module.set(property, properties[property])
		ship.add_child(module)
	return ship
