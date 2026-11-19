# Fling a Dummy

## Overview
Jeu Roblox (projet Rojo) : on lance un mannequin de crash-test avec un canon à travers un parcours d'obstacles cassables.
Concept choisi à partir d'une étude de marché (vault Obsidian `C:\Users\tbarillon\Documents\Obsidian Vault\Jeu Roblox\`,
à lire : `La recette.md` et `05 - Concepts/Concepts candidats.md`).

## Rôles
Claude est **responsable du projet** : il tranche le design, le game feel, le périmètre et la technique, et signale chaque
choix en une ligne. L'utilisateur est **testeur** : on lui fournit un protocole (où se connecter, quoi faire, quoi
observer) et on attend son retour. Une action destructive ou hors du dépôt se confirme toujours avec lui.

## Où trouver quoi
| Sujet | Document |
|---|---|
| Règles du jeu, chiffres, feuille de route | `docs/design.md` |
| Tâche en cours : prototype v0 (modules, vérification) | `docs/prototype-v0.md` |
| Étude de marché, relevé quotidien | `market/` (section ci-dessous) |

## Rojo et Studio
- Mapping : `src/shared` → `ReplicatedStorage/Shared`, `src/server` → `ServerScriptService/Server`,
  `src/client` → `StarterPlayer/StarterPlayerScripts/Client`. Garder `default.project.json` synchronisé avec `src/`.
- `rojo serve` écoute sur le port **34900** (`servePort` du projet), hors de la plage de `CSGO_surf_combat` (34872+).
- Connexion : Studio en mode Edit, plugin Rojo, port 34900, Connect. Le plugin installé est le « CSGO autoconnect » : si
  une tâche CSGO réserve Studio, il peut reconnecter Studio à CSGO. Vérifier le port connecté avant un test.
- Le décor est généré par le code (`CourseBuilder`) : rien à sauvegarder depuis Studio.

## Roblox Studio MCP
- **Ne jamais modifier de scripts via le MCP** : le code se modifie uniquement dans `src/` (Rojo écrase Studio).
- **Appels courts** : jamais d'attente dans `execute_luau` (boucle, `task.wait` long), qui peut figer Studio. Lancer
  l'action, puis lire le résultat par un appel suivant (`get_console_output`).
- Piloter le jeu par attributs (`DebugLaunch` sur le joueur, en contexte `Server`) plutôt qu'en simulant l'input.

## Qualité
- Outils Rokit (`rokit.toml`) : `rojo`, `stylua`, `selene`, `luau-lsp`, `lune`. Installer avec `rokit install`.
- Après toute modification `.luau` : `bash tools/check.sh` (selene, stylua, luau-lsp, tests Lune). Lire la sortie
  complète, sans filtre. `--fix` applique le formatage.
- Tests unitaires Lune dans `tests/specs/*.spec.luau` (chaque spec retourne `function(T, Loader)`, cf. `tests/lib/`). La
  logique pure va dans `src/shared` pour être testable.
- `GameConfig.luau` est exclu de StyLua (`-- stylua: ignore`) : garder l'alignement en colonnes à la main.
- **Mesurer avant de promettre** : un effet de gameplay annoncé (distance, gains, temps) se mesure, et la valeur figure
  dans le compte rendu. Sans mesure, écrire « non mesuré ».

## Workflow
- Dépôt GitHub à créer par l'utilisateur. Tant qu'il n'existe pas : travailler sur `main` dans ce dossier.
- Une fois le dépôt en place : une branche et une PR par tâche vers `main`. Projet pas encore équipé pour les worktrees
  (pas de script) : proposer `/setup-worktrees` quand deux tâches devront tourner en parallèle.

## Marché (`market/`)
Collecteur des classements Roblox (API publiques) qui alimente le vault. Scripts Python, lancés avec `python -I` depuis
`market/` : `collect.py` (relevé → `data/roblox.db`), `analyze.py --obsidian "<vault>"` (rapport + note du jour),
`prepare_lot.py` / `frames.py` / `contact_sheet.py` (dissection de vidéos). Données, rapports et images restent hors de git.
Relevé quotidien : tâche planifiée Windows **« Roblox market daily »** (18 h) qui lance `market/run_daily.ps1`
(journal dans `market/logs/`).
