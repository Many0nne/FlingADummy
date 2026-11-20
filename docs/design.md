# Fling a Dummy — document de conception

Titre provisoire (à tester avant publication). Origine du concept : vault Obsidian, `Jeu Roblox/05 - Concepts/Concepts candidats.md`
(concept A) et `Jeu Roblox/La recette.md` (ce qui fait percer un jeu Roblox). Jeux de référence pour la boucle, l'interface
et le rythme : fiches `04 - Jeux disséqués/` du vault (01 *Throw Food For Animals*, 09 *Throw a Seed*, 03 *Hyper Realistic
Ragdoll*, 06 *BloxNG*, 12 *Net a Fish!*).

## Le jeu en une phrase
Dans un centre d'essais de crash-test, on s'entraîne à soulever des mannequins pour devenir plus fort, puis on lance un
mannequin à bout de bras sur une piste semée de vitres, de caisses et de murs. On gagne selon la distance, les os cassés et
les objets détruits, multipliés par la zone atteinte.

## Cibles (mesurées sur les jeux qui percent)
| Moment | Cible |
|---|---|
| Première action | 0 s (zone de lancer à côté du point d'apparition) |
| Première récompense | < 25 s |
| Premier équipement d'entraînement | ≈ 30-45 s |
| Première offre payante | ≈ 1 min (v2) |
| Première renaissance | < 3 min (v1) |

## Boucle principale (≈ 10-15 s)
1. **Prendre le mannequin** : monter sur la zone de lancer jaune ; l'avatar tient un mannequin au-dessus de sa tête.
2. **Jauge à 1 clic** : une jauge verticale apparaît, l'aiguille monte et descend seule (`+1` à `+20`) ; un clic, un toucher
   ou Espace l'arrête. Pas de zone PERFECT ni de bonus : le haut de la jauge est le max (`+20`), comme dans les
   jeux de référence.
3. **Élan** : l'avatar se penche en arrière puis projette le mannequin (0,35 s).
4. **Vol** : bandes noires, caméra qui suit, compteurs (distance, os, objets), bannière de la zone traversée, radio du
   mannequin ; chaque choc a son son, ses particules et son popup (« +1 BONE », « SMASH x6 », combos).
5. **Résultat** (4,5 s) : titre selon la violence du crash, lignes de gains qui tombent une à une, total qui grimpe,
   phrase de blessure (« Shattered skull, broken left arm ») et cause (« Hit a brick wall at 140 km/h »).

## Mécanique secondaire : l'entraînement
- Poste d'entraînement à côté de chaque zone de lancer (invite « Train ») : l'avatar soulève un mannequin en boucle.
- Chaque répétition (0,8 s) ajoute la **Throw Power** de l'équipement ; les répétitions remplissent des niveaux
  (« LEVEL UP! Throw Power +N »), 3 répétitions au premier niveau puis × 1,2 par niveau.
- **Équipements** (achetés avec l'argent) : mannequin en bois +1, pierre +3, fer +10, or +40, diamant +160, néon +700,
  cosmique +3 000 par répétition ; prix 100 $, 1,5 K, 25 K, 150 K, 2 M, 25 M.
- Vitesse de lancer = 110 + 30 × ln(puissance / 10) studs/s : la puissance explose (10 → 1 M), la distance monte
  régulièrement (≈ 145 m → 2,2 km).

## Deux courbes
- **Throw Power** (entraînement) → distance → zones plus lointaines.
- **Argent** (lancers) → équipements (entraînement plus rapide) et **valeur du mannequin** (multiplicateur + 0,25 par
  niveau, de 250 $ × 1,7 par niveau).

## Zones de la piste (2,4 km)
Test Track ×1 · Parking Lot ×1,5 (100 m) · Warehouse ×2,2 (250 m) · Highway ×3,3 (450 m) · Construction Site ×5 (700 m) ·
Junkyard ×7,5 (1 km) · Airfield ×11 (1,4 km) · Rocket Range ×16 (1,9 km). Gains = (distance + 10 × os + 5 × objets) ×
zone atteinte × valeur du mannequin.

## Dégâts lisibles
Chaque membre (10 pièces) suit les chocs : une variation brusque de vitesse au-delà d'un seuil casse un os (2 au-delà d'un
second seuil), au plus 3 par membre. Gravité par membre : contusion, cassé, broyé ; le membre vire du jaune au rouge
sombre, sur le mannequin et sur le panneau radio.

## Direction artistique
Centre d'essais de crash-test : hub de labo (béton clair, bandes de danger jaunes et noires, enseigne « CRASH TEST LAB »),
piste en bitume avec barrières et arches colorées par zone, mannequin jaune à cibles de crash-test. Lumière de plein jour
saturée. Interface : section suivante.

## Interface (grammaire des jeux de référence 01 / 09)
- **Police** : Fredoka One partout, blanc à contour noir fin ; grands nombres abrégés (`1.2K`, `3.4M`).
- **Boutons** : carrés arrondis à icône dessinée en couleur et libellé dessous ; Index et Shop au bord gauche, Dummies
  au bord droit (place du bouton de collection des références) ; pastille rouge « ! » quand un achat est possible.
- **Compteurs** (bas gauche) : biceps + Throw Power (cyan), liasse + argent (blanc), revenu « +$N/s » en vert à droite
  de l'argent quand l'attribut joueur `Income` est positif (posé par la collection, #13).
- **Objectif** (haut centre) : « Throw your dummy! » → « Train! » → « Throw your dummy! »… ; « Buy better gear! » /
  « Buy a better dummy! » dès qu'un achat est possible (flèche au-dessus du bouton) ; « Press STOP to throw! » après un
  niveau gagné à l'entraînement. Cible du décor : triangle jaune au-dessus, chevrons jaunes au sol qui défilent vers
  elle. Logique dans `Shared.Objectives`.
- **Cibles du décor** (point d'accroche pour la carte et la collection) : une `BasePart` avec le tag `ObjectiveTarget`
  et l'attribut `Objective` (`"Throw"`, `"Train"`…), plus `Lane` (couloir) ou `OwnerUserId` (joueur) si elle n'est pas
  partagée ; le joueur suit la plus proche de celles qui lui sont ouvertes. En attendant que le décor les pose,
  `Server.ObjectiveTargets` marque la zone de lancer et le poste d'entraînement de chaque couloir.
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
- 6 couloirs côte à côte (6 joueurs par serveur), un par joueur, reconstruits après chaque lancer.
- Le décor est généré par le code (`CourseBuilder`) : rien à exporter depuis Studio.

## Feuille de route
- **v0** : boucle complète au canon (fait, remplacé).
- **v0.2** : boucle des jeux de référence (entraînement, lancer par l'avatar, game feel, dégâts lisibles, zones,
  grands nombres). ← en cours (issues #1 à #6)
- **v1** : variantes « 1 en N » révélées en cinématique, renaissance avec nouveau parcours et nouveau lanceur (lance-pierre
  géant, catapulte, canon), tutoriel en chaîne d'objectifs, récompense quotidienne, index (issue #7).
- **v2** : produits Robux (passer, x2, lancer auto), événement avec compte à rebours, vignette et page du jeu.
