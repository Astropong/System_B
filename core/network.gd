extends Node
## Multijoueur en réseau (ENet) : menu Héberger / Rejoindre / Langue,
## apparition et départ des joueurs.
##
## L'hôte (identifiant réseau 1) fait autorité sur le vaisseau et les portes ;
## chaque joueur fait autorité sur son propre personnage.
## Lancement automatique possible avec les arguments --host ou --join
## (--join=192.168.1.20 pour une autre adresse que 127.0.0.1), et langue
## forcée avec --lang=en (ou fr).
##
## Serveur dédié : avec l'étiquette de fonctionnalité « dedicated_server »
## (export en mode « Serveur dédié », ou étiquette ajoutée à une instance de
## lancement dans l'éditeur), le jeu crée la partie automatiquement, sans
## menu et sans personnage pour lui-même. À lancer de préférence avec --headless.

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8
const DEFAULT_ADDRESS := "127.0.0.1"

@export var player_scene: PackedScene = preload("res://player/player.tscn")

@onready var _ship: Ship = $"../Ship"
@onready var _crew: Node2D = $"../Ship/Crew"
@onready var _spawner: MultiplayerSpawner = $"../PlayerSpawner"
@onready var _menu: Control = %Menu
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _address: LineEdit = %Address
@onready var _status: Label = %Status
@onready var _language: OptionButton = %Language


func _ready() -> void:
	Language.apply_saved()
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with("--lang="):
			# Langue forcée pour cette session, sans la mémoriser.
			TranslationServer.set_locale(arg.get_slice("=", 1))
	_setup_language_choice()

	# Chaque joueur crée les personnages lui-même, à partir des données envoyées
	# par l'hôte (identifiant et position de départ).
	_spawner.spawn_function = _create_player
	_host_button.pressed.connect(host)
	_join_button.pressed.connect(func() -> void: join(_address.text))
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if OS.has_feature("dedicated_server"):
		start_dedicated_server.call_deferred()
		return

	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg == "--host":
			host.call_deferred()
		elif arg.begins_with("--join"):
			var address := arg.get_slice("=", 1) if "=" in arg else DEFAULT_ADDRESS
			join.call_deferred(address)


## Menu : liste des langues (noms non traduits), sur la langue actuelle.
func _setup_language_choice() -> void:
	for locale in Language.LOCALES:
		_language.add_item(Language.LOCALE_NAMES[locale])
	_language.select(Language.LOCALES.find(Language.get_current()))
	_language.item_selected.connect(func(index: int) -> void:
		Language.set_language(Language.LOCALES[index]))


## Crée la partie sur cette machine, en y jouant.
func host() -> void:
	if not _create_server():
		_status.text = tr("Impossible d'héberger : le port %d est peut-être déjà utilisé.") % DEFAULT_PORT
		return
	_spawn_player(1)
	_menu.hide()


## Crée la partie sans y jouer (serveur dédié).
func start_dedicated_server() -> void:
	_menu.hide()
	if not _create_server():
		printerr("Serveur dédié : impossible d'écouter sur le port %d." % DEFAULT_PORT)
		get_tree().quit(1)
		return
	print("Serveur dédié démarré sur le port %d (%d joueurs max)." % [DEFAULT_PORT, MAX_PLAYERS])


func _create_server() -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(DEFAULT_PORT, MAX_PLAYERS) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_ship.randomize_module_states()  # TEST : états aléatoires
	return true


## Rejoint une partie hébergée à l'adresse donnée.
func join(address: String) -> void:
	address = address.strip_edges()
	if address.is_empty():
		address = DEFAULT_ADDRESS
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, DEFAULT_PORT)
	if error != OK:
		_status.text = tr("Adresse invalide : %s") % address
		return
	multiplayer.multiplayer_peer = peer
	_status.text = tr("Connexion à %s...") % address
	_set_buttons_disabled(true)


## Fait apparaître le personnage d'un joueur chez tout le monde (hôte uniquement).
func _spawn_player(peer_id: int) -> void:
	_spawner.spawn({
		"id": peer_id,
		"position": _ship.get_spawn_position(_crew.get_child_count()),
	})


func _create_player(data: Dictionary) -> Node:
	var player := player_scene.instantiate()
	player.name = str(data["id"])  # le nom porte l'identifiant réseau du joueur
	player.position = data["position"]
	return player


func _set_buttons_disabled(disabled: bool) -> void:
	_host_button.disabled = disabled
	_join_button.disabled = disabled


# --- Côté hôte ---------------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	print("Joueur %d connecté." % peer_id)
	_spawn_player(peer_id)
	# État courant envoyé au nouveau venu : vaisseau, état des modules, portes
	# et personnages (ceux-ci ne sont transmis qu'à chaque changement d'ordre).
	_ship.send_motion_to(peer_id)
	_ship.send_module_states(peer_id)
	_ship.send_module_controls(peer_id)
	_ship.send_door_states(peer_id)
	for player in _crew.get_children():
		if player is Player and player.name != str(peer_id):
			player.send_state_to(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Joueur %d déconnecté." % peer_id)
	var player := _crew.get_node_or_null(str(peer_id))
	if player:
		player.queue_free()


# --- Côté joueur qui rejoint -----------------------------------------------

func _on_connected_to_server() -> void:
	_menu.hide()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_status.text = tr("Échec de la connexion.")
	_set_buttons_disabled(false)


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().reload_current_scene.call_deferred()
