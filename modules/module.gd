@tool
@abstract
class_name Module
extends Node2D
## Classe abstraite de base pour toutes les salles (modules) du vaisseau.
##
## Les caractéristiques du TYPE (identifiant, consommation idéale, taille,
## pannes possibles) sont fournies par chaque classe fille via les méthodes
## abstraites ci-dessous. Les valeurs propres à CHAQUE INSTANCE (puissance
## fournie, température, état) sont des variables de cette classe.

enum ModuleType { PILOTAGE, INFIRMERIE, REACTEUR, COULOIR, RADAR, GENERATEUR }

const TYPE_NAMES := {
	ModuleType.PILOTAGE: "Pilotage",
	ModuleType.INFIRMERIE: "Infirmerie",
	ModuleType.REACTEUR: "Réacteur",
	ModuleType.COULOIR: "Couloir",
	ModuleType.RADAR: "Radar",
	ModuleType.GENERATEUR: "Générateur",
}

## Taille d'une case en pixels : le diamètre du personnage.
const CELL_SIZE := 48.0

## Largeur de l'ouverture d'une porte entre deux modules (2 cases).
const DOOR_SIZE := CELL_SIZE * 2.0

const TEMPERATURE_MIN := 0.0
const TEMPERATURE_MAX := 500.0

const FLOOR_COLOR := Color(0.16, 0.17, 0.2)
const GRID_COLOR := Color(1, 1, 1, 0.05)
const WALL_COLOR := Color(0.55, 0.58, 0.65)
const TEXT_COLOR := Color(0.85, 0.88, 0.95)
const WALL_THICKNESS := 12.0

## Jauge de batterie (coin supérieur gauche de la salle).
const BATTERY_POSITION := Vector2(CELL_SIZE * 0.75, CELL_SIZE * 1.5)
const BATTERY_SIZE := Vector2(28, 140)
const BATTERY_EMPTY_COLOR := Color(0.08, 0.09, 0.1)
const BATTERY_OK_COLOR := Color(0.3, 0.9, 0.4)
const BATTERY_OVERLOAD_COLOR := Color(0.95, 0.25, 0.2)

## Taille (px) de la boîte de référence dans laquelle chaque type dessine
## son schéma ; le dessin est ensuite agrandi pour remplir la salle.
const DETAILS_REFERENCE := 240.0


# --- Valeurs propres à chaque instance -------------------------------------

## Puissance électrique effectivement fournie au module (W).
@export var power_supplied: float = 0.0:
	set(value):
		power_supplied = maxf(value, 0.0)
		queue_redraw()

## Température du module (K), bornée entre 0 et 500.
@export_range(0.0, 500.0, 0.1, "suffix:K") var temperature: float = 293.0:
	set(value):
		temperature = clampf(value, TEMPERATURE_MIN, TEMPERATURE_MAX)

## État du module : 1 = intact, 0 = détruit.
@export_range(0.0, 1.0, 0.01) var state: float = 1.0:
	set(value):
		state = clampf(value, 0.0, 1.0)
		queue_redraw()

## Ouvertures pour une porte dans les murs gauche et droit (réglées par le vaisseau).
@export var door_left: bool = true:
	set(value):
		door_left = value
		queue_redraw()
@export var door_right: bool = true:
	set(value):
		door_right = value
		queue_redraw()


# --- Caractéristiques du type (à définir dans chaque classe fille) ---------

## Identifiant du type de module.
@abstract func get_type_id() -> ModuleType

## Consommation électrique idéale (W).
@abstract func get_ideal_power() -> float

## Taille en cases (1 case = taille du personnage).
@abstract func get_size() -> Vector2i

## Pannes pouvant survenir dans ce type de module (à définir ultérieurement).
@abstract func get_possible_failures() -> Array[StringName]


# --- Méthodes communes -------------------------------------------------------

func get_type_name() -> String:
	return TYPE_NAMES[get_type_id()]


## Taille du module en pixels.
func get_pixel_size() -> Vector2:
	return Vector2(get_size()) * CELL_SIZE


## Rapport puissance fournie / puissance idéale (1 = alimentation parfaite).
func get_power_ratio() -> float:
	var ideal := get_ideal_power()
	return 1.0 if ideal <= 0.0 else power_supplied / ideal


