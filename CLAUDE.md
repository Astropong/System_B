# System B — contexte du projet

Jeu spatial 2D vu de dessus, multijoueur, dans un vaisseau modulaire.
Moteur : **Godot 4.7.2**, GDScript, rendu Forward+ (Direct3D 12 sous Windows).
Dépôt : https://github.com/Astropong/System_B (branche `main`).

## Conventions

- Commentaires, textes du jeu et messages de commit **en français**.
- **Multilangue** (`core/language.gd`, `i18n/translations.csv`, colonnes `fr` et
  `en`) : les clés sont les textes français. Tout nouveau texte affiché doit avoir
  sa ligne dans le CSV. `Label`/`Button` traduisent seuls leur `text` ; un texte
  composé ou dessiné passe par `tr("…") % valeurs`, et les nœuds qui dessinent du
  texte se redessinent sur `NOTIFICATION_TRANSLATION_CHANGED`. Après modification
  du CSV : réimporter (`--import`) pour régénérer les `.translation`.
- Indentation par **tabulations** dans les fichiers `.gd`.
- Commentaires de documentation `##` en tête de chaque script et des fonctions publiques.
- 1 case = **48 px** = diamètre du personnage (`Module.CELL_SIZE`). Les tailles se
  raisonnent en cases.
- Valeurs réglables regroupées en constantes en haut des fichiers, ou en `@export`.
  Ce fichier cite leurs **noms** : lire la valeur dans le code.

## Lancer et tester

- Scène principale : `main.tscn`. Menu **Héberger** / **Rejoindre** (adresse par
  défaut `127.0.0.1`, port UDP 7777) / **Langue** (mémorisée dans
  `user://settings.cfg`, sinon langue du système, sinon anglais).
- Arguments : `--host`, `--join`, `--join=<ip>`, `--release` (désactive le mode debug),
  `--lang=fr|en` (langue de la session, non mémorisée).
- Serveur dédié : étiquette de fonctionnalité `dedicated_server`, de préférence avec
  `--headless`. Il crée la partie sans menu ni personnage.
- Dans l'éditeur : menu Débogage → personnalisation des instances de lancement,
  2 instances (`--host` / `--join`) ou 3 (serveur dédié + 2 × `--join`).

### Vérifier sans l'éditeur
- Exécutable : `B:\Programmes\Godot\Godot_v4.7.2-stable_win64_console.exe`.
- Pas de Python sur la machine ; Git Bash et PowerShell disponibles.
- Erreurs de script / nouvelle `class_name` : `<godot> --headless --path . --import`.
- Lancement court : `<godot> --path . --host --quit-after 900` (avec rendu, pour
  compiler les shaders).
- Tests scriptés : un `SceneTree` passé par `--script <fichier.gd> -- --host` charge
  `main.tscn`, agit sur les nœuds et peut enregistrer des captures
  (`root.get_texture().get_image().save_png(...)`). Garder ces scripts hors du dépôt.
  - Les arguments après `--` se lisent avec `OS.get_cmdline_user_args()`.
  - `multiplayer` n'existe pas dans un `SceneTree` : passer par
    `current_scene.multiplayer`.
  - Simuler une touche : `Input.parse_input_event` avec un `InputEventAction`
    (ex. `interact`).
  - `--lang=en` pour des captures en anglais sans toucher au choix mémorisé.
- Réseau : un hôte et un client `--headless` lancés à quelques secondes d'écart ;
  trafic lu avec `ENetConnection.pop_statistic(HOST_TOTAL_SENT_DATA, ...)`.
  - Le port 7777 est souvent pris par des parties lancées depuis l'éditeur de
    l'utilisateur (ne pas les fermer) : `create_server` échoue (« Couldn't create
    an ENet host ») et le client rejoint l'ancienne version. Créer alors les pairs
    dans le script de test sur un autre port (`ENetMultiplayerPeer`, puis appeler
    `Ship.randomize_module_states`, `Network._spawn_player`, brancher
    `peer_connected` sur `Network._on_peer_connected`).
  - L'hôte de test doit vivre plus longtemps que le client : à sa fermeture, le
    client recharge la scène et perd l'état reçu.
