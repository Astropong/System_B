@tool
class_name ModuleMaintenance
extends Module
## Salle de maintenance : entretien et réparation des équipements.

const ACCENT := Color(0.75, 0.8, 0.88)


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.MAINTENANCE


func get_ideal_power() -> float:
	return 100.0


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Quatre établis contre les murs, avec leurs outils ; engrenage au sol.
	for i in QUADRANTS.size():
		var q := QUADRANTS[i]
		var y := q.y if i < 2 else q.y + QUADRANT_SIZE - 1.2
		_draw_furniture(cells(q.x, y, QUADRANT_SIZE, 1.2), ACCENT)
		for k in 3:
			var x := (q.x + 0.6 + k * 0.9) * CELL_SIZE
			draw_line(Vector2(x, (y + 0.3) * CELL_SIZE), Vector2(x, (y + 0.9) * CELL_SIZE),
					ACCENT.darkened(0.3), 4.0)
	var c := rect.get_center()
	var emblem := emblem_color(ACCENT)
	draw_arc(c, CELL_SIZE * 1.4, 0.0, TAU, 48, emblem, CELL_SIZE * 0.5)
	for k in 8:
		var dir := Vector2.from_angle(k * TAU / 8.0)
		draw_line(c + dir * CELL_SIZE * 1.6, c + dir * CELL_SIZE * 2.2, emblem, CELL_SIZE * 0.5)
