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

## Lancer et tester

- Scène principale : `main.tscn`. Au lancement, un menu propose **Héberger** ou
  **Rejoindre** (adresse par défaut `127.0.0.1`, port UDP **7777**).
- Arguments de lancement reconnus : `--host`, `--join`, `--join=<ip>`, `--release`.
- Serveur dédié : étiquette de fonctionnalité `dedicated_server` (export en mode
  « Serveur dédié », ou étiquette ajoutée à une instance de lancement), de préférence
  avec `--headless`. Il crée la partie sans menu ni personnage.
- Test multijoueur local : menu Débogage → personnalisation des instances de lancement,
  2 instances (`--host` / `--join`) ou 3 (serveur dédié + 2 × `--join`).
- Pas de tests automatisés pour l'instant : vérifier en jeu, à deux instances pour
  tout ce qui touche au réseau.

## Structure

| Fichier | Rôle |
|---|---|
| `main.tscn` | Scène principale : fond, vaisseau, réseau, brouillard, HUD/menu |
| `modules/module.gd` | Classe abstraite `Module` (`@abstract`) |
| `modules/module_*.gd` | Un fichier par type : Pilotage, Infirmerie, Reacteur, Couloir, Radar, Generateur |
| `ship.gd` | `Ship` : aligne les modules, génère murs/ombres/portes, avance, applique l'alimentation |
| `door.gd` | `Door` : porte coulissante entre deux modules |
| `power_rules.gd` | `PowerRules` : règles d'alimentation électrique |
| `temperature_rules.gd` | `TemperatureRules` : règles de température |
| `modules/heat_haze.gdshader` / `frost.gdshader` | Effets de chaleur et de gel des salles |
| `player.gd` / `player.tscn` | Personnage (rond), caméra et lumière de vision |
| `network.gd` | Réseau ENet : menu, connexion, apparition des joueurs, serveur dédié |
| `fog_of_war.gd` | `CanvasModulate` du brouillard de guerre (activé en jeu seulement) |
| `starfield.gd` | Fond étoilé infini par tuiles, sur un calque séparé |
| `debug_mode.gd` | `DebugMode.is_enabled()` : affichages réservés au développement |

## Architecture

### Modules (`modules/module.gd`)
- **Caractéristiques du type** (méthodes à fournir par chaque classe fille) :
  `get_type_id()`, `get_ideal_power()` (W), `get_size()` (cases),
  `get_possible_failures()` (vide pour l'instant). `get_min_power()` vaut par défaut
  la moitié de l'optimale et peut être redéfinie.
- **Valeurs d'instance** : `power_supplied` (W), `temperature` (°C, entier, −273 à 227),
  `state` (0–1).
- Tailles actuelles : 16×16, sauf Couloir 8×16. Un type peut apparaître plusieurs fois.
- Dessin : sol quadrillé, schéma du type (`_draw_details`, dans une boîte de référence
  240×240 agrandie), murs avec ouvertures, nom, jauge de batterie (debug seulement).
- **Éclairage** selon l'alimentation, appliqué via `self_modulate` + 4 lampes dessinées :
  sous le minimum → rouge 50 % ; entre minimum et optimum → blanc 50–90 % avec
  clignotements ; à l'optimum → blanc 100 % ; au-delà → légèrement orangé 100 %.
  Volontairement **pas de `Light2D`** dans les salles : elles rendraient les pièces
  visibles à travers les murs et casseraient le brouillard de guerre.

### Vaisseau (`ship.gd`)
- Les modules enfants de `Ship` sont alignés de gauche (arrière) à droite (avant), dans
  l'ordre de la scène : Generateur, Reacteur, Couloir, Couloir2, Pilotage.
- Le nœud `Structure` (généré, non sauvegardé) contient les collisions des murs, les
  `LightOccluder2D` et une `Door` par cloison (ouverture de 2 cases).
- Avance vers la droite à `speed` = 10 px/s (hôte uniquement, synchronisé par `ShipSync`).
- Les joueurs sont enfants de `Ship/Crew` : ils avancent avec le vaisseau et leurs
  coordonnées sont dans le repère du vaisseau.

### Alimentation (`power_rules.gd`)
- Appliquée par l'hôte 10 fois par seconde, puis envoyée en un seul RPC
  (`Ship._receive_power`, non fiable ordonné).
- Règle 1 : le Générateur est toujours à l'optimum.
- Règle 2 : tout autre module gagne 20 W/s, jusqu'à 120 % de son optimum, si un voisin
  a atteint sa propre alimentation minimale. Sans voisin alimenté, il garde sa charge.
- Voisins = module précédent et suivant (modules alignés).
- Envoyée avec les températures dans le RPC `Ship._receive_modules_state`.

### Température (`temperature_rules.gd`)
- Appliquée par l'hôte juste après l'alimentation.
- Règle 1 : tout module est à 0 °C par défaut.
- Règle 2 : +1 °C par tranche de 10 W d'alimentation (`0 + floor(W / 10)`).
- Effets visuels (calques enfants du module, créés dans `_create_climate_effects`) :
  au-dessus de 40 °C, déformation par la chaleur (lit l'écran via un `BackBufferCopy`,
  `unshaded` pour ne pas réassombrir) ; en dessous de 10 °C, givre depuis les murs.
  Intensité croissante jusqu'à 100 °C / −20 °C.

### Portes (`door.gd`)
- S'ouvrent quand un `CharacterBody2D` entre dans leur zone de détection, restent
  ouvertes tant qu'il y est, se referment `open_duration` = 3 s après.
- Décidées par l'hôte, appliquées partout par RPC `_apply_state`. Un joueur qui arrive
  reçoit l'état courant (`Ship.send_door_states`).

### Réseau (`network.gd`)
- ENet, 8 joueurs max. L'hôte (id 1) fait autorité sur le vaisseau, les portes et
  l'alimentation ; **chaque joueur fait autorité sur la position de son personnage**.
- Personnages créés par `PlayerSpawner` avec une fonction de spawn personnalisée
  (id + position envoyés par l'hôte) ; nom du nœud = id réseau.
- Seul le personnage local a caméra et `VisionLight` actives (brouillard propre à
  chaque joueur). Les autres joueurs prennent une couleur de `OTHER_PLAYER_COLORS`.

### Brouillard de guerre
- `FogOfWar` (`CanvasModulate`) à 0.25 = assombrissement de 75 %.
- `VisionLight` du joueur avec ombres ; son énergie (0.75) doit valoir 1 − la valeur
  du brouillard pour garder un éclairage normal dans la zone visible.
- Le fond étoilé est sur un `CanvasLayer` à part (`Background`) pour rester visible.

### Mode debug (`debug_mode.gd`)
- Actif dans l'éditeur et les exports « avec débogage » ; désactivé en export release
  ou avec l'argument `--release`. Utiliser `DebugMode.is_enabled()` pour tout
  affichage de développement.

## Points ouverts / pistes

- Déplacements non vérifiés par le serveur (triche possible) : à rendre autoritaire
  côté serveur si le jeu devient public.
- Pas de calcul d'itinéraire : un clic hors de l'axe d'une porte fait buter contre le mur.
- Pannes des modules à définir (`get_possible_failures`).
- État des modules pas encore utilisé par les règles ; la température n'a encore
  qu'un effet visuel.
- Mobilier des salles agrandi proportionnellement : certains éléments paraissent
  surdimensionnés.