- Pas de tests automatisés : vérifier aussi en jeu, à deux instances pour tout ce
  qui touche au réseau.

## Architecture

Fichiers rangés **par fonctionnalité** (scène, script et shaders ensemble) :
- `core/` : réseau, langue, mode debug ;
- `ship/` : vaisseau, portes, `rules/` (alimentation, température), `modules/`
  et leurs `shaders/` ;
- `player/` ; `world/` (fond étoilé, brouillard) ; `ui/` (interface) ;
  `i18n/` (traductions) ; `assets/` pour les futures ressources.
- Racine : `main.tscn` et fichiers du projet.

Après un déplacement, vérifier les chemins `res://` écrits dans les scripts
(`preload`) et les `.tscn`.

### Modules — `ship/modules/module.gd`, `ship/modules/module_*.gd`
- `Module` est abstraite (`@abstract`) ; un fichier par type (Pilotage, Infirmerie,
  Reacteur, Couloir, Radar, Generateur, Oxygene, Maintenance, Telecommunication,
  Laboratoire, Construction, Tourelles). Un type peut apparaître plusieurs fois.
- **À fournir par chaque type** : `get_type_id()`, `get_ideal_power()` (W),
  `get_possible_failures()`. `get_size()` (cases) vaut par défaut `DEFAULT_SIZE`
  (16 × 16) ; le Couloir la règle par instance (`size_cells`). `get_min_power()`
  vaut par défaut la moitié de l'optimale.
- **Valeurs d'instance** : `power_supplied` (W), `room_temperature` et
  `machine_temperature` (°C, réels, affichés arrondis), `state` (0–1),
  `grid_position` (cases, réglée dans la scène). `doorways` et `neighbors` sont
  calculés par le vaisseau.
- **Commandes** (affichées dans la fenêtre du module, voir Fenêtre de module) :
  `@export` `can_be_switched_off` (levier marche / arrêt, vrai par défaut) et
  `adjustable_power` (curseur d'alimentation cible, vrai par défaut, mis à faux
  dans le `_init` du Couloir et du Générateur). Curseur entre `get_min_power()`
  et `get_max_power()` (optimum × `max_power_ratio`, 1,5 par défaut). État
  synchronisé : `is_on`, `target_power` (négatif = optimum).
  - Le joueur demande à l'hôte (`request_switch`, `request_target_power`), qui
    applique et renvoie à tous (`_receive_controls`). Éteint : `power_supplied`
    passe à 0 aussitôt.
- Dessin : sol quadrillé, aménagement du type (`_draw_details`, à l'échelle réelle),
  zone d'interaction, murs, nom traduit en haut à gauche, jauge (verte, rouge sous
  le minimum) et températures (debug seulement).
- **Style des salles** (minimaliste) : une couleur `ACCENT` par type ; meubles en
  aplat sombre cerclés de cette couleur (`_draw_furniture`,
  `_draw_round_furniture`) dans les quatre zones `QUADRANTS` ; emblème au sol en
  transparence au centre (`emblem_color`). La croix centrale (cases 6 à 10) reste
  libre pour le passage entre les portes, le coin supérieur gauche pour le nom
  et la jauge. Coordonnées en cases avec `cells()` / `cell_point()`.
- **Éclairage** selon l'alimentation (`_update_lighting`) : rouge sous le minimum,
  blanc atténué avec clignotements jusqu'à l'optimum, orangé au-delà. Appliqué par
  `self_modulate` + 4 lampes dessinées. **Pas de `Light2D`** dans les salles : elles
  rendraient les pièces visibles à travers les murs (brouillard de guerre cassé).
- **Effets de température** (`_create_climate_effects`, shaders
  `ship/modules/shaders/heat_haze.gdshader` / `frost.gdshader`) : déformation au-dessus de
  `HEAT_THRESHOLD`, givre en dessous de `FROST_THRESHOLD` (température de la pièce).
  - La déformation relit l'écran : `BackBufferCopy` en mode **viewport** (le mode
    rectangle laisse des bandes noires) et `render_mode unshaded` (l'image lue est
    déjà assombrie par le brouillard).

