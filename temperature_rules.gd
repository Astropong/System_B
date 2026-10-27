class_name TemperatureRules
extends RefCounted
## Règles de température des modules du vaisseau (en °C, entiers).
##
## Comme l'alimentation, elles sont appliquées uniquement par l'hôte (voir
## Ship), juste après les règles d'alimentation, puis envoyées aux autres joueurs.
##
## Règles actuelles :
## 1. Tous les modules sont par défaut à BASE_TEMPERATURE (0 °C).
## 2. Chaque module gagne 1 °C par tranche de WATTS_PER_DEGREE W d'alimentation.

## Température d'un module sans alimentation (°C).
const BASE_TEMPERATURE := 0
## Puissance (W) nécessaire pour gagner un degré.
const WATTS_PER_DEGREE := 10.0


## Applique les règles à [param modules] (liste des modules dans l'ordre du vaisseau).
static func update(modules: Array[Module]) -> void:
	for m in modules:
		m.temperature = BASE_TEMPERATURE + floori(m.power_supplied / WATTS_PER_DEGREE)
