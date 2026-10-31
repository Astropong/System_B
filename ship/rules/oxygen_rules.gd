class_name OxygenRules
extends RefCounted
## Règles d'oxygène des modules du vaisseau (Module.oxygen, de 0 à 1).
##
## Comme l'alimentation, elles sont appliquées uniquement par l'hôte, au même
## rythme (voir Ship), puis les valeurs sont envoyées aux autres joueurs.
##
## Règles actuelles :
## 1. Un générateur d'oxygène opérationnel (allumé et à son alimentation
##    minimale, voir Module.is_operational) remplit sa propre salle, à une
##    vitesse proportionnelle à son alimentation (PRODUCTION_SPEED à
##    l'alimentation optimale).
## 2. Les autres modules se remplissent à partir de leurs voisins (reliés par
##    une porte, voir Module.neighbors) qui ont au moins SOURCE_MIN_LEVEL
##    d'oxygène : ils montent vers le taux du meilleur d'entre eux, sans le
##    dépasser. La vitesse (SPREAD_SPEED) est proportionnelle à l'alimentation
##    des générateurs d'oxygène opérationnels du vaisseau (leur somme, rapportée
##    à l'optimum) : sans eux, l'oxygène ne se propage pas.
## Rien ne consomme l'oxygène pour l'instant.

## Taux d'oxygène de chaque module au début de la partie.
const START_LEVEL := 0.5
## Taux minimal d'un voisin pour qu'il remplisse un module.
const SOURCE_MIN_LEVEL := 0.1
## Vitesse de production d'un générateur à l'alimentation optimale (taux par
## seconde).
const PRODUCTION_SPEED := 0.05
## Vitesse de propagation vers un voisin, avec un générateur à l'alimentation
## optimale (taux par seconde).
const SPREAD_SPEED := 0.03


## Applique les règles pour un pas de temps [param delta] (en secondes).
## [param modules] est la liste des modules du vaisseau.
static func update(modules: Array[Module], delta: float) -> void:
	# Règle 1 : production, et force de propagation du vaisseau.
	var drive := 0.0
	for m in modules:
		if m.get_type_id() == Module.ModuleType.OXYGENE and m.is_operational():
			var ratio := m.get_power_ratio()
			drive += ratio
			m.oxygen = minf(m.oxygen + PRODUCTION_SPEED * ratio * delta, 1.0)
	if drive <= 0.0:
		return

	# Règle 2 : on retient d'abord le taux visé par chaque module (le meilleur
	# voisin suffisamment rempli), pour que l'ordre de traitement n'influence
	# pas le résultat.
	var targets := {}
	for m in modules:
		if m.get_type_id() == Module.ModuleType.OXYGENE and m.is_operational():
			continue
		var best := 0.0
		for n in m.neighbors:
			if n.oxygen >= SOURCE_MIN_LEVEL:
				best = maxf(best, n.oxygen)
		if best > m.oxygen:
			targets[m] = best
	for m: Module in targets:
		m.oxygen = minf(m.oxygen + SPREAD_SPEED * drive * delta, targets[m])
