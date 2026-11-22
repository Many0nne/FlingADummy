# Fling a Dummy

## Overview
Jeu Roblox (projet Rojo) : on s'entraîne, on lance un mannequin de crash-test sur une piste d'obstacles cassables et on
gagne des mannequins de collection. Concept choisi à partir d'une étude de marché (vault Obsidian
`C:\Users\tbarillon\Documents\Obsidian Vault\Jeu Roblox\`, à lire : `La recette.md` et `05 - Concepts/Concepts candidats.md`).
Dépôt : `Many0nne/FlingADummy` (privé).

## Rôles
Claude est **responsable du projet et du code** : il tranche le design, le game feel, le périmètre et la technique, signale
chaque choix en une ligne, crée les issues et merge les PR. L'utilisateur est **testeur**, mais seulement en **sprint
review** (section « Sprints ») : jamais de demande de test tâche par tâche. Une action destructive ou hors du dépôt se
confirme toujours avec lui.

## Sprints
- On produit en continu : chaque tâche est vérifiée par Claude (tests, `check.sh`, Studio via MCP, mesures), puis mergée
  dès que la CI est verte, **sans attendre l'avis de l'utilisateur**. Un doute de rendu ou de game feel se tranche (choix
  signalé en une ligne) et part dans la review.
- Questions : une vraie décision de design peut être posée dans le thread de la tâche, sans bloquer le reste (avancer
  sur une autre tâche en attendant). Pas de question « est-ce que ça te va en jeu ? » : c'est pour la review.
- Sprint review : quand plusieurs issues sont mergées depuis la dernière review (repère : tag `review/<n>`) et qu'un avis
  de jeu est utile, Claude demande à l'utilisateur de jouer, sur le checkout principal à jour (`main`, port 34900, verrou
  `main -AcquireStudio`), avec **la liste des changements** depuis la review précédente : par issue, ce qui change pour
  le joueur, comment le voir, quoi observer. Liste construite à partir de `git log review/<n>..main --merges` et des
  sections « Pour la sprint review » des comptes rendus.
- Compte du testeur remis à zéro avant chaque review (#95), sauf demande contraire : verrou `main -AcquireStudio`,
  Play, `DebugWipe = true` sur le joueur (contexte `Server`, attribut lu en Studio seulement : sauvegarde d'un nouveau
  joueur, renaissances, collection et tutoriel compris), Stop (la sauvegarde vide est écrite au départ du joueur).
  Le dire dans la liste des changements (« compte remis à zéro : le tutoriel recommence »).
- Retours de la review : chacun devient une issue (ou rouvre la tâche), puis tag `review/<n+1>` sur le `main` testé.
- Tout compte rendu de tâche (délégué ou non) se termine par une section « Pour la sprint review » (3 à 5 lignes).

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
- Connexion automatique : le plugin installé est le « CSGO autoconnect » multi-projets (`Many0nne/CSGO_surf_combat`,
  `tools/rojo-plugin/README.md`). Chaque fenêtre Studio ne suit que la cible de sa place : `-AcquireStudio` connecte la
  place Fling a Dummy au port du worktree sans toucher la fenêtre CSGO (section « Studio et Blender partagés »).
  Prérequis poste : `CSGO_surf_combat\tools\rojo-plugin\install.ps1` lancé une fois, puis Studio redémarré (à refaire
  après `rojo plugin install` ou une mise à jour du plugin par Studio, qui remettent l'officiel).
- Connexion à la main (secours) : Studio en mode Edit, plugin Rojo, Disconnect, port, Connect. Vérifier le port connecté
  avant un test.
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
- Tests unitaires Lune dans `tests/specs/*.spec.luau` (chaque spec retourne `function(T, Loader, Lib)`, cf.
  `tests/lib/` ; `Lib.R15Rig` : cinématique directe d'un avatar R15 pour vérifier une pose). La logique pure va dans
  `src/shared` pour être testable.
- `GameConfig.luau` est exclu de StyLua (`-- stylua: ignore`) : garder l'alignement en colonnes à la main.
- Animations : le jeu joue les clips publiés, pas ceux du dépôt ; modifier un clip impose de republier et de mettre à
  jour `assets/anim/published.json` (procédure : `assets/anim/README.md`, un test de `check.sh` le contrôle).
- **Planches de référence** (`docs/planches/`) : toute création ou modification d'un mannequin (collection ou à lancer),
  d'un palier de base ou de l'appareil d'entraînement régénère la planche concernée et la joint à la PR (avant / après).
  Procédure (une réservation Studio) : `docs/planches/README.md` ; un test de `check.sh` compare le manifeste au
  catalogue et aux données d'apparence (looks, paliers), pas au code qui construit les modèles (`CourseBuilder`,
  `DummyShape`) : une modification de ce code régénère aussi la planche, sans rappel du test.
- **Mesurer avant de promettre** : un effet de gameplay annoncé (distance, gains, temps) se mesure, et la valeur figure
  dans le compte rendu. Sans mesure, écrire « non mesuré ».

## Workflow d'une tâche
1. Une tâche = une issue = une branche `feature|fix|tooling/<n>-<slug>` = un worktree `worktrees/fad-<slug>/` (ignoré par
   git), créé ou repris par `.\scripts\fad-worktree.ps1 <branche>` (section « Worktrees »).
2. Implémenter, puis `bash tools/check.sh` dans le worktree ; vérifier en jeu via le MCP Studio si le changement le demande,
   sous le verrou Studio (section « Studio et Blender partagés »).
3. Pas de test par l'utilisateur à ce stade (section « Sprints ») : noter dans le compte rendu la section « Pour la
   sprint review ».
4. Fonctionnement vérifié : commit, push, PR vers `main` avec `Closes #<n>`.
5. **Merger soi-même**, sans attendre d'ordre (règle propre à ce dépôt, elle remplace le « pas de merge sans ordre
   explicite » des consignes globales) : CI verte, puis `gh pr merge <n> --merge --delete-branch`. CI rouge : corriger,
   ne pas merger. Puis fermer le thread (settle) : le nettoyage automatique supprime alors le worktree et la branche
   locale (section « Worktrees »).
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
- Tests de limites des scripts (bac à sable jetable dans `%TEMP%`, faux `gh`/T3/Rojo/serveur de commande/plugin
  autoconnect, registre commun jetable par `ROJO_AUTOCONNECT_DIR`, ~10 min sur le poste chargé, Windows seulement) :
  `Import-Module Pester -RequiredVersion 3.4.0; Invoke-Pester tests/scripts`. À lancer après toute modification de
  `scripts/fad-worktree*.ps1` ; un cas limite découvert devient un test dans `tests/scripts/worktree.Tests.ps1`.
  Ils tournent aussi en CI (job `pester`, `windows-latest`, ~5 min), seulement quand `scripts/**`, `tests/scripts/**` ou
  `.github/workflows/ci.yml` changent : une PR qui casse un cas limite a une CI rouge.

## Studio et Blender partagés
Une seule place Studio (placeId 88580736516669) sert tous les worktrees (une fenêtre ne suit qu'un serveur Rojo à la
fois) : les tâches se la relaient par un verrou, `worktrees/.run/studio.lock`. Faire d'abord tout ce qui se passe de
Studio (code, `check.sh`, tests Lune, `rojo build`, Blender sans interface), puis ne garder Studio que le temps de la
vérification :

```powershell
.\scripts\fad-worktree.ps1 <branche> -AcquireStudio                # réserve et connecte la place, ou code 2 avec le détenteur
.\scripts\fad-worktree.ps1 <branche> -AcquireStudio -WaitStudio 20 # attend jusqu'à 20 min
.\scripts\fad-worktree.ps1 <branche> -ReleaseStudio                # libère, place renvoyée sur 34900 (aussi fait par -Stop et -Remove)
.\scripts\fad-worktree.ps1 -StudioStatus                           # détenteur, port connecté, dernier état signalé par le plugin
```

- Réserver avant toute action Studio (MCP, connexion du plugin, demande de test à l'utilisateur), libérer juste après.
  Code 2 : continuer le travail sans Studio et réessayer plus tard, ou attendre avec `-WaitStudio`. Ne jamais déconnecter
  Studio d'un autre worktree sans le verrou.
- Depuis le checkout principal (`rojo serve` lancé à la main sur 34900) : réserver avec la branche `main`
  (`.\scripts\fad-worktree.ps1 main -AcquireStudio`, puis `main -ReleaseStudio`). Au repos (après une libération), la
  place est sur 34900 : c'est normal. Studio connecté à 34900 **à la main** (dernière cible publiée ailleurs) : sans doute
  l'utilisateur qui teste ; la réservation d'un worktree répond alors code 2 et le nettoyage n'avance pas `main`.
  Demander à l'utilisateur avant Disconnect. Pour protéger un long test sur 34900, réserver `main`.
- Connexion automatique (#20) : après la prise du verrou, la réservation publie le port dans `worktrees/.run/studio.target`
  (checkout principal), inscrit le projet au registre commun (`%LOCALAPPDATA%\RojoAutoconnect\projects\fad.json`, place
  88580736516669), s'assure que le serveur de commande partagé répond (`http://127.0.0.1:34870/health` =
  `rojo-control 3`, lancé au besoin depuis le checkout principal, jamais arrêté : il sert aussi la fenêtre CSGO), puis
  attend 15 s que le plugin signale la connexion (`studio.status`). La libération renvoie la place sur `34900` si le Rojo
  du checkout principal répond, sinon la déconnecte.
- Pas connecté en 15 s (Studio fermé ou en Play, place non ouverte, plugin officiel) : la réservation affiche la
  procédure manuelle (plugin Rojo, mode Edit > Disconnect > port du worktree > Connect) ; le verrou reste pris.
- Garde-fou : `-StudioStatus` et `-AcquireStudio` affichent `ALERTE` quand le plugin signale la place connectée à un port
  qui n'est d'aucun Rojo de ce dépôt (code CSGO synchronisé dans la place) : ne pas sauvegarder ni publier la place.
- Un verrou est repris d'office si son détenteur n'a plus de worktree, plus de Rojo ou plus de thread T3 actif (threads
  settled, archivés ou supprimés ; un thread inconnu de T3 ne compte pas comme fini) : un agent qui s'arrête sans
  libérer ne bloque pas les autres.
- Aucune tâche n'attend l'avis de l'utilisateur avec le verrou (section « Sprints ») ; pendant une sprint review, le
  verrou est pris sur `main`.
- Blender : la session avec interface (MCP `blender`) sert une tâche à la fois ; les traitements par script passent par
  `"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup` (parallélisable).
- Après chaque synchronisation Rojo, relancer le playtest : la copie en Play ne prend pas les modifications.

## Marché (`market/`)
Collecteur des classements Roblox (API publiques) qui alimente le vault. Scripts Python, lancés avec `python -I` depuis
`market/` : `collect.py` (relevé → `data/roblox.db`), `analyze.py --obsidian "<vault>"` (rapport + note du jour),
`prepare_lot.py` / `frames.py` / `contact_sheet.py` (dissection de vidéos). Données, rapports et images restent hors de git.
Relevé quotidien : tâche planifiée Windows **« Roblox market daily »** (18 h) qui lance `market/run_daily.ps1`
(journal dans `market/logs/`).
