# Fling a Dummy

## Overview
Jeu Roblox (projet Rojo) : on s'entraîne, on lance un mannequin de crash-test sur une piste d'obstacles cassables et on
gagne des mannequins de collection. Concept choisi à partir d'une étude de marché (vault Obsidian
`C:\Users\tbarillon\Documents\Obsidian Vault\Jeu Roblox\`, à lire : `La recette.md` et `05 - Concepts/Concepts candidats.md`).
Dépôt : `Many0nne/FlingADummy` (privé).

## Rôles
Claude est **responsable du projet et du code** : il tranche le design, le game feel, le périmètre et la technique, signale
chaque choix en une ligne, crée les issues et merge les PR. L'utilisateur est **testeur** : on lui fournit un protocole
(où se connecter, quoi faire, quoi observer) et on attend son retour. Une action destructive ou hors du dépôt se confirme
toujours avec lui.

## Jeux de référence
Le style, l'interface et la boucle se calent **franchement** sur les jeux disséqués (vault, `04 - Jeux disséqués/` 01, 02,
09) : textures en briques à tenons, couleurs saturées, grammaire des menus, cinématique de lancer, tirage « 1 en N ». Avant
toute tâche de design, d'interface ou d'art, regarder les images (`C:\Users\tbarillon\.t3\scratch\2026-11-19-a-l-heure-actuelle-on-46b1211b\roblox-market\dissection\<jeu>\`,
planches 3 × 3 dans `.git/fad-tools/sheets/` du checkout principal) et comparer côte à côte dans la PR. La v0.2 a été
rejetée pour un style inventé.

## Où trouver quoi
| Sujet | Document |
|---|---|
| Règles du jeu, chiffres, feuille de route | `docs/design.md` |
| Refonte en cours (v0.3) : epic et tâches | issue #9 (tâches #10 à #15) |
| v0.2 (historique : décisions, mesures) | `docs/v0.2.md` |
| Prototype v0 (historique : premier plan, premières mesures) | `docs/prototype-v0.md` |
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

## Workflow d'une tâche
1. Une tâche = une issue = une branche `feature|fix|tooling/<n>-<slug>` = un worktree `worktrees/<slug>/` (ignoré par
   git). Script de worktree et verrou Studio : en cours (issue d'outillage) ; d'ici là `git worktree add` et la règle
   « Studio partagé » ci-dessous.
2. Implémenter, puis `bash tools/check.sh` dans le worktree ; vérifier en jeu via le MCP Studio si le changement le demande.
3. Besoin de l'avis de l'utilisateur (gameplay, rendu, UI) : protocole de test (connexion Studio, étapes, quoi observer),
   puis attendre son retour.
4. Fonctionnement vérifié (et validé par l'utilisateur si l'étape 3 s'appliquait) : commit, push, PR vers `main` avec
   `Closes #<n>`.
5. **Merger soi-même**, sans attendre d'ordre (règle propre à ce dépôt, elle remplace le « pas de merge sans ordre
   explicite » des consignes globales) : CI verte, puis `gh pr merge <n> --merge --delete-branch`. Si l'étape 3
   s'appliquait, seulement après le retour positif de l'utilisateur. CI rouge : corriger, ne pas merger. Puis supprimer le
   worktree et fermer le thread (settle).
- Push : le dépôt local utilise `gh auth git-credential` (config git locale) ; ne pas la retirer.
- **Rubrique « Trouvé »** : chaque point qui mérite une suite (bug, amélioration, dette, outillage) devient une issue,
  créée sans demander, avec ses labels (chercher d'abord une issue ouverte qui le couvre). Le compte rendu donne les
  numéros ; seules les remarques mineures restent de simples mentions.
- Labels : `gameplay`, `game-feel`, `ui`, `economie`, `direction-artistique`, `collection`, `tooling`, `backlog`.

## Studio et Blender partagés
- Une seule place Studio (placeId 88580736516669) : une seule tâche à la fois s'en sert. Tant que le verrou n'existe pas,
  annoncer dans le thread qu'on prend Studio, vérifier le port connecté, rendre la main vite. Faire d'abord tout ce qui se
  passe de Studio (code, `check.sh`, tests Lune, Blender).
- Blender : la session avec interface (MCP `blender`) sert une tâche à la fois ; les traitements par script passent par
  `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup` (parallélisable).
- Après chaque synchronisation Rojo, relancer le playtest : la copie en Play ne prend pas les modifications.

## Marché (`market/`)
Collecteur des classements Roblox (API publiques) qui alimente le vault. Scripts Python, lancés avec `python -I` depuis
`market/` : `collect.py` (relevé → `data/roblox.db`), `analyze.py --obsidian "<vault>"` (rapport + note du jour),
`prepare_lot.py` / `frames.py` / `contact_sheet.py` (dissection de vidéos). Données, rapports et images restent hors de git.
Relevé quotidien : tâche planifiée Windows **« Roblox market daily »** (18 h) qui lance `market/run_daily.ps1`
(journal dans `market/logs/`).
