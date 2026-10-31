class_name ShipCollisions
extends Node
## Collisions entre vaisseaux (groupe Ship.GROUP), résolues par l'hôte après
## le déplacement de tous les vaisseaux à chaque pas physique.
##
## Calcul dans le repère de l'espace (Ship.get_space_transform, pas la place
## des nœuds dans la scène : le vaisseau ancré n'y bouge pas).
## Chaque module est un rectangle (orienté avec son vaisseau). Quand deux
## vaisseaux se chevauchent, on retient la paire de modules la plus enfoncée
## (test des axes séparateurs) : point de contact, normale, profondeur. Si les
## vaisseaux se rapprochent en ce point, une impulsion (corps rigides : masse
## et moment d'inertie de chaque vaisseau, voir Ship) change leurs vitesses
## et leurs rotations ; les deux modules touchés perdent de l'état selon la
## vitesse de l'impact. Les vaisseaux sont aussi écartés pour ne plus se
## chevaucher. L'hôte envoie ensuite à tous les nouveaux mouvements et états.

## Coefficient de restitution (0 : choc mou, 1 : rebond parfait).
const RESTITUTION := 0.3
## Perte d'état d'un module touché par mètre par seconde de vitesse d'impact
## (vitesse de rapprochement le long de la normale) : à 20 m/s, il est détruit.
const DAMAGE_PER_SPEED := 0.05
## En dessous de cette vitesse d'impact (m/s), le choc n'abîme rien.
const MIN_DAMAGE_SPEED := 0.5
## Chevauchement toléré (px), sans correction de position (évite de trembler
## au contact).
const PENETRATION_SLOP := 1.0


func _ready() -> void:
	# Après le déplacement des vaisseaux (priorité 0) dans le même pas.
	process_physics_priority = 10


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	var ships: Array[Ship] = []
	for node in get_tree().get_nodes_in_group(Ship.GROUP):
		if node is Ship and not node.is_queued_for_deletion() and not node.get_modules().is_empty():
			ships.append(node)
	var hulls: Array = []
	for ship in ships:
		hulls.append(_get_hull(ship))
	for i in ships.size():
		for j in range(i + 1, ships.size()):
			var a: Dictionary = hulls[i]
			var b: Dictionary = hulls[j]
			if a["center"].distance_to(b["center"]) > a["radius"] + b["radius"]:
				continue
			var contact := _find_contact(a, b)
			if not contact.is_empty():
				_resolve(ships[i], ships[j], contact)
				# Positions changées : rectangles à recalculer.
				hulls[i] = _get_hull(ships[i])
				hulls[j] = _get_hull(ships[j])


## Rectangles des modules d'un vaisseau dans le monde (4 coins chacun) et
## cercle qui les contient tous (tri rapide des paires de vaisseaux).
func _get_hull(ship: Ship) -> Dictionary:
	var xform := ship.get_space_transform()
	var rects: Array[PackedVector2Array] = []
	var modules := ship.get_modules()
	var center := xform.origin
	var radius := 0.0
	for m in modules:
		var size := m.get_pixel_size()
		var corners := PackedVector2Array([
			xform * m.position,
			xform * (m.position + Vector2(size.x, 0)),
			xform * (m.position + size),
			xform * (m.position + Vector2(0, size.y)),
		])
		for c in corners:
			radius = maxf(radius, c.distance_to(center))
		rects.append(corners)
	return {"modules": modules, "rects": rects, "center": center, "radius": radius}


## Paire de modules la plus enfoncée entre deux vaisseaux : dictionnaire
## "normal" (unitaire, de a vers b), "depth" (px), "point" (monde), "module_a",
## "module_b" ; vide s'ils ne se touchent pas.
func _find_contact(a: Dictionary, b: Dictionary) -> Dictionary:
	var best := {}
	for i in a["rects"].size():
		var ra: PackedVector2Array = a["rects"][i]
		for j in b["rects"].size():
			var rb: PackedVector2Array = b["rects"][j]
			var overlap := _overlap(ra, rb)
			if overlap.is_empty() or (not best.is_empty() and overlap["depth"] <= best["depth"]):
				continue
			best = overlap
			best["point"] = _contact_point(ra, rb)
			best["module_a"] = a["modules"][i]
			best["module_b"] = b["modules"][j]
	return best


