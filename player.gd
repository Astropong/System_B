extends CharacterBody2D
## Personnage vu de dessus, dessiné comme un rond.
## - Flèches du clavier : déplacement direct.
## - Clic gauche (ou bouton maintenu) : le personnage se rend vers la souris.
## Il est placé dans le vaisseau (nœud Ship/Crew) : il avance avec lui, et sa
## position comme sa cible sont exprimées dans le repère du vaisseau.
##
## Multijoueur : le nom du nœud est l'identifiant réseau du joueur, qui fait
## autorité sur son personnage. Seul le personnage local lit les commandes et
## porte la caméra et la lumière (donc son propre brouillard de guerre) ;
## les autres sont simplement affichés à la position reçue du réseau.

@export var speed: float = 300.0
@export var radius: float = 24.0
@export var color: Color = Color(0.3, 0.7, 1.0)

## Couleurs des autres joueurs (le joueur local reste bleu).
const OTHER_PLAYER_COLORS: Array[Color] = [
	Color(1.0, 0.6, 0.2),   # orange
	Color(0.4, 0.9, 0.4),   # vert
	Color(1.0, 0.45, 0.7),  # rose
	Color(1.0, 0.9, 0.3),   # jaune
	Color(0.75, 0.5, 1.0),  # violet
	Color(0.95, 0.3, 0.3),  # rouge
]

var target: Vector2  # dans le repère du vaisseau
var has_target: bool = false


func _enter_tree() -> void:
	var peer_id := name.to_int()
	if peer_id > 0:
		set_multiplayer_authority(peer_id)


func _ready() -> void:
	target = position
	var is_local := is_multiplayer_authority()
	$Camera2D.enabled = is_local
	$VisionLight.enabled = is_local
	if is_local:
		$Camera2D.make_current()
	else:
		# Une couleur différente par joueur distant.
		color = OTHER_PLAYER_COLORS[name.to_int() % OTHER_PLAYER_COLORS.size()]


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Souris : tant que le bouton gauche est enfoncé, la cible suit le curseur.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		target = _global_to_parent(get_global_mouse_position())
		has_target = true

	# Clavier : les actions ui_* sont déjà associées aux flèches.
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if input_dir != Vector2.ZERO:
		has_target = false  # le clavier annule la cible de la souris
		velocity = input_dir * speed
	elif has_target:
		var to_target := target - position
		if to_target.length() <= speed * delta:
			velocity = to_target / delta  # dernier petit pas pile sur la cible
			has_target = false
		else:
			velocity = to_target.normalized() * speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	queue_redraw()


func _global_to_parent(point: Vector2) -> Vector2:
	var parent := get_parent() as Node2D
	return parent.to_local(point) if parent else point


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, color.darkened(0.4), 3.0)
	if has_target:
		var t := target - position  # le vaisseau n'est ni tourné ni agrandi
		draw_arc(t, 8.0, 0.0, TAU, 24, Color.WHITE, 2.0)
		draw_line(Vector2.ZERO, t, Color(1, 1, 1, 0.25), 1.0)
