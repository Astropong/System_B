@tool
class_name Starfield
extends Node2D
## Fond spatial infini : des étoiles générées par tuiles autour de la caméra.
## Chaque tuile a toujours les mêmes étoiles (graine fixe), donc le ciel est
## stable et défile quand le vaisseau avance.
## À placer dans un CanvasLayer « derrière » le jeu, pour que le brouillard de
## guerre ne l'atteigne pas.
##
## Le calque ne suit pas la caméra tel quel (follow_viewport désactivé) : à
## chaque image, il reprend la position et la rotation de la vue, mais pas son
## zoom. Les étoiles gardent ainsi la même taille et la même densité à l'écran
## quel que soit le zoom (mode pilotage compris), avec un nombre de tuiles
## constant ; elles défilent à la vitesse réelle du vaisseau dans le monde.

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


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var layer := get_parent() as CanvasLayer
	if layer:
		layer.follow_viewport_enabled = false
	# Juste avant le rendu : la vue de la caméra (interpolée) est alors connue.
	RenderingServer.frame_pre_draw.connect(_follow_view)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_follow_view):
		RenderingServer.frame_pre_draw.disconnect(_follow_view)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_tiles(Vector2(576, 324), Vector2(2600, 1600))


## Place le calque comme la vue du jeu, sans le zoom : le point du monde au
## centre de l'écran reste au centre, avec la même orientation.
func _follow_view() -> void:
	var layer := get_parent() as CanvasLayer
	if layer == null:
		return
	var view := get_viewport().get_canvas_transform()
	var screen_center := get_viewport_rect().size / 2.0
	var world_center := view.affine_inverse() * screen_center
	var rotation_only := Transform2D(view.get_rotation(), Vector2.ZERO)
	layer.transform = Transform2D(view.get_rotation(), screen_center - rotation_only * world_center)
	# La vue peut être tournée : on couvre le disque circonscrit à l'écran.
	var radius := screen_center.length()
	_update_tiles(world_center, Vector2(radius, radius))


func _update_tiles(center: Vector2, half: Vector2) -> void:
	var from := ((center - half) / tile_size).floor()
	var to := ((center + half) / tile_size).floor()
	var tiles := Rect2i(Vector2i(from), Vector2i(to - from) + Vector2i.ONE)
	if tiles != _drawn_tiles:
		_drawn_tiles = tiles
		queue_redraw()


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
