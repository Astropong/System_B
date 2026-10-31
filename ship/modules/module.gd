@tool
@abstract
class_name Module
extends Node2D
## Classe abstraite de base pour toutes les salles (modules) du vaisseau.
##
## Les caractéristiques du TYPE (identifiant, consommation idéale, pannes
## possibles) sont fournies par chaque classe fille via les méthodes abstraites
## ci-dessous ; la taille et l'alimentation minimale ont une valeur par défaut,
## redéfinissable. Les valeurs propres à CHAQUE INSTANCE (puissance
## fournie, températures de la machine et de la pièce, état, place dans le
## vaisseau) sont des variables de cette classe.

enum ModuleType {
	PILOTAGE, INFIRMERIE, REACTEUR, COULOIR, RADAR, GENERATEUR,
	OXYGENE, MAINTENANCE, TELECOMMUNICATION, LABORATOIRE, CONSTRUCTION, TOURELLES,
}

const TYPE_NAMES := {
	ModuleType.PILOTAGE: "Pilotage",
	ModuleType.INFIRMERIE: "Infirmerie",
	ModuleType.REACTEUR: "Réacteur",
	ModuleType.COULOIR: "Couloir",
	ModuleType.RADAR: "Radar",
	ModuleType.GENERATEUR: "Générateur",
	ModuleType.OXYGENE: "Générateur d'oxygène",
	ModuleType.MAINTENANCE: "Salle de maintenance",
	ModuleType.TELECOMMUNICATION: "Salle de télécommunication",
	ModuleType.LABORATOIRE: "Laboratoire",
	ModuleType.CONSTRUCTION: "Salle de construction",
	ModuleType.TOURELLES: "Tourelles",
}

## Taille d'une case en pixels : le diamètre du personnage.
const CELL_SIZE := 48.0

## Taille par défaut d'un module (cases).
const DEFAULT_SIZE := Vector2i(16, 16)

## Masse par défaut d'un module (kg) : 1 tonne (voir get_mass).
const DEFAULT_MASS := 1000.0

## Largeur de l'ouverture d'une porte entre deux modules (2 cases).
const DOOR_SIZE := CELL_SIZE * 2.0

## Bornes de la température (°C) : du zéro absolu à 227 °C (500 K).
const TEMPERATURE_MIN := -273
const TEMPERATURE_MAX := 227

## Effets visuels de température (voir _update_climate_effects).
## Déformation par la chaleur au-dessus de HEAT_THRESHOLD (°C), pleine à HEAT_FULL.
const HEAT_THRESHOLD := 40
const HEAT_FULL := 100
## Gel en dessous de FROST_THRESHOLD (°C), plein à FROST_FULL.
const FROST_THRESHOLD := 10
const FROST_FULL := -20
## Intensité d'un effet dès que son seuil est franchi (0–1).
const CLIMATE_EFFECT_MIN_STRENGTH := 0.3
const HEAT_SHADER := preload("res://ship/modules/shaders/heat_haze.gdshader")
const FROST_SHADER := preload("res://ship/modules/shaders/frost.gdshader")

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
const BATTERY_LOW_COLOR := Color(0.95, 0.25, 0.2)

## Éclairage de la salle selon l'alimentation (voir _update_lighting).
const LIGHT_LOW_COLOR := Color(1.0, 0.3, 0.25)        # sous le minimum : rouge
const LIGHT_NORMAL_COLOR := Color.WHITE
const LIGHT_OVERLOAD_COLOR := Color(1.0, 0.82, 0.6)   # au-delà de l'optimum : orangé
const LIGHT_LOW_INTENSITY := 0.5
const LIGHT_DEGRADED_MIN_INTENSITY := 0.5
const LIGHT_DEGRADED_MAX_INTENSITY := 0.9
## Écart (W) en dessous duquel l'alimentation est considérée comme optimale.
const POWER_TOLERANCE := 0.5
## Nombre moyen de clignotements par seconde, près du minimum et près de l'optimum.
const FLICKER_RATE_NEAR_MIN := 3.0
const FLICKER_RATE_NEAR_OPTIMAL := 0.8
## Lampes : position (retrait depuis les coins) et taille.
const LAMP_INSET := 24.0
const LAMP_RADIUS := 6.0

