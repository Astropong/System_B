@tool
class_name ModuleRadar
extends Module
## Radar : détecte ce qui entoure le vaisseau.


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.RADAR


func get_ideal_power() -> float:
	return 1200.0


func get_size() -> Vector2i:
	return Vector2i(16, 16)


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Écran radar circulaire avec balayage.
	var c := rect.get_center() + Vector2(0, 10)
	var green := Color(0.3, 1.0, 0.4)
	draw_circle(c, 70, Color(0.03, 0.12, 0.05))
	for r in [70.0, 46.0, 22.0]:
		draw_arc(c, r, 0, TAU, 48, green.darkened(0.5), 1.5)
	draw_line(c, c + Vector2.from_angle(-PI / 5) * 70, green, 2.0)
	draw_circle(c + Vector2(30, 25), 4, green)
