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
## Mouvement : le vaisseau garde sa vitesse ([member velocity]) et sa vitesse
## de rotation ([member angular_speed]) tant que rien ne le pousse (inertie).
## Les commandes du pilote ([member thrust_command], [member turn_command])
## font agir les réacteurs (ModuleReacteur) : accélération = poussée / masse
## totale des modules, accélération angulaire = couple / moment d'inertie.
##
## Multijoueur : chaque joueur simule le mouvement lui-même. L'hôte fait
## autorité : il envoie chaque changement de commandes (avec la position,
## l'orientation et les vitesses), et une correction toutes les
## MOTION_SYNC_INTERVAL secondes ; les autres résorbent l'écart en douceur.
## Tous les joueurs voient ainsi le vaisseau sous la même orientation.
## L'hôte applique aussi les règles d'alimentation (voir power_rules.gd)
## PowerRules.UPDATE_RATE fois par seconde, puis les règles de température
## (voir temperature_rules.gd), et envoie le résultat aux autres.

## Intervalle (s) entre deux corrections de position envoyées par l'hôte.
const MOTION_SYNC_INTERVAL := 1.0
## Vitesse de résorption d'un écart de position ou d'orientation (proportion par seconde).
const CORRECTION_RATE := 2.0
## Au-delà de cet écart (px), la position est corrigée d'un coup.
const CORRECTION_SNAP_DISTANCE := 96.0
## Au-delà de cet écart (degrés), l'orientation est corrigée d'un coup.
const CORRECTION_SNAP_ANGLE := 10.0
## Les deux seuils ci-dessus s'agrandissent de la distance (ou de l'angle)
## parcourue en ce temps (s) à la vitesse actuelle : à grande vitesse, une
## petite erreur sur le temps de trajet d'un message donne un grand écart.
const CORRECTION_SNAP_TIME := 0.1
## Longueur minimale (cases) d'un mur partagé pour y placer une porte.
const MIN_SHARED_WALL := 4
## Écart vertical (px) entre les joueurs à leur apparition (voir get_spawn_position).
const SPAWN_SPACING := 64.0

## Groupe de tous les vaisseaux de la partie (celui des joueurs et les autres),
## pour les synchroniser ensemble (voir Network).
const GROUP := &"ships"
## Matière de la coque, dessinée à la place des salles en vue « coque » :
## métal gris brossé en plaques (réglages dans le shader).
const HULL_SHADER := preload("res://ship/shaders/hull_metal.gdshader")

## Vue « coque » du joueur local (réglée par Piloting) : tous les vaisseaux
## sont dessinés comme une silhouette en métal (HULL_SHADER : salles et
## tuyères), avec les flammes des réacteurs, sans le brouillard de guerre, au
## lieu de leurs salles.
static var hull_view: bool = false

## Le vaisseau ancré de la partie (voir anchored), ou null.
static var anchor: Ship

## Échelle des forces : 1 case = 1 m (la taille du personnage).
const PIXELS_PER_METER := Module.CELL_SIZE
## Vitesse maximale d'un vaisseau (km/h), et en px/s : la vitesse est bornée
## à chaque pas (poussée et chocs compris). Au-delà de cette vitesse, rien
## n'est garanti (collisions entre vaisseaux, précision des positions) : le
## jeu suppose qu'elle n'est jamais dépassée.
const MAX_SPEED_KMH := 5000.0
const MAX_SPEED := MAX_SPEED_KMH / 3.6 * PIXELS_PER_METER
## Bras de levier (m) en dessous duquel un réacteur ne fait pas tourner.
const TORQUE_ARM_MIN := 0.01
## Répartition entre réacteurs (voir _allocate_throttles) : poids d'un couple
## face à une force (1/m : un couple de 20 N·m compte comme 1 N), et nombre de
## passes de calcul.
const TORQUE_WEIGHT := 1.0 / 20.0
const ALLOCATION_SWEEPS := 20

