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
## chaque image, il reprend la rotation de la vue, mais pas son zoom. Les
## étoiles gardent ainsi la même taille et la même densité à l'écran quel que
## soit le zoom (mode pilotage compris), avec un nombre de tuiles constant.
## Elles sont dans leur propre plan, qui avance du déplacement de la vue
## dans l'espace multiplié par le zoom : elles défilent à l'écran à la même
## vitesse que les vaisseaux, et ne glissent pas quand seul le zoom change.
## Espace : repère de Fleet ; la scène, elle, suit le vaisseau ancré (voir
## Ship.anchored), dont la place interpolée relie les deux.

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

## Le motif d'étoiles se répète tous les WRAP_TILES tuiles : le centre de la
## vue dans ce plan y est ramené (sans saut visible), sinon il grandirait
## sans fin et la précision des nombres ferait trembler les étoiles.
const WRAP_TILES := 1024

var _drawn_tiles: Rect2i
# Centre de la vue dans le plan des étoiles, et dans l'espace à l'image précédente.
var _star_center := Vector2.ZERO
var _last_world_center := Vector2.ZERO
var _has_view: bool = false


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


## Place le calque comme la vue du jeu, sans le zoom : le centre de la vue
## dans le plan des étoiles avance du déplacement de la vue dans l'espace
## multiplié par le zoom (même défilement à l'écran que l'espace), avec la
## même orientation.
func _follow_view() -> void:
	var layer := get_parent() as CanvasLayer
	if layer == null:
		return
	var view := get_viewport().get_canvas_transform()
	var screen_center := get_viewport_rect().size / 2.0
	# Vue depuis l'espace : espace → scène (inverse de la place du vaisseau
	# ancré), puis scène → écran.
	var space := Ship.anchor.get_interpolated_space_transform() if Ship.anchor else Transform2D.IDENTITY
	var space_view := view * space.affine_inverse()
	var world_center := space_view.affine_inverse() * screen_center
	var zoom := view.x.length()
	if _has_view:
		_star_center += (world_center - _last_world_center) * zoom
	else:
		_star_center = world_center * zoom
		_has_view = true
	_last_world_center = world_center
	var period := tile_size * WRAP_TILES
	_star_center = Vector2(fposmod(_star_center.x, period), fposmod(_star_center.y, period))
	var angle := space_view.get_rotation()
	layer.transform = Transform2D(angle, screen_center - Transform2D(angle, Vector2.ZERO) * _star_center)
	# La vue peut être tournée : on couvre le disque circonscrit à l'écran.
	var radius := screen_center.length()
	_update_tiles(_star_center, Vector2(radius, radius))


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
			rng.seed = hash(Vector3i(posmod(tx, WRAP_TILES), posmod(ty, WRAP_TILES), star_seed))
			var origin := Vector2(tx, ty) * tile_size
			for i in stars_per_tile:
				var pos := origin + Vector2(rng.randf(), rng.randf()) * tile_size
				var radius := rng.randf_range(0.6, 1.8)
				var brightness := rng.randf_range(0.4, 1.0)
				draw_circle(pos, radius, Color(brightness, brightness, minf(brightness + 0.1, 1.0)))