## Zone d'interaction (voir get_interaction_rect) : taille en cases et couleur.
const INTERACTION_SIZE := Vector2(2, 2)
const INTERACTION_COLOR := Color(1, 1, 1, 0.35)
## Au-dessus de cet état, le module est intact ; sinon il est cassé.
const BROKEN_THRESHOLD := 0.5

## Aménagement des salles (voir _draw_details) : meubles en aplat sombre
## cerclés de la couleur du type, emblème au sol en transparence.
const FURNITURE_COLOR := Color(0.23, 0.25, 0.3)
const FURNITURE_OUTLINE := 2.0
const EMBLEM_ALPHA := 0.22
## Coins supérieurs gauches (cases) des quatre zones d'aménagement d'une salle
## de taille DEFAULT_SIZE, de QUADRANT_SIZE × QUADRANT_SIZE cases chacune,
## hors de la croix de passage centrale.
const QUADRANTS: Array[Vector2] = [Vector2(2.5, 2.5), Vector2(10.5, 2.5), Vector2(2.5, 10.5), Vector2(10.5, 10.5)]
const QUADRANT_SIZE := 3.0


# --- Valeurs propres à chaque instance -------------------------------------

## Puissance électrique effectivement fournie au module (W). Ces valeurs sont
## reçues 10 fois par seconde pour tous les modules : la salle n'est
## redessinée que si ce qu'elle affiche change (jauge, températures arrondies).
@export var power_supplied: float = 0.0:
	set(value):
		value = maxf(value, 0.0)
		if value != power_supplied:
			power_supplied = value
			queue_redraw()

## Température de la pièce du module (°C), bornée entre TEMPERATURE_MIN et
## TEMPERATURE_MAX. Commande les effets de chaleur et de gel.
@export_range(-273, 227, 0.1, "suffix:°C") var room_temperature: float = TemperatureRules.ROOM_BASE_TEMPERATURE:
	set(value):
		value = clampf(value, TEMPERATURE_MIN, TEMPERATURE_MAX)
		if value == room_temperature:
			return
		var redraw := roundi(value) != roundi(room_temperature)
		room_temperature = value
		_update_climate_effects()
		if redraw:
			queue_redraw()

## Température de la machine du module (°C), bornée entre TEMPERATURE_MIN et
## TEMPERATURE_MAX. Réchauffe la pièce (voir temperature_rules.gd).
@export_range(-273, 227, 0.1, "suffix:°C") var machine_temperature: float = TemperatureRules.ROOM_BASE_TEMPERATURE:
	set(value):
		value = clampf(value, TEMPERATURE_MIN, TEMPERATURE_MAX)
		if roundi(value) != roundi(machine_temperature):
			queue_redraw()
		machine_temperature = value

## État du module : 1 = intact, 0 = détruit (voir is_intact).
@export_range(0.0, 1.0, 0.01) var state: float = 1.0:
	set(value):
		state = clampf(value, 0.0, 1.0)

## Vrai si le module peut être éteint (levier marche / arrêt de la fenêtre
## du module, voir ModuleWindow).
@export var can_be_switched_off: bool = true

## Vrai si l'alimentation cible du module se règle (curseur de la fenêtre du
## module), entre get_min_power() et get_max_power(). Faux pour le Couloir et
## le Générateur.
@export var adjustable_power: bool = true

## Alimentation cible maximale, en proportion de l'alimentation optimale.
@export_range(1.0, 3.0, 0.05) var max_power_ratio: float = 1.5

## Module allumé. Éteint, il ne consomme rien (power_supplied à 0).
## Décidé par l'hôte (voir request_switch).
var is_on: bool = true

## Alimentation cible (W) : la recharge s'arrête à cette valeur si
## [member adjustable_power], sinon à l'optimum. Décidée par l'hôte (voir
## request_target_power) ; négative tant qu'elle n'est pas réglée (optimum).
var target_power: float = -1.0

var _lamps: Node2D
var _light_color: Color = Color.WHITE
var _flicker_time_left: float = 0.0
var _flicker_factor: float = 1.0
var _heat_effect: Node2D
var _heat_backbuffer: BackBufferCopy
var _frost_effect: Node2D

## Place du module dans le vaisseau : coin supérieur gauche, en cases.
## Le vaisseau en déduit la position, les murs, les portes et les voisins.
@export var grid_position: Vector2i = Vector2i.ZERO:
	set(value):
		grid_position = value
		_request_arrangement()

