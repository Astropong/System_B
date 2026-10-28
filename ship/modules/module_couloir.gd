@tool
class_name ModuleCouloir
extends Module
## Couloir : relie les autres modules entre eux. Sa taille se règle dans la
## scène ([member size_cells]) ; il est dessiné dans le sens de sa longueur.

const ACCENT := Color(0.9, 0.75, 0.2, 0.45)

## Taille du couloir (cases).
@export var size_cells: Vector2i = Vector2i(8, 16):
	set(value):
		size_cells = value
		queue_redraw()
		var ship := get_parent()
		if ship != null and ship.has_method("arrange_modules"):
			ship.arrange_modules()


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.COULOIR


func get_ideal_power() -> float:
	return 10.0


func get_size() -> Vector2i:
	return size_cells


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Deux lignes de guidage le long des murs, axe central en pointillés.
	var s := rect.size
	if s.y >= s.x:
		for x in [CELL_SIZE, s.x - CELL_SIZE]:
			draw_line(Vector2(x, 0), Vector2(x, s.y), ACCENT, 2.0)
		draw_dashed_line(Vector2(s.x / 2.0, 0), Vector2(s.x / 2.0, s.y), Color(1, 1, 1, 0.2), 2.0, 16.0)
	else:
		for y in [CELL_SIZE, s.y - CELL_SIZE]:
			draw_line(Vector2(0, y), Vector2(s.x, y), ACCENT, 2.0)
		draw_dashed_line(Vector2(0, s.y / 2.0), Vector2(s.x, s.y / 2.0), Color(1, 1, 1, 0.2), 2.0, 16.0)
