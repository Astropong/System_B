extends CanvasModulate
## Brouillard de guerre : assombrit tout ce que la lumière du joueur
## n'éclaire pas. Les murs et les portes fermées projettent des ombres.
## Masqué dans l'éditeur pour ne pas noircir la vue ; activé en jeu.


func _ready() -> void:
	visible = true