## Vaisseau ancré (sur chaque machine, celui du joueur local ; un seul à la
## fois, voir make_anchor ; à cocher dans la scène pour celui du départ) : son
## nœud reste immobile à l'origine de la scène (top_level), et c'est l'espace
## qui bouge autour de lui (Fleet et ses vaisseaux, fond étoilé). Sa place
## dans l'espace est alors gardée à part (space_position, space_rotation).
## L'ancrage est local : le réseau et les règles ne connaissent que l'espace.
## Pourquoi : à grande vitesse, un vaisseau qui bouge dans la scène déplace
## ses murs, ses lumières et ses ombres de centaines de pixels par pas
## physique. Ni le moteur physique (personnage qui bute sur des murs restés
## en arrière) ni l'interpolation de l'image (ombres décalées, cible de la
## souris fausse) ne suivent. Ancré, l'intérieur ne bouge plus, quelle que
## soit la vitesse, et reste près de l'origine (précision des nombres).
@export var anchored: bool = false

## Vitesse du centre de masse du vaisseau dans l'espace (px/s). Réglée ici au
## départ, puis changée seulement par la poussée des réacteurs (inertie : sans
## poussée, le vaisseau la garde).
@export var velocity := Vector2.ZERO

## Vitesse de rotation du vaisseau autour de son centre de masse, en degrés
## par seconde (positif : sens horaire à l'écran). Même fonctionnement que
## [member velocity].
@export var angular_speed: float = 0.0

## Place du vaisseau dans l'espace (repère de Fleet, px) : celle de son nœud,
## ou, s'il est ancré, une valeur à part (son nœud ne bouge pas).
var space_position: Vector2:
	get:
		return _space_position if anchored else position
	set(value):
		if anchored:
			_space_position = value
		else:
			position = value

## Orientation du vaisseau dans l'espace (radians), comme space_position.
## Jamais repliée dans [-π, π] : un saut de 2π serait interpolé.
var space_rotation: float:
	get:
		return _space_rotation if anchored else rotation
	set(value):
		if anchored:
			_space_rotation = value
		else:
			rotation = value

## Commandes du pilote, décidées par l'hôte (voir request_controls) et
## connues de tous : direction de poussée voulue, dans le repère de l'espace
## (longueur 0 à 1)...
var thrust_command := Vector2.ZERO
## ... et rotation voulue (-1 à 1, positif : sens horaire) : part de leur
## poussée que donnent les réacteurs qui font tourner dans ce sens.
var turn_command: float = 0.0

var _arranging: bool = false
var _rules_timer: float = 0.0
var _motion_timer: float = 0.0
var _position_error := Vector2.ZERO
var _rotation_error: float = 0.0  # radians
# Joueur qui a envoyé les dernières commandes (hôte) : s'il part, elles sont
# annulées (voir release_controls_of).
var _pilot_id: int = 0
# Silhouette de la vue « coque » (voir hull_view), et vue actuellement appliquée.
var _hull: Node2D
var _hull_flames: Node2D
var _showing_hull: bool = false
# Physique de l'équipage (voir get_crew_space) : espace, corps des murs et
# leurs formes.
var _crew_space := RID()
var _walls_body := RID()
var _wall_shapes: Array[RID] = []
# Vaisseau ancré : place dans l'espace, et celle du pas physique précédent
# (interpolation de l'image, voir get_interpolated_space_transform).
var _space_position := Vector2.ZERO
var _space_rotation: float = 0.0
var _previous_space_position := Vector2.ZERO
var _previous_space_rotation: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	if not Engine.is_editor_hint():
		_create_hull()
		# Équipage : enfants de Crew (créé ici pour les vaisseaux construits
		# par Fleet), dessinés au-dessus des salles.
		if get_node_or_null("Crew") == null:
			var crew := Node2D.new()
			crew.name = "Crew"
			add_child(crew)
		if anchored:
			make_anchor()
	child_order_changed.connect(arrange_modules)
	arrange_modules()


func _exit_tree() -> void:
	if anchor == self:
		anchor = null
	_free_crew_space()


