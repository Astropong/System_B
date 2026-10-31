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
##
## Personnages : enfants du nœud Crew de leur vaisseau (n'importe lequel).
## L'hôte les crée (_create_player), les fait changer de vaisseau
## (_transfer_player) et les retire (_remove_player) chez tous par RPC ; un
## nouveau venu reçoit d'abord ceux qui existent. (Un MultiplayerSpawner ne
## gère que les enfants d'un seul nœud, et déplacer un nœud qu'il a créé
## casse son suivi.)
## Debug : DEBUG_NEXT_SHIP_ACTION fait passer le joueur local au vaisseau
## suivant (en attendant un vrai moyen de monter à bord).

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8
const DEFAULT_ADDRESS := "127.0.0.1"
## Action (project.godot, F2) : passer au vaisseau suivant, en mode debug.
const DEBUG_NEXT_SHIP_ACTION := &"debug_next_ship"

@export var player_scene: PackedScene = preload("res://player/player.tscn")

## Vaisseau où apparaissent les joueurs.
@onready var _ship: Ship = $"../Ships/Ship"
@onready var _fleet: Fleet = $"../Ships"
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
	_fleet.spawn_starting_ships()
	for ship in _get_ships():
		ship.randomize_module_states()  # TEST : états aléatoires
	return true


## Tous les vaisseaux de la partie : celui des joueurs et les autres.
func _get_ships() -> Array[Node]:
	return get_tree().get_nodes_in_group(Ship.GROUP)


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


## Fait apparaître le personnage d'un joueur chez tout le monde, dans le
## vaisseau de départ (hôte uniquement).
func _spawn_player(peer_id: int) -> void:
	var at := _ship.get_spawn_position(_ship.get_node("Crew").get_child_count())
	_create_player.rpc(peer_id, _ship.get_path(), at)


## Tous les personnages, quel que soit leur vaisseau.
func get_players() -> Array[Player]:
	var players: Array[Player] = []
	for ship in _get_ships():
		for child in ship.get_node("Crew").get_children():
			if child is Player:
				players.append(child)
	return players


func _find_player(peer_id: int) -> Player:
	for player in get_players():
		if player.name == str(peer_id):
			return player
	return null


## Crée le personnage d'un joueur dans le vaisseau [param ship_path] (chemin
## absolu, le même sur toutes les machines), à la place [param at] (repère
## du vaisseau).
@rpc("authority", "call_local", "reliable")
func _create_player(peer_id: int, ship_path: NodePath, at: Vector2) -> void:
	var ship := get_node_or_null(ship_path) as Ship
	if ship == null or _find_player(peer_id) != null:
		return
	var player: Player = player_scene.instantiate()
	player.name = str(peer_id)  # le nom porte l'identifiant réseau du joueur
	player.position = at
	ship.get_node("Crew").add_child(player)


@rpc("authority", "call_local", "reliable")
func _remove_player(peer_id: int) -> void:
	var player := _find_player(peer_id)
	if player:
		player.queue_free()


## Demande à l'hôte de faire passer le joueur local dans [param ship].
func request_transfer(ship: Ship) -> void:
	_request_transfer.rpc_id(1, ship.get_path())


## Hôte : le demandeur quitte son vaisseau (et ses commandes, s'il pilotait)
## pour une place d'apparition du vaisseau visé.
@rpc("any_peer", "call_local", "reliable")
func _request_transfer(ship_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var player := _find_player(peer_id)
	var target := get_node_or_null(ship_path) as Ship
	if player == null or target == null or target == player.get_ship():
		return
	player.get_ship().release_controls_of(peer_id)
	var at := target.get_spawn_position(target.get_node("Crew").get_child_count())
	_transfer_player.rpc(peer_id, ship_path, at)


@rpc("authority", "call_local", "reliable")
func _transfer_player(peer_id: int, ship_path: NodePath, at: Vector2) -> void:
	var player := _find_player(peer_id)
	var target := get_node_or_null(ship_path) as Ship
	if player and target:
		player.transfer_to(target, at)


## Debug : F2 fait passer le joueur local au vaisseau suivant (ordre de l'arbre).
func _unhandled_input(event: InputEvent) -> void:
	if not DebugMode.is_enabled() or not event.is_action_pressed(DEBUG_NEXT_SHIP_ACTION):
		return
	var player := Player.get_local()
	if player == null or Piloting.is_active() or ModuleWindow.is_open:
		return
	var ships := _get_ships()
	var next: Ship = ships[(ships.find(player.get_ship()) + 1) % ships.size()]
	request_transfer(next)


func _set_buttons_disabled(disabled: bool) -> void:
	_host_button.disabled = disabled
	_join_button.disabled = disabled


# --- Côté hôte ---------------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	print("Joueur %d connecté." % peer_id)
	# Le nouveau venu reçoit les personnages existants (les vaisseaux de
	# Fleet lui sont déjà parvenus par leur MultiplayerSpawner), puis le sien
	# est créé chez tous.
	for player in get_players():
		_create_player.rpc_id(peer_id, player.name.to_int(), player.get_ship().get_path(), player.position)
	_spawn_player(peer_id)
	# État courant envoyé au nouveau venu : vaisseaux, état des modules, portes
	# et personnages (ceux-ci ne sont transmis qu'à chaque changement d'ordre).
	for ship: Ship in _get_ships():
		ship.send_motion_to(peer_id)
		ship.send_module_states(peer_id)
		ship.send_module_controls(peer_id)
		ship.send_door_states(peer_id)
	for player in get_players():
		if player.name != str(peer_id):
			player.send_state_to(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Joueur %d déconnecté." % peer_id)
	for ship: Ship in _get_ships():
		ship.release_controls_of(peer_id)
	_remove_player.rpc(peer_id)


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
