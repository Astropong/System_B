class_name PowerRules
extends RefCounted
## Règles d'alimentation électrique des modules du vaisseau.
##
## Elles sont appliquées uniquement par l'hôte, UPDATE_RATE fois par seconde
## (voir Ship), puis les valeurs sont envoyées aux autres joueurs.
##
## Règles actuelles :
## 1. Le générateur est toujours alimenté de manière optimale.
## 2. Tout autre module se recharge de CHARGE_SPEED W/s, jusqu'à
##    MAX_CHARGE_RATIO × son alimentation optimale, dès qu'un module adjacent
##    (relié par une porte, voir Module.neighbors) a atteint sa propre
##    alimentation minimale de fonctionnement (Module.get_min_power()).

## Nombre de mises à jour de l'alimentation par seconde.
const UPDATE_RATE := 10.0
## Vitesse de recharge d'un module (W par seconde).
const CHARGE_SPEED := 20.0
## Plafond de recharge, en proportion de l'alimentation optimale (120 %).
const MAX_CHARGE_RATIO := 1.2


## Applique les règles pour un pas de temps [param delta] (en secondes).
## [param modules] est la liste des modules du vaisseau.
static func update(modules: Array[Module], delta: float) -> void:
	# Règle 1 : le générateur est toujours à l'optimum.
	for m in modules:
		if m.get_type_id() == Module.ModuleType.GENERATEUR:
			m.power_supplied = m.get_ideal_power()

	# On note d'abord quels modules alimentent leurs voisins (ceux qui ont atteint
	# leur alimentation minimale), pour que l'ordre de traitement n'influence pas
	# le résultat.
	var supplying := {}
	for m in modules:
		supplying[m] = m.power_supplied >= m.get_min_power()

	# Règle 2 : recharge progressive à partir d'un voisin suffisamment alimenté.
	for m in modules:
		if m.get_type_id() == Module.ModuleType.GENERATEUR:
			continue
		var has_powered_neighbor := false
		for n in m.neighbors:
			if supplying.get(n, false):
				has_powered_neighbor = true
		var cap := m.get_ideal_power() * MAX_CHARGE_RATIO
		if has_powered_neighbor and m.power_supplied < cap:
			m.power_supplied = minf(m.power_supplied + CHARGE_SPEED * delta, cap)
