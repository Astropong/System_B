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
- **F11** (action `toggle_fullscreen`, autoload `Fullscreen`, `core/fullscreen.gd`) :
  plein écran / fenêtre. Fenêtre de base 1152 × 648 (valeur par défaut de Godot),
  étirée (`canvas_items`, `expand`) : un écran d'un autre format que 16:9 montre
  un peu plus de monde, sans importance.
- **F2** (mode debug, action `debug_next_ship`) : passer au vaisseau suivant.
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
  - Dans Git Bash, définir les variables (chemins) dans une commande à part
    avant `( … ) &` : une affectation chaînée par `&&` à la commande lancée en
    arrière-plan n'existe que dans celle-ci, et le client ne démarre pas.
  - Tests qui lisent la souris : le vrai curseur (l'utilisateur travaille à côté)
    fausse `get_mouse_position` ; tester plutôt la logique directement.
- **Performance** (la machine est chargée par ailleurs : comparer dans un même
  lancement, et répéter) :
  - calcul seul : `--headless --fixed-fps 60` (un pas physique par image, au
    plus vite) et temps entre images (`Time.get_ticks_usec`) ; ≈ 0,6 ms par pas
    (médiane) avec 6 vaisseaux ;
  - rendu : `Engine.max_fps = 0`, vsync coupée, médiane et 95e centile du
    temps d'image. Ne pas se fier à `Performance.TIME_PHYSICS_PROCESS` (somme
    des pas de l'image, dépend du nombre d'images par seconde) ;
  - réseau : `ENetConnection.pop_statistic` ; ≈ 0,8 ko/s par vaisseau et par
    client (alimentation et températures), 8 ko/s pour les 6 vaisseaux.
- Pas de tests automatisés : vérifier aussi en jeu, à deux instances pour tout ce
  qui touche au réseau.

## Architecture

Fichiers rangés **par fonctionnalité** (scène, script et shaders ensemble) :
- `core/` : réseau, langue, mode debug, plein écran ;
- `ship/` : vaisseau, autres vaisseaux (`fleet.gd`), collisions, portes, mode pilotage, `rules/` (alimentation,
  température), `modules/` (avec le volant du Pilotage) et leurs `shaders/` ;
- `player/` ; `world/` (fond étoilé, brouillard) ; `ui/` (interface) ;
  `i18n/` (traductions) ; `assets/` pour les futures ressources.
- Racine : `main.tscn` et fichiers du projet.

**Éditeur ouvert pendant des modifications de scripts** : il a déjà réenregistré
`main.tscn` avec des propriétés de modules faussées (`grid_position =
Color(...)`, `null`), empilant les salles. Vérifier `git diff main.tscn` avant
de commiter.

Après un déplacement, vérifier les chemins `res://` écrits dans les scripts
(`preload`) et les `.tscn`.

### Modules — `ship/modules/module.gd`, `ship/modules/module_*.gd`
- `Module` est abstraite (`@abstract`) ; un fichier par type (Pilotage, Infirmerie,
  Reacteur, Couloir, Radar, Generateur, Oxygene, Maintenance, Telecommunication,
  Laboratoire, Construction, Tourelles). Un type peut apparaître plusieurs fois.
- **À fournir par chaque type** : `get_type_id()`, `get_ideal_power()` (W),
  `get_possible_failures()`. `get_size()` (cases) vaut par défaut `DEFAULT_SIZE`
  (16 × 16) ; le Couloir la règle par instance (`size_cells`). `get_min_power()`
  vaut par défaut la moitié de l'optimale. `get_mass()` (kg) vaut par défaut
  `DEFAULT_MASS` (1 t).