## Ancre ce vaisseau à la place du précédent (le joueur local monte à bord,
## voir Player). Sans saut visible : chaque vaisseau garde sa place dans
## l'espace, seule change celle qui est fixe à l'écran.
func make_anchor() -> void:
	if anchor == self:
		return
	if anchor:
		anchor._release_anchor()
	_anchor()


## Ancre le vaisseau : la place de son nœud dans l'espace (repère de son
## parent Fleet) devient sa place gardée à part, et le nœud, indépendant de
## son parent (top_level), revient à l'origine de la scène, où il restera.
func _anchor() -> void:
	_space_position = position
	_space_rotation = rotation
	_previous_space_position = _space_position
	_previous_space_rotation = _space_rotation
	anchored = true
	top_level = true
	position = Vector2.ZERO
	rotation = 0.0
	reset_physics_interpolation()
	anchor = self


## Le vaisseau n'est plus ancré : son nœud reprend sa place dans l'espace.
func _release_anchor() -> void:
	var at := _space_position
	var angle := _space_rotation
	anchored = false
	top_level = false
	position = at
	rotation = angle
	reset_physics_interpolation()
	if anchor == self:
		anchor = null


## Place et orientation dans l'espace (repère de Fleet).
func get_space_transform() -> Transform2D:
	return Transform2D(space_rotation, space_position)


## Place dans l'espace à l'image affichée : pour un vaisseau ancré, interpolée
## entre les deux derniers pas physiques, comme le reste de l'image (Fleet et
## le fond étoilé s'en servent pour placer l'espace autour de lui).
func get_interpolated_space_transform() -> Transform2D:
	if not anchored or not is_physics_interpolated_and_enabled():
		return get_space_transform()
	var weight := Engine.get_physics_interpolation_fraction()
	return Transform2D(lerpf(_previous_space_rotation, _space_rotation, weight),
			_previous_space_position.lerp(_space_position, weight))


## Saut de position (correction d'un coup) : affiché tel quel, sans
## interpolation depuis l'ancienne place.
func _reset_space_interpolation() -> void:
	if anchored:
		_previous_space_position = _space_position
		_previous_space_rotation = _space_rotation
	else:
		reset_physics_interpolation()


func _process(_delta: float) -> void:
	if _hull == null:
		return
	if hull_view != _showing_hull:
		_show_hull(hull_view)
	if _showing_hull:
		_hull_flames.queue_redraw()  # flammes vacillantes


# --- Vue « coque » ------------------------------------------------------------

## Nœud de la silhouette, placé sous l'équipage, et nœud enfant des flammes
## (sans la texture de métal). Tous deux non éclairés : le brouillard de
## guerre (CanvasModulate) ne les assombrit pas.
func _create_hull() -> void:
	_hull = Node2D.new()
	_hull.name = "Hull"
	_hull.visible = false
	var metal := ShaderMaterial.new()
	metal.shader = HULL_SHADER
	_hull.material = metal
	_hull.draw.connect(_draw_hull)
	add_child(_hull)
	move_child(_hull, 0)

	_hull_flames = Node2D.new()
	_hull_flames.name = "Flames"
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_hull_flames.material = unshaded
	_hull_flames.draw.connect(_draw_hull_flames)
	_hull.add_child(_hull_flames)


## Montre la silhouette et masque salles, murs et portes, ou l'inverse.
func _show_hull(shown: bool) -> void:
	_showing_hull = shown
	_hull.visible = shown
	for m in get_modules():
		m.visible = not shown
	_get_structure().visible = not shown


## Salles (murs compris) et tuyères, en blanc : la couleur vient du shader.
func _draw_hull() -> void:
	for m in get_modules():
		_hull.draw_rect(Rect2(m.position, m.get_pixel_size()).grow(Module.WALL_THICKNESS / 2.0), Color.WHITE)
		if m is ModuleReacteur:
			var nozzle: PackedVector2Array = m.get_nozzle_polygon()
			for i in nozzle.size():
				nozzle[i] += m.position
			_hull.draw_colored_polygon(nozzle, Color.WHITE)


