class_name DebugMode
extends RefCounted
## Mode débogage : affichages réservés au développement (jauges de batterie...).
##
## Actif quand le jeu est lancé depuis l'éditeur ou exporté « avec débogage » ;
## désactivé dans un export release.
## Pour prévisualiser le rendu release depuis l'éditeur, lancer le jeu avec
## l'argument --release.

static var _enabled: Variant = null


static func is_enabled() -> bool:
	if _enabled == null:
		var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
		_enabled = OS.is_debug_build() and not args.has("--release")
	return _enabled
