# Prototype v0 — plan d'implémentation

Objectif : la boucle complète jouable dans Studio (charger, lancer, vol, résultat, améliorations), pour la faire tester à
l'utilisateur. Règles de jeu et chiffres : `docs/design.md`. Constantes : `src/shared/GameConfig.luau` (déjà écrit).

## État au 2026-11-19
- Fait : tous les modules ci-dessous, specs Lune (`Economy`, `Gauge`, `Damage`, `Format`), vérification dans Studio
  par le MCP (lancers, HUD, caméra, achat). Reste : test de l'utilisateur (sensation), puis premier commit.
- Écarts au plan :
  - vitres brisées au **franchissement** de leur z par le torse (pas `Touched`, qui rate une vitre fine à grande
    vitesse) ; le ralentissement × 0,9 ne compte pas comme un choc (sinon jusqu'à 10 os par vitre) ;
  - caisses (densité 0,05) et briques (0,08) très légères, mannequin lourd (1,5) : sinon la pile de caisses à 90 m
    arrêtait tous les lancers du niveau 1 à 87 m, quelle que soit la jauge ;
  - `Workspace.Gravity = GRAVITY` (120) ; aucun lancer avant le chargement des données (attribut `DataReady`).

### Mesures (Studio, `DebugLaunch`, 2026-11-19)
Réglages : gravité 120, vitesse de base 125, seuils d'os 70 / 150, frottement du sol 0,35, prix de départ 100 / 150.

| Puissance | Jauge | Distance | Os | Objets | Gains | Vol |
|---|---|---|---|---|---|---|
| 1 | 0 | 63 m | 2 | 1 | 88 $ | 2,9 s |
| 1 | 0,5 | 106 m | 3 | 10 | 186 $ | 3,3 s |
| 1 | 1 | 174-176 m | 5 | 9-11 | 325-335 $ | 4,0 s |
| 2 | 1 | 196 m | 6 | 14 | 391 $ | 3,9 s |
| 4 | 1 | 312 m | 6 | 35 | 656 $ | 4,6 s |
| 8 | 1 | 816 m | 14 | 28 | 1 315 $ | 6,9 s |
| 15 | 1 (réglage précédent) | 2 773 m | 0 | 3 | — | 5,2 s |

- Boucle : charge ≈ 1 s + vol 3-4 s + résultat 2,6 s ≈ **7 s** (cible ≈ 10 s).
- Première récompense : canon prêt dès l'arrivée, donc ≈ 1 s de charge + 3-4 s de vol ; le délai d'arrivée en jeu
  n'est pas mesuré.
- Dès la puissance ≈ 8, le mannequin survole tout le parcours (720 m) : les obstacles ne servent plus. À traiter avec
  la renaissance et le nouveau parcours (v1).

## Modules
### `src/shared` (logique pure, testée sous Lune dans `tests/specs/`)
- `GameConfig` : constantes (fait).
- `Economy` : `launchSpeed(powerLevel)`, `valueMultiplier(valueLevel)`, `upgradeCost(kind, level)` (prix pour passer au
  niveau suivant, `nil` au niveau max), `payout(stats, valueLevel)` → total arrondi + détail
  (`stats = { distance, bones, smashed, perfect }`).
- `Gauge` : `value(t)` en onde triangle sur `GAUGE_PERIOD` (0 → 1 → 0), `launchFactor(v)` = `GAUGE_MIN_FACTOR + (1 - min) × v`,
  `isPerfect(v)`.
- `Damage` : `bonesForImpact(dv)` (0, 1 ou 2 selon `BONE_IMPACT_DV` / `DOUBLE_BONE_DV`), `tint(baseColor, bones)` (jaune →
  orange → rouge → rouge sombre).
- `Format` : `money(n)` avec séparateurs (`$12,345`), `meters(n)`.
- `Remotes` : le serveur crée `ReplicatedStorage.Remotes`, le client l'attend. RemoteEvents : `Launch` (client → serveur,
  valeur de jauge 0-1, bornée côté serveur), `BuyUpgrade` (`"Power"` | `"Value"`), `LaunchStarted` (serveur → client, le
  modèle du mannequin, pour la caméra), `LaunchResult` (serveur → client, détail des gains).

### `src/server`
- `init.server.luau` : amorçage (groupes de collision, construction des couloirs, services).
- `CollisionGroups` : `Dummy` (ne se touche pas lui-même), `Characters` (ne touche ni `Dummy` ni `Debris`), `Cannon`
  (ne touche pas `Dummy`), `Debris` (éclats de verre, ne touchent pas `Dummy`).
- `CourseBuilder` : supprime `Workspace.Baseplate` s'il existe ; par couloir `i`, origine `x = (i - 1) × LANE_SPACING` :
  - sol (`LANE_WIDTH` × 2 × `COURSE_LENGTH`, dessus à y = 0), faible frottement pour que le mannequin glisse ;
  - murs latéraux transparents (0,85) de `SIDE_WALL_HEIGHT` pour garder le mannequin dans son couloir ;
  - plateforme de tir derrière z = 0, apparition du joueur à côté du canon ;
  - canon : socle + fût (Part cylindre, axe X orienté sur la direction de tir, pitch `LAUNCH_PITCH_DEG`), bouche à
    `MUZZLE_HEIGHT` ;
  - repères au sol tous les 50 m (bande blanche + BillboardGui « 50 m ») ;
  - obstacles régénérables (`resetObstacles(lane)`) : dossier détruit puis reconstruit d'après une table
    `{ z, kind }` — vitres à 45, 140, 240, 420, 620 ; caisses à 90, 300, 480 ; murs de briques à 185, 360, 550.
    - **vitre** : ancrée, `CanCollide = false`, `CanTouch = true`, hauteur 30. Touchée par le mannequin actif → détruite,
      remplacée par ~10 éclats (groupe `Debris`, détruits après 4 s), vitesse du mannequin × 0,9, +1 objet (franchissement, cf. État).
    - **caisses** : pile 3 × 3 de caisses de 4 studs, non ancrées, bois.
    - **mur** : 6 × 5 briques de 4 × 2 × 2 en quinconce, non ancrées.
    - Toutes les pièces non ancrées : `SetNetworkOwner(nil)` (sinon le joueur le plus proche les simule).
