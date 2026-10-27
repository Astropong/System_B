@tool
class_name ModuleGenerateur
extends Module
## Générateur : produit l'électricité du vaisseau.


func get_type_id() -> Module.ModuleType:
	return Module.ModuleType.GENERATEUR


func get_ideal_power() -> float:
	return 300.0


func get_size() -> Vector2i:
	return Vector2i(16, 16)


func get_possible_failures() -> Array[StringName]:
	return []


func _draw_details(rect: Rect2) -> void:
	# Trois blocs de batteries avec un éclair.
	var yellow := Color(1.0, 0.85, 0.2)
	for i in 3:
		var cell := Rect2(rect.position + Vector2(36 + i * 64, 72), Vector2(40, 112))
		draw_rect(cell, Color(0.1, 0.1, 0.08))
		draw_rect(cell, yellow, false, 2.0)
		var c := cell.get_center()
		draw_polyline(PackedVector2Array([
			c + Vector2(5, -22), c + Vector2(-8, 2), c + Vector2(2, 2),
			c + Vector2(-5, 22), c + Vector2(8, -2), c + Vector2(-2, -2),
			c + Vector2(5, -22),
		]), yellow, 2.0)
