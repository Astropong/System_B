class_name Language
extends RefCounted
## Langue du jeu : choix parmi LOCALES, mémorisé dans SETTINGS_PATH.
##
## Les textes sont traduits par le TranslationServer à partir de
## i18n/translations.csv, dont les clés sont les textes en français : écrire
## les textes du jeu en français, puis ajouter leur ligne dans ce fichier.
## Les Label et Button traduisent leur texte d'eux-mêmes ; un texte composé
## dans le code passe par tr() (avec % après tr pour les valeurs).

## Langues proposées, avec leur nom dans leur propre langue.
const LOCALES := ["fr", "en"]
const LOCALE_NAMES := {"fr": "Français", "en": "English"}
## Langue si le système n'en propose aucune de LOCALES.
const DEFAULT_LOCALE := "en"

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "general"
const SETTINGS_KEY := "language"


## Applique la langue mémorisée, ou à défaut celle du système si elle est
## proposée, sinon DEFAULT_LOCALE. À appeler au démarrage.
static func apply_saved() -> void:
	var config := ConfigFile.new()
	var locale := ""
	if config.load(SETTINGS_PATH) == OK:
		locale = config.get_value(SETTINGS_SECTION, SETTINGS_KEY, "")
	if locale not in LOCALES:
		locale = OS.get_locale_language()
	if locale not in LOCALES:
		locale = DEFAULT_LOCALE
	TranslationServer.set_locale(locale)


## Change de langue et mémorise le choix.
static func set_language(locale: String) -> void:
	TranslationServer.set_locale(locale)
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)  # garde les autres réglages éventuels
	config.set_value(SETTINGS_SECTION, SETTINGS_KEY, locale)
	config.save(SETTINGS_PATH)


## Langue actuelle (l'une de LOCALES).
static func get_current() -> String:
	var locale := TranslationServer.get_locale().get_slice("_", 0)
	return locale if locale in LOCALES else DEFAULT_LOCALE
