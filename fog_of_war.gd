extends CanvasModulate
## Brouillard de guerre : assombrit tout ce que la lumière du joueur
## n'éclaire pas. Les murs et les portes fermées projettent des ombres.
## L'intensité se règle avec la couleur du nœud FogOfWar :
## 0.25 = assombri de 75 %, 0 = noir total.
## La lumière du joueur (VisionLight, dans player.tscn) s'ajoute à cette base :
## son énergie doit valoir 1 - cette valeur (ici 0.75) pour un éclairage normal.
## Masqué dans l'éditeur pour ne pas noircir la vue ; activé en jeu.


func _ready() -> void:
	visible = true
