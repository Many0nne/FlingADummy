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
- `rojo serve` du checkout principal écoute sur le port **34900** (`servePort` du projet), les worktrees sur `34900+N`
  (section « Worktrees »), hors de la plage de `CSGO_surf_combat` (34872+).
- Connexion : Studio en mode Edit, plugin Rojo, port, Connect. Le plugin installé est le « CSGO autoconnect » : si
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
1. Une tâche = une issue = une branche `feature|fix|tooling/<n>-<slug>` = un worktree `worktrees/fad-<slug>/` (ignoré par
   git), créé ou repris par `.\scripts\fad-worktree.ps1 <branche>` (section « Worktrees »).
2. Implémenter, puis `bash tools/check.sh` dans le worktree ; vérifier en jeu via le MCP Studio si le changement le demande,
   sous le verrou Studio (section « Studio et Blender partagés »).
3. Besoin de l'avis de l'utilisateur (gameplay, rendu, UI) : protocole de test (connexion Studio, étapes, quoi observer),
   puis attendre son retour.
4. Fonctionnement vérifié (et validé par l'utilisateur si l'étape 3 s'appliquait) : commit, push, PR vers `main` avec
   `Closes #<n>`.
5. **Merger soi-même**, sans attendre d'ordre (règle propre à ce dépôt, elle remplace le « pas de merge sans ordre
   explicite » des consignes globales) : CI verte, puis `gh pr merge <n> --merge --delete-branch`. Si l'étape 3
   s'appliquait, seulement après le retour positif de l'utilisateur. CI rouge : corriger, ne pas merger. Puis fermer le
   thread (settle) : le nettoyage automatique supprime alors le worktree et la branche locale (section « Worktrees »).