### Vaisseau — `ship/ship.gd`
- Place ses modules enfants selon leur `grid_position`, l'ensemble centré sur le
  vaisseau ; l'avant est à droite. Disposition actuelle (64 × 64 cases) : trois
  colonnes de salles séparées par deux couloirs verticaux de 8 × 64 cases.
- Deux modules qui partagent au moins `MIN_SHARED_WALL` cases de mur sont voisins,
  avec une porte au milieu de la partie commune (verticale ou pivotée de 90°).
- Le nœud `Structure` (généré, non sauvegardé) contient les collisions des murs, les
  `LightOccluder2D` (murs fusionnés par droite : `_merge_wall_lines`) et les `Door`.
- Avance à `speed` (vers la droite de l'écran) et tourne à `angular_speed` (°/s),
  **simulé par chaque joueur**. Changer l'une des vitesses sur l'hôte envoie
  position, orientation et vitesses aux autres (`_receive_motion`) ; l'hôte
  corrige aussi position et orientation toutes les `MOTION_SYNC_INTERVAL` s
  (`_receive_position`), écart résorbé en douceur, ou d'un coup au-delà de
  `CORRECTION_SNAP_DISTANCE` / `CORRECTION_SNAP_ANGLE`.
- Les joueurs sont enfants de `Ship/Crew` : coordonnées dans le repère du vaisseau
  (qui tourne). La caméra du joueur tourne avec le vaisseau (`ignore_rotation`
  désactivé dans `player.tscn`) : le vaisseau reste droit à l'écran, l'espace tourne.
- **Interpolation physique** activée (`physics/common/physics_interpolation`) :
  sans elle, la rotation par pas physiques fait trembler l'image. Conséquences :
  - déplacer les nœuds en `_physics_process`, pas en `_process` ;
  - après un saut (correction d'un coup), appeler `reset_physics_interpolation()` ;
  - ne pas replier les angles (un saut de 360° serait interpolé) ;
  - caméra en mode physique (`process_callback`), sans lissage de position.
- L'hôte applique alimentation puis température `PowerRules.UPDATE_RATE` fois par
  seconde, et envoie tout en un RPC (`_receive_power_and_temperatures`, non fiable ordonné).

### Alimentation — `ship/rules/power_rules.gd`
- Un module éteint est à 0 W. Le Générateur allumé est toujours à l'optimum.
- Optimum : 100 W pour tous les modules, 10 W pour les couloirs.
- Tout autre module gagne `CHARGE_SPEED` W/s, plafonné à `Module.get_power_cap()`
  (cible du curseur, sinon optimum), si un voisin (`Module.neighbors`, relié par
  une porte) a atteint sa propre alimentation minimale. Sinon il garde sa charge.
  Au-dessus du plafond (cible baissée), il y redescend aussitôt.

### Température — `ship/rules/temperature_rules.gd`
- Machine : cible = puissance / `MACHINE_WATTS_PER_DEGREE`.
- Pièce : cible = `ROOM_BASE_TEMPERATURE` + machine / `ROOM_MACHINE_DIVISOR`.
- Chacune rejoint sa cible à une vitesse (°C/s) lente sous un petit écart, rapide
  au-delà d'un grand écart, linéaire entre les deux (`_approach`, constantes
  `MACHINE_*` / `ROOM_*`). Mise à jour au même pas que l'alimentation.
- N'a pour l'instant qu'un effet visuel. À 150 W (cible maximale), la machine
  plafonne à 75 °C et la pièce à 35 °C : ni chaleur (`HEAT_THRESHOLD`) ni givre
  (`FROST_THRESHOLD`) ne se déclenchent actuellement.

### Portes — `ship/door.gd`
- S'ouvrent quand un `CharacterBody2D` entre dans leur zone, se referment
  `open_duration` s après son départ. Décidées par l'hôte, appliquées par RPC.

### Réseau — `core/network.gd`, `player/player.gd`
- ENet, 8 joueurs max. L'hôte (id 1) fait autorité sur le vaisseau, les portes et
  l'alimentation ; chaque joueur fait autorité sur son personnage.
- Personnages créés par `PlayerSpawner` (fonction de spawn personnalisée) ; nom du
  nœud = id réseau.
- **Pas de `MultiplayerSynchronizer`** : un joueur envoie ses **ordres** (direction
  clavier, cible souris) quand ils changent, avec sa position de départ ; chaque
  machine simule le déplacement. Position finale à l'arrêt, correction toutes les
  `CORRECTION_INTERVAL` s pendant un déplacement.
  - `Player._compute_velocity` doit rester **identique sur toutes les machines**.
    Les ordres (flèches, cible souris) sont dans le repère du vaisseau, qui est
    celui de l'écran ; la vitesse renvoyée est tournée de l'orientation du
    vaisseau (`_get_ship_rotation`), car `move_and_slide` agit dans le repère du monde.
- **Joueur qui arrive** : `Network._on_peer_connected` lui envoie l'état du vaisseau,
  l'état des modules, leurs commandes (`Ship.send_module_controls`), les portes et
  les personnages. Toute nouvelle donnée
  synchronisée doit y être ajoutée.
- **État des modules** (`Module.state`) : décidé par l'hôte, envoyé en fiable par
  `Ship.send_module_states` (à tous, ou à un joueur qui arrive) → RPC
  `Ship._receive_module_states`. À rappeler après chaque changement d'état.
  Pour tester, `Ship.randomize_module_states` le tire au hasard à la création de
  la partie (`Network._create_server`).
- Seul le personnage local a caméra et `VisionLight` actives (brouillard propre à
  chaque joueur).

### Brouillard de guerre — `world/fog_of_war.gd`
- `CanvasModulate` à 0.25 ; l'énergie de `VisionLight` (`player/player.tscn`) doit valoir
  1 − cette valeur pour un éclairage normal dans la zone visible.
- Le fond étoilé (`world/starfield.gd`) est sur un `CanvasLayer` à part pour rester visible.

### Fenêtre de module — `ui/module_window.gd`
- Action `interact` (Espace, clic droit ; `project.godot`) dans la zone
  d'interaction d'un module (`Module.get_interaction_rect`, 2 × 2 cases au centre) :
  ouvre la fenêtre ; même action pour la fermer. Indication en bas d'écran.
- Gauche : levier marche / arrêt (manche en haut = allumé) puis curseur vertical
  de l'alimentation cible, chacun affiché selon les booléens du module ; colonne
  masquée si aucun. Curseur : rail noir, manette carrée (texture générée,
  `_make_grabber_texture`), repère « 100% » à droite à la hauteur de l'optimum
  (placement manuel, `_layout_slider`), cliquable pour y ramener la cible.
  Pendant un glissement, la cible part toutes les
  `SLIDER_SEND_INTERVAL` s, puis au relâchement.
- Centre : `Module.build_interface` (bouton d'exemple par défaut) ; pour des
  éléments propres à un type, la redéfinir dans son `module_*.gd`. Côté : état (« Intact » si `state` > `BROKEN_THRESHOLD`, sinon « Cassé »),
  consommation, températures de la machine et de la pièce.
- `ModuleWindow.is_open` immobilise le personnage local. Les boutons de la
  fenêtre ne prennent pas le focus (Espace sert à fermer).
- Locale à chaque joueur : seules les commandes passent par l'hôte.

### Mode debug — `core/debug_mode.gd`
- Actif dans l'éditeur et les exports « avec débogage », sauf avec `--release`.
  Utiliser `DebugMode.is_enabled()` pour tout affichage de développement.

## Points ouverts / pistes

- Déplacements non vérifiés par le serveur (triche possible). Les ordres de
  déplacement sont déjà envoyés : il resterait à faire simuler l'hôte seul.
- L'alimentation et la température partent 10 fois par seconde même sans changement :
  principal trafic restant.
- Pas de calcul d'itinéraire : un clic hors de l'axe d'une porte fait buter contre le mur.
- Pannes des modules à définir (`get_possible_failures`) ; `state` seulement affiché
  (valeurs aléatoires de test).
- Surchauffe et surtension à venir : le curseur permet de dépasser l'optimum
  (éclairage orangé), sans autre conséquence pour l'instant.
- Le mobilier est seulement dessiné : il ne bloque pas les déplacements.
- Effets de chaleur et de givre inaccessibles avec les puissances actuelles (voir
  Température) : seuils ou règles à revoir avec la surchauffe.
- Un message de connexion déjà affiché ne change pas de langue avant le suivant.