- **Réacteur** (`module_reacteur.gd`) : tuyère sur le côté `nozzle_side` (réglé
  par instance, dessinée hors du mur), poussée en sens opposé, `MAX_THRUST`
  × alimentation / optimum s'il est opérationnel (allumé, au-dessus du
  minimum ; l'état cassé n'est pas pris en compte). Flamme au bout de la tuyère
  (nœud enfant `Flame`, vacillante) de longueur `FLAME_LENGTH` × `flame_level`,
  réglé à chaque pas par `Ship._apply_forces` (part de poussée fournie), rien
  sous `FLAME_MIN_LEVEL` (triangle trop plat, erreur de triangulation).
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
    vérifie qu'il est à bord (`Ship.has_crew_member`),
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
    déjà assombrie par le brouillard). La copie n'est visible qu'avec l'effet :
    chaque copie d'écran coûte ≈ 0,6 ms par image (toujours actives, elles
    prenaient ≈ 11 ms par image).
- Les valeurs reçues 10 fois par seconde (alimentation, températures) ne font
  redessiner la salle que si l'affichage change (jauge, températures arrondies).
  De même, ne pas réaffecter la place d'un nœud inchangée (`Ship._apply_forces`
  ne le fait pas à l'arrêt, ni `Fleet._process` si le vaisseau ancré ne bouge
  pas) : tous ses descendants seraient recalculés.

### Vaisseau — `ship/ship.gd`
- Place ses modules enfants selon leur `grid_position`, l'ensemble centré sur le
  vaisseau ; l'avant est à droite. Le jeu visera à construire son vaisseau en
  ajoutant des modules sur la grille : la forme n'a pas à être un rectangle.
  Disposition actuelle : trois colonnes de salles séparées par deux couloirs
  verticaux de 8 × 64 cases ; réacteur arrière dans la colonne de gauche ;
  réacteurs latéraux par paires avant / arrière (`ReacteurHautArriere`,
  `ReacteurBasArriere` collés à la colonne de gauche, `ReacteurHautAvant` collé
  à celle de droite, `ReacteurBasAvant` dans son coin bas) : une paire du même
  côté pousse sans tourner, une paire en diagonale tourne sans pousser. Pas de
  réacteur à l'avant.