- Push : le dépôt local utilise `gh auth git-credential` (config git locale) ; ne pas la retirer.
- **Rubrique « Trouvé »** : chaque point qui mérite une suite (bug, amélioration, dette, outillage) devient une issue,
  créée sans demander, avec ses labels (chercher d'abord une issue ouverte qui le couvre). Le compte rendu donne les
  numéros ; seules les remarques mineures restent de simples mentions.
- Labels : `gameplay`, `game-feel`, `ui`, `economie`, `direction-artistique`, `collection`, `tooling`, `backlog`.

## Worktrees (travail en parallèle)
Une branche = un worktree `worktrees/fad-<slug>/` (slug = branche avec `/` → `-`) = un `rojo serve` sur son propre port.
Script idempotent, à relancer au début de chaque tâche (PowerShell, depuis la racine du checkout principal ou d'un worktree) :

```powershell
.\scripts\fad-worktree.ps1 feature/x             # crée/reprend, lance rojo serve, vérifie [OK (200)]
.\scripts\fad-worktree.ps1 fix/y -Base feature/x # nouvelle branche depuis une autre base (défaut : main)
.\scripts\fad-worktree.ps1 feature/x -NoUp       # sans démarrer Rojo
.\scripts\fad-worktree.ps1 feature/x -Slot 2     # impose le slot (port 34902)
.\scripts\fad-worktree.ps1 feature/x -Stop       # arrête Rojo (et libère Studio)
.\scripts\fad-worktree.ps1 feature/x -Remove     # arrête Rojo, supprime le worktree (branche gardée)
```

- Ports par slot N : checkout principal = slot 0 = `34900` (`rojo serve` lancé à la main), worktrees `34900+N`. Port, pid
  et journal du serveur : `worktrees/.run/<slug>.port|.pid|.log` (hors du worktree, rien de versionné).
- Un worktree déjà présent au bon endroit et sur la bonne branche est repris tel quel (même créé à la main avec
  `git worktree add`), ainsi qu'un `rojo serve --port <port du slot>` lancé à la main (`-Slot` pour retrouver son port).
- Le script écrit `.claude/settings.local.json` dans le worktree (exclu de git) : la session peut écrire dans
  `worktrees/.briefs` (compte rendu du brief) et `%TEMP%`. Les réglages déjà présents sont conservés.
- `/delegate` : `-NoUp -NoRegister` pour créer le worktree depuis le thread qui délègue, puis `-RegisterThread <id>` avec
  l'id du thread créé. Règles propres à ce dépôt : skill de projet `delegation-fad`.
- Lancer `bash tools/check.sh`, `rojo build` et `lune run …` depuis le worktree concerné.
- Nettoyage auto (registre `worktrees/.owners.json`) : `scripts/fad-worktree-cleanup.ps1` arrête Rojo quand les threads T3
  du worktree ne sont plus actifs (settled, archivés), et supprime le worktree quand la PR de la branche est mergée
  (ou fermée sans merge) et que tout est poussé ; la branche locale est aussi supprimée si la PR est mergée. Fermer ou
  archiver un thread ne supprime jamais rien à lui seul. Tâche planifiée « Fling a Dummy worktree cleanup » (toutes les
  10 min, à réinstaller sur un nouveau poste) : `scripts/install-cleanup-task.ps1`. À chaque passage, elle avance aussi le
  checkout principal sur `origin/main` (fast-forward, seulement s'il est sur `main` sans modification). Journal :
  `worktrees/.cleanup.log`.
- Tests de limites des scripts (bac à sable jetable dans `%TEMP%`, faux `gh`/T3/Rojo, ~3 min, Windows seulement, hors CI) :
  `Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester tests/scripts`. À lancer après toute modification de
  `scripts/fad-worktree*.ps1` ; un cas limite découvert devient un test dans `tests/scripts/worktree.Tests.ps1`.

## Studio et Blender partagés
Une seule place Studio (placeId 88580736516669) sert tous les worktrees (une fenêtre ne suit qu'un serveur Rojo à la
fois) : les tâches se la relaient par un verrou, `worktrees/.run/studio.lock`. Faire d'abord tout ce qui se passe de
Studio (code, `check.sh`, tests Lune, `rojo build`, Blender sans interface), puis ne garder Studio que le temps de la
vérification :

```powershell
.\scripts\fad-worktree.ps1 <branche> -AcquireStudio                # réserve, ou code 2 avec le détenteur
.\scripts\fad-worktree.ps1 <branche> -AcquireStudio -WaitStudio 20 # attend jusqu'à 20 min
.\scripts\fad-worktree.ps1 <branche> -ReleaseStudio                # libère (aussi fait par -Stop et -Remove)
.\scripts\fad-worktree.ps1 -StudioStatus                           # détenteur et port auquel Studio est connecté
```

- Réserver avant toute action Studio (MCP, connexion du plugin, demande de test à l'utilisateur), libérer juste après.
  Code 2 : continuer le travail sans Studio et réessayer plus tard, ou attendre avec `-WaitStudio`. Ne jamais déconnecter
  Studio d'un autre worktree sans le verrou.
- Connexion à la main pour l'instant : la réservation affiche le port du worktree et celui auquel Studio est connecté ;
  plugin Rojo (mode Edit) > Disconnect > port du worktree > Connect. Après la libération, revenir sur `34900` si le
  checkout principal sert. L'auto-connexion par le plugin multi-projets (`Many0nne/CSGO_surf_combat#589`) se branchera
  plus tard (issue de suivi).
- Un verrou est repris d'office si son détenteur n'a plus de worktree, plus de Rojo ou plus de thread T3 actif : un
  agent qui s'arrête sans libérer ne bloque pas les autres.
- Une tâche qui attend l'avis de l'utilisateur garde le verrou jusqu'à son retour : regrouper ces demandes.
- Blender : la session avec interface (MCP `blender`) sert une tâche à la fois ; les traitements par script passent par
  `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup` (parallélisable).
- Après chaque synchronisation Rojo, relancer le playtest : la copie en Play ne prend pas les modifications.

## Marché (`market/`)
Collecteur des classements Roblox (API publiques) qui alimente le vault. Scripts Python, lancés avec `python -I` depuis
`market/` : `collect.py` (relevé → `data/roblox.db`), `analyze.py --obsidian "<vault>"` (rapport + note du jour),
`prepare_lot.py` / `frames.py` / `contact_sheet.py` (dissection de vidéos). Données, rapports et images restent hors de git.
Relevé quotidien : tâche planifiée Windows **« Roblox market daily »** (18 h) qui lance `market/run_daily.ps1`
(journal dans `market/logs/`).
