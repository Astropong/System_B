# System B — contexte du projet

Jeu spatial 2D vu de dessus, multijoueur, dans un vaisseau modulaire.
Moteur : **Godot 4.7.2**, GDScript, rendu Forward+ (Direct3D 12 sous Windows).
Dépôt : https://github.com/Astropong/System_B (branche `main`).

## Conventions

- Commentaires, textes du jeu et messages de commit **en français**.
- Indentation par **tabulations** dans les fichiers `.gd`.
- Commentaires de documentation `##` en tête de chaque script et des fonctions publiques.
- 1 case = **48 px** = diamètre du personnage (`Module.CELL_SIZE`). Les tailles se
  raisonnent en cases.
- Valeurs réglables regroupées en constantes en haut des fichiers, ou en `@export`.
  Ce fichier cite leurs **noms** : lire la valeur dans le code.

## Lancer et tester

- Scène principale : `main.tscn`. Menu **Héberger** / **Rejoindre** (adresse par
  défaut `127.0.0.1`, port UDP 7777).
- Arguments : `--host`, `--join`, `--join=<ip>`, `--release` (désactive le mode debug).
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
- Réseau : un hôte et un client `--headless` lancés à quelques secondes d'écart ;
  trafic lu avec `ENetConnection.pop_statistic(HOST_TOTAL_SENT_DATA, ...)`.
- Pas de tests automatisés : vérifier aussi en jeu, à deux instances pour tout ce
  qui touche au réseau.

## Architecture

### Modules — `modules/module.gd`, `modules/module_*.gd`
- `Module` est abstraite (`@abstract`) ; un fichier par type (Pilotage, Infirmerie,
  Reacteur, Couloir, Radar, Generateur). Un type peut apparaître plusieurs fois.
- **À fournir par chaque type** : `get_type_id()`, `get_ideal_power()` (W),
  `get_size()` (cases), `get_possible_failures()`. `get_min_power()` vaut par défaut
  la moitié de l'optimale.
- **Valeurs d'instance** : `power_supplied` (W), `temperature` (°C, entier),
  `state` (0–1).
- Dessin : sol quadrillé, schéma du type (`_draw_details`, boîte de référence
  `DETAILS_REFERENCE` agrandie), murs, nom, jauge et température (debug seulement).
- **Éclairage** selon l'alimentation (`_update_lighting`) : rouge sous le minimum,
  blanc atténué avec clignotements jusqu'à l'optimum, orangé au-delà. Appliqué par
  `self_modulate` + 4 lampes dessinées. **Pas de `Light2D`** dans les salles : elles
  rendraient les pièces visibles à travers les murs (brouillard de guerre cassé).
- **Effets de température** (`_create_climate_effects`, shaders
  `heat_haze.gdshader` / `frost.gdshader`) : déformation au-dessus de
  `HEAT_THRESHOLD`, givre en dessous de `FROST_THRESHOLD`.
  - La déformation relit l'écran : `BackBufferCopy` en mode **viewport** (le mode
    rectangle laisse des bandes noires) et `render_mode unshaded` (l'image lue est
    déjà assombrie par le brouillard).

### Vaisseau — `ship.gd`
- Aligne ses modules enfants de gauche (arrière) à droite (avant), dans l'ordre de
  la scène.
- Le nœud `Structure` (généré, non sauvegardé) contient les collisions des murs, les
  `LightOccluder2D` (une seule fois par cloison partagée) et une `Door` par cloison.
- Avance à `speed`, **simulé par chaque joueur**. Changer `speed` sur l'hôte envoie
  position + vitesse aux autres ; l'hôte corrige aussi la position toutes les
  `MOTION_SYNC_INTERVAL` s, écart résorbé en douceur.
- Les joueurs sont enfants de `Ship/Crew` : coordonnées dans le repère du vaisseau.
- L'hôte applique alimentation puis température `PowerRules.UPDATE_RATE` fois par
  seconde, et envoie tout en un RPC (`_receive_modules_state`, non fiable ordonné).

### Alimentation — `power_rules.gd`
- Le Générateur est toujours à l'optimum.
- Tout autre module gagne `CHARGE_SPEED` W/s, jusqu'à `MAX_CHARGE_RATIO` × son
  optimum, si un voisin (module précédent ou suivant) a atteint sa propre
  alimentation minimale. Sinon il garde sa charge.

### Température — `temperature_rules.gd`
- `BASE_TEMPERATURE` (0 °C) + 1 °C par tranche de `WATTS_PER_DEGREE` W.
- N'a pour l'instant qu'un effet visuel.

### Portes — `door.gd`
- S'ouvrent quand un `CharacterBody2D` entre dans leur zone, se referment
  `open_duration` s après son départ. Décidées par l'hôte, appliquées par RPC.

### Réseau — `network.gd`, `player.gd`
- ENet, 8 joueurs max. L'hôte (id 1) fait autorité sur le vaisseau, les portes et
  l'alimentation ; chaque joueur fait autorité sur son personnage.
- Personnages créés par `PlayerSpawner` (fonction de spawn personnalisée) ; nom du
  nœud = id réseau.
- **Pas de `MultiplayerSynchronizer`** : un joueur envoie ses **ordres** (direction
  clavier, cible souris) quand ils changent, avec sa position de départ ; chaque
  machine simule le déplacement. Position finale à l'arrêt, correction toutes les
  `CORRECTION_INTERVAL` s pendant un déplacement.
  - `Player._compute_velocity` doit rester **identique sur toutes les machines**.
- **Joueur qui arrive** : `Network._on_peer_connected` lui envoie l'état du vaisseau,
  des portes et des personnages. Toute nouvelle donnée synchronisée doit y être ajoutée.
- Seul le personnage local a caméra et `VisionLight` actives (brouillard propre à
  chaque joueur).

### Brouillard de guerre — `fog_of_war.gd`
- `CanvasModulate` à 0.25 ; l'énergie de `VisionLight` (player.tscn) doit valoir
  1 − cette valeur pour un éclairage normal dans la zone visible.
- Le fond étoilé (`starfield.gd`) est sur un `CanvasLayer` à part pour rester visible.

### Mode debug — `debug_mode.gd`
- Actif dans l'éditeur et les exports « avec débogage », sauf avec `--release`.
  Utiliser `DebugMode.is_enabled()` pour tout affichage de développement.

## Points ouverts / pistes

- Déplacements non vérifiés par le serveur (triche possible). Les ordres de
  déplacement sont déjà envoyés : il resterait à faire simuler l'hôte seul.
- L'alimentation et la température partent 10 fois par seconde même sans changement :
  principal trafic restant.
- Pas de calcul d'itinéraire : un clic hors de l'axe d'une porte fait buter contre le mur.
- Pannes des modules à définir (`get_possible_failures`) ; `state` pas encore utilisé.
- Mobilier des salles agrandi proportionnellement : certains éléments paraissent
  surdimensionnés.