- **Tous les vaisseaux sont enfants de `Ships`** (`ship/fleet.gd`, repère de
  l'espace) : celui de départ des joueurs (`Ships/Ship`, dans `main.tscn`) et
  les autres, créés et retirés à la
  volée par l'hôte (`Fleet.spawn_ship(description)`, `Fleet.remove_ship`, refusé
  si un équipage est à bord),
  recréés chez tous (y compris les joueurs qui arrivent) par le
  `MultiplayerSpawner` `Ships/ShipSpawner`. Description : position, modules
  ([type `Module.ModuleType`, place, propriétés parmi `MODULE_PROPERTIES`]),
  rotation et vitesses facultatives ; seul ce dictionnaire passe sur le réseau.
  `Ships` est le repère de l'espace (voir Vaisseau ancré) : positions en espace.
  Au départ, `STARTING_SHIPS` (5 vaisseaux immobiles de 4 modules) autour du
  nôtre. Tous
  sont dans le groupe `Ship.GROUP` : `Network` les synchronise tous (joueur
  qui arrive, états aléatoires, départ d'un pilote). Après un `spawn_ship`,
  envoyer l'état des modules (`send_module_states`).
- **Collisions entre vaisseaux** (`ship/ship_collisions.gd`, nœud
  `ShipCollisions`, hôte seul, après le déplacement des vaisseaux) : modules =
  rectangles orientés, paire la plus enfoncée (axes séparateurs), impulsion de
  corps rigides (`RESTITUTION`, masse et inertie de chaque vaisseau),
  écartement selon la masse. Les deux modules touchés perdent
  `DAMAGE_PER_SPEED` × vitesse d'impact (m/s) d'état, au-delà de
  `MIN_DAMAGE_SPEED`. Envoi fiable du mouvement (`Ship.send_motion`, au plus
  toutes les `MOTION_SEND_INTERVAL` s par vaisseau : en poussée continue, un
  petit choc a lieu à chaque pas ; l'envoi retardé part ensuite) et des
  états après un choc ; les autres machines voient un court chevauchement.
- Deux modules qui partagent au moins `MIN_SHARED_WALL` cases de mur sont voisins,
  avec une porte au milieu de la partie commune (verticale ou pivotée de 90°).
- Le nœud `Structure` (généré, non sauvegardé) contient les
  `LightOccluder2D` (murs fusionnés par droite : `_merge_wall_lines`) et les `Door`.
- **Physique de l'équipage par vaisseau** (`Ship.get_crew_space`) : chaque
  vaisseau a son propre espace `PhysicsServer2D` (jamais simulé, seulement
  des tests de déplacement), où murs (`_add_crew_wall`), battants des portes
  et personnages sont des corps statiques en coordonnées du vaisseau. Le monde
  de Godot ne contient aucun mur : le déplacement de l'équipage ne dépend ni
  de la place du vaisseau dans la scène, ni de sa vitesse, ni de l'ancrage,
  sur aucune machine (l'hôte simule correctement les personnages des autres
  vaisseaux). Les corps quittent l'espace dans `_exit_tree` ; le vaisseau le
  libère dans le sien (après ses enfants), pas à la destruction
  (`NOTIFICATION_PREDELETE` précède la sortie de l'arbre des enfants).
- **Mouvement à inertie, physique stricte**, **simulé par chaque joueur**
  (`_apply_forces`) : `velocity` (px/s, espace, vitesse du centre de masse) et
  `angular_speed` (°/s) se conservent sans poussée (valeurs de départ en
  `@export`, nulles : immobile au début). Échelle : `PIXELS_PER_METER`
  (1 case = 1 m). **Vitesse maximale** `MAX_SPEED_KMH` (`MAX_SPEED` en px/s),
  bornée à chaque pas, chocs compris : le jeu suppose qu'elle n'est jamais
  dépassée (collisions entre vaisseaux, précision).
  - Chaque réacteur pousse là où il est : force / `get_total_mass` sur le centre
    de masse (`get_center_of_mass`), couple = poussée × `get_torque_arm` (bras de
    levier signé autour du centre de masse) / `get_moment_of_inertia` (modules =
    plaques). Le vaisseau tourne autour de son centre de masse (l'origine du
    nœud, centre de la grille, tourne autour de lui).
  - Commandes `thrust_command` (direction voulue, repère de l'espace, longueur ≤ 1)
    et `turn_command` (−1 à 1, part du couple maximal dans ce sens,
    `get_max_angular_acceleration(sens)`). `_allocate_throttles` répartit entre
    les réacteurs (part 0 à 1 chacun) : visée = toute la poussée possible dans
    la direction voulue, rien sur le côté, le couple demandé ; solution la plus
    proche aux moindres carrés (couple pondéré par `TORQUE_WEIGHT`). Un réacteur
    hors de l'axe fait aussi tourner : le régulateur du pilote compense.
  - Un joueur demande les commandes (`request_controls`) ; l'hôte les borne,
    les refuse si le joueur n'est pas à bord (`has_crew_member`) ou sans
    pilotage alimenté, et les annule si celui-ci perd son
    alimentation (`set_controls`), puis envoie commandes, position, orientation
    et vitesses à tous (`_receive_motion`). Chaque machine calcule les forces
    avec l'alimentation qu'elle connaît. L'hôte
  corrige aussi position, orientation et vitesses toutes les `MOTION_SYNC_INTERVAL` s
  (`_receive_position`). Place reçue avancée du temps de trajet du message
  (`_message_age` : moitié de l'aller-retour ENet), écart résorbé en douceur,
  ou d'un coup au-delà de `CORRECTION_SNAP_DISTANCE` / `CORRECTION_SNAP_ANGLE`
  (seuils agrandis du chemin parcouru en `CORRECTION_SNAP_TIME` s).
- Les personnages sont enfants du nœud `Crew` de leur vaisseau (créé par
  `Ship._ready` s'il manque) : coordonnées dans le repère du vaisseau
  (qui tourne). `Player.get_ship()`, `Player.get_local()`. La caméra du joueur tourne avec le vaisseau (`ignore_rotation`
  désactivé dans `player.tscn`) : le vaisseau reste droit à l'écran, l'espace tourne.
- **Vaisseau ancré** (`anchored`, `Ship.anchor`, un seul par machine) : celui du
  joueur local (`make_anchor`, appelé à sa création et à chaque changement de
  vaisseau ; `Ship` est coché dans `main.tscn` pour le menu et le serveur
  dédié). Son nœud ignore son parent (`top_level`) et reste immobile à l'origine de la scène ; sa place
  dans l'espace est `space_position` / `space_rotation` (pour les autres
  vaisseaux, ces propriétés sont leur `position` / `rotation`). L'ancrage est
  local à chaque machine : réseau et règles ne connaissent que l'espace. C'est l'espace
  qui bouge : `Ships` (`Fleet`) est
  placé à chaque image à l'inverse de `get_interpolated_space_transform()`
  (interpolation faite à la main, coupée sur `Fleet`), et le fond étoilé en
  tient compte. Raison : à grande vitesse (centaines de px par pas), un
  vaisseau qui bouge dans la scène casse la physique de l'équipage (murs
  restés en arrière), l'éclairage (lumière et ombres interpolées
  différemment des salles) et la cible de la souris (vue interpolée, vaisseau
  au pas physique). Ancré, rien de cela ne dépend plus de la vitesse
  (vérifié hôte et client jusqu'à 10 000 km/h en tournant).
  - **Toujours raisonner en espace** pour les vaisseaux : `space_position`,
    `space_rotation`, `get_space_transform()` ; jamais `position`,
    `global_position` ou `global_transform` d'un vaisseau pour la physique
    entre vaisseaux, les commandes ou le réseau. Un saut :
    `_reset_space_interpolation()`.
  - Rien de physique dans le monde pour l'intérieur d'un vaisseau (ni corps
    ni `Area2D`) : utiliser l'espace de l'équipage ou des tests dans le
    repère du vaisseau (voir Physique de l'équipage, Portes).
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

### Mode pilotage — `ship/piloting.gd`, `ship/modules/steering_wheel.gd`
- Fenêtre du Pilotage (`ModulePilotage.build_interface`) : volant cliquable
  (`SteeringWheel`, couleur `HOVER_COLOR` et agrandissement `HOVER_SCALE` au
  survol, appliqué dans le dessin car un conteneur remet `scale` à 1) →
  `Piloting.enter()` (nœud `HUD/Piloting`, local à chaque joueur).
- En `TRANSITION_TIME` s, la caméra du joueur (restée enfant du personnage) se
  décale sur un point `LOOK_AHEAD` cases devant le centre du vaisseau (0 pour
  le moment : vaisseau centré), annule sa
  rotation et dézoome de `ZOOM_FACTOR` (`_apply_camera`, tours entiers retirés
  avec `_turns`).
- **Vue « coque »** pendant tout le mode (transitions comprises) : `Ship.hull_view`
  (statique, local) fait dessiner chaque vaisseau en silhouette (salles avec
  murs, tuyères `ModuleReacteur.get_nozzle_polygon`) par son nœud `Hull`,
  texturée par `ship/shaders/hull_metal.gdshader` (`Ship.HULL_SHADER` : métal
  gris brossé en plaques, dans le repère du vaisseau, détails trop fins
  estompés selon le zoom), et les flammes (`draw_flame_on`) par son enfant
  `Flames`. Tous deux non éclairés, donc hors brouillard ; salles et
  `Structure` masquées.
- **Statistiques** à gauche de l'écran pendant le mode (`_create_stats`,
  `_update_stats`, marge `STATS_MARGIN`) : pour l'instant la vitesse du
  vaisseau en km/h (`SPEED_TEXT`). Textes composés : `tr(...) % valeur`,
  traduction automatique des labels coupée.
- **Souris seulement** (le clavier ne pilote pas). Bouton gauche maintenu :
  direction centre de l'écran → souris (pas vaisseau → souris : la caméra vise
  devant le vaisseau et tournerait la cible avec lui), arrondie à
  `THRUST_ANGLE_STEP`, montrée par un trait et un cercle (`_draw`, comme la
  cible du personnage). Le vaisseau pousse dans cette direction et y tourne son
  avant. Bouton relâché : ni poussée ni rotation commandée, stabilisation
  (rotation annulée). Régulateur
  `_turn_command` : vitesse visée permettant de s'arrêter sur la cible
  (`BRAKING_MARGIN`), rattrapée en `TURN_RESPONSE` s, arrondie en précision
  relative (`TURN_STEPS_PER_DOUBLING`, rien sous `TURN_MIN_COMMAND`) ;
  accélérations propres à chaque sens (freinage avec le sens opposé à l'écart).
  Sans poussée, le vaisseau garde sa vitesse ; sans réacteur avant, freiner une
  marche avant demande de se retourner.
  Commandes demandées à l'hôte au plus toutes les `SEND_INTERVAL` s. Clic droit :
  sortie. `Piloting.is_active()` (transitions comprises) immobilise le personnage
  et bloque la fenêtre de module.
- Sans module de pilotage à son alimentation minimale (`Ship.is_helm_powered`),
  aucune commande : le pilote n'envoie rien (avertissement `UNPOWERED_TEXT`),
  l'hôte refuse les demandes et annule les commandes en cours, le vaisseau garde
  son mouvement (inertie). Le mode reste accessible.

### Portes — `ship/door.gd`
- S'ouvrent quand un `Player` de `Crew` entre dans leur zone, se
  referment `open_duration` s après son départ. Décidées par l'hôte, appliquées
  par RPC. Zone testée à la main à chaque pas (`_count_bodies_near`, repère du
  vaisseau, `DETECTION_DEPTH` + rayon du personnage), pas par une `Area2D`.
  Battant : forme dans l'espace de l'équipage, désactivée porte ouverte.

### Réseau — `core/network.gd`, `player/player.gd`
- ENet, 8 joueurs max. L'hôte (id 1) fait autorité sur le vaisseau, les portes et
  l'alimentation ; chaque joueur fait autorité sur son personnage.
- Personnages créés, déplacés et retirés par l'hôte par RPC (`Network._create_player`,
  `_transfer_player`, `_remove_player`, chemins absolus des vaisseaux), pas par
  un `MultiplayerSpawner` (un seul parent possible, et déplacer un nœud qu'il a
  créé casse son suivi). Nom du nœud = id réseau. Ils apparaissent dans
  `Ships/Ship`, au centre du premier module de pilotage, espacés de
  `Ship.SPAWN_SPACING` (`Ship.get_spawn_position`).
- **Changer de vaisseau** : `Network.request_transfer(vaisseau)` → l'hôte
  annule les commandes du joueur dans l'ancien, choisit une place d'apparition
  et envoie `_transfer_player` → `Player.transfer_to` (reparenté, ordres
  annulés ; joueur local : nouveau vaisseau ancré). Pour l'instant seulement
  en mode debug : **F2** (action `debug_next_ship`) = vaisseau suivant.
- Chaque joueur peut piloter le vaisseau où il se trouve : `Piloting` et
  `ModuleWindow` suivent le vaisseau du personnage local (plus de vaisseau
  réglé dans la scène). Le mode pilotage s'arrête si le personnage change de vaisseau.
- Commandes : actions `move_left/right/up/down` (`project.godot`) = flèches, ZQSD
  et WASD, liées à la lettre de la touche (`keycode`), pas à sa place ; bouton
  gauche maintenu : aller vers la souris, arrêt au relâchement.
- Légère inertie : `Player.move_velocity` (repère du vaisseau) rejoint la vitesse
  voulue à `ACCELERATION` près ; vers une cible, la vitesse voulue baisse pour
  s'arrêter dessus. Reprise de la vitesse après glissement contre les murs
  (`Player._move` : `PhysicsServer2D.body_test_motion` dans l'espace de
  l'équipage, `MAX_SLIDES` glissements ; `Player` est un `Node2D`, pas un
  `CharacterBody2D`). Elle part avec chaque ordre (`_receive_order`,
  `_receive_state_from_host`).
- **Pas de `MultiplayerSynchronizer`** : un joueur envoie ses **ordres** (direction
  clavier, cible souris) quand ils changent, avec sa position de départ ; chaque
  machine simule le déplacement. Position finale à l'arrêt, correction toutes les
  `CORRECTION_INTERVAL` s pendant un déplacement.
  - `Player._compute_velocity` doit rester **identique sur toutes les machines**.
    Tout y est dans le repère du vaisseau (ordres, position, vitesse), qui
    est celui de l'écran.
- **Joueur qui arrive** : `Network._on_peer_connected` lui envoie les personnages
  existants (avant le sien), puis l'état des vaisseaux,
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
  Le calque ne suit pas la vue tel quel (`follow_viewport_enabled` coupé au
  lancement) : avant chaque rendu (`frame_pre_draw`, `_follow_view`), il reprend
  la rotation de la vue dans l'espace, pas son zoom ; son centre avance du
  déplacement de la vue dans l'espace (vue × inverse de la place interpolée
  du vaisseau ancré) × le zoom (étoiles au même défilement que les vaisseaux, sans
  glissement quand seul le zoom change), ramené dans une période de
  `WRAP_TILES` tuiles (motif répété : pas de perte de précision lors des
  longs trajets). Étoiles de taille et densité
  constantes, nombre de tuiles constant (en suivant le zoom, le dézoom ×20
  redessinait des milliers de tuiles : ≈ 0,7 s par image).

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
- `ModuleWindow.is_open` immobilise le personnage local ; statique, remis à faux
  dans `_exit_tree` (scène rechargée quand l'hôte part). Les boutons de la
  fenêtre ne prennent pas le focus (Espace sert à fermer).
- Locale à chaque joueur : seules les commandes passent par l'hôte.

### Mode debug — `core/debug_mode.gd`
- Actif dans l'éditeur et les exports « avec débogage », sauf avec `--release`.
  Utiliser `DebugMode.is_enabled()` pour tout affichage de développement.

## Points ouverts / pistes

- Déplacements non vérifiés par le serveur (triche possible). Les ordres de
  déplacement sont déjà envoyés : il resterait à faire simuler l'hôte seul.
- L'alimentation et la température partent 10 fois par seconde même sans changement :
  principal trafic restant (≈ 0,8 ko/s par vaisseau et par client, mesuré).
- Collisions entre vaisseaux fiables jusqu'à ≈ 1 700 km/h de vitesse relative ;
  jusqu'à `MAX_SPEED_KMH` × 2 de vitesse relative, deux vaisseaux peuvent
  s'enfoncer trop ou se traverser (pas de détection continue).
- Pas de calcul d'itinéraire : viser hors de l'axe d'une porte fait buter contre le mur.
- Pannes des modules à définir (`get_possible_failures`) ; `state` seulement affiché
  (valeurs aléatoires de test).
- Surchauffe et surtension à venir : le curseur permet de dépasser l'optimum
  (éclairage orangé), sans autre conséquence pour l'instant.
- Le mobilier est seulement dessiné : il ne bloque pas les déplacements.
- Pilotage : plusieurs joueurs peuvent piloter à la fois (dernière demande
  gagnante ; si le dernier pilote se déconnecte, `Ship.release_controls_of`
  annule ses commandes). En vue dézoomée, le brouillard de guerre assombrit
  presque tout le vaisseau.
- Effets de chaleur et de givre inaccessibles avec les puissances actuelles (voir
  Température) : seuils ou règles à revoir avec la surchauffe.
- Un message de connexion déjà affiché ne change pas de langue avant le suivant.