## Ouvertures des portes, réglées par le vaisseau : liste de [côté (Side),
## position du centre de l'ouverture le long de ce côté (px)].
var doorways: Array = []:
	set(value):
		doorways = value
		queue_redraw()

## Modules adjacents reliés par une porte (réglés par le vaisseau).
var neighbors: Array[Module] = []


# --- Caractéristiques du type (à définir dans chaque classe fille) ---------

## Identifiant du type de module.
@abstract func get_type_id() -> ModuleType

## Consommation électrique idéale (W).
@abstract func get_ideal_power() -> float

## Pannes pouvant survenir dans ce type de module (à définir ultérieurement).
@abstract func get_possible_failures() -> Array[StringName]


## Alimentation minimale de fonctionnement (W) : par défaut la moitié de
## l'alimentation optimale. Une classe fille peut la redéfinir.
func get_min_power() -> float:
	return get_ideal_power() * 0.5


## Masse du module (kg) : DEFAULT_MASS par défaut. Une classe fille peut la
## redéfinir. Le vaisseau en déduit sa masse et son inertie (voir Ship).
func get_mass() -> float:
	return DEFAULT_MASS


## Alimentation cible maximale (W) : optimum × [member max_power_ratio].
func get_max_power() -> float:
	return get_ideal_power() * max_power_ratio


## Alimentation à laquelle la recharge s'arrête (W) : la cible réglée si
## [member adjustable_power], sinon l'optimum.
func get_power_cap() -> float:
	if not adjustable_power or target_power < 0.0:
		return get_ideal_power()
	return target_power


## Taille en cases (1 case = taille du personnage) : DEFAULT_SIZE par défaut.
## Une classe fille peut la redéfinir.
func get_size() -> Vector2i:
	return DEFAULT_SIZE


# --- Méthodes communes -------------------------------------------------------

## Vrai si l'état du module dépasse BROKEN_THRESHOLD.
func is_intact() -> bool:
	return state > BROKEN_THRESHOLD


## Zone d'interaction (px, coordonnées locales) : un joueur qui s'y trouve
## peut ouvrir la fenêtre du module (voir ModuleWindow). Pour l'instant
## INTERACTION_SIZE cases au centre de la salle.
func get_interaction_rect() -> Rect2:
	var size := INTERACTION_SIZE * CELL_SIZE
	return Rect2((get_pixel_size() - size) / 2.0, size)


## Remplit le centre de la fenêtre du module avec les éléments propres au
## type. Par défaut : un bouton d'exemple. Une classe fille peut la redéfinir.
## Les boutons ne doivent pas prendre le focus (Espace ferme la fenêtre).
func build_interface(container: Container) -> void:
	var button := Button.new()
	button.text = tr("Bouton d'exemple : %s") % get_type_name()
	button.focus_mode = Control.FOCUS_NONE
	var presses := [0]
	button.pressed.connect(func() -> void:
		presses[0] += 1
		button.text = (tr("Bouton d'exemple : %s") % get_type_name()) + " (%d)" % presses[0])
	container.add_child(button)


## Nom du type, traduit dans la langue du jeu (voir Language).
func get_type_name() -> String:
	return tr(TYPE_NAMES[get_type_id()])


func _notification(what: int) -> void:
	# Changement de langue : le nom et les textes de debug sont dessinés.
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


## Taille du module en pixels.
func get_pixel_size() -> Vector2:
	return Vector2(get_size()) * CELL_SIZE


## À appeler quand la place ou la taille du module change : le vaisseau
## replace alors ses modules et reconstruit murs et portes.
func _request_arrangement() -> void:
	queue_redraw()
	var ship := get_parent()
	if ship != null and ship.has_method("arrange_modules"):
		ship.arrange_modules()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# Lampes dessinées par un nœud enfant, pour ne redessiner qu'elles.
	_lamps = Node2D.new()
	_lamps.name = "Lamps"
	_lamps.draw.connect(_draw_lamps)
	add_child(_lamps)
	_create_climate_effects()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_lighting(delta)


# --- Commandes : levier marche / arrêt et curseur d'alimentation -------------

## Demande à l'hôte d'allumer ou d'éteindre le module (joueur local).
func request_switch(on: bool) -> void:
	_request_switch.rpc_id(1, on)


