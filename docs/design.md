# Fling a Dummy — document de conception

Titre provisoire (à tester avant publication). Origine du concept : vault Obsidian, `Jeu Roblox/05 - Concepts/Concepts candidats.md`
(concept A) et `Jeu Roblox/La recette.md` (ce qui fait percer un jeu Roblox). Jeux de référence pour la boucle, l'interface
et le rythme : fiches `04 - Jeux disséqués/` du vault (01 *Throw Food For Animals*, 09 *Throw a Seed*, 03 *Hyper Realistic
Ragdoll*, 06 *BloxNG*, 12 *Net a Fish!*).

## Le jeu en une phrase
Dans un lobby de 4 joueurs, on s'entraîne en soulevant un mannequin pour devenir plus fort, puis on lance un mannequin de
crash-test à bout de bras dans un canyon de briques à tenons, sur une piste partagée semée de vitres, de tours de caisses,
de murs, de voitures-cibles et de panneaux-cibles. On gagne selon la distance, les os cassés et les objets détruits,
multipliés par la zone atteinte.

## Cibles (mesurées sur les jeux qui percent)
| Moment | Cible |
|---|---|
| Première action | 0 s (zone de lancer à côté du point d'apparition) |
| Première récompense | < 25 s |
| Premier équipement d'entraînement | ≈ 30-45 s |
| Première offre payante | ≈ 1 min (v2) |
| Première renaissance | < 3 min (v1) |

## Boucle principale (≈ 10-15 s)
1. **Prendre le mannequin** : monter sur sa place de la zone de lancer ; l'avatar tient un mannequin au-dessus de sa tête.
2. **Jauge à 1 clic** : une jauge verticale apparaît, l'aiguille monte et descend seule (`+1` à `+20`) ; un clic, un toucher
   ou Espace l'arrête. Pas de zone PERFECT ni de bonus : le haut de la jauge est le max (`+20`), comme dans les
   jeux de référence.
3. **Élan** : l'avatar se penche en arrière puis projette le mannequin (0,35 s).
4. **Vol** : bandes noires, caméra qui suit, compteurs (distance, os, objets), bannière de la zone traversée, radio du
   mannequin ; chaque choc a son son, ses particules et son popup (« +1 BONE », « SMASH x6 », combos).
5. **Résultat** (4,5 s) : titre selon la violence du crash, lignes de gains qui tombent une à une, total qui grimpe,
   phrase de blessure (« Shattered skull, broken left arm ») et cause (« Hit a brick wall at 140 km/h »).

## Mécanique secondaire : l'entraînement
- Un appareil d'entraînement par joueur, devant l'entrée de sa base, au milieu (podium à tenons, râtelier de mannequins,
  invite « Lift » / « Training dummy ») : l'avatar soulève au-dessus de la tête (développé) le mannequin de son palier
  d'équipement, en boucle. Pendant la séance, l'invite est masquée et aucun objectif ne s'affiche : seul le bouton STOP.
- Chaque répétition (0,8 s) donne **+1 EXP** et remplit la barre de niveau, 3 répétitions au premier niveau puis × 1,2
  par niveau. Le passage de niveau (« LEVEL UP! Throw Power +N ») donne la **Throw Power** : N = gain de l'équipement ×
  répétitions du niveau franchi (`Training.levelPower`), soit le même rythme qu'un gain à chaque répétition.
- **Équipements** (achetés avec l'argent) : mannequin en bois +1, pierre +3, fer +10, or +40, diamant +160, néon +700,
  cosmique +3 000 par répétition ; prix 100 $, 1,5 K, 25 K, 150 K, 2 M, 25 M.
- Vitesse de lancer = 110 + 30 × ln(puissance / 10) studs/s : la puissance explose (10 → 1 M), la distance monte
  régulièrement (≈ 145 m → 2,2 km).

## Deux courbes
- **Throw Power** (entraînement) → distance → zones plus lointaines.
- **Argent** (lancers) → équipements (entraînement plus rapide) et **valeur du mannequin** (multiplicateur + 0,25 par
  niveau, de 250 $ × 1,7 par niveau).

## Carte (v0.3) : lobby de 4 joueurs, piste unique
- **Hub** (pelouse à damier entourée de parois en gradins) : une **base par joueur** (terrain clôturé, 6 présentoirs vides
  prêts pour la collection, panneau « NOM'S BASE ») avec son **appareil d'entraînement** devant l'entrée, au milieu
  (podium à tenons, pastille jaune, râtelier, invite « Lift »), passage libre entre les deux, stands à auvents rayés « SELL » et « SHOP » (branchés par la collection et la
  boutique), chevrons jaunes vers la zone de lancer. Plan dans `Shared.CourseLayout`.
- **Zone de lancer commune** : bande orange à damier, ligne de départ blanche, **4 places côte à côte** (pastille à la
  couleur du joueur, nom et record au-dessus). Le joueur réapparaît à côté de sa place.
- **Piste partagée** (80 studs de large, 2,4 km) au fond d'un canyon en 3 gradins : parois en briques, herbe (ou neige,
  sable…) voxel qui déborde de chaque marche, décor voxel sur les terre-pleins et au pied des parois (traversable).
- **Obstacles partagés** (`Server.Obstacles`) : rangées de 4 vitres (une par colonne), tours de caisses (2 × 2 × 4) par
  colonne, murs de briques sur toute la largeur des colonnes, voitures-cibles et panneaux-cibles en damier jaune et noir.
  Une pièce déplacée réapparaît à sa place **5 s après le dernier choc** subi par son obstacle, une par une de bas en haut
  (0,05 s d'écart), en grossissant depuis son centre ; jamais sur un mannequin posé dedans. Un objet projeté est compté
  pour le mannequin le plus proche (règles dans `Shared.ObstacleRules`).

## Zones de la piste (2,4 km)
Chaque zone a son identité (couleur du sol, des parois, du dessus des gradins, décor), comme les zones de *Throw a Seed* :
| Zone | Début | Gains | Sol / parois | Décor |
|---|---|---|---|---|
| Meadow | 0 m | ×1 | vert citron / brun | arbres, buissons, fleurs, rochers |
| Forest | 100 m | ×1,5 | vert foncé / brun | sapins, champignons géants |
| Desert | 250 m | ×2,2 | sable / ocre | palmiers, cactus, buissons secs |
| Construction | 450 m | ×3,3 | jaune / brique | plots, barrières rayées, poutrelles |
| Snowfield | 700 m | ×5 | blanc bleuté / bleu glace | sapins enneigés, bonshommes de neige |
| Volcano | 1 km | ×7,5 | rouge / basalte, dessus lave | roches à veines de lave, arbres morts |
| Candy Land | 1,4 km | ×11 | rose / violet, dessus menthe | sucettes, sucres d'orge, boules de gomme |
| Moon Base | 1,9 km | ×16 | lavande / violet nuit | cristaux, cratères, fusées |

Gains = (distance + 10 × os + 5 × objets) × zone atteinte × valeur du mannequin.

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
  de l'argent quand l'attribut joueur `Income` est positif (posé par la collection, #13).
- **Objectif** (haut centre) : « Throw your dummy! » → « Train! » → « Throw your dummy! »… ; « Buy better gear! » /
  « Buy a better dummy! » dès qu'un achat est possible (flèche au-dessus du bouton) ; rien pendant la séance
  d'entraînement (le bouton STOP suffit). Cible du décor : triangle jaune au-dessus, chevrons jaunes au sol qui défilent vers
  elle. Logique dans `Shared.Objectives`.
- **Cibles du décor** (point d'accroche pour la carte et la collection) : une `BasePart` avec le tag `ObjectiveTarget`
  et l'attribut `Objective` (`"Throw"`, `"Train"`…), plus `Slot` (place du lobby) ou `OwnerUserId` (joueur) si elle
  n'est pas partagée ; le joueur suit la plus proche de celles qui lui sont ouvertes. `CourseBuilder` marque la pastille
  et l'appareil d'entraînement de chaque place.
- **Fenêtres** : cadre sombre, bandeau dégradé (icône, titre), croix rouge ; cartes d'objets grises (nom, rareté
  colorée de `Shared.Rarity`, rendu 3D en `ViewportFrame`, statistique, bouton : prix vert / rouge, « EQUIPPED »).
  Shop = équipements d'entraînement ; Dummies = mannequin lancé (valeur) et mannequins à venir en silhouette (#14) ;
  Index = cases vides en attendant la collection (#13).
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
  les places libres (mesure de 4 vols simultanés).
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
