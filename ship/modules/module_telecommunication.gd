@tool
class_name ModuleTelecommunication
extends Module
## Salle de télécommunication : liaisons avec l'extérieur du vaisseau.

const ACCENT := Color(0.72, 0.52, 1.0)


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.TELECOMMUNICATION


func get_ideal_power() -> float:
	return 100.0


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Huit baies de serveurs, ondes au sol.
	for q in QUADRANTS:
		for x in [q.x + 0.3, q.x + 1.7]:
			var rack := cells(x, q.y, 1.0, QUADRANT_SIZE)
			_draw_furniture(rack, ACCENT)
			for k in range(1, 4):
				var y := rack.position.y + rack.size.y * k / 4.0
				draw_line(Vector2(rack.position.x + 8, y), Vector2(rack.end.x - 8, y), ACCENT.darkened(0.4), 2.0)
	var c := rect.get_center()
	var emblem := emblem_color(ACCENT)
	draw_circle(c, CELL_SIZE * 0.4, emblem)
	for r in [1.2, 2.2]:
		for angle in [0.0, PI]:
			draw_arc(c, CELL_SIZE * r, angle - PI / 4.0, angle + PI / 4.0, 24, emblem, 6.0)