## Demande à l'hôte de régler l'alimentation cible à [param watts] (joueur local).
func request_target_power(watts: float) -> void:
	_request_target_power.rpc_id(1, watts)


## Hôte : vrai si l'auteur de la demande en cours est à bord du vaisseau du
## module (une demande partie juste avant un changement de vaisseau est ignorée).
func _is_requester_aboard() -> bool:
	var ship := get_parent() as Ship
	return ship != null and ship.has_crew_member(multiplayer.get_remote_sender_id())


## Envoie l'état des commandes (marche, cible) à un joueur qui arrive (hôte).
func send_controls_to(peer_id: int) -> void:
	_receive_controls.rpc_id(peer_id, is_on, target_power)


@rpc("any_peer", "call_local", "reliable")
func _request_switch(on: bool) -> void:
	if not multiplayer.is_server() or not can_be_switched_off or not _is_requester_aboard():
		return
	_apply_controls(on, target_power)
	_receive_controls.rpc(is_on, target_power)


@rpc("any_peer", "call_local", "reliable")
func _request_target_power(watts: float) -> void:
	if not multiplayer.is_server() or not adjustable_power or not _is_requester_aboard():
		return
	_apply_controls(is_on, watts)
	_receive_controls.rpc(is_on, target_power)


@rpc("authority", "call_remote", "reliable")
func _receive_controls(on: bool, watts: float) -> void:
	_apply_controls(on, watts)


## Éteint, le module ne consomme plus rien, immédiatement.
func _apply_controls(on: bool, watts: float) -> void:
	is_on = on
	if watts >= 0.0:
		target_power = clampf(watts, get_min_power(), get_max_power())
	if not is_on:
		power_supplied = 0.0


## Rapport puissance fournie / puissance idéale (1 = alimentation parfaite).
func get_power_ratio() -> float:
	var ideal := get_ideal_power()
	return 1.0 if ideal <= 0.0 else power_supplied / ideal


## Éclairage selon l'alimentation :
## - sous le minimum : rouge, à 50 % ;
## - entre le minimum et l'optimum : blanc, de 50 % à 90 %, avec clignotements ;
## - à l'optimum : blanc, à 100 %, stable ;
## - au-delà de l'optimum : légèrement orangé, à 100 %.
## L'éclairage teinte le dessin de la salle (self_modulate) et ses lampes ;
## les personnages et les portes ne sont pas affectés.
func _update_lighting(delta: float) -> void:
	var power := power_supplied
	var optimal := get_ideal_power()
	var minimum := get_min_power()
	var color := LIGHT_NORMAL_COLOR
	var intensity := 1.0
	var flickering := false
	var progress := 1.0

	if power < minimum:
		color = LIGHT_LOW_COLOR
		intensity = LIGHT_LOW_INTENSITY
	elif power < optimal - POWER_TOLERANCE:
		progress = inverse_lerp(minimum, optimal, power)
		intensity = lerpf(LIGHT_DEGRADED_MIN_INTENSITY, LIGHT_DEGRADED_MAX_INTENSITY, progress)
		flickering = true
	elif power > optimal + POWER_TOLERANCE:
		color = LIGHT_OVERLOAD_COLOR

	# Clignotements : de brèves baisses de lumière, plus fréquentes près du minimum.
	if flickering:
		if _flicker_time_left > 0.0:
			_flicker_time_left -= delta
		elif randf() < lerpf(FLICKER_RATE_NEAR_MIN, FLICKER_RATE_NEAR_OPTIMAL, progress) * delta:
			_flicker_time_left = randf_range(0.04, 0.15)
			_flicker_factor = randf_range(0.45, 0.8)
	if not flickering or _flicker_time_left <= 0.0:
		_flicker_factor = 1.0

	var lit := Color(color.r * intensity * _flicker_factor, color.g * intensity * _flicker_factor,
			color.b * intensity * _flicker_factor)
	if lit != _light_color:
		_light_color = lit
		self_modulate = lit
		if _lamps:
			_lamps.queue_redraw()


