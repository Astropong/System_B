@tool
class_name ModuleCouloir
extends Module
## Couloir : relie les autres modules entre eux.


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.COULOIR


func get_ideal_power() -> float:
	return 100.0


func get_size() -> Vector2i:
	return Vector2i(8, 16)


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Bandes de passage et ligne centrale en pointillés.
	var c := rect.get_center()
	var stripe := Color(0.9, 0.75, 0.2, 0.6)
	draw_line(Vector2(0, c.y - CELL_SIZE), Vector2(rect.size.x, c.y - CELL_SIZE), stripe, 2.0)
	draw_line(Vector2(0, c.y + CELL_SIZE), Vector2(rect.size.x, c.y + CELL_SIZE), stripe, 2.0)
	draw_dashed_line(Vector2(0, c.y), Vector2(rect.size.x, c.y), Color(1, 1, 1, 0.25), 2.0, 12.0)