## Murs du module sous forme de segments [début, fin] en coordonnées locales,
## avec une ouverture au milieu des murs gauche/droit qui ont une porte.
## Le vaisseau s'en sert aussi pour construire les collisions et les ombres.
func get_wall_lines() -> Array:
	var size := get_pixel_size()
	var half_t := WALL_THICKNESS / 2.0
	var lines := [
		[Vector2(-half_t, 0), Vector2(size.x + half_t, 0)],
		[Vector2(-half_t, size.y), Vector2(size.x + half_t, size.y)],
	]
	var gap_top := (size.y - DOOR_SIZE) / 2.0
	var gap_bottom := gap_top + DOOR_SIZE
	for side in [[0.0, door_left], [size.x, door_right]]:
		var x: float = side[0]
		if side[1]:
			lines.append([Vector2(x, 0), Vector2(x, gap_top)])
			lines.append([Vector2(x, gap_bottom), Vector2(x, size.y)])
		else:
			lines.append([Vector2(x, 0), Vector2(x, size.y)])
	return lines


func _draw() -> void:
	var size := get_pixel_size()
	var rect := Rect2(Vector2.ZERO, size)

	# Sol et quadrillage (une case = un personnage).
	draw_rect(rect, FLOOR_COLOR)
	for i in range(1, get_size().x):
		draw_line(Vector2(i * CELL_SIZE, 0), Vector2(i * CELL_SIZE, size.y), GRID_COLOR)
	for j in range(1, get_size().y):
		draw_line(Vector2(0, j * CELL_SIZE), Vector2(size.x, j * CELL_SIZE), GRID_COLOR)

	# Schéma propre au type de module, agrandi et centré dans la salle.
	var k := minf(size.x, size.y) / DETAILS_REFERENCE
	draw_set_transform((size - Vector2(k, k) * DETAILS_REFERENCE) / 2.0, 0.0, Vector2(k, k))
	_draw_details(Rect2(0, 0, DETAILS_REFERENCE, DETAILS_REFERENCE))
	draw_set_transform(Vector2.ZERO)

	# Murs (avec les ouvertures des portes).
	for line in get_wall_lines():
		draw_line(line[0], line[1], WALL_COLOR, WALL_THICKNESS)

	# Nom du module.
	draw_string(ThemeDB.fallback_font, Vector2(0, 48), get_type_name(),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 28, TEXT_COLOR)

	_draw_battery()


## Jauge verticale de l'alimentation : pleine et verte à l'alimentation
## optimale, elle vire progressivement au rouge au-delà, jusqu'au plafond
## de recharge (PowerRules.MAX_CHARGE_RATIO).
func _draw_battery() -> void:
	var rect := Rect2(BATTERY_POSITION, BATTERY_SIZE)
	var ratio := get_power_ratio()

	# Borne de la pile, puis corps vide.
	draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.3, -6), Vector2(rect.size.x * 0.4, 6)), WALL_COLOR)
	draw_rect(rect, BATTERY_EMPTY_COLOR)

	# Remplissage depuis le bas.
	var fill := clampf(ratio, 0.0, 1.0)
	if fill > 0.0:
		var inner_height := rect.size.y - 6.0
		var h := inner_height * fill
		var overload := clampf((ratio - 1.0) / (PowerRules.MAX_CHARGE_RATIO - 1.0), 0.0, 1.0)
		var color := BATTERY_OK_COLOR.lerp(BATTERY_OVERLOAD_COLOR, overload)
		draw_rect(Rect2(rect.position.x + 3, rect.end.y - 3 - h, rect.size.x - 6, h), color)

	draw_rect(rect, WALL_COLOR, false, 2.0)

	# Valeurs : puissance fournie et puissance optimale.
	var font := ThemeDB.fallback_font
	var text_x := rect.position.x - 30
	var text_w := rect.size.x + 60
	draw_string(font, Vector2(text_x, rect.end.y + 22), "%d W" % roundi(power_supplied),
			HORIZONTAL_ALIGNMENT_CENTER, text_w, 16, TEXT_COLOR)
	draw_string(font, Vector2(text_x, rect.end.y + 40), "opt. %d W" % roundi(get_ideal_power()),
			HORIZONTAL_ALIGNMENT_CENTER, text_w, 13, TEXT_COLOR.darkened(0.3))


## Dessin schématique propre à chaque type (facultatif à surcharger).
## [param _rect] est la boîte de référence (DETAILS_REFERENCE × DETAILS_REFERENCE).
func _draw_details(_rect: Rect2) -> void:
	pass
