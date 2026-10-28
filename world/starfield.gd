@tool
class_name Starfield
extends Node2D
## Fond spatial infini : des étoiles générées par tuiles autour de la caméra.
## Chaque tuile a toujours les mêmes étoiles (graine fixe), donc le ciel est
## stable et défile quand le vaisseau avance.
## À placer dans un CanvasLayer « derrière » le jeu (follow_viewport activé),
## pour que le brouillard de guerre ne l'atteigne pas.

@export var tile_size: float = 512.0:
	set(value):
		tile_size = maxf(value, 64.0)
		queue_redraw()
@export var stars_per_tile: int = 14:
	set(value):
		stars_per_tile = value
		queue_redraw()
@export var star_seed: int = 2026:
	set(value):
		star_seed = value
		queue_redraw()

var _drawn_tiles: Rect2i


func _process(_delta: float) -> void:
	var tiles := _visible_tiles()
	if tiles != _drawn_tiles:
		_drawn_tiles = tiles
		queue_redraw()


func _visible_tiles() -> Rect2i:
	var center := Vector2(576, 324)
	var half := Vector2(2600, 1600)
	var camera := get_viewport().get_camera_2d() if not Engine.is_editor_hint() else null
	if camera:
		center = camera.get_screen_center_position()
		half = get_viewport_rect().size / camera.zoom / 2.0
	var from := ((center - half) / tile_size).floor()
	var to := ((center + half) / tile_size).floor()
	return Rect2i(Vector2i(from), Vector2i(to - from) + Vector2i.ONE)


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	for tx in range(_drawn_tiles.position.x, _drawn_tiles.end.x):
		for ty in range(_drawn_tiles.position.y, _drawn_tiles.end.y):
			rng.seed = hash(Vector3i(tx, ty, star_seed))
			var origin := Vector2(tx, ty) * tile_size
			for i in stars_per_tile:
				var pos := origin + Vector2(rng.randf(), rng.randf()) * tile_size
				var radius := rng.randf_range(0.6, 1.8)
				var brightness := rng.randf_range(0.4, 1.0)
				draw_circle(pos, radius, Color(brightness, brightness, minf(brightness + 0.1, 1.0)))