## Test des axes séparateurs entre deux rectangles (4 coins dans l'ordre) :
## axe de plus petit chevauchement, orienté de [param ra] vers [param rb],
## et profondeur ; vide s'ils sont séparés.
func _overlap(ra: PackedVector2Array, rb: PackedVector2Array) -> Dictionary:
	var depth := INF
	var normal := Vector2.ZERO
	for corners in [ra, rb]:
		for k in 2:
			var axis: Vector2 = (corners[k + 1] - corners[k]).normalized()
			var a_range := _project(ra, axis)
			var b_range := _project(rb, axis)
			var overlap := minf(a_range.y, b_range.y) - maxf(a_range.x, b_range.x)
			if overlap <= 0.0:
				return {}
			if overlap < depth:
				depth = overlap
				normal = axis
	if normal.dot(_center(rb) - _center(ra)) < 0.0:
		normal = -normal
	return {"normal": normal, "depth": depth}


func _project(corners: PackedVector2Array, axis: Vector2) -> Vector2:
	var low := INF
	var high := -INF
	for c in corners:
		var d := c.dot(axis)
		low = minf(low, d)
		high = maxf(high, d)
	return Vector2(low, high)


func _center(corners: PackedVector2Array) -> Vector2:
	return (corners[0] + corners[2]) / 2.0


## Point de contact : moyenne des coins de chaque rectangle situés dans
## l'autre (à défaut, milieu entre les deux centres).
func _contact_point(ra: PackedVector2Array, rb: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for pair in [[ra, rb], [rb, ra]]:
		for c in pair[0]:
			if Geometry2D.is_point_in_polygon(c, pair[1]):
				sum += c
				count += 1
	return sum / count if count > 0 else (_center(ra) + _center(rb)) / 2.0


## Impulsion au point de contact (si les vaisseaux se rapprochent), dégâts
## aux deux modules touchés, puis écartement des vaisseaux.
func _resolve(a: Ship, b: Ship, contact: Dictionary) -> void:
	var ppm := Ship.PIXELS_PER_METER
	var n: Vector2 = contact["normal"]
	var point: Vector2 = contact["point"]
	var mass_a := a.get_total_mass()
	var mass_b := b.get_total_mass()
	var inertia_a := a.get_moment_of_inertia()
	var inertia_b := b.get_moment_of_inertia()
	# Bras de levier (m) depuis chaque centre de masse.
	var r_a := (point - a.get_space_transform() * (a.get_center_of_mass() * ppm)) / ppm
	var r_b := (point - b.get_space_transform() * (b.get_center_of_mass() * ppm)) / ppm
	var w_a := deg_to_rad(a.angular_speed)
	var w_b := deg_to_rad(b.angular_speed)
	# Vitesse de chaque vaisseau au point de contact (m/s).
	var v_a := a.velocity / ppm + w_a * Vector2(-r_a.y, r_a.x)
	var v_b := b.velocity / ppm + w_b * Vector2(-r_b.y, r_b.x)
	var closing_speed := -(v_b - v_a).dot(n)

	if closing_speed > 0.0:
		var arm_a := r_a.cross(n)
		var arm_b := r_b.cross(n)
		var resistance := 1.0 / mass_a + 1.0 / mass_b \
				+ arm_a * arm_a / inertia_a + arm_b * arm_b / inertia_b
		var impulse := (1.0 + RESTITUTION) * closing_speed / resistance  # N·s
		a.velocity -= n * impulse / mass_a * ppm
		b.velocity += n * impulse / mass_b * ppm
		a.angular_speed -= rad_to_deg(arm_a * impulse / inertia_a)
		b.angular_speed += rad_to_deg(arm_b * impulse / inertia_b)
		if closing_speed >= MIN_DAMAGE_SPEED:
			var damage := closing_speed * DAMAGE_PER_SPEED
			contact["module_a"].state -= damage
			contact["module_b"].state -= damage
			a.send_module_states()
			b.send_module_states()

	# Écartement selon la masse : le plus léger bouge le plus.
	var push: float = contact["depth"] - PENETRATION_SLOP
	if push > 0.0:
		var share_a := mass_b / (mass_a + mass_b)
		a.space_position -= n * push * share_a
		b.space_position += n * push * (1.0 - share_a)

	if closing_speed > 0.0:
		a.send_motion()
		b.send_motion()