## Petites lampes dans les coins de la salle, de la couleur de l'éclairage.
func _draw_lamps() -> void:
	var size := get_pixel_size()
	for corner in [Vector2(LAMP_INSET, LAMP_INSET), Vector2(size.x - LAMP_INSET, LAMP_INSET),
			Vector2(LAMP_INSET, size.y - LAMP_INSET), Vector2(size.x - LAMP_INSET, size.y - LAMP_INSET)]:
		var halo := _light_color
		halo.a = 0.12
		_lamps.draw_circle(corner, LAMP_RADIUS * 4.0, halo)
		halo.a = 0.25
		_lamps.draw_circle(corner, LAMP_RADIUS * 2.2, halo)
		_lamps.draw_circle(corner, LAMP_RADIUS, _light_color)
		_lamps.draw_arc(corner, LAMP_RADIUS, 0.0, TAU, 16, WALL_COLOR.darkened(0.3), 1.5)


## Crée les calques des effets de chaleur et de gel, posés sur la salle
## (sous les personnages et les portes, dessinés après les modules).
func _create_climate_effects() -> void:
	var rect := Rect2(Vector2.ZERO, get_pixel_size())

	# La déformation lit l'écran déjà dessiné : une copie de l'arrière-plan
	# juste avant elle garantit que la salle elle-même y figure. Copie de tout
	# l'écran : en mode rectangle, la zone copiée ne suit pas la mise à
	# l'échelle de la fenêtre et laisse des bandes noires.
	# Copie active seulement avec l'effet (voir _update_climate_effects) :
	# chaque copie de l'écran coûte cher (≈ 0,6 ms par module et par image).
	_heat_backbuffer = BackBufferCopy.new()
	_heat_backbuffer.name = "HeatBackBuffer"
	_heat_backbuffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(_heat_backbuffer)

	_heat_effect = _create_effect_layer("HeatEffect", HEAT_SHADER, rect)
	_frost_effect = _create_effect_layer("FrostEffect", FROST_SHADER, rect)
	_update_climate_effects()


func _create_effect_layer(layer_name: String, shader: Shader, rect: Rect2) -> Node2D:
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	shader_material.set_shader_parameter("room_size", rect.size)
	var layer := Node2D.new()
	layer.name = layer_name
	layer.material = shader_material
	layer.visible = false
	layer.draw.connect(func() -> void: layer.draw_rect(rect, Color.WHITE))
	add_child(layer)
	return layer


## Affiche la déformation par la chaleur au-dessus de HEAT_THRESHOLD et le gel
## en dessous de FROST_THRESHOLD, d'autant plus marqués que l'écart est grand.
func _update_climate_effects() -> void:
	if _heat_effect == null:
		return
	_set_effect_strength(_heat_effect, room_temperature > HEAT_THRESHOLD,
			inverse_lerp(HEAT_THRESHOLD, HEAT_FULL, room_temperature))
	_heat_backbuffer.visible = _heat_effect.visible
	_set_effect_strength(_frost_effect, room_temperature < FROST_THRESHOLD,
			inverse_lerp(FROST_THRESHOLD, FROST_FULL, room_temperature))


func _set_effect_strength(layer: Node2D, active: bool, progress: float) -> void:
	layer.visible = active
	if active:
		var strength := lerpf(CLIMATE_EFFECT_MIN_STRENGTH, 1.0, clampf(progress, 0.0, 1.0))
		(layer.material as ShaderMaterial).set_shader_parameter("strength", strength)