- `DummyFactory.build()` : mannequin de crash-test en 10 pièces (tête boule, torse, bras haut/bas, jambes haut/bas),
  `BallSocketConstraint` avec limites (cou 40°, épaules 110°, coudes/genoux 100°, hanches 80°, torsion ±30°), axe des
  attachements le long du membre. Jaune crash-test, avant-bras et tibias gris foncé. Pas de Humanoid. Groupe `Dummy`.
  Gabarit (en studs, debout, centre du torse à l'origine) : torse 2 × 2,4 × 1,1 ; tête Ø 1,5 à y = 2,1 ; bras haut
  0,8 × 1,2 × 0,8 à (± 1,45 ; 0,6), bras bas à (± 1,45 ; − 0,62) ; cuisse 0,95 × 1,3 × 0,95 à (± 0,5 ; − 1,85),
  tibia à (± 0,5 ; − 3,17).
- `PlayerData` : attributs du joueur `Money`, `PowerLevel`, `ValueLevel`, `BestDistance` ; leaderstats `Cash` et `Best`
  (statut visible dans le hub) ; DataStore `PlayerData_v1` sous `pcall` (Studio sans accès API : avertissement, on
  continue) ; sauvegarde au départ et dans `BindToClose` ; achat d'amélioration validé côté serveur.
- `LaneService` : attribue le premier couloir libre à l'arrivée, le libère au départ ; place le personnage sur la
  plateforme à chaque apparition ; personnages dans le groupe `Characters`.
- `LaunchService` :
  - `launch(player, gauge)` : seulement si l'attribut `LaneState == "Ready"`, puis `"Flying"` ; vitesse =
    `Economy.launchSpeed × Gauge.launchFactor` ; mannequin posé à la bouche, toutes les pièces à cette vitesse + petite
    rotation aléatoire ; `LaunchStarted:FireClient`.
  - suivi sur Heartbeat : distance = max(z du torse − z de la bouche) ; dégâts = variation de vitesse de chaque membre
    entre deux frames (après `IMPACT_GRACE_TIME`), `Damage.bonesForImpact`, plafond par membre, teinte ; caisses et briques
    du couloir qui dépassent `SMASH_SPEED` comptées une fois ; attributs `Distance`, `Bones`, `Smashed` sur le modèle du
    mannequin (le client les affiche en direct).
  - fin : torse sous `REST_SPEED` pendant `REST_TIME`, ou `MAX_FLIGHT_TIME`, ou y < `KILL_Y`. Gains crédités,
    `BestDistance`, `LaunchResult:FireClient`, `"Result"`, puis après `RESULT_TIME` : mannequin détruit, obstacles
    reconstruits, `"Ready"`.
  - Studio seulement : l'attribut joueur `DebugLaunch` (0-1) déclenche un lancer, et chaque résultat s'écrit en console
    `[Launch] distance=… bones=… smashed=… payout=…` (vérification par le MCP sans simuler d'input).

### `src/client`
- `init.client.luau` : amorçage.
- `Hud` (interface construite en code, textes en anglais) : argent en haut au centre ; compteurs de vol (distance, os,
  objets) en gros pendant le vol ; deux boutons d'amélioration à droite (niveau, effet, prix, grisés si trop cher) ;
  jauge en bas au centre avec zone PERFECT et consigne « HOLD TO CHARGE » ; panneau de résultat (« +$1,234 » et détail,
  « PERFECT » le cas échéant) pendant `RESULT_TIME`.
- `LaunchInput` : clic gauche, toucher ou Espace (non consommés par l'interface) quand `LaneState == "Ready"` → l'aiguille
  part ; relâcher → `Launch:FireServer(valeur)`.
- `FlightCamera` : sur `LaunchStarted`, caméra Scriptable qui suit le torse (décalage arrière-côté-haut, lissage
  exponentiel) ; retour à la caméra normale à la fin du résultat ou si le mannequin disparaît.

## Vérification
1. `bash tools/check.sh` sans avertissement (specs `Economy`, `Gauge`, `Damage`, `Format`).
2. Studio par le MCP : playtest, `DebugLaunch` à 0,5 puis 1, lire `[Launch]` en console ; vérifier que le lancer suivant
   repart (`LaneState`) et que l'argent et les niveaux bougent. Appels MCP courts (pas d'attente dans `execute_luau`).
3. Mesurer et noter : temps de la première récompense (cible < 25 s), distance au niveau 1 (≈ 100 à 150 m attendus),
   durée d'une boucle (≈ 10 s).
4. Protocole de test pour l'utilisateur : quoi faire, quoi observer (sensation du lancer, lisibilité des dégâts, envie
   de relancer), puis attendre son retour.

## Ensuite (v1)
Variantes « 1 en N », renaissance précoce et nouveau parcours, sons (chercher avec le MCP Studio `search_asset`),
ralenti des records, récompense quotidienne. Voir `docs/design.md`.
