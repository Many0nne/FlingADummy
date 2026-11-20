# Fling a Dummy — document de conception

Titre provisoire (à tester avant publication). Origine du concept : vault Obsidian, `Jeu Roblox/05 - Concepts/Concepts candidats.md`
(concept A) et `Jeu Roblox/La recette.md` (ce qui fait percer un jeu Roblox). Jeux de référence pour la boucle, l'interface
et le rythme : fiches `04 - Jeux disséqués/` du vault (01 *Throw Food For Animals*, 09 *Throw a Seed*, 03 *Hyper Realistic
Ragdoll*, 06 *BloxNG*, 12 *Net a Fish!*).

## Le jeu en une phrase
Dans un lobby de 4 joueurs, on s'entraîne en soulevant un mannequin pour devenir plus fort, puis on lance un mannequin de
crash-test à bout de bras dans un canyon de briques à tenons, sur une piste partagée semée de vitres, de tours de caisses,
de murs, de voitures-cibles et de panneaux-cibles. Le lancer ne rapporte pas d'argent : sa **CHANCE** (zones traversées,
os cassés, objets détruits) pousse un tirage « 1 en N » qui fait gagner un **mannequin de collection** ; posé dans sa
base, il rapporte des $/s, seule source d'argent.

## Cibles (mesurées sur les jeux qui percent)
| Moment | Cible |
|---|---|
| Première action | 0 s (zone de lancer à côté du point d'apparition) |
| Première récompense | < 25 s |
| Premier équipement d'entraînement | ≈ 30-45 s |
| Première offre payante | ≈ 1 min (v2) |
| Première renaissance | < 3 min (v1) |

## Boucle principale (≈ 10-15 s)
1. **Prendre le mannequin** : poser le pied n'importe où sur la bande de lancer ; le serveur fige l'avatar à cet endroit
   (à 3 studs des bords au plus près), face à la piste (écarté de 5 studs au moins d'un voisin déjà figé), et il tient un mannequin au-dessus de sa tête.
   Plus de déplacement ni de saut jusqu'au lancer (pas de sortie, comme les références).
2. **Jauge à 1 clic** : une jauge verticale apparaît, l'aiguille monte et descend seule (`+1` à `+20`) ; un clic, un toucher
   ou Espace l'arrête, avec un clic net et un petit rebond de la jauge, puis le whoosh au lâcher. Pas de zone PERFECT ni
   de bonus : le haut de la jauge est le max (`+20`), comme dans les jeux de référence. **Valeur vérifiée par le
   serveur** (`Shared.Gauge.verify`) : il note l'ouverture de la jauge, et le client envoie `GaugeStop` (sans charge) au
   clic : le serveur note son arrivée (une fois par lancer, jauge ouverte seulement) et en déduit l'instant du clic
   (latence `GetNetworkPing` (aller-retour) bornée à 1 s déduite, tolérance 0,12 s). Il garde la valeur du client à la réception
   de `Launch` si elle est atteignable dans cette fenêtre, sinon la sienne. Sans `GaugeStop` (client ancien, perte), repli :
   clic estimé depuis l'arrivée de `Launch` (lâcher de l'animation et latence déduits, lâcher en retard de
   `GAUGE_RELEASE_SLACK` = 0,25 s au plus, constante partagée avec le lâcher de secours du client).
3. **Élan** : l'avatar se penche en arrière puis projette le mannequin (0,35 s).
4. **Vol** : bandes noires, caméra qui suit, bannière **CHANCE** (« 1.36X / CHANCE / 🍀 MEADOW ») qui monte pendant le
   vol, compteurs (distance, os, objets), radio du mannequin ; chaque choc a son son, ses particules et son popup
   (« +1 BONE », « SMASH x6 », combos).
5. **Atterrissage** (≈ 1 s, #53) : dès que le mannequin s'arrête (détecté par le client), trèfle et CHANCE finale
   « 🍀 X1.36 » au-dessus de lui (même police et même vert que la bannière du vol, apparition en rebond) et titre du
   crash dessous (« BRUTAL! »), « NEW RECORD! » au-dessus en cas de record, comme le « X1.22 » de 09 ; pas d'écran de
   détail, comme 01. S'il repart (calé un instant contre un obstacle), le vol reprend. Le tirage part dès que le
   serveur a compté le lancer (1 s d'arrêt), « X » au moins 0,9 s à l'écran : **arrêt → silhouette ≈ 1,1 s** (cible
   < 1,5 s). Le détail reste sur la radio X-RAY, dans son coin jusqu'à 3 s après le comptage : bilan à sa gauche
   (distance, os, objets détruits, blessures « Shattered skull, broken left arm », cause « Hit a brick wall at
   140 km/h »).
6. **Tirage « 1 en N »** (`Client.Prize`, suspense calé sur 09 et 01) : silhouette noire debout au point
   d'atterrissage, caméra de face qui se rapproche. La cote défile en continu depuis « 1 IN 1 » (un tic par chiffre, de
   plus en plus aigu, vite puis de plus en plus lentement : `Collection.climbOdds`, 0,7 à 1,5 s par palier selon
   l'écart) ; à chaque palier atteint, la silhouette se change en candidat plus rare (`Collection.teaseSequence` : 0 à 3
   mannequins plus courants, chacun à sa cote, puis le gagné), comme la pousse → buisson → arbre de 09 : éclair blanc,
   étincelles, anneau, secousse, contour à la couleur de la rareté, exclamation en haut (« Lucky! » → « Super lucky! »
   → « Incredible luck! », comme « Super chanceux ! » de 01), arrêt de 0,45 s, puis la cote repart. Puis roulement (1,1 s, la silhouette tremble de plus en plus) et révélation : éclair plein
   écran, mannequin en couleurs qui grossit, rayons ; en haut au centre, **une seule fois** : taille et rareté
   (« BIG · RARE »), nom, « NEW! », $/s, cote ; bouton GO BACK (automatique après 5 s ; le serveur rend la main au plus
   tard 20 s après l'atterrissage).
7. **Poser** : de retour au hub, panneau « Place your Crash Dummy! » en bas au centre (rendu 3D). **Première pose à la
   main** (étape du tutoriel) : flèche et chevrons vers un présentoir libre de sa base, présentoirs libres en
   surbrillance, invite « Place » (E). Ensuite le bouton **AUTO** apparaît seulement dans sa base ou à moins de
   12 studs de sa clôture (vérifié aussi par le serveur). Mannequin jamais posé : rangé d'office au tirage suivant.

## Mécanique secondaire : l'entraînement
- Un appareil d'entraînement par joueur, devant sa base à côté de l'entrée (podium à tenons, râtelier de mannequins
  suspendus, invite « Lift » / « Training dummy ») : l'avatar soulève au-dessus de la tête (développé) le mannequin de son palier
  d'équipement, en boucle. Pendant la séance, l'invite est masquée et aucun objectif ne s'affiche : seul le bouton STOP.
- Chaque répétition (0,8 s) donne l'**EXP de l'équipement** (« +N EXP », comme « +4 EXP / répétition » de 09) qui
  remplit la barre de niveau : 3 EXP au premier niveau puis × 1,2 par niveau, l'EXP en trop passe au niveau suivant
  (plusieurs niveaux d'un coup avec un bon équipement). Le passage de niveau (« LEVEL UP! Throw Power +N ») donne autant
  de **Throw Power** que l'EXP qu'il demandait : puissance gagnée = EXP gagnée = gain × répétitions.
- **Équipements** (achetés avec l'argent) : mannequin en bois +1, pierre +3, fer +10, or +40, diamant +160, néon +700,
  cosmique +3 000 EXP par répétition ; prix 100 $, 1,5 K, 25 K, 150 K, 2 M, 25 M.
- Vitesse de lancer = 110 + 30 × ln(puissance / 10) studs/s : la puissance explose (10 → 1 M), la distance monte
  régulièrement (≈ 145 m → 2,2 km).

## Deux courbes
Comme 01 et 09 : le lancer fait le lien entre les deux.
- **Throw Power** (entraînement) → distance → zones plus lointaines → **CHANCE** → mannequins plus rares.
- **Revenu** (mannequins posés dans la base) → argent → équipements (entraînement plus rapide) ; plus tard la boutique
  de mannequins à lancer (#14, multiplicateur de chance) et les présentoirs achetables (#52).

## CHANCE et tirage (`Shared.Economy`, `Shared.Collection`)
- CHANCE = chance des zones × (1 + 2 % par os cassé + 1 % par objet détruit), arrondie au centième. La chance des zones
  vaut celle de la zone à son entrée et monte en continu jusqu'à celle de la suivante (18 au bout de la piste) : un
  premier lancer (≈ 145 m) donne ≈ 1.4X, comme le 1.36X de 09.
- Tirage : les mannequins sont essayés du plus rare au plus courant, chacun sort avec la probabilité min(1, CHANCE / n)
  (le plus courant ramasse le reste) ; la taille se tire de même à CHANCE^0,5. Probabilités exactes affichables
  (`Collection.probabilities`, `sizeProbabilities`), cote affichée = 1 / probabilité à CHANCE 1, × celle de la taille.
- **Premier lancer** : Crash Dummy (Common, 4 $/s) garanti.
- **21 mannequins** (déclinaisons du modèle : couleur, matériau, casque, lunettes, cape) de Common à Secret :
  | Rareté | Mannequins | Revenu ($/s) | n |
  |---|---|---|---|
  | Common | Crash, Rookie, Traffic | 4 à 6 | 2 à 5 |
  | Uncommon | Mint, Biker, Nerd | 15 à 30 | 10 à 25 |
  | Rare | Ocean, Hero, Pilot | 70 à 150 | 60 à 150 |
  | Epic | Ice, Toxic, Royal | 400 à 700 | 500 à 1 200 |
  | Legendary | Gold, Lava, Diamond | 2 500 à 5 000 | 4 K à 10 K |
  | Mythic | Galaxy, Ghost, Neon | 20 K à 40 K | 40 K à 100 K |
  | Secret | Crash King, Void, Cosmic | 150 K à 300 K | 500 K à 2 M |
- **Tailles** : Normal (×1 revenu), Big (×1,5, 1 en 8), Huge (×3, 1 en 60), Giant (×8, 1 en 500) ; modèle agrandi.

## Base (`Server.BaseService`)
- 6 présentoirs par base ; les mannequins posés sont construits par le serveur (visibles de tous), nom coloré par
  rareté et $/s au-dessus ; revenu total de la base au-dessus du panneau « NOM'S BASE » (comparaison entre joueurs).
- Revenu versé chaque seconde (attribut `Income`, compteur « +$N/s ») : **seule source d'argent**.
- AUTO : premier présentoir libre ; base pleine, le nouveau remplace le moins rentable s'il rapporte plus (l'ancien est
  revendu), sinon il est revendu ; revente = 2 min de revenu. Inventaire, vente au stand SELL, présentoirs achetables
  et Index : #52.
- Sauvegarde avec les données du joueur (`Collection` : présentoirs, mannequin en main, mannequins découverts, pour
  « NEW! » ; `Draws` : nombre de tirages).

## Carte (v0.3) : lobby de 4 joueurs, piste unique
- **Hub** (pelouse à damier entourée de parois en gradins) : une **base par joueur** (terrain clôturé, 6 présentoirs
  pour la collection, panneau « NOM'S BASE » et revenu au-dessus) avec son **appareil d'entraînement** à côté de l'entrée, qu'il
  laisse libre (podium à tenons, pastille jaune, râtelier, invite « Lift », briques fines `FadBrickFine`), stands à
  auvents rayés « SELL » et « SHOP » (branchés par la collection et la boutique), chevrons jaunes vers la zone de
  lancer. Plan dans `Shared.CourseLayout`.
- **Zone de lancer commune** : la **bande de lancer**, sur toute la largeur de la piste et toute la profondeur de la zone
  (16 studs, du hub au départ), au ras de la pelouse : carreaux de 4 studs à tenons orange et jaune, reflet blanc qui
  glisse d'un bout à l'autre (animé par chaque client), liseré blanc à peine surélevé côté piste (compté comme bande),
  comme *Throw Food For Animals* et *Throw a Seed*. Pas de place attitrée : jusqu'à 15 joueurs figés y tiennent côte à
  côte (4 par serveur). Le joueur réapparaît dans le hub, 6 studs derrière la bande, et y revient après chaque lancer.
- **Piste fermée aux avatars** : barrière invisible juste derrière le liseré (groupe `AvatarBarrier`, qui ne
  collisionne qu'avec `Characters`), et pièces d'obstacles dans le groupe `Obstacles`, que les avatars traversent : un
  joueur ne descend pas sur la piste et ne bouscule pas les obstacles des autres.
- **Piste partagée** (80 studs de large, 2,4 km) au fond d'un canyon en 3 gradins : parois en briques, herbe (ou neige,
  sable…) voxel qui déborde de chaque marche, décor voxel sur les terre-pleins et au pied des parois (traversable).
- **Obstacles partagés** (`Server.Obstacles`) : rangées de 4 vitres (une par colonne), tours de caisses (2 × 2 × 4) par
  colonne, murs de briques sur toute la largeur des colonnes, voitures-cibles et panneaux-cibles en damier jaune et noir.
  Une pièce déplacée réapparaît à sa place **5 s après le dernier choc** subi par son obstacle, une par une de bas en haut
  (0,05 s d'écart), en grossissant depuis son centre ; jamais sur un mannequin posé dedans. Un objet projeté est compté
  pour le mannequin le plus proche (règles dans `Shared.ObstacleRules`).

## Zones de la piste (2,4 km)
Chaque zone a son identité (couleur du sol, des parois, du dessus des gradins, décor), comme les zones de *Throw a Seed* :
| Zone | Début | CHANCE à l'entrée | Sol / parois | Décor |
|---|---|---|---|---|
| Meadow | 0 m | ×1 | vert citron / brun | arbres, buissons, fleurs, rochers |
| Forest | 100 m | ×1,25 | vert foncé / brun | sapins, champignons géants |
| Desert | 250 m | ×1,6 | sable / ocre | palmiers, cactus, buissons secs |
| Construction | 450 m | ×2,2 | jaune / brique | plots, barrières rayées, poutrelles |
| Snowfield | 700 m | ×3,2 | blanc bleuté / bleu glace | sapins enneigés, bonshommes de neige |
| Volcano | 1 km | ×5 | rouge / basalte, dessus lave | roches à veines de lave, arbres morts |
| Candy Land | 1,4 km | ×8 | rose / violet, dessus menthe | sucettes, sucres d'orge, boules de gomme |
| Moon Base | 1,9 km | ×12 | lavande / violet nuit | cristaux, cratères, fusées |

Panneaux d'entrée de zone : « FOREST x1.25 CHANCE ».

## Dégâts lisibles
Chaque membre (10 pièces) suit les chocs : une variation brusque de vitesse au-delà d'un seuil casse un os (2 au-delà d'un
second seuil), au plus 3 par membre. Gravité par membre : contusion, cassé, broyé ; le membre vire du jaune au rouge
sombre, sur le mannequin et sur le panneau radio.

## Direction artistique
Calée sur les jeux de référence (01 *Throw Food For Animals*, 09 *Throw a Seed*, 02 *Break and Steal an Egg*) : tout en
**briques à tenons** (tenons en relief, biseau clair en haut à gauche) aux couleurs saturées, sol en damier deux tons de
carreaux de 8 studs à 4 × 4 tenons, canyon en gradins à damier brun coiffés d'herbe voxel qui déborde en escalier,
arbres et rochers voxel, barrières en blocs, stands à auvents rayés, ciel bleu à nuages, lumière de plein jour claire et
saturée aux ombres douces. Matériaux : trois `MaterialVariant` synchronisés par Rojo dans `MaterialService`, teintés par
la couleur de chaque pièce : `FadChecker` (16 studs, damier marqué : sol), `FadWall` (16 studs, damier plus doux :
parois et herbe), `FadBrick` (2 studs : coulées d'herbe, accessoires, obstacles) ; textures produites par
`assets/course/build_textures.py` (contrastes mesurés en jeu contre 01, captures `docs/captures/textures/`). Le thème
crash-test reste dans les objets (mannequin, voitures-cibles, panneaux en damier jaune et noir), pas dans le décor.
Interface : section suivante.

## Interface (grammaire des jeux de référence 01 / 09)
- **Police** : Fredoka One partout, blanc à contour noir fin ; grands nombres abrégés (`1.2K`, `3.4M`).
- **Boutons** : carrés arrondis à icône dessinée en couleur et libellé dessous ; Index et Shop au bord gauche, Dummies
  au bord droit (place du bouton de collection des références) ; pastille rouge « ! » quand un achat est possible.
- **Compteurs** (bas gauche) : biceps + Throw Power (cyan), liasse + argent (blanc), revenu « +$N/s » en vert à droite
  de l'argent quand l'attribut joueur `Income` (revenu de la base) est positif ; l'argent du revenu tombe tout seul.
- **Tutoriel** (objectif en haut au centre) : toute la boucle une fois, dans l'ordre des références, puis plus jamais de
  texte, de flèche ni de chevrons : « Throw your dummy! » (premier lancer) → « Place your dummy! » (première pose à la main,
  flèche vers un présentoir libre) → « Train! » (jusqu'au premier niveau) → « Buy better gear! » dès que le premier équipement est abordable. Pour un achat,
  la flèche désigne où cliquer : bouton UPGRADE du popup « NEW GEAR! », sinon bouton d'achat de la carte quand la
  fenêtre est ouverte (comme la flèche rouge de la boutique de 09), sinon le bouton du HUD qui ouvre la fenêtre. Étapes
  sauvegardées avec le joueur (attribut `Tutorial`, drapeaux) ; une sauvegarde antérieure en déduit les étapes déjà faites.
  Rien pendant la jauge, le vol, le résultat et la séance d'entraînement. Cible du décor : triangle jaune au-dessus,
  chevrons jaunes au sol qui défilent vers elle. Logique dans `Shared.Tutorial` et `Shared.Objectives`.
- **Popup « NEW GEAR! »** (comme « Nouvel équipement ! » de 09) : en haut au centre dès que l'équipement suivant est
  abordable, écran libre (pas pendant la jauge, le vol, le résultat, ni boutique ouverte) : rendu 3D, nom, prix et gain,
  bouton vert UPGRADE qui achète en un clic, croix. Fermé, il ne revient pas pour ce palier, mais revient pour le
  suivant. Tout au long du jeu, pas seulement au tutoriel.
- **Cibles du décor** (point d'accroche pour la carte et la collection) : une `BasePart` avec le tag `ObjectiveTarget`
  et l'attribut `Objective` (`"Throw"`, `"Train"`…), plus `Slot` (place du lobby) ou `OwnerUserId` (joueur) si elle
  n'est pas partagée ; le joueur suit la plus proche de celles qui lui sont ouvertes. `Span` : cible allongée sur X,
  visée en son point le plus proche du joueur. `CourseBuilder` marque la bande de lancer (partagée, `Span`) et
  l'appareil d'entraînement de chaque place.
- **Fenêtres** : cadre sombre, bandeau dégradé (icône, titre), croix rouge ; cartes d'objets grises (nom, rareté
  colorée de `Shared.Rarity`, rendu 3D en `ViewportFrame`, statistique, bouton : prix vert / rouge, « EQUIPPED »).
  Shop = équipements d'entraînement ; Dummies = mannequin lancé (Crash Dummy, x1 CHANCE) et mannequins à venir en
  silhouette (#14) ; Index = cases vides en attendant son contenu (#52).
- **Jauge** : capsule verticale à contour noir, dégradé vert (haut) → rouge (bas), 4 traits, curseur blanc, `+N` à
  droite, « Click to throw! » dessous.
- **Popups** : « LEVEL UP! » / « NEW EQUIPMENT! » jaunes à contour en haut au centre, sous-titre dessous.
- Icônes : rendues par `assets/icons/build_icons.py` (Blender), ids dans `Shared.Assets.ICONS` (emoji de repli à 0).

## Architecture
- Tout est **simulé par le serveur** (propriétaire réseau `nil`) : le joueur ne pilote pas le mannequin en vol, la latence
  ne se voit donc pas, le score est fiable et les autres joueurs voient les lancers des voisins.
- Les chocs sont annoncés à tous les clients (`Impact`), qui jouent sons, particules et popups.
- Les poses de l'avatar (mannequin tenu, entraînement, élan) sont calculées par chaque client d'après les attributs du
  joueur (`Action`), en écrasant `Transform` des articulations (Motor6D ou AnimationConstraint).
- Lobby de 4 joueurs (`SLOT_COUNT`, `MaxPlayers` du projet Rojo) sur **une piste partagée** : chaque joueur a une place
  (`Server.SlotService`) ; les vols coexistent, les obstacles réapparaissent d'eux-mêmes au lieu d'être reconstruits.
- Studio : `DebugLaunch` (0-1) sur le joueur lance son mannequin, `DebugLaunchBots` (n) lance n mannequins de test depuis
  les places libres (mesure de 4 vols simultanés), `DebugPlace` pose le mannequin en main (AUTO) ; `FreshPlayer` sur
  Workspace : nouveau joueur sans sauvegarde.
- Le décor est généré par le code (`CourseBuilder`) : rien à exporter depuis Studio.

## Feuille de route
- **v0** : boucle complète au canon (fait, remplacé).
- **v0.2** : boucle des jeux de référence (entraînement, lancer par l'avatar, game feel, dégâts lisibles, zones,
  grands nombres) (fait, rejeté pour son style).
- **v0.3** : boucle et style calés sur les références (epic #9) : carte (#10), mannequin et cinématique (#11), interface
  (#12), collection (#13), boutique (#14), économie (#15). ← en cours
- **v1** : variantes « 1 en N » révélées en cinématique, renaissance avec nouveau parcours et nouveau lanceur (lance-pierre
  géant, catapulte, canon), tutoriel en chaîne d'objectifs, récompense quotidienne, index (issue #7).
- **v2** : produits Robux (passer, x2, lancer auto), événement avec compte à rebours, vignette et page du jeu.
