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
4. **Vol** : bandes noires, caméra qui suit (derrière et un peu sur le côté au ras du sol ; plus le mannequin monte,
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
  remplit la barre de niveau : 3 EXP au premier niveau puis × 1,2 par niveau, l'EXP en trop passe au niveau suivant
  (plusieurs niveaux d'un coup avec un bon équipement). Le passage de niveau (« LEVEL UP! Throw Power +N ») donne autant
  de **Throw Power** que l'EXP qu'il demandait : puissance gagnée = EXP gagnée = gain × répétitions.
- **Équipements** (achetés avec l'argent) : mannequin en bois +1, pierre +3, fer +10, or +40, diamant +160, néon +700,
  cosmique +3 000 EXP par répétition ; prix 100 $, 1,5 K, 25 K, 150 K, 2 M, 25 M. Suite (#94, `Training.EXTENDED`) :
  ruby, emerald, plasma, omega, infinite, gain × 4 et prix × 3,5 par palier (+12 K à +3 M, $88M à $14B) ; section
  « Progression longue ».
- Vitesse de lancer = 110 + 30 × ln(puissance / 10) studs/s : la puissance explose (10 → 1 M), la distance monte
  régulièrement (≈ 145 m → 2,2 km).

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
  | Uncommon | Mint, Biker, Nerd | 15 à 30 | 10 à 25 |
  | Rare | Ocean, Hero, Pilot | 70 à 150 | 60 à 150 |
  | Epic | Ice, Toxic, Royal | 400 à 700 | 500 à 1 200 |
  | Legendary | Gold, Lava, Diamond | 2 500 à 5 000 | 4 K à 10 K |
  | Mythic | Galaxy, Ghost, Neon | 20 K à 40 K | 40 K à 100 K |
  | Secret | Crash King, Void, Cosmic | 150 K à 300 K | 500 K à 2 M |
- **Tailles** : Normal (×1 revenu), Big (×1,5, 1 en 8), Huge (×3, 1 en 60), Giant (×8, 1 en 500) ; modèle agrandi.
- **Spectacle par rareté** (#66) : chaque mannequin a son modèle (`Shared.DummyModels`, pièces ajoutées de plus en
  plus folles). Le modèle grandit avec la rareté (×1 Common à ×1,8 Secret, `Collection.RARITY_SCALE`, multiplié par
  la taille ; plafonné à ×2,5 sur un présentoir, `Collection.DISPLAY_SCALE_MAX`). Effets (`Shared.DummyAura`) : thème propre dès Uncommon (notes, bulles, réacteur, flocons…), puis aura
  de la couleur de la rareté : éclats dès Rare, onde au sol et lumière dès Epic, flaque de lumière et poussières
  montantes dès Legendary, gloire de rayons dès Mythic, colonne de lumière et gerbe d'étoiles en Secret. Les
  particules ne se rendent pas dans les fenêtres (ViewportFrame) : les vignettes montrent le modèle seul.

## Boutique de mannequins à lancer (#14, `Shared.ThrowDummies`)
L'équivalent des aliments de 01 et des graines de 09 : le mannequin qu'on lance, distinct des mannequins de collection
(on le possède une fois pour toutes, il ne rapporte rien, il ne va pas dans la barre d'outils).
- **Catalogue** (prix provisoires, recalés par #15 ; ×12 à ×25 entre niveaux, comme 09 : $1.2K, $15K, $300K) :
  | Mannequin | Prix | Chance | Comportement | Réglage |
  |---|---|---|---|---|
  | Crash Dummy | offert | 1.0x | Classic | densité 1,5, frottement 0,3, rebond 0,3 (le mannequin d'origine) |
  | Rubber Dummy (rose, pompon) | $1.2K | 1.25x | Bouncy | frottement 0,05 ; chaque rebond au sol rend 85 % de la chute vers le haut et garde 85 % de l'élan vers l'avant |
  | Glass Dummy (verre, étiquette FRAGILE) | $15K | 1.5x | Fragile | chocs × 2 pour les os : plus d'os cassés (+2 % chacun) |
  | Steel Dummy (acier, plaques de lest) | $300K | 2.0x | Heavy | densité 8 : il défonce les obstacles au lieu d'y rebondir |
  | Glider Dummy (vert, aile orange) | $4M | 2.5x | Glides | 70 % de la gravité compensée quand il descend (plus de 4 studs/s) |
  | Rocket Dummy (rouge, réacteur) | $50M | 3.0x | Jetpack | poussée de 60 studs/s² vers l'avant pendant la 1re seconde |
  Les pièges (`Shared.Traps`) remplacent la vitesse comme pour tous : le comportement reprend ensuite (portance,
  rebond) ou est fini (poussée).
- **Suite du catalogue** (#94, `ThrowDummies.EXTENDED`) : 14 mannequins de 4x à 135x (« Ruby Rubber Dummy »,
  « Infinite Rocket Dummy »), chacun avec le comportement et la physique d'un des cinq ci-dessus sous une palette de
  `Shared.DummyFamilies`, prix = Rocket × (chance / 3)^1,8 ($84M à $47B) ; seuls les six premiers sont exposés sur le
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
- **Mesures** (Studio, `DebugLaunch` = 1, attribut `DebugThrowDummy`, 2 vols chacun ; détail dans la PR #14) :
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
puis des jours avec la renaissance proposée plus bas. Chiffres provisoires : #15 les recale avec le joueur simulé de
Studio.

**Joueur simulé** (`lune run tools/progression [joueurs] [heures]`, médiane de 60 joueurs sur 24 h) : vrais modules
du jeu (tirage, entraînement, CHANCE des zones, prix), une boucle = un lancer (15 s, comme 09) puis 15 s
d'entraînement, achats dès que possible (le moins cher d'abord), mannequins hors présentoirs vendus aussitôt. Distance
≈ 0,012 × vitesse² (vols mesurés de #14 : 145-168 m à la puissance 10, ≈ 1 150 m à 10,5 K), os et objets ≈ +30 % de
CHANCE au départ, +55 % à 10,5 K. Modèle non mesuré en jeu : les pièges, les comportements des mannequins à lancer et
le temps réel d'une boucle le décaleront. Depuis #97, la piste fait 6 km (temps ci-dessous rejoués avec elle) ; les
vols mesurés au-delà de 2,4 km s'écartent du modèle (tableau « Fin de piste » plus bas).

**Grands nombres** (`Shared.Format`) : K, M, B, T, Qa, Qi, Sx, Sp, Oc, No, Dc (10^33), puis notation scientifique ;
3 chiffres significatifs tronqués ; cote « 1 IN 300Qa » (`Format.odds`), cote complète du secret avec séparateurs
jusqu'au milliard puis abrégée (`Format.fullOdds`), CHANCE « X5.11K », chance « 135x ».

### Collection : 11 raretés, 64 mannequins
Contenu en masse sans dessiner de pièce (`Shared.DummyFamilies`, comme les variantes « Emerald », « Ruby » de 09) :
un mannequin généré croise une **famille** (un des 21 modèles dessinés : pièces ajoutées, pièces masquées, effets) et
une **palette** (couleur du corps, teinte et matériau des pièces ajoutées, couleur des effets ; ni verre ni champ de
force, invisibles dans les fenêtres). Identifiant « palette_famille », nom « Palette Famille » (« Golden Void Dummy »).
Règles de cote et de revenu :
- raretés dessinées (Common à Secret) : 1 à 3 générés au-dessus des dessinés, sous la rareté suivante (cote et revenu
  en progression géométrique entre les deux, arrondis à 2 chiffres) ; un seul Common (deux cotes de Common à moins de 1
  d'écart sortiraient aussi souvent l'une que l'autre) ;
- au-delà de Secret : 6 par rareté, deux décades de cote chacune, revenu = 300 K × (n / 2 M) ^ 0,45 (les dessinés
  suivent ≈ n ^ 0,81 ; au-delà, l'exposant 0,45 garde un revenu × 3 à × 10 d'une rareté à l'autre, règle des
  références, au lieu de × 40).

| Rareté | Mannequins | Cotes (taille normale) | Revenu ($/s) | Premier obtenu (simulé) |
|---|---|---|---|---|
| Common | 4 | 1 IN 3 à 10 | 4 à 9 | 15 s (garanti) |
| Uncommon | 6 | 1 IN 13 à 51 | 15 à 57 | 75 s |
| Rare | 6 | 1 IN 62 à 372 | 70 à 310 | 4 min |
| Epic | 6 | 1 IN 502 à 3K | 400 à 1.8K | 8 min |
| Legendary | 6 | 1 IN 4K à 28K | 2.5K à 14K | 23 min |
| Mythic | 6 | 1 IN 40K à 330K | 20K à 110K | 89 min |
| Secret | 6 | 1 IN 500K à 4M | 150K à 410K | 3,8 h (5,7 h avec la piste de 2,4 km) |
| Divine | 6 | 1 IN 5M à 100M | 450K à 1.7M | 7,1 h (12,3 h avec la piste de 2,4 km) |
| Celestial | 6 | 1 IN 500M à 10B | 3.6M à 14M | 23,7 h (après la 3e renaissance ; 47,5 h avec 2,4 km) |
| Ethereal | 6 | 1 IN 50B à 1T | 29M à 110M | 185 h (après la 7e ; > 300 h avec 2,4 km) |
| Infinity | 6 | 1 IN 5T à 100T | 230M à 870M | > 300 h |

Celestial à Infinity : piste de 6 km (#97) et renaissance de #108 (prix × 4, section « Renaissance »), 40 joueurs
sur 300 h ; avec la proposition × 2 (#109) : 21 h, 50 h et 161 h.

En taille Giant (× 500 de cote), le plus rare s'affiche « 1 IN 50Qa ». Spectacle : Divine et au-delà jouent la
séquence complète du secret (phrase propre à la rareté : « THE HEAVENS HAVE OPENED... »), aura un cran plus fournie par
rareté (éclats, poussières, colonne de lumière plus haute et plus large), modèle × 1,86 à × 2,05. Index : 11 onglets à
la hauteur de la colonne ; vente : boutons « Sell all » sur deux rangées. Les générés n'ont pas encore d'icône propre
dans la barre d'outils (icône de rareté jusqu'à Secret, nom au-delà).

### Mannequins à lancer : 20, jusqu'à 135x
| Mannequin | Chance | Prix | Atteint (simulé) |
|---|---|---|---|
| Crash / Rubber / Glass / Steel / Glider / Rocket | 1.0x à 3.0x | $0 à $50M | départ à 57 min |
| Ruby Rubber | 4.0x | $84M | 73 min |
| Emerald Glass | 5.0x | $130M | 100 min |
| Sapphire Steel | 6.5x | $200M | 116 min |
| Amber Glider | 8.0x | $290M | 2,2 h |
| Golden Rocket | 10x | $440M | 2,6 h |
| Frost Rubber | 13x | $700M | 2,9 h |
| Magma Glass | 17x | $1.1B | 3,6 h |
| Shadow Steel | 22x | $1.8B | 3,9 h |
| Radiant Glider | 30x | $3.2B | 4,5 h |
| Starlight Rocket | 40x | $5.3B | 5,3 h |
| Nebula Rubber | 55x | $9.4B | 6,0 h |
| Plasma Glass | 75x | $16B | 7,2 h |
| Quantum Glider | 100x | $28B | 7,9 h |
| Infinite Rocket | 135x | $47B | 8,9 h (12,9 h avec la piste de 2,4 km) |

Prix = Rocket × (chance / 3)^1,8 : sans renaissance, le revenu ne monte qu'avec le nombre de tirages × la CHANCE
(polynomial), des prix × 6 à chaque niveau (essai : × 12-25 comme les graines de 09) rendaient la suite hors d'atteinte
(4x à 2,2 h, 6,5x à 9 h, rien au-delà en 12 h).

### Training Gear : 12 paliers
| Équipement | EXP / rép. | Prix | Atteint (simulé) |
|---|---|---|---|
| Wooden → Cosmic | +1 à +3K | $0 à $25M | départ à 41 min |
| Ruby | +12K | $88M | 88 min |
| Emerald | +48K | $310M | 2,5 h |
| Plasma | +190K | $1.1B | 3,3 h |
| Omega | +760K | $3.9B | 4,9 h |
| Infinite | +3M | $14B | 6,6 h |

Puissance : 1 K à 5 min, 100 K à 20 min, 1 M à 45 min, 100 M à 3,2 h, 10 B à 7,8 h. Avec la piste de 2,4 km, le bout
était atteint dès ≈ 760 K de puissance (43 min simulées) et la puissance n'ajoutait ensuite que des os et des objets ;
la piste de 6 km (#97) donne un but aux paliers prolongés (tableau « Fin de piste » ci-dessous).
**Effet de bord** : la CHANCE plus haute fait sortir des raretés plus rentables plus tôt, et tout le catalogue d'achats
est fini à ≈ 9 h simulées au lieu de 13 h (revenu 10 M/s à 7,8 h au lieu de 13,7 h) : la cible « une douzaine
d'heures » avant la première renaissance (désormais à 9,6 h) se recale avec l'économie (#15, #109).

### Repères comparés aux références
| Repère | Fling a Dummy (simulé) | 09 *Throw a Seed* | 01 *Throw Food For Animals* |
|---|---|---|---|
| Première récompense | 15 s | 21 s | 24 s |
| Premier équipement | 45 s ($100) | 1:45 ($500) | 0:42 ($1) |
| Deuxième projectile | 105 s (1.25x, $1.2K) | 1:42 (1.25x, $1.2K) | 1:27 (pomme) |
| Puissance | 1K à 5 min, 100K à 20 min | 1.34K à 4 min, 114K à 11 min | 503 à 17 min |
| Revenu | 1K/s à 7 min, 100K/s à 83 min | 2.19K/s à 3:36 | 1.08K/s vers 9 min, 391K/s à 17 min |
| Projectile le plus fort | 135x à 8,9 h | 135x (durée inconnue) | non observé |
| Cote la plus haute | 1 IN 100T (50Qa en Giant) | 1 IN 300Qa | non observé |
| Collection | 64 mannequins, 11 raretés | 110 plantes, 10 raretés + Royal | non observé |

Écarts : la puissance et le revenu montent ≈ 2 fois moins vite que 09 après 5 min (#15 recale le rythme : gains de
l'entraînement, revenus des premières raretés) ; la collection reste plus petite que celle de 09 (familles et palettes
à ajouter sans dessin).

### Piste prolongée (#97) et renaissance (#108) : les deux leviers
1. **Piste prolongée à 6 km** (#97) : six thèmes de plus après Moon Base, un tous les 600 m (section « Zones de la
   piste »), CHANCE des zones de × 18 à × 60. Joueur simulé rejoué (60 joueurs, 24 h) et vols mesurés en Studio
   (Crash Dummy, jauge pleine, `DebugLaunch`) :
   | Fin de piste | Vitesse | Puissance | Atteinte (simulé) | CHANCE des zones | Vols mesurés à cette puissance |
   |---|---|---|---|---|---|
   | 2,4 km (fin de Moon Base) | 447 | 760 K | 43 min | × 18 | (#14, #33) |
   | 3,6 km (Neon City) | 548 | 22 M | 2,1 h | × 27 | 3 811 m (48.6X), 2 994 m (42.8X, geyser déclenché) |
   | 4,8 km (Haunted Castle) | 632 | 360 M | 4,0 h | × 40 | 3 591 m (47.4X), 3 139 m (39.6X) |
   | 6 km (bout) | 707 | 4,4 B | 6,8 h | × 60 | 6 037 m (96.6X), 5 903 m, 4 860 m, 4 343 m, 4 090 m |
   **Mesures comparées au modèle** : jusqu'à 22 M le modèle tient (± 10 %) ; au-delà, il est optimiste. Les vols
   montent très haut (≈ 590 studs à 4,4 B), atterrissent tous vers 3,6-3,9 km puis **glissent** : la distance finale
   dépend de la glissade (obstacles traversés en diagonale, pièges), d'où 4,1 à 6,0 km à 4,4 B (bout atteint 1 fois
   sur 5, frôlé une fois : 5 903 m coupé par l'ancienne limite de vol de 16 s, portée à 22 s) et 3,1-3,6 km à 360 M.
   Le bout de piste est donc plutôt atteint vers 10-50 B de puissance (≈ 8 à 10 h simulées, non mesuré). Effet
   simulé : CHANCE finale × 3,3 (17 K au lieu de 5,1 K à 24 h), Divine à 7,1 h au lieu de 12,3 h.
2. **Renaissance** : faite (#108), section suivante. L'estimation de conception (une renaissance refaite en 1 à 2 h)
   était trop optimiste : avec la piste de 6 km, le joueur simulé met 4 à 80 h entre deux renaissances (prix × 4).

### Renaissance (#108, `Shared.Rebirth`)
Le levier après le dernier équipement (≈ 9,6 h simulées avec la piste de 6 km, 14,4 h avec 2,4 km), comme la
RENAISSANCE de *Net a Fish!* (12) et
d'*Ant Evolution* (05) : on repart de zéro contre une CHANCE plus forte, pour toujours.
- **Condition** : posséder le dernier équipement d'entraînement (Infinite) **et** payer **$50B × 4^k** (k renaissances
  déjà faites : $50B, $200B, $800B, $3.2T…). Validée par le serveur (`PlayerData.rebirth` : chargé, au hub, ni en vol
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
    ✖) et **KEEPS** (vert, ✔), condition « ✔ Infinite Dummy » et prix « ✔ $50B » (vert, rouge sinon), compteur
    « Rebirths: k » (coches et croix en emoji ✅ / ❌), gros bouton vert **REBIRTH** grisé avec la condition manquante (« NEED INFINITE GEAR »,
    « NEED $50B ») ; deux clics (« SURE? » orange pendant 3 s) : la renaissance efface beaucoup ;
  - à la renaissance, **écran plein violet** (« REBIRTH! », « LUCK x2 FOREVER! », « Rebirth k • total luck x8 »,
    rayons et gerbe d'étoiles violettes de 05, 3,4 s) ;
  - **annonce** aux autres joueurs du serveur (bandeau violet et ligne de chat, file de `Client.Announce`) :
    « Ana rebirthed! Rebirth 3: x8 luck » ;
  - **badge « REBIRTH x8 »** violet au coin gauche de la bannière CHANCE (en miroir du badge du mannequin lancé à
    droite ; multiplicateur déjà compté dans le chiffre) ;
  - **texte flottant de la base** : « 💪 1.2K  🌟 3 » (compteur violet à côté de la Throw Power, dès 1).
- **Sauvegarde** : champ `Rebirths` (entier, `Rebirth.read` : 0 pour une sauvegarde antérieure, borné à 60).
- **Joueur simulé** (`lune run tools/progression 40 300`, médianes ; 3e argument : facteur de prix pour les essais),
  rejoué avec la piste de 6 km (#97) ; entre parenthèses, la piste de 2,4 km (#108) :
  | Renaissance | Prix | CHANCE | Atteinte (× 4, #108) | Atteinte (× 2, proposition #109) |
  |---|---|---|---|---|
  | 1 | $50B | x2 | 9,6 h (14,4 h) | 9,6 h (14,4 h) |
  | 2 | $200B (× 2 : $100B) | x4 | 13,3 h (20,7 h) | 12,5 h (19,3 h) |
  | 3 | $800B ($200B) | x8 | 18,9 h (29,9 h) | 14,8 h (23,4 h) |
  | 4 | $3.2T ($400B) | x16 | 29,5 h (46 h) | 17,6 h (27,6 h) |
  | 5 | $12.8T ($800B) | x32 | 50 h (80 h) | 20,8 h (32,1 h) |
  | 6 | $51.2T ($1.6T) | x64 | 87 h (147 h) | 24,4 h (37,8 h) |
  | 7 | $204T ($3.2T) | x128 | 167 h (265 h) | 29,2 h (45,1 h) |
  Premières sorties : Celestial 23,7 h (× 2 : 21 h), Ethereal 185 h (50 h), Infinity > 300 h (161 h).
  Le prix × 4 croît plus vite que le revenu, qui ne monte qu'avec la CHANCE (× 2) et le nombre de tirages : l'écart
  entre deux renaissances double presque à chaque fois (4, 6, 11, 21, 37, 80 h).
- **Proposition** (#109, pas appliquée) : prix **× 2** par renaissance. L'écart reste de 2 à 5 h jusqu'à la 8e, puis
  7 à 60 h ; Celestial, Ethereal et Infinity deviennent atteignables (21, 50, 161 h), dans l'esprit « des jours de
  jeu » visé par #94.
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
  (`DISPLAY_PRICES`) : 1 K, 5 K, 25 K, 100 K (7e à 10e, à recaler par #15) ; panneau « MAX » à 10. Les présentoirs 7 à
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
  vol portée de 16 à 22 s (`MAX_FLIGHT_TIME`) : un vol de 4,4 B met 14 à 16 s pour glisser jusqu'au bout.
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
Hors de cette phase, le mannequin passe sans rien. L'anneau propulseur est un cerceau néon suspendu (centre à 85 studs : hauteur
d'un vol de 32° qui retomberait ≈ 150 m plus loin, aux sites de la Moon Base) ; seule son ouverture déclenche (boîte
carrée de 8 studs, #85), ni colonne ni pad au sol.
Pièges de la piste prolongée (#97) : le **geyser** (Mars) projette à la verticale pendant son éruption (bouche et
panache allumés, 35 % d'un cycle de 3 s) ; le **massif de cristaux** (Crystal Cave) renvoie haut en gardant l'élan ;
le **portique laser** (Neon City) grille pendant sa phase allumée (faisceaux visibles la moitié d'un cycle de 2 s) et
freine un peu ; le **toboggan arc-en-ciel** (Sky Kingdom) relance vers l'avant et le haut ; le **fantôme** (Haunted
Castle) jaillit de sa tombe comme le diable en boîte et emporte le mannequin en tournoyant ; le **trou de ver**
(Galaxy) est un portail dressé sur la piste qui propulse vers l'avant. Les vols à pleine puissance atterrissent vers
3,7 km puis glissent : après 3,6 km, aucun piège ne garde moins de 80 % d'un élan de 300 studs/s (un laser à 55 %
arrêtait un vol de 4,4 B à 4,1 km, mesuré).

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
