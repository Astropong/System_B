class_name PowerRules
extends RefCounted
## Règles d'alimentation électrique des modules du vaisseau.
##
## Elles sont appliquées uniquement par l'hôte, UPDATE_RATE fois par seconde
## (voir Ship), puis les valeurs sont envoyées aux autres joueurs.
##
## Règles actuelles :
## 0. Un module éteint (Module.is_on faux) ne consomme rien.
## 1. Le générateur allumé est toujours alimenté de manière optimale.
## 2. Tout autre module se recharge de CHARGE_SPEED W/s, jusqu'à son plafond
##    (Module.get_power_cap() : la cible réglée au curseur, sinon l'optimum),
##    dès qu'un module adjacent (relié par une porte, voir Module.neighbors) a
##    atteint sa propre alimentation minimale de fonctionnement
##    (Module.get_min_power()). Au-dessus du plafond (cible baissée), il y
##    redescend aussitôt.

## Nombre de mises à jour de l'alimentation par seconde.
const UPDATE_RATE := 10.0
## Vitesse de recharge d'un module (W par seconde).
const CHARGE_SPEED := 20.0


## Applique les règles pour un pas de temps [param delta] (en secondes).
## [param modules] est la liste des modules du vaisseau.
static func update(modules: Array[Module], delta: float) -> void:
	# Règles 0 et 1 : module éteint à 0, générateur allumé à l'optimum.
	for m in modules:
		if not m.is_on:
			m.power_supplied = 0.0
		elif m.get_type_id() == Module.ModuleType.GENERATEUR:
			m.power_supplied = m.get_ideal_power()

	# On note d'abord quels modules alimentent leurs voisins (ceux qui ont atteint
	# leur alimentation minimale), pour que l'ordre de traitement n'influence pas
	# le résultat.
	var supplying := {}
	for m in modules:
		supplying[m] = m.power_supplied >= m.get_min_power()

	# Règle 2 : recharge progressive à partir d'un voisin suffisamment alimenté.
	for m in modules:
		if not m.is_on or m.get_type_id() == Module.ModuleType.GENERATEUR:
			continue
		var has_powered_neighbor := false
		for n in m.neighbors:
			if supplying.get(n, false):
				has_powered_neighbor = true
		var cap := m.get_power_cap()
		if m.power_supplied > cap:
			m.power_supplied = cap
		elif has_powered_neighbor and m.power_supplied < cap:
			m.power_supplied = minf(m.power_supplied + CHARGE_SPEED * delta, cap)
