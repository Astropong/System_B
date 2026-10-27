@tool
class_name ModuleReacteur
extends Module
## Réacteur : propulsion du vaisseau.


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.REACTEUR


func get_ideal_power() -> float:
	return 1500.0


func get_size() -> Vector2i:
	return Vector2i(16, 16)


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Cœur du réacteur : anneaux concentriques et supports.
	var c := rect.get_center() + Vector2(0, 10)
	var orange := Color(1.0, 0.5, 0.15)
	for angle in [PI / 4, 3 * PI / 4, 5 * PI / 4, 7 * PI / 4]:
		draw_line(c + Vector2.from_angle(angle) * 50, c + Vector2.from_angle(angle) * 85, WALL_COLOR, 4.0)
	draw_circle(c, 62, Color(0.2, 0.1, 0.05))
	draw_arc(c, 62, 0, TAU, 48, orange, 3.0)
	draw_arc(c, 44, 0, TAU, 48, orange.darkened(0.3), 2.0)
	draw_circle(c, 26, orange)
	draw_circle(c, 13, Color(1.0, 0.95, 0.7))
