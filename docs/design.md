# Fling a Dummy — document de conception

Titre provisoire (à tester avant publication). Origine du concept : vault Obsidian, `Jeu Roblox/05 - Concepts/Concepts candidats.md`
(concept A) et `Jeu Roblox/La recette.md` (ce qui fait percer un jeu Roblox). Jeux de référence pour la boucle, l'interface
et le rythme : fiches `04 - Jeux disséqués/` du vault (01 *Throw Food For Animals*, 09 *Throw a Seed*, 03 *Hyper Realistic
Ragdoll*, 06 *BloxNG*, 12 *Net a Fish!*).

## Le jeu en une phrase
Dans un lobby de 4 joueurs, on s'entraîne en soulevant un mannequin pour devenir plus fort, puis on lance un mannequin de
crash-test à bout de bras dans un canyon de briques à tenons, sur une piste partagée en douze thèmes, chacun avec ses
obstacles cassables et son piège signature (trampoline, ventilateur, presse, lave…). Le lancer ne rapporte pas d'argent : sa **CHANCE** (zones traversées,
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
4. **Vol** (hauteur plafonnée à 100 studs, glissade bornée : section « Vol plafonné », #113) : bandes noires,
   caméra qui suit (derrière et un peu sur le côté au ras du sol ; plus le mannequin monte,
   plus elle plonge vers la piste et se recale dans son axe, distance bornée selon la vitesse : `Shared.FlightFraming`,
   #88, comme la caméra de suivi de 01 et 09), bannière **CHANCE** (« 1.36X / CHANCE / 🍀 MEADOW ») qui monte pendant le
   vol, compteurs (distance, os, objets), radio du mannequin ; chaque choc a son son, ses particules et son popup
   (« +1 BONE », « SMASH x6 », combos).
5. **Atterrissage** (≈ 1 s, #53) : dès que le mannequin s'arrête (détecté par le client), trèfle et CHANCE finale
   « 🍀 X1.36 » au-dessus de lui (même police et même vert que la bannière du vol, apparition en rebond) et titre du
   crash dessous (« BRUTAL! »), « NEW RECORD! » au-dessus en cas de record, comme le « X1.22 » de 09 ; pas d'écran de
   détail, comme 01. S'il repart (plus de 0,4 s au-dessus du seuil d'arrêt), le vol reprend. Le tirage part dès que le
   serveur a compté le lancer (1 s d'arrêt), « X » au moins 0,9 s à l'écran : **arrêt → silhouette 1,07 s** (mesuré
   en Studio, 2 lancers ; cible < 1,5 s). Le détail reste sur la radio X-RAY, dans son coin jusqu'à 3 s après le comptage : bilan à sa gauche
   (distance, record, os, objets détruits, blessures « Shattered skull, broken left arm », cause « Hit a brick wall at
   140 km/h »).
6. **Tirage « 1 en N »** (`Client.Prize`, suspense calé sur 09 et 01) : silhouette noire debout au point
   d'atterrissage, caméra de face qui se rapproche. La cote défile en continu depuis « 1 IN 1 » (un tic par chiffre, de
   plus en plus aigu, vite puis de plus en plus lentement : `Collection.climbOdds`, 0,7 à 1,5 s par palier selon
   l'écart) ; à chaque palier atteint, la silhouette se change en candidat plus rare (`Collection.teaseSequence` : 0 à 3
   mannequins plus courants, chacun à sa cote, puis le gagné), comme la pousse → buisson → arbre de 09 : éclair blanc,
   étincelles, anneau, secousse, contour à la couleur de la rareté, exclamation en haut (« Lucky! » → « Super lucky! »
   → « Incredible luck! », comme « Super chanceux ! » de 01), arrêt de 0,45 s, puis la cote repart. Puis roulement (1,1 s, la silhouette tremble de plus en plus) et révélation : éclair plein
   écran, mannequin en couleurs qui grossit, rayons ; en haut au centre, **une seule fois** : taille et rareté
   (« BIG · RARE »), nom, « NEW! », $/s, cote ; bouton GO BACK (automatique après 5 à 8 s selon le palier ; le serveur
   rend la main au plus tard 20 s après l'atterrissage, jusqu'à ≈ 41 s pour un secret : `RevealPlan.resultTime`). HUD du
   hub masqué de l'atterrissage au GO BACK (#60).
   **Spectacle par palier de rareté** (#67, `Shared.RevealPlan`, effets `Client.RevealFx`) : Common / Uncommon,
   révélation vive (double anneau, éclat, sons) ; Rare / Epic, la silhouette hésite entre 2 ou 3 formes pendant le
   roulement (1,8 s), confettis de la couleur de la rareté ; Legendary / Mythic, ciel qui s'assombrit dès la silhouette,
   rayons et colonne de lumière, cote qui grimpe longtemps (× 1,6), explosion et forte secousse ; Secret, en plus, la
   séquence de 09 : écran noir et phrase propre au mannequin écrite lettre à lettre, décor dédié (tapis rouge, colonnes
   dorées, construit au-dessus de la piste), portail, pluie de pièces, « SECRET!! » et cote complète. Suspense mesuré :
   Common 2,8 s, Epic 7,1 s, Legendary 11,1 s, Secret 20,6 s jusqu'au portail. Passable au clic (ou Espace) après 1 s.
   **Annonce** à partir de Legendary : bandeau en haut pour tous les joueurs et ligne dans le chat, envoyés à la fin du
   résultat du gagnant (personne ne lui gâche son tirage). Test : attribut `DebugPrize` (Studio, contexte Server) =
   rareté 1-11, son nom ou « id:taille », imposé au prochain tirage.
7. **Poser** : de retour au hub, panneau « Place your Crash Dummy! » en bas au centre (rendu 3D). **Première pose à la
   main** (étape du tutoriel) : flèche et chevrons vers un présentoir libre de sa base, présentoirs libres en
   surbrillance, invite « Place » (E). Le mannequin gagné va d'abord au **stock** (inventaire) et dans la **barre
   d'outils** Roblox (#54) : un lancer suivant sans poser l'y laisse et y ajoute le nouveau, rien ne se perd ; le
   panneau montre le dernier gagné. Ensuite, la pose passe par la barre : mannequin **équipé** près d'un présentoir
   libre → invite « Place » ; le bouton **AUTO** (dans sa base ou à moins de 12 studs de sa clôture, vérifié aussi par
   le serveur) pose le mannequin tenu, sinon le dernier gagné.

## Mécanique secondaire : l'entraînement
- Un appareil d'entraînement par joueur, devant sa base à côté de l'entrée (podium à tenons, râtelier de mannequins
  suspendus, invite « Lift » / « Training dummy ») : l'avatar soulève au-dessus de la tête (développé) le mannequin de son palier
  d'équipement, en boucle. Pendant la séance, l'invite est masquée et aucun objectif ne s'affiche : seul le bouton STOP.
- **L'appareil s'habille au Training Gear acheté** (#92, `Shared.BaseLook.station`, comme les barres bois → pierre →
  fer → cyan de 01 / 09) : planches du podium, montants, traverse et marches à la couleur du mannequin du palier (bois,
  pierre, fer, or, diamant, néon, cosmique) ; le râtelier montre les mannequins des trois derniers paliers jusqu'au sien (bois, pierre, fer tant qu'il en possède moins de trois) ; étincelles
  dès le Diamond, liseré néon (bordure du podium, sous la traverse) dès le Neon. Achat : confettis au-dessus du
  râtelier, vus de tous (en plus du popup du propriétaire). La bordure du podium reste à la couleur de la place.
- Chaque répétition (0,8 s) donne l'**EXP de l'équipement** (« +N EXP », comme « +4 EXP / répétition » de 09) qui
  remplit la barre de niveau : 3 EXP au premier niveau puis × 1,2 par niveau, plafonnée à 12 répétitions de
  l'équipement du joueur (`LEVEL_MAX_REPS`, #15 : un niveau dure 10 s au plus, au moins un « LEVEL UP! » par séance ;
  sans plafond, le niveau 30 au bois demandait 594 répétitions, ≈ 8 min sans aucun gain ; 01 et 09 montent un niveau
  toutes les ≈ 3 s au début, un plafond plus bas ferait sonner le popup en continu), l'EXP en trop passe au niveau suivant
  (plusieurs niveaux d'un coup avec un bon équipement). Le passage de niveau (« LEVEL UP! Throw Power +N ») donne autant
  de **Throw Power** que l'EXP qu'il demandait : puissance gagnée = EXP gagnée = gain × répétitions.
- **Équipements** (achetés avec l'argent) : mannequin en bois +1, pierre +3, fer +10, or +40, diamant +160, néon +700,
  cosmique +3 000 EXP par répétition ; prix 100 $, 8 K, 120 K, 800 K, 1,8 M, 4,5 M (#15). Suite (#94,
  `Training.EXTENDED`) : ruby, emerald, plasma, omega, infinite, gain × 4 par palier (+12 K à +3 M), prix $20M, $50M,
  $200M (#133), $1.8B, $50B (le dernier, condition de la renaissance, après la plupart des mannequins à lancer) ; section
  « Progression longue ».
- Vitesse de lancer = 130 + 38 × ln(puissance / 10) studs/s (110 + 30 avant #113, qui borne la glissade) : la
  puissance explose (10 → 4,4 B), la distance monte régulièrement (≈ 140 m → 6 km).

## Deux courbes
Comme 01 et 09 : le lancer fait le lien entre les deux.
- **Throw Power** (entraînement) → distance → zones plus lointaines → **CHANCE** → mannequins plus rares.
- **Revenu** (mannequins posés dans la base) → argent → équipements (entraînement plus rapide), **mannequins à lancer**
  (boutique du stand SHOP, multiplicateur de chance) et présentoirs achetables.

## CHANCE et tirage (`Shared.Economy`, `Shared.Collection`)
- CHANCE = chance des zones × (1 + 2 % par os cassé + 1 % par objet détruit) × multiplicateur du mannequin lancé
  (section suivante) × 2^k (k renaissances, section « Renaissance »), arrondie au centième. La chance des zones
  vaut celle de la zone à son entrée et monte en continu jusqu'à celle de la suivante (18 à 2,4 km, 60 au bout de la
  piste de 6 km) : un
  premier lancer (≈ 145 m) donne ≈ 1.4X, comme le 1.36X de 09.
- Tirage : les mannequins sont essayés du plus rare au plus courant, chacun sort avec la probabilité min(1, CHANCE / n)
  (le plus courant ramasse le reste) ; la taille se tire de même à CHANCE^0,5. Probabilités exactes affichables
  (`Collection.probabilities`, `sizeProbabilities`), cote affichée = 1 / probabilité à CHANCE 1, × celle de la taille.
- **Premier lancer** : Crash Dummy (Common, 4 $/s) garanti.
- **64 mannequins** sur 11 raretés (#94) : les 21 dessinés ci-dessous (déclinaisons du modèle : couleur, matériau,
  casque, lunettes, cape), plus 43 générés par familles et palettes (`Shared.DummyFamilies`, section « Progression
  longue ») en haut de chaque rareté et dans quatre raretés au-delà de Secret (Divine, Celestial, Ethereal, Infinity).
  Mannequins dessinés :
  | Rareté | Mannequins | Revenu ($/s) | n |
  |---|---|---|---|
  | Common | Crash, Rookie, Traffic | 4 à 6 | 2 à 5 |
  | Uncommon | Mint, Biker, Nerd | 25 à 33 | 10 à 25 |
  | Rare | Ocean, Hero, Pilot | 150 à 200 | 60 à 150 |
  | Epic | Ice, Toxic, Royal | 900 à 1 200 | 500 à 1 200 |
  | Legendary | Gold, Lava, Diamond | 5 500 à 7 300 | 4 K à 10 K |
  | Mythic | Galaxy, Ghost, Neon | 33 K à 44 K | 40 K à 100 K |
  | Secret | Crash King, Void, Cosmic | 200 K à 260 K | 500 K à 2 M |
- **Revenus étagés** (#15, retour 10 de la review 2 : « la production des dummies par /s est trop proche des uns des
  autres ») : chaque rareté a sa plage de revenu (`Rarity.LIST[i].income`), × 2 du plus courant au plus rare, puis
  × 3 au passage à la rareté suivante (× 6 d'une rareté à l'autre) ; ses mannequins, dessinés et générés, s'y placent
  en progression géométrique par cote croissante (`DummyFamilies.bandIncome`). Avant, le plus rentable d'une rareté
  touchait le moins rentable de la suivante (Epic 1,8 K, Legendary 2,5 K) : un nouveau mannequin rare ne se voyait pas
  sur le compteur.
- **Tailles** : Normal (×1 revenu), Big (×2, 1 en 8), Huge (×5, 1 en 60), Giant (×12, 1 en 500) ; modèle agrandi
  (× 1,5 / × 3 / × 8 avant #15).
- **Spectacle par rareté** (#66) : chaque mannequin a son modèle (`Shared.DummyModels`, pièces ajoutées de plus en
  plus folles). Le modèle grandit avec la rareté (×1 Common à ×1,8 Secret, `Collection.RARITY_SCALE`, multiplié par
  la taille ; plafonné à ×2,5 sur un présentoir, `Collection.DISPLAY_SCALE_MAX`). Effets (`Shared.DummyAura`) : thème propre dès Uncommon (notes, bulles, réacteur, flocons…), puis aura
  de la couleur de la rareté : éclats dès Rare, onde au sol et lumière dès Epic, flaque de lumière et poussières
  montantes dès Legendary, gloire de rayons dès Mythic, colonne de lumière et gerbe d'étoiles en Secret. Les
  particules ne se rendent pas dans les fenêtres (ViewportFrame) : les vignettes montrent le modèle seul.

## Boutique de mannequins à lancer (#14, `Shared.ThrowDummies`)
L'équivalent des aliments de 01 et des graines de 09 : le mannequin qu'on lance, distinct des mannequins de collection
(on le possède une fois pour toutes, il ne rapporte rien, il ne va pas dans la barre d'outils).
- **Catalogue** (prix calés par #15 en alternance avec les équipements, section « Progression longue » ; le 1.25x
  proche de la graine 1.25x de 09, $1.2K) :
  | Mannequin | Prix | Chance | Comportement | Réglage |
  |---|---|---|---|---|
  | Crash Dummy | offert | 1.0x | Classic | densité 1,5, frottement 0,3, rebond 0,3 (le mannequin d'origine) |
  | Rubber Dummy (rose, pompon) | $1.5K | 1.25x | Bouncy | frottement 0,05 ; 4 rebonds au sol (60 % de la chute rendue vers le haut à chacun, le premier à ≈ 35 studs), à élan constant et sans frein, pour + 15 % de la portée naturelle à l'arrêt (#130) |
  | Glass Dummy (verre, étiquette FRAGILE) | $40K | 1.5x | Fragile | chocs × 2 pour les os : plus d'os cassés (+2 % chacun) |
  | Steel Dummy (acier, plaques de lest) | $250K | 2.0x | Heavy | densité 8 : il défonce les obstacles au lieu d'y rebondir |
  | Glider Dummy (vert, aile orange) | $1.2M | 2.5x | Glides | redescend du sommet à vitesse tenue (≈ 40 studs/s depuis le plafond, au lieu d'une chute libre à 150), pour + 20 % de la portée naturelle (#130) |
  | Rocket Dummy (rouge, réacteur) | $3M | 3.0x | Jetpack | poussée à plat vers l'avant pendant les 2 premières secondes (≈ + 25 % de vitesse), croisière allongée, pour + 20 % de la portée naturelle (#130) |
  Les pièges (`Shared.Traps`) remplacent la vitesse comme pour tous : le comportement reprend ensuite (portance,
  rebond) ou est fini (poussée). Réglages calculés par `FlightArc.plan` pour chaque vol (section « Comportements sous
  le vol plafonné »).
- **Suite du catalogue** (#94, `ThrowDummies.EXTENDED`) : 14 mannequins de 4x à 135x (« Ruby Rubber Dummy »,
  « Infinite Rocket Dummy »), chacun avec le comportement et la physique d'un des cinq ci-dessus sous une palette de
  `Shared.DummyFamilies`, prix calés par #15 ($12M à $200B, colonne `cost` de `ThrowDummies.EXTENDED`) ; seuls les six premiers sont exposés sur le
  stand (`ThrowDummies.SHOWCASE`). La boutique s'ouvre sur le prochain achat (défilement automatique, comme la
  fenêtre Training Gear).
- **Achat séquentiel** : seul le suivant s'achète, puis il est équipé d'office ; bouton **EQUIP** sur les possédés.
  Validé par le serveur (`ThrowDummies.act` : action, indice, ordre, possession, argent ; remote `ThrowDummy`).
- **Fenêtre « Dummy Shop »** (invite « Buy dummies » du stand SHOP, ou bouton SHOP du popup « NEW DUMMY! ») : bandeau
  rose, une carte par mannequin teintée à sa couleur comme les graines de 09 : nom, « 1.25x CHANCE » en jaune, rendu,
  comportement, bouton EQUIPPED / EQUIP (vert) / prix (jaune abordable, rouge sinon, refus « NOT ENOUGH MONEY! ») /
  « 🔒 prix » pour ceux d'après. Quatre cartes par rangée, la suite défile vers le bas (#45).
- **Popup « NEW DUMMY! »** (« Nouvelle graine débloquée ! » de 09 à 2:00) : même cadre que « NEW GEAR! » (un seul à la
  fois, l'équipement d'abord), bandeau rose, rendu, nom, prix et chance, bouton **SHOP** qui ouvre la boutique ; dès
  que le suivant est abordable, fermé il ne revient pas pour ce mannequin. Achat : popup « NEW DUMMY! » jaune.
- **En jeu** : l'avatar tient sur la bande le mannequin équipé (chaque client le construit d'après `ThrowEquipped`), le
  serveur lance ce mannequin avec son modèle et sa physique ; la bannière CHANCE porte un badge vert « RUBBER 1.25x »
  (multiplicateur déjà compté dans le chiffre).
- **Sauvegarde** avec les données du joueur : `ThrowTier` (mannequins possédés : les N premiers) et `ThrowEquipped`,
  bornés au catalogue au chargement.
- **Mesures** (avant le vol plafonné : historique, voir #130 pour les valeurs actuelles ; Studio, `DebugLaunch` = 1,
  attribut `DebugThrowDummy`, 2 vols chacun ; détail dans la PR #14) :
  | Mannequin | Puissance 10 : distance, CHANCE | Puissance 10,5 K : distance, CHANCE |
  |---|---|---|
  | Crash | 143-168 m, 1.76-1.81X | 1 139-1 167 m, 9.42-10.06X |
  | Rubber | 257-441 m, 2.69-3.56X, vol de 8,5-10,5 s | (avant le rebond dirigé) 1 033-1 136 m, 11.6-13.3X |
  | Glass | 144-145 m, 19-20 os, 3.32-3.40X | 989-1 143 m, 30 os, 15.2-18.7X |
  | Steel | 184-197 m, 28-30 objets, 3.85-3.91X | 1 645-1 649 m, 57-93 objets, 34.2-43.7X |
  | Glider | 248-254 m, 4.45-4.59X | (portance 0,5) 993-1 240 m, 22.4-25.1X |
  | Rocket | 320-324 m, 6.26-6.74X | 1 221-1 835 m, 33.0-62.9X |
  À haute puissance les pièges (tremplin de ski à 731 m, lave, canons) décident de la distance : les comportements s'y
  lisent surtout aux os et aux objets.

## Progression longue (#94)
Retour de la sprint review 1 : on arrivait au bout des améliorations en ≈ 1 h (Rocket et Cosmic achetés, bout de la
piste atteint à 43 min, dernier mannequin de collection à « 1 IN 2M »). *Throw a Seed* (09) monte jusqu'à des plantes
« 1 IN 300Qa » et des graines à 135x. La courbe ci-dessous vise **une douzaine d'heures** de jeu sans renaissance,
puis des jours avec la renaissance plus bas ; revenus et prix recalés par #15, cotes inchangées (section « Rythme et
économie »).

**Joueur simulé** (`lune run tools/progression [joueurs] [heures]`, `tools/ProgressionSim.luau`, médiane de 60
joueurs sur 14 h ; garde-fou : `tests/specs/Progression.spec.luau`) : vrais modules
du jeu (tirage, entraînement, CHANCE des zones, prix), une boucle = un lancer (15 s, comme 09) puis 15 s
d'entraînement, achats dès que possible (le moins cher d'abord), mannequins hors présentoirs vendus aussitôt. Distance
du vol plafonné (#113, `Shared.FlightArc` : premier contact au sol prévu, plus 0,4 de la glissade freinée, recalée
sur les vols mesurés de 10 K à 4,4 B), os et objets ≈ +30 % de CHANCE au départ, +55 % à 10,5 K. Non mesurés en jeu :
les pièges, les comportements des mannequins à lancer et le temps réel d'une boucle. Depuis #97, la piste fait 6 km
(temps ci-dessous rejoués avec elle).

**Grands nombres** (`Shared.Format`) : K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc (10^33), puis notation scientifique ;
3 chiffres significatifs tronqués ; cote « 1 IN 300Qa » (`Format.odds`), cote complète du secret avec séparateurs
jusqu'au milliard puis abrégée (`Format.fullOdds`), CHANCE « X5.11K », chance « 135x ».

### Collection : 11 raretés, 64 mannequins
Contenu en masse sans dessiner de pièce (`Shared.DummyFamilies`, comme les variantes « Emerald », « Ruby » de 09) :
un mannequin généré croise une **famille** (un des 21 modèles dessinés : pièces ajoutées, pièces masquées, effets) et
une **palette** (couleur du corps, teinte et matériau des pièces ajoutées, couleur des effets ; ni verre ni champ de
force, invisibles dans les fenêtres). Identifiant « palette_famille », nom « Palette Famille » (« Golden Void Dummy »).
Règles de cote et de revenu :
- raretés dessinées (Common à Secret) : 1 à 3 générés au-dessus des dessinés, sous la rareté suivante (cote en
  progression géométrique entre les deux, arrondie à 2 chiffres) ; un seul Common (deux cotes de Common à moins de 1
  d'écart sortiraient aussi souvent l'une que l'autre) ;
- au-delà de Secret : 6 par rareté, deux décades de cote chacune ;
- revenu (#15) : plage de la rareté (`Rarity.LIST[i].income`, × 2 du plus courant au plus rare, × 3 au passage à la
  rareté suivante), progression géométrique par cote croissante (`DummyFamilies.bandIncome`), dessinés compris. Avant
  #15 : revenus en progression géométrique jusqu'à la rareté suivante (le plus rentable d'une rareté touchait le moins
  rentable de la suivante), puis 300 K × (n / 2 M) ^ 0,45 au-delà de Secret.

| Rareté | Mannequins | Cotes (taille normale) | Revenu ($/s) | Avant #15 | Premier obtenu (simulé) |
|---|---|---|---|---|---|
| Common | 4 | 1 IN 3 à 10 | 4 à 8 | 4 à 9 | 15 s (garanti) |
| Uncommon | 6 | 1 IN 13 à 51 | 25 à 50 | 15 à 57 | 75 s |
| Rare | 6 | 1 IN 62 à 372 | 150 à 300 | 70 à 310 | 3 min |
| Epic | 6 | 1 IN 502 à 3K | 900 à 1.8K | 400 à 1.8K | 9 min |
| Legendary | 6 | 1 IN 4K à 28K | 5.5K à 11K | 2.5K à 14K | 24 min |
| Mythic | 6 | 1 IN 40K à 330K | 33K à 66K | 20K à 110K | 51 min (89 min avant #15) |
| Secret | 6 | 1 IN 500K à 4M | 200K à 400K | 150K à 410K | 2,2 h (3,8 h) |
| Divine | 6 | 1 IN 5M à 100M | 1.2M à 2.4M | 450K à 1.7M | 4,9 h (7,1 h) |
| Celestial | 6 | 1 IN 500M à 10B | 7.5M à 15M | 3.6M à 14M | 26,3 h (après la 4e renaissance ; 23,7 h) |
| Ethereal | 6 | 1 IN 50B à 1T | 45M à 90M | 29M à 110M | 73 h (après la 9e ; 185 h) |
| Infinity | 6 | 1 IN 5T à 100T | 270M à 540M | 230M à 870M | 262 h (> 300 h) |

Celestial à Infinity : 40 joueurs sur 300 h, renaissance à $350B × 2^k (section « Renaissance ») ; avant #15 entre
parenthèses ($50B × 4^k).

En taille Giant (× 500 de cote), le plus rare s'affiche « 1 IN 50Qa ». Spectacle : Divine et au-delà jouent la
séquence complète du secret (phrase propre à la rareté : « THE HEAVENS HAVE OPENED... »), aura un cran plus fournie par
rareté (éclats, poussières, colonne de lumière plus haute et plus large), modèle × 1,86 à × 2,05. Index : 11 onglets à
la hauteur de la colonne ; vente : boutons « Sell all » sur deux rangées. Les générés n'ont pas encore d'icône propre
dans la barre d'outils (icône de rareté jusqu'à Secret, nom au-delà).

### Mannequins à lancer : 20, jusqu'à 135x
| Mannequin | Chance | Prix | Atteint (simulé, #133) | Après #15 | Avant #15 |
|---|---|---|---|---|---|
| Rubber | 1.25x | $1.5K | 90 s | 90 s | $1.2K, 105 s |
| Glass | 1.5x | $40K | 4 min | 4 min | $15K, 4 min |
| Steel | 2.0x | $250K | 7 min | 8 min | $300K, 11 min |
| Glider | 2.5x | $1.2M | 12 min | 15 min | $4M, 24 min |
| Rocket | 3.0x | $3M | 16 min | 21 min | $50M, 57 min |
| Ruby Rubber | 4.0x | $12M | 24 min | 30 min | $84M, 73 min |
| Emerald Glass | 5.0x | $25M | 31 min | 39 min | $130M, 100 min |
| Sapphire Steel | 6.5x | $35M | 35 min | 44 min | $200M, 116 min |
| Amber Glider | 8.0x | $100M ($120M avant #133) | 47 min (48) | 61 min | $290M, 2,2 h |
| Golden Rocket | 10x | $140M ($180M) | 52 min (54) | 69 min | $440M, 2,6 h |
| Frost Rubber | 13x | $450M ($600M) | 66 min (69) | 92 min | $700M, 2,9 h |
| Magma Glass | 17x | $1B | 77 min (80) | 108 min | $1.1B, 3,6 h |
| Shadow Steel | 22x | $5B | 2,2 h | 2,9 h | $1.8B, 3,9 h |
| Radiant Glider | 30x | $9B | 2,7 h | 3,4 h | $3.2B, 4,5 h |
| Starlight Rocket | 40x | $15B | 3,2 h | 4,1 h | $5.3B, 5,3 h |
| Nebula Rubber | 55x | $30B | 3,9 h (4,0) | 4,9 h | $9.4B, 6,0 h |
| Plasma Glass | 75x | $80B | 5,9 h (6,1) | 6,8 h | $16B, 7,2 h |
| Quantum Glider | 100x | $120B | 7,2 h (7,4) | 8,2 h | $28B, 7,9 h |
| Infinite Rocket | 135x | $200B | 8,6 h (8,8) | 9,2 h | $47B, 8,9 h |

Atteint : joueur simulé rejoué par #133 (60 joueurs, 14 h, médianes ; gains de #129, comportements de #130), avant #133
entre parenthèses quand il diffère. Prix calés par #15 (section « Rythme et économie ») : la règle Rocket × (chance /
3)^1,8 de #94 laissait un trou de × 6 à × 12 entre les mannequins dessinés et les équipements ($300K → $2M → $4M →
$25M), le « mur » de la review 2. Amber Glider, Golden Rocket et Frost Rubber baissés par #133 (section « Rythme et
économie »).

### Training Gear : 12 paliers
| Équipement | EXP / rép. | Prix | Atteint (simulé, #133) | Après #129 | Avant #15 |
|---|---|---|---|---|---|
| Stone | +6 (+3 avant #129) | $100 | 45 s | 45 s | $100, 45 s |
| Iron | +45 (+10) | $8K | 3 min | 3 min | $1.5K, 2 min |
| Gold | +400 (+40) | $120K | 6 min | 6 min | $25K, 5 min |
| Diamond | +2.2K (+160) | $800K | 10 min | 11 min | $150K, 9 min |
| Neon | +9K (+700) | $1.8M | 15 min | 15 min | $2M, 18 min |
| Cosmic | +35K (+3K) | $4.5M | 18 min | 21 min | $25M, 41 min |
| Ruby | +140K (+12K) | $20M | 27 min | 30 min | $88M, 88 min |
| Emerald | +560K (+48K) | $50M | 39 min | 42 min | $310M, 2,5 h |
| Plasma | +2.2M (+190K) | $200M ($300M avant #133) | 57 min (60) | 66 min | $1.1B, 3,3 h |
| Omega | +8.8M (+760K) | $1.8B | 90 min (94) | 106 min | $3.9B, 4,9 h |
| Infinite | +35M (+3M) | $50B | 4,8 h (4,9) | 5,4 h | $14B, 6,6 h |

Puissance (gains de #129) : 1 K à 3 min, 100 K à 12 min, 1 M à 17 min, 100 M à 43 min, 10 B à 2,1 h (avant #129 :
5 min, 21 min, 32 min, 85 min, 6,4 h ; avant #15 : 5 min, 20 min, 45 min, 3,2 h, 7,8 h). Avec la piste de 2,4 km, le bout était atteint dès ≈ 760 K de puissance et la puissance
n'ajoutait ensuite que des os et des objets ; la piste de 6 km (#97) donne un but aux paliers prolongés (tableau
« Fin de piste » ci-dessous). Bout de piste simulé à 57 min depuis #133 (58 min après #130, 105 min après #129, 4,2 h
avant #129, 4,6 h avec le modèle de distance d'avant #113, 6,8 h avant #15), avec la distance recalée sur les vols
mesurés par #113.

### Rythme et économie (#15)
Retours de la review 2 (compte neuf) : les présentoirs s'achetaient trop vite (point 2 : les quatre en 7 min), et « à
partir des premiers millions, il devient beaucoup plus dur de s'améliorer » (point 10 : 12.7K/s, prochaine
amélioration à 25 M, soit 33 min d'attente). Objectif, calé sur 01 et 09 : premier achat en moins d'une minute, puis un
achat (équipement, mannequin à lancer ou présentoir) toutes les 1 à 5 min la première heure (6 min au plus depuis #133),
puis de plus en plus espacés, **sans mur** : le ratio « prix du prochain achat / revenu » (attente au revenu du moment, plancher 60 s) ne
fait jamais de saut de plus de × 2 d'un achat au suivant. Prix trouvés en calant chaque achat sur un calendrier cible
(écarts de 45 s à 5 min la première heure, puis × 1,22 par achat), lissés et arrondis ; revenus étagés par rareté
(section « CHANCE et tirage ») ; présentoirs vers 10 min, 30 min, 1 h et 2,5 h ; renaissance à $350B × 2^k.

Relevés (60 joueurs, 14 h, médianes ; achats : équipements, mannequins à lancer, présentoirs, renaissances, rachats
après une renaissance compris ; depuis #130, distance du mannequin équipé avec son comportement ; rejoués après #133) :
| Relevé | Achats | Revenu | Puissance | Rareté max | Avant #15 : achats, revenu, puissance, rareté |
|---|---|---|---|---|---|
| 2 min | 2 | $110/s | 336 | Uncommon | 3, $91/s, 161, Uncommon |
| 5 min | 4 | $1K/s | 4.05K | Rare | 6, $432/s, 1.19K, Rare |
| 10 min | 7 | $7.06K/s | 74.3K | Epic | 10, $2.18K/s, 15.3K, Epic |
| 30 min | 15 | $117K/s | 25.1M | Legendary | 13, $18.7K/s, 339K, Legendary |
| 60 min | 22 | $727K/s | 655M | Mythic | 15, $63.9K/s, 2.52M, Legendary |
| 3 h | 28 | $7.47M/s | 31.5B | Secret | 23, $707K/s, 80.6M, Mythic |
| 8 h | 33 | $35.6M/s | 296B | Divine | 33, $10.8M/s, 11B, Divine |
| 14 h | 65 (1 renaissance) | $94.8M/s | 125B | Divine | 94 (2 renaissances), $34.8M/s, 9.23B, Divine |

Prix suivant / revenu, minute par minute (médiane, `lune run tools/progression 60 14 "" courbe.csv` pour la courbe
complète) :
| Minute | 1 | 5 | 10 | 15 | 20 | 30 | 60 | 2 h | 4 h | 6 h | 8 h | 10 h |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Après #15 | 51 s | 2 min | 3 min | 3 min | 4 min | 5 min | 8 min | 23 min | 50 min | 66 min | 89 min | 110 min |
| Après #129 | 51 s | 2 min | 2 min | 3 min | 3 min | 5 min | 9 min | 22 min | 51 min | 73 min | 96 min | 104 min |
| Après #130 | 51 s | 2 min | 2 min | 2 min | 3 min | 4 min | 9 min | 23 min | 53 min | 77 min | 94 min | 92 min |
| Après #133 | 51 s | 2 min | 2 min | 2 min | 3 min | 4 min | 9 min | 25 min | 53 min | 72 min | 96 min | 96 min |
| Avant #15 | 52 s | 68 s | 3 min | 8 min | 9 min | 22 min | 18 min | 18 min | 25 min | 38 min | 50 min | 29 min |

Achat par achat (le moins cher d'abord : même ordre pour tous les joueurs ; ratio juste après l'achat ; rejoué après #133) :
| # | Achat | Prix | Atteint | Prix suivant / revenu | Saut |
|---|---|---|---|---|---|
| 1 | Stone Dummy (équipement) | $100 | 45 s | 51 s | × 1,0 |
| 2 | Rubber Dummy (à lancer) | $1.5K | 90 s | 100 s | × 1,7 |
| 3 | Iron Dummy | $8K | 3 min | 2 min | × 1,3 |
| 4 | Glass Dummy | $40K | 4 min | 3 min | × 1,2 |
| 5 | Gold Dummy | $120K | 6 min | 3 min | × 1,0 |
| 6 | Steel Dummy | $250K | 7 min | 2 min | × 0,8 |
| 7 | Présentoir 7 | $450K | 9 min | 3 min | × 1,2 |
| 8 | Diamond Dummy | $800K | 10 min | 2 min | × 0,9 |
| 9 | Glider Dummy | $1.2M | 12 min | 2 min | × 1,0 |
| 10 | Neon Dummy | $1.8M | 15 min | 2 min | × 1,0 |
| 11 | Rocket Dummy | $3M | 16 min | 3 min | × 1,1 |
| 12 | Cosmic Dummy | $4.5M | 18 min | 3 min | × 1,3 |
| 13 | Présentoir 8 | $7M | 21 min | 4 min | × 1,3 |
| 14 | Ruby Rubber Dummy | $12M | 24 min | 5 min | × 1,1 |
| 15 | Ruby Dummy | $20M | 27 min | 4 min | × 0,9 |
| 16 | Emerald Glass Dummy | $25M | 31 min | 4 min | × 1,1 |
| 17 | Sapphire Steel Dummy | $35M | 35 min | 5 min | × 1,2 |
| 18 | Emerald Dummy | $50M | 39 min | 5 min | × 1,0 |
| 19 | Présentoir 9 | $70M | 43 min | 6 min | × 1,1 |
| 20 | Amber Glider Dummy | $100M ($120M avant #133) | 47 min | 6 min | × 1,0 |
| 21 | Golden Rocket Dummy | $140M ($180M) | 52 min | 6 min | × 1,1 |
| 22 | Plasma Dummy | $200M ($300M) | 57 min | 10 min | × 1,6 |
| 23 | Frost Rubber Dummy | $450M ($600M) | 66 min | 16 min | × 1,6 |
| 24 | Magma Glass Dummy | $1B | 77 min | 20 min | × 1,2 |
| 25 | Omega Dummy | $1.8B | 90 min | 22 min | × 1,1 |
| 26 | Présentoir 10 (Golden) | $3B | 110 min | 28 min | × 1,3 |
| 27 | Shadow Steel Dummy | $5B | 2,2 h | 36 min | × 1,3 |
| 28 | Radiant Glider Dummy | $9B | 2,7 h | 42 min | × 1,2 |
| 29 | Starlight Rocket Dummy | $15B | 3,2 h | 57 min | × 1,4 |
| 30 | Nebula Rubber Dummy | $30B | 3,9 h | 72 min | × 1,2 |
| 31 | Infinite Dummy | $50B | 4,8 h | 71 min | × 1,0 |
| 32 | Plasma Glass Dummy | $80B | 5,9 h | 85 min | × 1,2 |
| 33 | Quantum Glider Dummy | $120B | 7,2 h | 104 min | × 1,2 |
| 34 | Infinite Rocket Dummy | $200B | 8,6 h | 2,2 h | × 1,3 |
| | Renaissance 1 | $350B | 10,5 h (10,6 h avant #133, 11,1 h avant #130) | | |

Saut le plus fort : **× 1,67** depuis #129 (× 1,69 avant, × 4,29 avant #15 : Steel Dummy à 11 min, 11 min d'attente pour le Glider ; puis
× 3,3 au Glider, 32 min d'attente pour le Cosmic, le mur du point 10). 22 achats la première heure (21 avant #133, 19 avant #129, 15 avant #15, dont 10
dans les 10 premières minutes). Les écarts approchent 5 min dès ≈ 40 min de jeu ; depuis #133, aucun ne dépasse
**6 min** dans la première heure (médiane de 200 joueurs, garde-fou `Progression.spec`).

**Écart entre deux achats de la première heure (#133).** Règle : un achat fait dans la première heure suit le
précédent de 6 min (360 s) au plus. #129 avait porté la borne du test à 7 min (375 s au 20e achat). Relevé d'avant
#133 (instants médians, s ; écart au précédent entre parenthèses) :
| Achat | 15 joueurs (ancien test) | 60 joueurs | 200 joueurs |
|---|---|---|---|
| 18 Emerald Dummy ($50M) | 2475 | 2310 | 2295 |
| 19 Présentoir 9 ($70M) | 2685 (210) | 2580 (270) | 2580 (285) |
| 20 Amber Glider Dummy ($120M) | 3045 (**360**) | 2895 (315) | 2880 (300) |
| 21 Golden Rocket Dummy ($180M) | 3405 (**360**) | 3240 (345) | 3255 (**375**) |
| 22 Plasma Dummy ($300M) | 3840 (435) | 3615 (375) | 3645 (390) |
| 23 Frost Rubber Dummy ($600M) | 4560 (720) | 4155 (540) | 4215 (570) |
Cause : les prix entre le présentoir 9 et le Plasma Dummy. Entre 43 et 60 min, deux achats seulement (Amber Glider
× 1,71 le présentoir 9, la plus forte marche de prix depuis la 25e minute, où elles vont de × 1,25 à × 1,43 ; puis
Golden Rocket × 1,5), alors que le présentoir 9 n'ajoute au revenu que le 9e mannequin de la base, le moins
rentable : le ratio « prix suivant / revenu » monte à 7 min juste après le présentoir. Trois écarts de 5,7 min en
moyenne, donc au-dessus de 6 min dès que le hasard des tirages retarde un achat. Le Plasma Dummy tombe à 60 min ± 1 :
selon les graines, l'écart qui le précède (6 à 7 min) compte ou non dans la première heure. L'ordre d'achat du
joueur simulé (le moins cher d'abord) n'y est pour rien : ce sont les moins chers restants, un vrai joueur les prend
dans le même ordre. Baisser seulement l'Amber Glider et le Golden Rocket ne suffisait pas (essai à $110M et $150M :
le Golden Rocket arrive plus tôt et l'attente du Plasma Dummy passe à 7,5 min). Correction : les quatre prix de la
fenêtre, Amber Glider $100M (× 1,43), Golden Rocket $140M (× 1,4), Plasma Dummy $200M (× 1,43), Frost Rubber $450M
(× 2,25 : avec $600M et le Plasma Dummy à $220M, 10,5 min d'attente et un saut du ratio jusqu'à × 1,98). Relevé
d'après #133 :
| Achat | 15 joueurs | 60 joueurs | 200 joueurs (test) |
|---|---|---|---|
| 19 Présentoir 9 ($70M) | 2685 (210) | 2580 (270) | 2580 (285) |
| 20 Amber Glider Dummy ($100M) | 2985 (300) | 2835 (255) | 2835 (255) |
| 21 Golden Rocket Dummy ($140M) | 3315 (330) | 3135 (300) | 3150 (315) |
| 22 Plasma Dummy ($200M) | 3615 (300) | 3435 (300) | 3450 (300) |
| 23 Frost Rubber Dummy ($450M) | 4230 (615) | 3945 (510) | 3945 (495) |
La première heure finit sur le Plasma Dummy à 57 min ; l'attente suivante (Frost Rubber, 8 à 10 min) ouvre la
deuxième heure, où les écarts s'allongent comme prévu (Magma Glass ≈ 11 min après). Bruit : la médiane de 15 joueurs
déplace les instants de ± 60 s selon les graines (plus grand écart de la première heure de 330 à 435 s sur 7 lots de 15
joueurs avant #133, 330 à 390 s sur 4 lots après) ; 330 à 420 s sur 4 lots de 200 joueurs avant, 300 à 315 s sur 3 lots
après. Le garde-fou `Progression.spec` mesure donc la première heure sur 200 joueurs (75 min simulées, ≈ 1 s), et l'ancien
réglage y échoue (375 s). Jalons (60 joueurs, 14 h) : Plasma Dummy 57 min (60, − 5 %), Omega 90 min (94, − 4 %),
Infinite 4,8 h (4,9), bout de piste 57 min (58), première renaissance 10,5 h (10,6) ; revenu à 60 min $727K/s ($758K/s),
puissance 655 M (557 M) ; saut le plus fort du ratio × 1,67 (inchangé).

Écarts aux références : la puissance monte ≈ 3 fois moins vite que 09 (× 10 toutes les ≈ 8 min au lieu de 3,5 min) ;
le revenu suit 01 jusqu'à ≈ 10 min ($3.3K/s), puis plus lentement (01 : 391K/s à 17 min). Mesuré en Studio (compte
neuf, 5 min pilotées par attributs : lancer jauge pleine, pose, 15 s d'entraînement, achats dès que possible) : Stone
Dummy à 44 s, Rubber Dummy à 2:07, Iron Dummy à 2:54, Glass Dummy à 4:29 (simulé : 45 s, 90 s, 3 min, 4 min) ; revenu
$548/s à 4:48 (simulé : $790/s à 5 min). Le Rubber Dummy rebondit bien plus loin que le modèle (1,2 à 1,9 km à
161 de puissance, Rare dès 2:24) mais allonge la boucle (vols de 15 à 21 s) : mesure d'avant #113 ; depuis #130, + 15 %
de la portée naturelle et vols de 10 à 16 s.

### Gains des équipements calés sur 09 (#129)
Le joueur simulé montait ≈ 2 fois moins vite que *Throw a Seed* (09) : #15 avait recalé les prix, pas les gains de
`Training.GEARS`. Gains relevés (Stone +6, Iron +45, Gold +400, Diamond +2.2K, Neon +9K, Cosmic +35K, soit ≈ × 4 à
× 9 par palier au lieu de × 3 à × 4,5 ; la suite garde × `GAIN_STEP` = 4), prix, répétitions par séance et niveaux
inchangés. Cible : ≈ 1 K vers 4 min, ≈ 100 K vers 11-12 min, tolérance ± 30 %. Joueur simulé rejoué (60 joueurs, 14 h,
médianes) :
| Repère | Avant #129 | Après #129 | 09 *Throw a Seed* |
|---|---|---|---|
| Puissance 1 K | 5 min | 3 min | 1.34K à 4 min |
| Puissance 100 K | 21 min | 12 min | 114K à 11 min |
| Puissance 1 M | 32 min | 17 min | — |
| × 10 (1 M → 10 M → 100 M) | 19 min, 34 min | 10 min, 16 min | ≈ 3,5 min |
| Fin de Moon Base (2,4 km) | 30 min | 17 min | — |
| Fin de piste (6 km) | 4,2 h | 105 min | — |
| Première renaissance | 11,5 h | 11,1 h | — |
| Saut le plus fort du ratio d'achat | × 1,73 | × 1,67 | — |
Puissance à 14 h : 137 B (11,8 B avant). Le rythme de 09 est tenu sur les 20 premières minutes ; ensuite les prix de #15
(inchangés) bornent la montée des équipements (**cible × 10 toutes les 3,5 à 5 min manquée après 12 min**, écart connu : levier suivant = prix ou répétitions, hors périmètre de #129) : × 10 toutes les 10 à 16 min jusqu'à 100 M. La fin de piste arrive à 105 min
(> 45 min) : pas de recalage de la renaissance, qui reste à 11,1 h (le prix en $ pilote le calendrier). Garde-fou
`Progression.spec` : écart maximal entre deux achats de la première heure porté de 6 à 7 min (le 20e achat tombe à 375 s
d'écart), puis ramené à 6 min par #133 (prix de l'Amber Glider au Frost Rubber, section « Rythme et économie »).
Planche `entrainement.jpg` : les gains affichés sur l'appareil changent, à régénérer en Studio (manifeste déjà à jour).

### Repères comparés aux références
| Repère | Fling a Dummy (simulé) | 09 *Throw a Seed* | 01 *Throw Food For Animals* |
|---|---|---|---|
| Première récompense | 15 s | 21 s | 24 s |
| Premier équipement | 45 s ($100) | 1:45 ($500) | 0:42 ($1) |
| Deuxième projectile | 90 s (1.25x, $1.5K) | 1:42 (1.25x, $1.2K) | 1:27 (pomme) |
| Puissance | 1K à 3 min, 100K à 12 min | 1.34K à 4 min, 114K à 11 min | 503 à 17 min |
| Revenu | 1K/s à 6 min, 100K/s à 32 min | 2.19K/s à 3:36 | 1.08K/s vers 9 min, 391K/s à 17 min |
| Projectile le plus fort | 135x à 8,6 h | 135x (durée inconnue) | non observé |
| Cote la plus haute | 1 IN 100T (50Qa en Giant) | 1 IN 300Qa | non observé |
| Collection | 64 mannequins, 11 raretés | 110 plantes, 10 raretés + Royal | non observé |

Écarts : la puissance suit 09 sur les 20 premières minutes depuis #129 (≈ 2 fois moins vite avant), le revenu ≈ 2 fois plus vite qu'avant #15 (100K/s à
40 min au lieu de 83) ; la collection reste plus petite que celle de 09 (familles et palettes à ajouter sans dessin).

### Piste prolongée (#97) et renaissance (#108) : les deux leviers
1. **Piste prolongée à 6 km** (#97) : six thèmes de plus après Moon Base, un tous les 600 m (section « Zones de la
   piste »), CHANCE des zones de × 18 à × 60. Joueur simulé rejoué (60 joueurs, 14 h, après #15 et #113) et vols mesurés en Studio
   (Crash Dummy, jauge pleine, `DebugLaunch`) :
   | Fin de piste | Vitesse | Puissance (Crash Dummy) | Atteinte (simulé, mannequin équipé : #130 ; #129 avant) | CHANCE des zones | Vols mesurés (#113, 6 par puissance) |
   |---|---|---|---|---|---|
   | 2,4 km (fin de Moon Base) | 557 | 760 K | 13 min (17) | × 18 | (#14, #33) |
   | 3,6 km (Neon City) | 685 | 22 M | 20 min (32) | × 27 | 3 590 à 3 630 m |
   | 4,8 km (Haunted Castle) | 791 | 360 M | 48 min (54) | × 40 | 4 867 à 4 991 m, 5 021 à 5 510 m après un piège |
   | 6 km (bout) | 886 | 4,4 B | 58 min (105 ; 4,2 h avant #129) | × 60 | bout de piste 6 fois sur 6 (6 043-6 048 m) |
   Depuis #130, le joueur simulé compte la distance du mannequin équipé : la fin de piste arrive avec moins de
   puissance (Golden Rocket à 54 min, + 20 %).
   Avant #113, les vols montaient à ≈ 590 studs à 4,4 B puis glissaient au hasard (4,1 à 6,0 km à 4,4 B, mesures de
   #97) ; le vol plafonné (#113, section « Vol plafonné ») tient ces paliers à ± 2 % hors pièges. Effet simulé de la
   piste de 6 km : CHANCE finale × 3,3 (17 K au lieu de 5,1 K à 24 h), Divine à 7,1 h au lieu de 12,3 h.
2. **Renaissance** : faite (#108), section suivante. L'estimation de conception (une renaissance refaite en 1 à 2 h)
   était trop optimiste : avec la piste de 6 km, le joueur simulé met 4 à 80 h entre deux renaissances avec le prix
   × 4 de #108, 4 à 11 h jusqu'à la 7e avec le prix × 2 de #15.

### Vol plafonné et glissade bornée (#113, `Shared.FlightArc`)
Retours de la sprint review 2 : le mannequin glissait parfois de 4 ou 5 thèmes après l'atterrissage, et la puissance
le faisait monter toujours plus haut (≈ 590 studs à 4,4 B, carte vue de très haut par la caméra de vol).
- **Hauteur max 100 studs** (`APEX_HEIGHT`) : le lâcher ne change pas (32°, vitesse de la puissance et de la jauge).
  Si le sommet naturel dépasse le plafond, la montée est freinée pour s'arrêter pile à 100 studs, le mannequin y file
  à plat, puis retombe librement pour toucher le sol là où l'aurait posé l'arc naturel (`FlightArc.plan`) : la
  puissance en trop part en distance. Sous ≈ 600 de puissance, l'arc reste naturel. La caméra de vol reste à ≈ 130
  studs de la piste, obstacles et pièges lisibles (captures : `docs/captures/vol/`).
- **Glissade bornée** : après le premier choc (sol, obstacle), frein de 600 studs/s² sur l'élan le long de la piste
  (sous 6 studs de haut seulement : pas en l'air après un rebond) et vitesse latérale amortie (× e^-6t) : le mannequin
  reste dans sa colonne et s'arrête en ≈ 1 s. Hauteur comptée depuis le fond de la piste (y = 0) : posé sur un
  gradin ou un obstacle de plus de 6 studs, le mannequin n'est pas freiné (rare : il reste dans sa colonne). Glissade théorique = vitesse² / 1 200 (470 m au plus à 4,4 B), mesurée
  à 0,3 à 0,75 de cette valeur (obstacles et rebonds au point de chute).
- **Pièges** : un piège qui projette lève le plafond pour le reste du vol (son rebond peut le passer, c'est voulu) ;
  l'élan n'est ni freiné ni amorti pendant 0,5 s après un piège (`TRAP_COAST` : la poussée d'un canon ou d'un ventilateur au
  sol se voit, non mesuré), puis le frein reprend au sol.
- **Mesures** (Studio, `DebugLaunchBots`, Crash Dummy, jauge pleine, 6 vols par puissance) :
  | Puissance | Sommet avant → après | Premier contact | Glissade avant → après | Distance finale avant | Distance finale après |
  |---|---|---|---|---|---|
  | 10 K | 123 → 100 studs | 746-756 m → 1 149 m | 67-109 → 60-80 m | 823-865 m (± 2,5 %) | 1 210-1 265 m (± 2,3 %) |
  | 22 M | 356 → 100 | 2 245 m → 3 509-3 525 m | 253-1 116 → 66-121 m | 2 501-3 365 m (± 15 %) | 3 590-3 630 m (± 0,6 %) |
  | 360 M | 472 → 100 | 2 993 m → 4 726 m | 289-556 → 141-265 m | 3 282-3 548 m (± 4 %) | 4 867-4 991 m (± 1,3 %) ; 5 021-5 510 m après un piège |
  | 4,4 B | 589 → 100 | 3 744 m → 5 720-6 008 m | 660-2 071 → 40-323 m | 4 400-5 819 m (± 14 %) | 6 043-6 048 m (± 0,1 %) : bout de piste 6 sur 6, contre la paroi (trou de ver à 5 848 m) |
  Durée d'un vol à 4,4 B : 10 à 12 s (12 à 16,5 s avant). La vitesse de lancer est relevée (110 + 30 × ln → 130 +
  38 × ln) pour garder les paliers du modèle malgré la glissade raccourcie : 22 M → 3,6 km, 360 M → 4,8-5 km, 4,4 B →
  bout de piste.
- **Joueur simulé recalé** : distance = premier contact de `FlightArc.plan` + 0,4 × la glissade théorique
  (`tools/ProgressionSim.luau`). Temps rejoués avec l'économie de #15 (60 joueurs, 14 h) : achats décalés de 0 à
  0,2 h (Infinite Rocket 9,4 h au lieu de 9,6 h), bout de piste 4,2 h au lieu de 4,6 h.

### Comportements sous le vol plafonné (#130, `Shared.FlightArc`)
Mesurés après #113, le Rocket ne gagnait plus que + 1,6 % (sa poussée finissait avant la croisière, dont la fin était
calculée sans elle), le Rubber partait au hasard (3,6 à 5,5 km à 22 M : ± 21 %, rebonds physiques) et le Glider
variait de 4,2 à 5 km. Décision : **chaque comportement gagne une part fixe de la portée naturelle** (l'arc du Crash
Dummy à même puissance et jauge), quelle que soit la puissance, sans passer le plafond :
- `ThrowDummies` donne la part (`glide`, `thrust`, `bounce`) ; `FlightArc.plan` en tire les réglages du vol : poussée
  (studs/s²) qui ajoute la part au point de chute de l'arc naturel, fin de croisière reculée d'autant ; vitesse de
  descente tenue du planeur qui allonge sa descente de la part × durée de l'arc ; élan des rebonds du caoutchouc qui
  ajoute la part à l'arrêt (glissade plus courte comprise).
- **Rocket** (+ 20 %) : pousse à plat pendant 2 s (montée et début de croisière), vitesse ≈ + 25 %, croisière plus
  longue au plafond. **Glider** (+ 20 %) : quitte le plafond au même point que le Crash Dummy et redescend à
  ≈ 40 studs/s (≈ 2,5 s de descente au lieu de 1,3). **Rubber** (+ 15 %) : 4 rebonds de hauteur fixe (≈ 35, 13, 4,5
  et 1,7 studs), élan rétabli à chaque rebond, pas de frein au sol entre deux rebonds ; rebond reconnu sur la chute la
  plus forte depuis le précédent (les membres touchent souvent avant le torse), au plus les 4 du plan (les petits
  rebonds physiques ne comptent pas), au sol seulement (torse sous 6 studs), jamais plus haut que la
  chute. Pièges : pendant leur poussée (0,5 s), ni rebond réglé ni portance ; après un piège, le Rubber rebondit
  librement (physique).
- Sol plat (test Lune, de 200 à 4,4 B de puissance) : Rubber + 14,5 %, Glider + 18,5 %, Rocket + 22,5 % à l'arrêt
  (part de la portée naturelle, plus la glissade du Rocket plus rapide).
- **Mesures** (Studio, `DebugLaunchBots` avec `DebugBotsPower` et `DebugBotsDummy`, jauge pleine, 3 couloirs ; 6 à 9 vols
  par mannequin à 22 M et 4,4 B, 3 à 6 à 360 M et 1 M ; distance finale, durée du vol ; Rubber, Glider et Rocket
  revérifiés sur le code final) :
  | Puissance | Crash | Rubber avant → après | Glider avant → après | Rocket avant → après |
  |---|---|---|---|---|
  | 22 M | 3 584-3 624 m, 7,5-8,5 s | 3 611-5 537 m (± 21 %) → **4 186-4 304 m (+ 17 %)**, un vol à 3 872 m (dispersion ± 5 % avec lui), 2 à 4 rebonds, 10,5-11,9 s | 4 212-4 989 m (± 8 %) → **4 310-4 577 m (+ 24 %, ± 3 %)**, 8,9-9,7 s | 3 650-3 669 m (+ 1,6 %) → **4 320-4 694 m (+ 23 %, ± 4 %)**, 7,6-9 s ; 5 501 m après un piège |
  | 360 M | 4 834-4 907 m | → 5 201-5 819 m (+ 7 à + 20 %) | → bout de piste (6 037 m) | → 5 751-5 770 m (+ 19 %) |
  | 1 M | 2 451-2 500 m | → 3 300 m (piège vers 2,9 km, 3 sur 3) | → 3 007 m (+ 21 %), 2 vols sur 3 projetés par un piège | → 3 018 m (+ 22 %), idem |
  | 4,4 B | 6 044-6 049 m, 9,8-15,4 s | bout de piste avant comme après, 13,1-16 s | bout de piste, 9,1-11,5 s | bout de piste, 7,8-7,9 s |
  Premier contact au point du plan (Glider 4 192 m, Rocket 4 197 m, prévus 4 211 m ; Crash et Rubber 3 506-3 523 m,
  prévus 3 508 m, à 22 M). Glissade après le premier contact à 22 M : Crash 61-104 m (un vol à 249 m), Rubber 664-798 m
  (rebonds compris), Glider 118-385 m, Rocket 124-497 m (vitesse plus haute). Moyennes à 22 M dans la cible
  (+ 17 à + 24 %), vols isolés jusqu'à + 28 %. Sommet 100 studs pour tous (101 au plus : l'asservissement de
  croisière dépasse d'un stud, comme pour le Crash Dummy de #113) ; vol le plus long 16 s (Rubber à 4,4 B) : `MAX_FLIGHT_TIME` (20 s) suffit. À 4,4 B le Crash
  Dummy finit déjà contre la paroi : l'avantage s'y lit en CHANCE de zone avant le bout de piste, pas à l'arrivée.
- **Joueur simulé** : distance et CHANCE du mannequin équipé (`ProgressionSim.distanceFor` avec son comportement,
  glissade à la vitesse d'arrivée du plan). Rejoué sur l'économie de #129 (60 joueurs, 14 h) : achats avancés de 0 à
  5 min la première heure (Golden Rocket 54 min au lieu de 59), de 10 à 25 min ensuite (Magma Glass 80 min au lieu de
  91, Infinite Rocket 8,8 h au lieu de 9,2 h), renaissance 10,6 h au lieu de 11,1 h, saut le plus fort inchangé
  (× 1,67), bout de piste 58 min au lieu de 105.

### Renaissance (#108, `Shared.Rebirth`)
Le levier après tout le catalogue d'achats (≈ 11,1 h simulées depuis #129 ; 9,6 h avant), comme la
RENAISSANCE de *Net a Fish!* (12) et
d'*Ant Evolution* (05) : on repart de zéro contre une CHANCE plus forte, pour toujours.
- **Condition** : posséder le dernier équipement d'entraînement (Infinite) **et** payer **$350B × 2^k** (k renaissances
  déjà faites : $350B, $700B, $1.4T, $2.8T… ; $50B × 4^k avant #15 et #109). Validée par le serveur (`PlayerData.rebirth` : chargé, au hub, ni en vol
  ni jauge ouverte, `Rebirth.missing`), remote `Rebirth` sans charge ; la séance d'entraînement en cours s'arrête.
- **Remis à zéro** (valeurs d'un nouveau joueur, `Rebirth.RESET`) : argent, Throw Power, niveau et EXP
  d'entraînement, équipement d'entraînement, mannequins à lancer achetés (retour au Crash Dummy). **Gardés** :
  collection (base, présentoirs achetés, stock, Index), tutoriel terminé, record de distance, tirages.
- **Effet** : CHANCE × 2^k définitive, dans la même chaîne que la CHANCE des zones et du mannequin lancé
  (`Economy.chance`, champ `rebirth`, capté au lancer) : tirage de la rareté et de la taille.
- **Interface** :
  - bouton **Rebirth** (🌟, sous Shop dans la colonne de gauche) dès le premier lancer, pour que l'objectif se voie
    tôt (bouton Renaissance de 12) ; pastille « ! » quand la renaissance est possible ;
  - popup **« REBIRTH READY! »** une fois par renaissance quand la condition est remplie (« Renaissance prête ! » de
    12) ;
  - fenêtre **Rebirth** (bandeau violet → rose) : « LUCK x2 FOREVER », « Luck x4 → x8 », colonnes **RESETS** (rouge,
    ✖) et **KEEPS** (vert, ✔), condition « ✔ Infinite Dummy » et prix « ✔ $350B » (vert, rouge sinon), compteur
    « Rebirths: k » (coches et croix en emoji ✅ / ❌), gros bouton vert **REBIRTH** grisé avec la condition manquante (« NEED INFINITE GEAR »,
    « NEED $350B ») ; deux clics (« SURE? » orange pendant 3 s) : la renaissance efface beaucoup ;
  - à la renaissance, **écran plein violet** (« REBIRTH! », « LUCK x2 FOREVER! », « Rebirth k • total luck x8 »,
    rayons et gerbe d'étoiles violettes de 05, 3,4 s) ;
  - **annonce** aux autres joueurs du serveur (bandeau violet et ligne de chat, file de `Client.Announce`) :
    « Ana rebirthed! Rebirth 3: x8 luck » ;
  - **badge « REBIRTH x8 »** violet au coin gauche de la bannière CHANCE (en miroir du badge du mannequin lancé à
    droite ; multiplicateur déjà compté dans le chiffre) ;
  - **texte flottant de la base** : « 💪 1.2K  🌟 3 » (compteur violet à côté de la Throw Power, dès 1).
- **Sauvegarde** : champ `Rebirths` (entier, `Rebirth.read` : 0 pour une sauvegarde antérieure, borné à 60).
- **Joueur simulé** (`lune run tools/progression 40 300`, médianes ; 3e argument : facteur de prix pour les essais),
  piste de 6 km, prix de #15 ; prix × 2 (#109, appliqué) comparé au × 4 de #108 :
  | Renaissance | Prix (× 2) | CHANCE | Atteinte (× 2, après #129) | Atteinte (× 4 : $350B, $1.4T, $5.6T…) |
  |---|---|---|---|---|
  | 1 | $350B | x2 | 10,8 h | 11,5 h |
  | 2 | $700B | x4 | 15,2 h | 17,7 h |
  | 3 | $1.4T | x8 | 19,3 h | 27 h |
  | 4 | $2.8T | x16 | 23,7 h | 48,3 h |
  | 5 | $5.6T | x32 | 29,1 h | 88 h |
  | 6 | $11.2T | x64 | 36,5 h | 173 h |
  | 7 | $22.4T | x128 | 44,8 h | > 300 h |
  | 10 | $179T | x1.02K | 96,4 h | |
  | 14 | $2.86Qa | x16.3K | 294 h | |
  Premières sorties : Celestial 26 h (× 4 : 33 h), Ethereal 73 h (225 h), Infinity 262 h (> 300 h).
  Avec le prix × 4, l'écart entre deux renaissances double presque à chaque fois (6, 10, 21, 40, 84 h) : le revenu ne
  monte qu'avec la CHANCE (× 2) et le nombre de tirages. Avec × 2 (#109), il reste de 4 à 9 h jusqu'à la 7e, puis 11 à
  74 h ; Celestial, Ethereal et Infinity deviennent atteignables, dans l'esprit « des jours de jeu » visé par #94.
- **Studio** : `DebugWipe` (section « Architecture ») remet le compte à zéro, renaissances comprises.

## Base et collection (`Server.BaseService`, `Shared.Inventory`)
- **Présentoirs** : 6 au départ (2 rangées de 3), jusqu'à 10. Les mannequins posés sont construits par le serveur
  (visibles de tous), nom coloré par rareté et $/s au-dessus.
- **Texte flottant** au-dessus du centre de la base (#91, comme les jardins de 09 et les enclos de 01 ; `BillboardGui`
  à 24 studs, police Fredoka One et contour du HUD) : portrait du joueur, « NOM'S BASE », revenu « $223/s » en vert et
  Throw Power « 💪 1.2K » en cyan (renaissances « 🌟 3 » en violet à côté, #108), mis à jour en direct (achat, pose, entraînement) ; « EMPTY BASE · $0/s » sans
  joueur. Taille en studs plus une marge en pixels : lisible de près et à travers tout le hub (affiché jusqu'à
  600 studs). Comparaison entre joueurs d'un coup d'œil ; plus de panneau à l'entrée.
- **Paliers visuels de la base** (#61, `Shared.BaseLook`) : la base change d'aspect à chaque présentoir acheté, un
  joueur voit de loin les bases les plus avancées du serveur.
  | Présentoirs | Palier | Clôture | Sol | Décor |
  |---|---|---|---|---|
  | 6 | Wood | bois | terre | — |
  | 7 | Garden | bois | terre | massifs de fleurs, lanternes à l'entrée |
  | 8 | Stone | pierre (plus haute) | dalles grises | + lanternes aux 4 coins |
  | 9 | Noble | pierre à chapeaux dorés | grès | + drapeaux à la couleur de la place aux coins |
  | 10 | Golden | métal doré | tapis à la couleur de la place | + arche d'entrée (piliers à la couleur de la place, linteau doré), paillettes dorées sur toute la base |
  Achat : confettis au-dessus de la base, vus de tous (en plus du popup « NEW DISPLAY! » du propriétaire).
- Revenu versé chaque seconde (attribut `Income`, compteur « +$N/s ») : **seule source d'argent**.
- **Stock** (inventaire) : les mannequins possédés non posés, doublons compris, dans l'ordre d'arrivée ; tout mannequin
  gagné y entre. Plafond technique 200 (`INVENTORY_MAX`) : au-delà, le moins rentable du stock est vendu d'office.
- **Barre d'outils** (Backpack Roblox, `Server.DummyTools`, logique dans `Shared.BackpackPlan`) : un outil par mannequin
  du stock, doublons compris, rareté décroissante puis ordre d'arrivée ; nom du mannequin, icône du mannequin
  (`Assets.DUMMY_ICONS`, rendus des modèles de #66), sinon de sa rareté (buste à sa couleur, `Assets.RARITY_ICONS` ;
  nom affiché à la place tant qu'aucune n'est publiée), info-bulle
  « nom · rareté · $/s ». Équipé, l'avatar le porte debout devant la poitrine, à l'échelle de sa taille (0,42 × échelle
  de la taille), animation « Carry » du haut du corps (marche et saut libres) ; chaque client construit le modèle tenu
  (`DummyShape.buildVisual`) d'après l'outil équipé. Barre masquée et mannequin déséquipé hors du hub (bande, vol,
  tirage, entraînement). Posé, vendu ou rangé par PLACE BEST : son outil quitte la barre ; le Backpack est reconstruit
  depuis le stock à chaque réapparition et à chaque arrivée (pas de sauvegarde à part).
- **AUTO** (bouton compact au-dessus de la barre d'outils, le panneau « Place your… » n'existe que pendant l'étape
  « Place » du tutoriel) : pose le mannequin tenu, sinon le dernier gagné, sur le premier présentoir libre ; base pleine,
  le nouveau remplace le moins rentable s'il rapporte plus (l'ancien retourne au stock), sinon il reste au stock (AUTO
  est alors caché). Rien n'est jamais vendu sans clic.
- **Fenêtre « My Dummies »** (bouton Dummies, panneau à droite comme « Mes plantes » de 09) : en haut « IN YOUR BASE
  n/N · INVENTORY n », total $/s et bouton orange **PLACE BEST** (remplit les présentoirs avec les plus rentables, posés
  et stock confondus ; un posé reste en place s'il en fait partie) ; puis une ligne par mannequin, posés d'abord, puis
  $/s décroissant (doublons du stock regroupés, « x3 ») : rendu 3D, badge PLACED, nom, taille et rareté colorées, $/s,
  boutons **PLACE** (règle AUTO, depuis n'importe où ; « BASE FULL » si rien ne lui va) ou **REMOVE** (posé → stock),
  et **SELL $N** (stock seulement : un posé se retire d'abord). Pastille « ! » sur Dummies quand un mannequin du stock
  peut être posé. Pendant la première pose du tutoriel, PLACE et PLACE BEST sont inactifs (pose à la main).
- **Stand SELL** du hub (invite « Sell dummies ») : fenêtre rouge, boutons « Sell all » colorés par rareté (nombre en
  stock ; deux clics : « SURE? » et le total, puis vente), puis le stock et ses prix. Prix de vente = **2 min de
  revenu** (`SELL_MINUTES`). L'argent vendu vole du bouton au compteur.
- **Pad « 6 > 7 »** devant la base (dalle en briques vertes, panneau en bois et prix sur plaque verte, comme le pad
  « 8 > 9 » de 09 ; de l'autre côté de l'entrée que l'appareil) : invite « Buy display » (propriétaire seulement)
  qui achète le présentoir suivant, popup « NEW DISPLAY! » ; refus « NOT ENOUGH MONEY! » si l'argent manque. Prix
  (`DISPLAY_PRICES`) : 450 K, 7 M, 70 M, 3 B (7e à 10e, #15 : achetés vers 10 min, 27 min, 54 min et 2,5 h simulées ;
  1 K à 100 K avant, les quatre en 7 min) ; panneau « MAX » à 10. Les présentoirs 7 à
  10 existent dès la construction (grisés, semi-transparents, sans invite tant qu'ils ne sont pas achetés), deux le
  long de chaque clôture avant et arrière : les 6 premiers ne bougent pas.
- **Index** (bouton Index, fenêtre bleue comme 09) : raretés en onglets à gauche (« Common 2/3 »), titre et barre de
  progression de la rareté, cases des mannequins (cote « 1 IN N », rendu et nom, ✔ et meilleure taille obtenue ;
  silhouette noire et « ??? » s'il n'a jamais été obtenu), total « Unlocked: x / 64 » en bas. L'Index garde les
  mannequins obtenus même vendus.
- **Réplication** : le serveur publie la collection dans des attributs du joueur (`Stock`, `BaseDummies`, `Displays`,
  `DummyIndex`, `PendingDummy` = dernier gagné), en clés « id:taille ». Le client n'envoie que des intentions (remote
  `Inventory` : Place / Sell + clé, Remove + présentoir, SellRarity + rareté, PlaceBest ; invite du pad), le serveur
  valide tout. Deux doublons sont interchangeables : le client désigne un mannequin du stock par sa clé.
- **Sauvegarde** avec les données du joueur (`Collection` : présentoirs, présentoirs achetés, stock, Index = meilleure
  taille par mannequin ; `Draws` : nombre de tirages ; `Rebirths` : renaissances, section « Renaissance »). Migration des sauvegardes de #13 : le mannequin en main passe au
  stock, la liste des découverts devient l'Index.

## Carte (v0.3) : lobby de 4 joueurs, piste unique
- **Hub** (pelouse à damier entourée de parois en gradins) : une **base par joueur** (terrain clôturé, 6 à 10 présentoirs
  pour la collection, texte flottant « NOM'S BASE » avec revenu et Throw Power, aspect qui monte avec les présentoirs
  achetés, pad d'achat de présentoir) avec son **appareil
  d'entraînement** à côté de l'entrée, qu'il
  laisse libre (podium à tenons, pastille jaune, râtelier, invite « Lift », briques fines `FadBrickFine`), deux stands
  détaillés au fond (#68, `Server.Props`, animés par `Client.HubShops`), chevrons jaunes vers la zone de lancer. Plan
  dans `Shared.CourseLayout`.
- **Stands** (échoppes de 01 / 09 : bois, auvent rayé, comptoir garni, marchand en blocs juché derrière, qui se balance
  et salue, bulle d'appel, anneau lumineux au sol devant l'invite) :
  - **SHOP** (bleu, haut) : les mannequins à lancer exposés sur des plateaux tournants (comptoir, étagère du fond),
    vitrine en verre du Rocket Dummy, caisses empilées dont une ouverte, enseigne néon « DUMMY SHOP » coiffée d'une tête
    de mannequin à cibles qui tourne ; invite « Buy dummies ».
  - **SELL** (rouge, large) : caisse enregistreuse, balance dorée, liasses et sacs « $ », pancarte « SELL = 2 MIN OF
    INCOME », pièce géante qui tourne au-dessus de l'enseigne ; éclat de pièces au-dessus du comptoir à chaque vente
    faite au stand (attribut `Sales`) ; invite « Sell dummies ».
- **Zone de lancer commune** : la **bande de lancer**, sur toute la largeur de la piste et toute la profondeur de la zone
  (16 studs, du hub au départ), au ras de la pelouse : carreaux de 4 studs à tenons orange et jaune, reflet blanc qui
  glisse d'un bout à l'autre (animé par chaque client), liseré blanc à peine surélevé côté piste (compté comme bande),
  comme *Throw Food For Animals* et *Throw a Seed*. Pas de place attitrée : jusqu'à 15 joueurs figés y tiennent côte à
  côte (4 par serveur). Le joueur réapparaît dans le hub, 6 studs derrière la bande, et y revient après chaque lancer.
- **Piste fermée aux avatars** : barrière invisible juste derrière le liseré (groupe `AvatarBarrier`, qui ne
  collisionne qu'avec `Characters`), et pièces d'obstacles dans le groupe `Obstacles`, que les avatars traversent : un
  joueur ne descend pas sur la piste et ne bouscule pas les obstacles des autres.
- **Piste partagée** (80 studs de large, 6 km depuis #97) au fond d'un canyon en 3 gradins : parois en briques, herbe
  (ou neige, sable…) voxel qui déborde de chaque marche, décor voxel sur les terre-pleins et au pied des parois
  (traversable). **Arche d'arrivée** à 6 km (ligne et bandeau à damier, panneau « FINISH 6 KM »), traversable : le
  mannequin passe dessous et s'arrête contre la paroi en gradins du bout (6 040 m ; vol mesuré à 6 037 m). Limite d'un
  vol de 20 s (`MAX_FLIGHT_TIME`, 22 s avant #113) : un vol de 4,4 B met 10 à 12 s jusqu'au bout.
- **Coût du décor généré** (#97, mesuré en Studio, journal `[Course]` du serveur, 3 démarrages) : 25 160 instances
  construites en 307-485 ms (hub et zone de lancer 11-20 ms, piste 100-196 ms, obstacles 91-124 ms). Avant / après,
  répartis sur la même construction (le décor avant 2,4 km est identique) : hub et 12 premiers thèmes ≈ 12 600
  instances, piste de ces thèmes 41-79 ms ; six thèmes de 2,4 à 6 km ≈ 12 900 instances (× 2 environ), 60-114 ms de
  piste en plus. `StreamingEnabled` est coupé : chaque client reçoit tout (client Studio : 60 FPS, 119 Mo pour les
  instances).
- **Obstacles partagés** (`Server.Obstacles`, plan dans `Shared.TrackPlan`) : dans chaque thème, les 2 ou 3 obstacles cassables du thème à
  tour de rôle (un site de plus que le minimum : il a remplacé la rangée de vitres retirée par #90) (`Server.ThemeObstacles`, un par colonne ou d'un seul tenant sur la largeur des colonnes) et son piège
  signature (section « Zones de la piste », un second piège dans les thèmes longs), sites espacés régulièrement
  (≈ 35 m, 4 à 9 par thème).
  Une pièce déplacée réapparaît à sa place **5 s après le dernier choc** subi par son obstacle, une par une de bas en haut
  (0,05 s d'écart), en grossissant depuis son centre ; jamais sur un mannequin posé dedans. Un objet projeté est compté
  pour le mannequin le plus proche (règles dans `Shared.ObstacleRules`).

## Zones de la piste (6 km, #33, #97)
Douze thèmes courts au début (un changement tous les 60 à 150 m sur le premier kilomètre, où vole un joueur débutant :
un premier lancer à ≈ 145 m en traverse 3), plus longs ensuite, puis six thèmes de 600 m de 2,4 à 6 km (#97, rien n'a
bougé avant 2,4 km). Chaque thème a son identité (couleur du sol, des parois,
du dessus des gradins, décor), comme les zones de *Throw a Seed*, ses obstacles cassables et un piège signature
(`Shared.Zones`). CHANCE à l'entrée de chaque thème calée sur l'ancienne courbe à la même distance (entre deux entrées,
écart de +5 % au plus, vers 1,9 km) :
| Zone | Début | CHANCE | Obstacles | Piège |
|---|---|---|---|---|
| Meadow | 0 m | ×1 | bottes de foin, tours de caisses | trampoline |
| Farm | 60 m | ×1,15 | tracteurs, clôture, bottes de foin | ventilateur géant |
| Forest | 135 m | ×1,35 | rondins, ruches | rondin qui balance |
| Beach | 220 m | ×1,5 | châteaux de sable, planches de surf | vague |
| Desert | 315 m | ×1,8 | tonneaux, cactus | tornade de sable |
| Construction | 420 m | ×2,1 | échafaudages, mur de briques, plots | presse hydraulique |
| Junkyard | 535 m | ×2,5 | voitures-cibles, piles de pneus, panneaux-cibles | aimant de grue |
| Snowfield | 660 m | ×3 | bonshommes de neige, mur de glace | tremplin de saut à ski |
| Volcano | 800 m | ×3,8 | rochers de lave, mur de basalte | bassin de lave |
| Candy Land | 950 m | ×4,7 | sucres d'orge, mur de guimauves | canon à confettis |
| Toy Town | 1,25 km | ×7 | cubes de jouet, soldats de plomb | diable en boîte |
| Moon Base | 1,65 km | ×10 | satellites, rover | anneau propulseur |
| Mars | 2,4 km | ×18 | rochers rouille, atterrisseurs | geyser de poussière |
| Crystal Cave | 3 km | ×22 | massifs de cristaux, mur d'améthyste | massif de cristaux rebondissant |
| Neon City | 3,6 km | ×27 | taxis, bornes d'arcade | portique laser |
| Sky Kingdom | 4,2 km | ×33 | nuages en cubes, montgolfières | toboggan arc-en-ciel |
| Haunted Castle | 4,8 km | ×40 | citrouilles, cercueils | fantôme qui jaillit de sa tombe |
| Galaxy | 5,4 km | ×49 (×60 au bout) | astéroïdes, soucoupes volantes | portail de trou de ver |

CHANCE de 2,4 à 6 km : progression géométrique (× 1,22 par thème), × 27 à 3,6 km, × 40 à 4,8 km, × 60 au bout.
Décor : rochers, cratères et radars (Mars), grands cristaux et stalagmites (Crystal Cave), tours à ceintures néon,
enseignes et lampadaires (Neon City), nuages, arcs-en-ciel et îles flottantes (Sky Kingdom), citrouilles-lanternes,
tombes, toiles d'araignée et arbres morts (Haunted Castle), planètes à anneau, étoiles et astéroïdes (Galaxy). Dans la
Galaxy, la nuit tombe chez le joueur dont la caméra y entre (`Client.ZoneSky`, ciel étoilé, jour rendu au retour).
Planche comparée à la référence 09 : `docs/captures/themes/piste-6km-vs-ref.jpg`.

Panneaux d'entrée de zone : « FOREST x1.35 CHANCE ».

**Pièges signatures** (`Shared.Traps`, habillage `Server.TrapProps`) : un par colonne d'obstacles, décor sans collision ;
le serveur le déclenche quand le torse traverse sa boîte (trajet de la frame testé, une fois par vol et par piège,
toutes colonnes confondues) et
remplace la vitesse du mannequin (rebond, souffle, coup de rondin, écrasement, arrachement, propulsion), casse 1 à 3 os
sur les membres les plus proches et écrit la cause du crash (« Squashed by a hydraulic press », gardée pour les os
cassés dans les 0,8 s qui suivent). Chaque client joue son
son, sa gerbe de particules et son popup (« BOING! ») ; les pièces mobiles (pales, rondin, presse, diable, vague) sont
animées par chaque client (`Client.TrapMotion`) sur l'horloge du serveur, avec la phase que le serveur prend pour
décider si le piège agit (`Traps.CYCLES`, `Traps.active`, #79) : la presse n'écrase que pendant sa descente, le diable
n'éjecte que sorti, l'aimant n'arrache que plaque allumée (néon et étincelles), le rondin ne frappe que le torse qu'il
touche, en passant en bas de son balancement, et pousse le mannequin dans l'axe de la piste, dans le sens où il va (vers l'avant ou en arrière).
Hors de cette phase, le mannequin passe sans rien. L'anneau propulseur est un cerceau néon suspendu (centre à 85 studs : sous le
plafond du vol (100 studs, #113), traversé au début de la chute d'un vol qui retombe dans la Moon Base) ; seule son ouverture déclenche (boîte
carrée de 8 studs, #85), ni colonne ni pad au sol.
Pièges de la piste prolongée (#97) : le **geyser** (Mars) projette à la verticale pendant son éruption (bouche et
panache allumés, 35 % d'un cycle de 3 s) ; le **massif de cristaux** (Crystal Cave) renvoie haut en gardant l'élan ;
le **portique laser** (Neon City) grille pendant sa phase allumée (faisceaux visibles la moitié d'un cycle de 2 s) et
freine un peu ; le **toboggan arc-en-ciel** (Sky Kingdom) relance vers l'avant et le haut ; le **fantôme** (Haunted
Castle) jaillit de sa tombe comme le diable en boîte et emporte le mannequin en tournoyant ; le **trou de ver**
(Galaxy) est un portail dressé sur la piste qui propulse vers l'avant. Depuis #113, les vols touchent le sol au point
prévu puis freinent fort (section « Vol plafonné ») : un piège traversé à l'atterrissage relance encore le mannequin
(toboggan à 360 M : jusqu'à + 12 %, trou de ver à 4,4 B : jusqu'au bout) ; après 3,6 km, aucun piège ne garde moins de
80 % d'un élan de 300 studs/s.

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
- **Boutons** : carrés arrondis à icône dessinée en couleur et libellé dessous ; Index, Shop et Rebirth (dès le
  premier lancer, section « Renaissance ») au bord gauche, Dummies au bord droit (place du bouton de collection des références) ; pastille rouge « ! » quand un achat est possible.
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
  abordable, écran libre (pas pendant la jauge, le vol, le résultat, ni fenêtre ou bandeau ouverts) : rendu 3D, nom, prix et gain,
  bouton vert UPGRADE qui achète en un clic, croix. Fermé, il ne revient pas pour ce palier, mais revient pour le
  suivant. Tout au long du jeu, pas seulement au tutoriel. Taille de celui de 09 (≈ un quart de la largeur).
- **Superposition du haut de l'écran** (`Shared.Overlay`, #87, #62) : une fenêtre ouverte ou un bandeau d'annonce
  masquent l'offre et le texte de l'objectif ; un popup de palier (« LEVEL UP! », fréquent pendant l'entraînement) ne
  masque que le texte, l'offre reste cliquable ; l'offre affichée fait passer le texte sous elle (masqué si la flèche
  désigne son bouton). Tout revient à la fermeture, sans rejouer le son.
- **Cibles du décor** (point d'accroche pour la carte et la collection) : une `BasePart` avec le tag `ObjectiveTarget`
  et l'attribut `Objective` (`"Throw"`, `"Train"`…), plus `Slot` (place du lobby) ou `OwnerUserId` (joueur) si elle
  n'est pas partagée ; le joueur suit la plus proche de celles qui lui sont ouvertes. `Span` : cible allongée sur X,
  visée en son point le plus proche du joueur. `CourseBuilder` marque la bande de lancer (partagée, `Span`) et
  l'appareil d'entraînement de chaque place.
- **Fenêtres** : cadre sombre, bandeau dégradé (icône, titre), croix rouge ; cartes d'objets grises (nom, rareté
  colorée de `Shared.Rarity`, rendu 3D en `ViewportFrame`, statistique, bouton : prix vert / rouge, « EQUIPPED »).
  Shop = équipements d'entraînement ; Dummy Shop : section « Boutique de mannequins à lancer » ; Dummies (« My
  Dummies »), vente et Index : section « Base et collection ». Toutes les
  listes défilent verticalement (#45) : boutiques en grille (`UIKit.cardGrid`, 3 cartes par rangée pour Training Gear,
  4 pour Dummy Shop, ouvertes sur la rangée du prochain achat), lignes de collection et grille de l'Index.
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
  les places libres (mesure de 4 vols simultanés), `DebugPlace` pose le mannequin tenu ou le dernier gagné (AUTO), `DebugEquip` (« id:taille », « » pour ranger) équipe un mannequin de la barre, `DebugThrowDummy` (1-6) donne et équipe ce
  mannequin à lancer ; `DebugWipe` (true) remet toute la sauvegarde du joueur à l'état d'un nouveau joueur
  (renaissances, collection, tutoriel et records compris ; écrite à son départ : remise à zéro du compte du testeur
  avant une sprint review, #95) ; `FreshPlayer` sur
  Workspace : nouveau joueur sans sauvegarde.
- Le décor est généré par le code (`CourseBuilder`) : rien à exporter depuis Studio.

## Feuille de route
- **v0** : boucle complète au canon (fait, remplacé).
- **v0.2** : boucle des jeux de référence (entraînement, lancer par l'avatar, game feel, dégâts lisibles, zones,
  grands nombres) (fait, rejeté pour son style).
- **v0.3** : boucle et style calés sur les références (epic #9) : carte (#10), mannequin et cinématique (#11), interface
  (#12), collection (#13), boutique (#14), économie (#15), progression longue (#94 ; piste prolongée et renaissance :
  #97). ← en cours
- **v1** : variantes « 1 en N » révélées en cinématique, renaissance avec nouveau parcours et nouveau lanceur (lance-pierre
  géant, catapulte, canon), tutoriel en chaîne d'objectifs, récompense quotidienne, index (issue #7).
- **v2** : produits Robux (passer, x2, lancer auto), événement avec compte à rebours, vignette et page du jeu.
