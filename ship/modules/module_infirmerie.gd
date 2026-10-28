@tool
class_name ModuleInfirmerie
extends Module
## Infirmerie : soigne l'équipage.


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.INFIRMERIE


func get_ideal_power() -> float:
	return 600.0


func get_size() -> Vector2i:
	return Vector2i(16, 16)


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Croix médicale et deux lits.
	var c := rect.get_center() + Vector2(0, 30)
	var green := Color(0.3, 0.9, 0.5)
	draw_rect(Rect2(c - Vector2(10, 30), Vector2(20, 60)), green)
	draw_rect(Rect2(c - Vector2(30, 10), Vector2(60, 20)), green)
	for x in [40.0, rect.size.x - 88.0]:
		draw_rect(Rect2(x, 44, 48, 72), Color(0.85, 0.85, 0.9, 0.8), false, 2.0)
		draw_rect(Rect2(x + 8, 50, 32, 14), Color(0.85, 0.85, 0.9, 0.5))
