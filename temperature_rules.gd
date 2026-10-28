class_name TemperatureRules
extends RefCounted
## Règles de température des modules du vaisseau (en °C).
##
## Comme l'alimentation, elles sont appliquées uniquement par l'hôte (voir
## Ship), juste après les règles d'alimentation, puis envoyées aux autres joueurs.
##
## Chaque module a deux températures :
## - celle de sa MACHINE, qui tend vers la moitié de la puissance fournie
##   (cible = power_supplied / MACHINE_WATTS_PER_DEGREE) ;
## - celle de sa PIÈCE, qui tend vers ROOM_BASE_TEMPERATURE plus la température
##   de la machine divisée par ROOM_MACHINE_DIVISOR.
## Chacune avance vers sa cible à une vitesse qui dépend de l'écart : lente sous
## un petit écart, rapide au-delà d'un grand écart, linéaire entre les deux.

## Température par défaut d'une pièce (°C).
const ROOM_BASE_TEMPERATURE := 20.0

## Puissance (W) par degré de température cible de la machine.
const MACHINE_WATTS_PER_DEGREE := 2.0
## Écarts (°C) et vitesses (°C/s) de rapprochement de la machine.
const MACHINE_SMALL_GAP := 10.0
const MACHINE_LARGE_GAP := 50.0
const MACHINE_SLOW_SPEED := 1.0
const MACHINE_FAST_SPEED := 5.0

## La pièce reçoit la température de la machine divisée par ce nombre.
const ROOM_MACHINE_DIVISOR := 5.0
## Écarts (°C) et vitesses (°C/s) de rapprochement de la pièce.
const ROOM_SMALL_GAP := 5.0
const ROOM_LARGE_GAP := 20.0
const ROOM_SLOW_SPEED := 0.5
const ROOM_FAST_SPEED := 2.0


## Applique les règles à [param modules] (liste des modules dans l'ordre du
## vaisseau) pour un pas de [param delta] secondes.
static func update(modules: Array[Module], delta: float) -> void:
	for m in modules:
		var machine_target := m.power_supplied / MACHINE_WATTS_PER_DEGREE
		m.machine_temperature = _approach(m.machine_temperature, machine_target, delta,
				MACHINE_SMALL_GAP, MACHINE_LARGE_GAP, MACHINE_SLOW_SPEED, MACHINE_FAST_SPEED)

		var room_target := ROOM_BASE_TEMPERATURE + m.machine_temperature / ROOM_MACHINE_DIVISOR
		m.room_temperature = _approach(m.room_temperature, room_target, delta,
				ROOM_SMALL_GAP, ROOM_LARGE_GAP, ROOM_SLOW_SPEED, ROOM_FAST_SPEED)


## Rapproche [param current] de [param target] sans la dépasser. Vitesse
## [param slow_speed] sous un écart [param small_gap], [param fast_speed]
## au-delà de [param large_gap], interpolée linéairement entre les deux.
static func _approach(current: float, target: float, delta: float,
		small_gap: float, large_gap: float, slow_speed: float, fast_speed: float) -> float:
	var gap := absf(target - current)
	var t := clampf(inverse_lerp(small_gap, large_gap, gap), 0.0, 1.0)
	var speed := lerpf(slow_speed, fast_speed, t)
	return move_toward(current, target, speed * delta)
