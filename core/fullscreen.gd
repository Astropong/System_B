extends Node
## Plein écran : l'action « toggle_fullscreen » (F11, project.godot) fait
## passer la fenêtre en plein écran, sur tout l'écran, ou la ramène en fenêtre.
## Chargé automatiquement (autoload « Fullscreen »), donc actif partout :
## menu, partie, fenêtre de module.
## L'image s'adapte seule à la taille de l'écran (display/window/stretch dans
## project.godot).


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen") and not event.is_echo():
		toggle()
		get_viewport().set_input_as_handled()


## Passe du mode fenêtré au plein écran, ou l'inverse.
static func toggle() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