func _draw_hull_flames() -> void:
	for m in get_modules():
		if m is ModuleReacteur:
			m.draw_flame_on(_hull_flames, m.position)


## Chaque machine applique les mêmes forces aux mêmes commandes (et à
## l'alimentation des réacteurs qu'elle connaît) ; l'hôte corrige les écarts.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_previous_space_position = _space_position
	_previous_space_rotation = _space_rotation
	_apply_forces(delta)
	if is_multiplayer_authority():
		# Pilotage privé d'alimentation : plus aucune commande.
		if (thrust_command != Vector2.ZERO or turn_command != 0.0) and not is_helm_powered():
			set_controls(Vector2.ZERO, 0.0)
		_update_module_rules(delta)
		_motion_timer += delta
		if _motion_timer >= MOTION_SYNC_INTERVAL:
			_motion_timer = 0.0
			_receive_position.rpc(space_position, space_rotation, velocity, angular_speed)
	else:
		_apply_correction(delta)


# --- Physique de l'équipage ---------------------------------------------------

## Espace physique propre au vaisseau, où se déplace son équipage : murs
## (_add_crew_wall), battants des portes (Door) et personnages (Player), tous
## en coordonnées du vaisseau, donc immobiles quels que soient sa place dans
## la scène, sa vitesse et sa rotation. Le monde de Godot ne contient aucun
## mur : un vaisseau rapide y déplacerait ses murs de centaines de pixels par
## pas, et le moteur physique ne suivrait pas (murs restés en arrière, zones
## en retard d'un pas). Créé à la première demande (pas dans l'éditeur).
## Espace jamais simulé (inactif) : il ne sert qu'aux tests de déplacement
## (PhysicsServer2D.body_test_motion), et tous ses corps sont statiques,
## placés directement.
func get_crew_space() -> RID:
	if not _crew_space.is_valid():
		_crew_space = PhysicsServer2D.space_create()
		_walls_body = PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(_walls_body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_set_space(_walls_body, _crew_space)
	return _crew_space


## Ajoute aux murs de l'équipage un rectangle de taille [param size] (px)
## centré sur [param center] (repère du vaisseau).
func _add_crew_wall(size: Vector2, center: Vector2) -> void:
	if Engine.is_editor_hint():
		return
	get_crew_space()
	var shape := PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(shape, size / 2.0)
	PhysicsServer2D.body_add_shape(_walls_body, shape, Transform2D(0.0, center))
	_wall_shapes.append(shape)


func _clear_crew_walls() -> void:
	if not _walls_body.is_valid():
		return
	PhysicsServer2D.body_clear_shapes(_walls_body)
	for shape in _wall_shapes:
		PhysicsServer2D.free_rid(shape)
	_wall_shapes.clear()


## Espace libéré à la sortie de l'arbre, qui vient après celle des enfants
## (portes, personnages : leurs corps l'ont déjà quitté). Pas à la
## destruction : elle précède la sortie de l'arbre des enfants.
func _free_crew_space() -> void:
	if not _crew_space.is_valid():
		return
	_clear_crew_walls()
	PhysicsServer2D.free_rid(_walls_body)
	PhysicsServer2D.free_rid(_crew_space)
	_walls_body = RID()
	_crew_space = RID()


# --- Masse et forces ----------------------------------------------------------

## Masse totale du vaisseau (kg) : somme des masses de ses modules.
func get_total_mass() -> float:
	var mass := 0.0
	for m in get_modules():
		mass += m.get_mass()
	return mass


## Centre de masse (m), dans le repère du vaisseau (origine : centre de la grille).
func get_center_of_mass() -> Vector2:
	var mass := 0.0
	var moment := Vector2.ZERO
	for m in get_modules():
		mass += m.get_mass()
		moment += _module_offset(m) * m.get_mass()
	return Vector2.ZERO if mass <= 0.0 else moment / mass


## Moment d'inertie (kg·m²) autour du centre de masse : chaque module est une
## plaque rectangulaire de masse uniforme.
func get_moment_of_inertia() -> float:
	var center := get_center_of_mass()
	var inertia := 0.0
	for m in get_modules():
		var size := Vector2(m.get_size()) * Module.CELL_SIZE / PIXELS_PER_METER
		inertia += m.get_mass() * ((_module_offset(m) - center).length_squared() + size.length_squared() / 12.0)
	return inertia


## Bras de levier d'un réacteur (m) : couple (N·m) par newton de poussée autour
## du centre de masse [param center] (positif : sens horaire, nul si sa poussée
## passe par le centre de masse).
func get_torque_arm(reactor: ModuleReacteur, center: Vector2) -> float:
	var r := _module_offset(reactor) - center
	var d := reactor.get_thrust_direction()
	return r.x * d.y - r.y * d.x


## Accélération angulaire maximale (°/s², positive) dans le sens [param direction]
## (signe : positif = horaire) : couple de tous les réacteurs opérationnels qui
## font tourner dans ce sens, divisé par le moment d'inertie.
func get_max_angular_acceleration(direction: float) -> float:
	var center := get_center_of_mass()
	var torque := 0.0
	for m in get_modules():
		if m is ModuleReacteur:
			var arm := get_torque_arm(m, center)
			if absf(arm) > TORQUE_ARM_MIN and signf(arm) == signf(direction):
				torque += m.get_thrust() * absf(arm)
	var inertia := get_moment_of_inertia()
	return 0.0 if inertia <= 0.0 else rad_to_deg(torque / inertia)


## Répartition des commandes entre les réacteurs [param reactors] : part de
## sa poussée que fournit chacun (0 à 1). Visée : toute la poussée possible
## dans la direction voulue [param wanted] (repère du vaisseau), aucune force
## sur le côté, et le couple turn_command × couple maximal dans ce sens. Ce
## n'est pas toujours atteignable (un réacteur hors de l'axe fait aussi
## tourner) : on prend la répartition la plus proche, aux moindres carrés
## (descente par coordonnées, bornée à [0, 1], ALLOCATION_SWEEPS passes).
## Le calcul est le même sur toutes les machines.
func _allocate_throttles(reactors: Array[ModuleReacteur], wanted: Vector2, center: Vector2) -> PackedFloat64Array:
	var throttles := PackedFloat64Array()
	throttles.resize(reactors.size())
	# Effet de chaque réacteur à pleine poussée : force (N) et couple pondéré.
	var effects: Array[Vector3] = []
	var max_forward := 0.0
	var max_torque := 0.0
	for r in reactors:
		var thrust := r.get_thrust()
		var direction := r.get_thrust_direction()
		var arm := get_torque_arm(r, center)
		effects.append(Vector3(direction.x, direction.y, arm * TORQUE_WEIGHT) * thrust)
		max_forward += maxf(direction.dot(wanted), 0.0) * thrust
		if absf(arm) > TORQUE_ARM_MIN and signf(arm) == signf(turn_command):
			max_torque += absf(arm) * thrust
	var target := Vector3(wanted.x * max_forward, wanted.y * max_forward,
			signf(turn_command) * absf(turn_command) * max_torque * TORQUE_WEIGHT)
	# Écart entre l'effet obtenu et la visée, mis à jour à chaque changement.
	var residual := -target
	for sweep in ALLOCATION_SWEEPS:
		for i in reactors.size():
			var effect := effects[i]
			var norm := effect.length_squared()
			if norm <= 0.0:
				continue
			var value := clampf(throttles[i] - effect.dot(residual) / norm, 0.0, 1.0)
			residual += effect * (value - throttles[i])
			throttles[i] = value
	return throttles


## Physique stricte : chaque réacteur pousse là où il est. La somme des forces
## accélère le centre de masse, la somme de leurs couples fait tourner le
## vaisseau autour de lui (un réacteur hors de l'axe fait donc aussi tourner).
## Règle aussi la flamme de chaque réacteur (sa part de poussée).
func _apply_forces(delta: float) -> void:
	var center := get_center_of_mass()
	var wanted := thrust_command.rotated(-space_rotation)  # repère du vaisseau
	var reactors: Array[ModuleReacteur] = []
	for m in get_modules():
		if m is ModuleReacteur:
			reactors.append(m)
	var throttles := _allocate_throttles(reactors, wanted, center)
	var force := Vector2.ZERO  # N, repère du vaisseau
	var torque := 0.0  # N·m
	for i in reactors.size():
		var reactor := reactors[i]
		reactor.flame_level = throttles[i]
		var thrust := reactor.get_thrust() * throttles[i]
		force += reactor.get_thrust_direction() * thrust
		torque += get_torque_arm(reactor, center) * thrust
	var mass := get_total_mass()
	var inertia := get_moment_of_inertia()
	if mass > 0.0:
		velocity += (force / mass * PIXELS_PER_METER).rotated(space_rotation) * delta
	velocity = velocity.limit_length(MAX_SPEED)
	if inertia > 0.0:
		angular_speed += rad_to_deg(torque / inertia) * delta
	# Rien à faire à l'arrêt : réaffecter la place d'un nœud, même inchangée,
	# fait recalculer celle de tous ses descendants (coûteux).
	if velocity != Vector2.ZERO or angular_speed != 0.0:
		space_position = _drift(space_position, space_rotation, velocity, angular_speed, delta).origin
		space_rotation = _drift_rotation(space_rotation, angular_speed, delta)


## Place après [param duration] s sans poussée, depuis [param from_position]
## et [param from_rotation] (radians) : le centre de masse avance à la vitesse
## [param speed] (px/s), et l'origine du vaisseau tourne autour de lui à
## [param spin] (°/s).
func _drift(from_position: Vector2, from_rotation: float, speed: Vector2, spin: float,
		duration: float) -> Transform2D:
	var center_offset := get_center_of_mass() * PIXELS_PER_METER
	var center_position := from_position + center_offset.rotated(from_rotation) + speed * duration
	var new_rotation := _drift_rotation(from_rotation, spin, duration)
	return Transform2D(new_rotation, center_position - center_offset.rotated(new_rotation))


## Orientation après [param duration] s à [param spin] °/s, non repliée
## (Transform2D.get_rotation la replierait : saut de 2π interpolé).
func _drift_rotation(from_rotation: float, spin: float, duration: float) -> float:
	return from_rotation + deg_to_rad(spin) * duration


## Centre d'un module par rapport au centre du vaisseau (m).
func _module_offset(m: Module) -> Vector2:
	return (m.position + m.get_pixel_size() / 2.0) / PIXELS_PER_METER


# --- Commandes et synchronisation du mouvement -------------------------------

## Envoie le mouvement du vaisseau à un joueur qui vient d'arriver (hôte).
func send_motion_to(peer_id: int) -> void:
	_receive_motion.rpc_id(peer_id, space_position, space_rotation, velocity, angular_speed, thrust_command, turn_command)


## Envoie à tous l'état du mouvement et les commandes (hôte), de manière
## fiable : après un changement de commandes ou un choc (ShipCollisions).
func send_motion() -> void:
	if is_inside_tree() and is_multiplayer_authority():
		_receive_motion.rpc(space_position, space_rotation, velocity, angular_speed, thrust_command, turn_command)


## Change les commandes de poussée et de rotation et les envoie aux autres,
## avec l'état du mouvement (hôte).
func set_controls(thrust: Vector2, turn: float) -> void:
	if thrust == thrust_command and turn == turn_command:
		return
	thrust_command = thrust
	turn_command = turn
	send_motion()


## Demande à l'hôte de changer les commandes (joueur aux commandes, voir
## Piloting) ; l'hôte les borne et ignore la demande si le pilotage n'est pas
## alimenté (is_helm_powered).
func request_controls(thrust: Vector2, turn: float) -> void:
	_request_controls.rpc_id(1, thrust, turn)


## Vrai si un module de pilotage a au moins son alimentation minimale : sans
## cela, les commandes de pilotage sont sans effet (le vaisseau garde son
## mouvement, par inertie).
func is_helm_powered() -> bool:
	for m in get_modules():
		if m is ModulePilotage and m.power_supplied >= m.get_min_power():
			return true
	return false


## Un joueur quitte la partie (hôte) : s'il pilotait, plus de poussée ni de
## rotation commandée (le vaisseau garde son mouvement, par inertie).
func release_controls_of(peer_id: int) -> void:
	if peer_id == _pilot_id:
		_pilot_id = 0
		set_controls(Vector2.ZERO, 0.0)


@rpc("any_peer", "call_local", "reliable")
func _request_controls(thrust: Vector2, turn: float) -> void:
	if not multiplayer.is_server() or not is_helm_powered():
		return
	_pilot_id = multiplayer.get_remote_sender_id()
	set_controls(thrust.limit_length(1.0), clampf(turn, -1.0, 1.0))


## Changement de commandes (ou arrivée dans la partie) : envoi fiable.
@rpc("authority", "call_remote", "reliable")
func _receive_motion(new_position: Vector2, new_rotation: float, new_velocity: Vector2,
		new_angular_speed: float, thrust: Vector2, turn: float) -> void:
	thrust_command = thrust
	turn_command = turn
	velocity = new_velocity
	angular_speed = new_angular_speed
	_correct_to(new_position, new_rotation)


## Correction périodique : une correction perdue est remplacée par la suivante.
## Les vitesses sont reprises telles quelles, position et orientation en douceur.
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_position(new_position: Vector2, new_rotation: float, new_velocity: Vector2,
		new_angular_speed: float) -> void:
	velocity = new_velocity
	angular_speed = new_angular_speed
	_correct_to(new_position, new_rotation)


## Écart à la place envoyée par l'hôte, résorbé en douceur ou d'un coup.
## Le message a mis du temps à arriver : la place reçue est avancée de ce
## temps (voir _message_age), sinon, à grande vitesse, le vaisseau serait
## ramené en arrière à chaque correction. Le seuil du saut grandit avec la
## vitesse (CORRECTION_SNAP_TIME) : l'estimation de ce temps reste imprécise.
func _correct_to(new_position: Vector2, new_rotation: float) -> void:
	var age := _message_age()
	new_position = _drift(new_position, new_rotation, velocity, angular_speed, age).origin
	new_rotation = _drift_rotation(new_rotation, angular_speed, age)
	var snapped := false
	_position_error = new_position - space_position
	if _position_error.length() > CORRECTION_SNAP_DISTANCE + velocity.length() * CORRECTION_SNAP_TIME:
		space_position = new_position
		_position_error = Vector2.ZERO
		snapped = true
	_rotation_error = angle_difference(space_rotation, new_rotation)
	if absf(_rotation_error) > deg_to_rad(CORRECTION_SNAP_ANGLE + absf(angular_speed) * CORRECTION_SNAP_TIME):
		space_rotation = new_rotation
		_rotation_error = 0.0
		snapped = true
	if snapped:
		_reset_space_interpolation()


## Temps (s) mis par un message de l'hôte pour arriver : moitié du temps
## d'aller-retour mesuré par ENet (0 sans connexion ENet).
func _message_age() -> float:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or multiplayer.is_server():
		return 0.0
	var host := peer.get_peer(1)
	if host == null:
		return 0.0
	return host.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 2000.0


func _apply_correction(delta: float) -> void:
	if _position_error != Vector2.ZERO:
		var step := _position_error * minf(1.0, CORRECTION_RATE * delta)
		if step.length() < 0.01:
			step = _position_error
		space_position += step
		_position_error -= step
	if _rotation_error != 0.0:
		var turn := _rotation_error * minf(1.0, CORRECTION_RATE * delta)
		if absf(turn) < 0.00001:
			turn = _rotation_error
		space_rotation += turn
		_rotation_error -= turn


## Alimentation puis température des modules : mise à jour à intervalle fixe
## (hôte uniquement), résultat envoyé aux autres en un seul message.
func _update_module_rules(delta: float) -> void:
	var step := 1.0 / PowerRules.UPDATE_RATE
	_rules_timer += delta
	if _rules_timer < step:
		return
	var modules := get_modules()
	while _rules_timer >= step:
		_rules_timer -= step
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
	_receive_power_and_temperatures.rpc(power, room_temperatures, machine_temperatures)


@rpc("authority", "call_remote", "unreliable_ordered")
func _receive_power_and_temperatures(power: PackedFloat32Array, room_temperatures: PackedFloat32Array,
		machine_temperatures: PackedFloat32Array) -> void:
	var modules := get_modules()
	for i in mini(power.size(), modules.size()):
		modules[i].power_supplied = power[i]
	for i in mini(room_temperatures.size(), modules.size()):
		modules[i].room_temperature = room_temperatures[i]
	for i in mini(machine_temperatures.size(), modules.size()):
		modules[i].machine_temperature = machine_temperatures[i]


## TEST : tire au hasard l'état de chaque module (hôte, à la création de la
## partie). Les joueurs qui arrivent le reçoivent par send_module_states.
func randomize_module_states() -> void:
	for m in get_modules():
		m.state = randf()
	send_module_states()


## Envoie l'état (Module.state) de tous les modules (hôte) : à un seul joueur
## si [param peer_id] est donné (joueur qui arrive), sinon à tous.
## À rappeler après chaque changement d'état décidé par l'hôte.
func send_module_states(peer_id: int = 0) -> void:
	var states := PackedFloat32Array()
	for m in get_modules():
		states.append(m.state)
	if peer_id == 0:
		_receive_module_states.rpc(states)
	else:
		_receive_module_states.rpc_id(peer_id, states)


## État des modules : rare, donc envoyé de manière fiable à chaque changement
## plutôt qu'avec l'alimentation (10 fois par seconde).
@rpc("authority", "call_remote", "reliable")
func _receive_module_states(states: PackedFloat32Array) -> void:
	var modules := get_modules()
	for i in mini(states.size(), modules.size()):
		modules[i].state = states[i]


## Envoie l'état des commandes de tous les modules (marche / arrêt,
## alimentation cible) à un joueur qui vient d'arriver (hôte). Les
## changements ultérieurs sont envoyés par chaque module.
func send_module_controls(peer_id: int) -> void:
	for m in get_modules():
		m.send_controls_to(peer_id)


func get_modules() -> Array[Module]:
	var result: Array[Module] = []
	for child in get_children():
		if child is Module:
			result.append(child)
	return result


## Position d'apparition du n-ième joueur : au centre du premier module de
## pilotage (à défaut, du premier module), en décalant chaque joueur
## verticalement de SPAWN_SPACING.
func get_spawn_position(index: int) -> Vector2:
	var modules := get_modules()
	if modules.is_empty():
		return Vector2.ZERO
	var room: Module = modules[0]
	for m in modules:
		if m is ModulePilotage:
			room = m
			break
	return room.position + room.get_pixel_size() / 2.0 + Vector2(0, (index % 5 - 2) * SPAWN_SPACING)


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
		if _showing_hull:
			m.visible = false
		m.doorways = []
		m.neighbors = []

	var doors := []
	for i in modules.size():
		for j in range(i + 1, modules.size()):
			var door := _connect(modules[i], modules[j])
			if not door.is_empty():
				doors.append(door)

	_build_structure(modules, doors)
	if _hull:
		_hull.queue_redraw()
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

	_clear_crew_walls()
	for line in _merge_wall_lines(modules):
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		var size := Vector2(
				maxf(absf(b.x - a.x), Module.WALL_THICKNESS),
				maxf(absf(b.y - a.y), Module.WALL_THICKNESS))
		_add_crew_wall(size, (a + b) / 2.0)

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
