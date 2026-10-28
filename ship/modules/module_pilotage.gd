@tool
class_name ModulePilotage
extends Module
## Pilotage : poste de commande du vaisseau.


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.PILOTAGE


func get_ideal_power() -> float:
	return 800.0


func get_size() -> Vector2i:
	return Vector2i(16, 16)


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Baie vitrée et console à l'avant (côté droit), siège du pilote.
	var w := rect.size.x
	var h := rect.size.y
	draw_line(Vector2(w - 4, 40), Vector2(w - 4, h - 40), Color(0.4, 0.8, 1.0, 0.8), 4.0)
	var console := Rect2(w - 64, 48, 36, h - 96)
	draw_rect(console, Color(0.1, 0.14, 0.22))
	draw_rect(console, Color(0.4, 0.7, 1.0), false, 2.0)
	for i in 4:
		draw_rect(Rect2(console.position + Vector2(8, 12 + i * 32), Vector2(20, 18)), Color(0.3, 0.9, 1.0, 0.7))
	var seat := Vector2(w - 112, h / 2.0)
	draw_circle(seat, 18, Color(0.35, 0.3, 0.45))
	draw_arc(seat, 18, 0, TAU, 32, Color(0.6, 0.55, 0.75), 2.0)