## Murs du module sous forme de segments [début, fin] en coordonnées locales,
## interrompus à chaque ouverture de porte ([member doorways]). Les murs du
## haut et du bas débordent d'une demi-épaisseur pour fermer les coins.
## Le vaisseau s'en sert aussi pour construire les collisions et les ombres.
func get_wall_lines() -> Array:
	var size := get_pixel_size()
	var half_t := WALL_THICKNESS / 2.0
	var lines := []
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		var horizontal: bool = side == SIDE_TOP or side == SIDE_BOTTOM
		var length := size.x if horizontal else size.y
		var start := -half_t if horizontal else 0.0
		var end := length + half_t if horizontal else length
		var gaps: Array[float] = []
		for doorway in doorways:
			if doorway[0] == side:
				gaps.append(doorway[1])
		gaps.sort()
		var cuts: Array[float] = [start]
		for center in gaps:
			cuts.append(center - DOOR_SIZE / 2.0)
			cuts.append(center + DOOR_SIZE / 2.0)
		cuts.append(end)
		for i in range(0, cuts.size(), 2):
			if cuts[i + 1] - cuts[i] < 0.5:
				continue
			if horizontal:
				var y := 0.0 if side == SIDE_TOP else size.y
				lines.append([Vector2(cuts[i], y), Vector2(cuts[i + 1], y)])
			else:
				var x := 0.0 if side == SIDE_LEFT else size.x
				lines.append([Vector2(x, cuts[i]), Vector2(x, cuts[i + 1])])
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

	# Aménagement propre au type de module, à l'échelle réelle.
	_draw_details(rect)

	# Zone d'interaction.
	var zone := get_interaction_rect()
	draw_rect(zone, Color(INTERACTION_COLOR, 0.08))
	draw_rect(zone, INTERACTION_COLOR, false, 2.0)

	# Murs (avec les ouvertures des portes).
	for line in get_wall_lines():
		draw_line(line[0], line[1], WALL_COLOR, WALL_THICKNESS)

	# Nom du module, en haut à gauche (le milieu des murs accueille les portes).
	draw_string(ThemeDB.fallback_font, Vector2(CELL_SIZE * 0.75, CELL_SIZE * 0.9), get_type_name(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, TEXT_COLOR)

	# Jauge d'alimentation : uniquement en mode débogage (voir debug_mode.gd).
	if DebugMode.is_enabled():
		_draw_battery()


## Jauge verticale de l'alimentation : pleine à l'alimentation optimale (le
## plafond de recharge), rouge sous l'alimentation minimale, verte au-dessus.
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
		var color := BATTERY_OK_COLOR if power_supplied >= get_min_power() else BATTERY_LOW_COLOR
		draw_rect(Rect2(rect.position.x + 3, rect.end.y - 3 - h, rect.size.x - 6, h), color)

	draw_rect(rect, WALL_COLOR, false, 2.0)

	# Valeurs : puissance fournie et puissance optimale.
	var font := ThemeDB.fallback_font
	var text_x := rect.position.x - 30
	var text_w := rect.size.x + 60
	draw_string(font, Vector2(text_x, rect.end.y + 22), "%d W" % roundi(power_supplied),
			HORIZONTAL_ALIGNMENT_CENTER, text_w, 16, TEXT_COLOR)
	draw_string(font, Vector2(text_x, rect.end.y + 40), tr("opt. %d W") % roundi(get_ideal_power()),
			HORIZONTAL_ALIGNMENT_CENTER, text_w, 13, TEXT_COLOR.darkened(0.3))
	draw_string(font, Vector2(text_x, rect.end.y + 60), tr("pièce %d °C") % roundi(room_temperature),
			HORIZONTAL_ALIGNMENT_CENTER, text_w, 16, TEXT_COLOR)
	draw_string(font, Vector2(text_x, rect.end.y + 78), tr("mach. %d °C") % roundi(machine_temperature),
			HORIZONTAL_ALIGNMENT_CENTER, text_w, 13, TEXT_COLOR.darkened(0.3))


## Aménagement propre à chaque type (facultatif à surcharger), dessiné à
## l'échelle réelle dans [param _rect] (la salle entière, en px).
## Convention : le milieu de chaque mur peut recevoir une porte, on laisse donc
## libre une croix de passage centrale (cases 6 à 10) ; les meubles occupent
## les quatre quarts, l'emblème du type est peint au sol au centre.
## Le coin supérieur gauche (cases 0 à 2) accueille le nom et la jauge.
func _draw_details(_rect: Rect2) -> void:
	pass


## Rectangle en cases converti en pixels (coordonnées locales).
static func cells(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(x * CELL_SIZE, y * CELL_SIZE, w * CELL_SIZE, h * CELL_SIZE)


## Point en cases converti en pixels.
static func cell_point(x: float, y: float) -> Vector2:
	return Vector2(x, y) * CELL_SIZE


## Meuble : aplat sombre cerclé de [param accent].
func _draw_furniture(r: Rect2, accent: Color) -> void:
	draw_rect(r, FURNITURE_COLOR)
	draw_rect(r, accent, false, FURNITURE_OUTLINE)


## Meuble rond : disque sombre cerclé de [param accent].
func _draw_round_furniture(center: Vector2, radius: float, accent: Color) -> void:
	draw_circle(center, radius, FURNITURE_COLOR)
	draw_arc(center, radius, 0.0, TAU, 48, accent, FURNITURE_OUTLINE)


## Couleur d'emblème au sol : [param accent] en transparence.
static func emblem_color(accent: Color) -> Color:
	return Color(accent, EMBLEM_ALPHA)
