# Fling a Dummy — document de conception

Titre provisoire (à tester avant publication). Origine du concept : vault Obsidian, `Jeu Roblox/05 - Concepts/Concepts candidats.md`
(concept A) et `Jeu Roblox/La recette.md` (ce qui fait percer un jeu Roblox). Jeux de référence pour la boucle, l'interface
et le rythme : fiches `04 - Jeux disséqués/` du vault (01 *Throw Food For Animals*, 09 *Throw a Seed*, 03 *Hyper Realistic
Ragdoll*, 06 *BloxNG*, 12 *Net a Fish!*).

## Le jeu en une phrase
Dans un lobby de 4 joueurs, on s'entraîne en soulevant un mannequin pour devenir plus fort, puis on lance un mannequin de
crash-test à bout de bras dans un canyon de briques à tenons, sur une piste partagée en douze thèmes, chacun avec ses
vitres, ses obstacles cassables et son piège signature (trampoline, ventilateur, presse, lave…). Le lancer ne rapporte pas d'argent : sa **CHANCE** (zones traversées,
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
   rareté 1-7, son nom ou « id:taille », imposé au prochain tirage.
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
- **Revenu** (mannequins posés dans la base) → argent → équipements (entraînement plus rapide), **mannequins à lancer**
  (boutique du stand SHOP, multiplicateur de chance) et présentoirs achetables.

## CHANCE et tirage (`Shared.Economy`, `Shared.Collection`)
- CHANCE = chance des zones × (1 + 2 % par os cassé + 1 % par objet détruit) × multiplicateur du mannequin lancé
  (section suivante), arrondie au centième. La chance des zones
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
- **Achat séquentiel** : seul le suivant s'achète, puis il est équipé d'office ; bouton **EQUIP** sur les possédés.
  Validé par le serveur (`ThrowDummies.act` : action, indice, ordre, possession, argent ; remote `ThrowDummy`).
- **Fenêtre « Dummy Shop »** (invite « Buy dummies » du stand SHOP, ou bouton SHOP du popup « NEW DUMMY! ») : bandeau
  rose, une carte par mannequin teintée à sa couleur comme les graines de 09 : nom, « 1.25x CHANCE » en jaune, rendu,
  comportement, bouton EQUIPPED / EQUIP (vert) / prix (jaune abordable, rouge sinon, refus « NOT ENOUGH MONEY! ») /
  « 🔒 prix » pour ceux d'après. Quatre cartes visibles, la suite défile.
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

## Base et collection (`Server.BaseService`, `Shared.Inventory`)
- **Présentoirs** : 6 au départ (2 rangées de 3), jusqu'à 10. Les mannequins posés sont construits par le serveur
  (visibles de tous), nom coloré par rareté et $/s au-dessus ; revenu total de la base au-dessus du panneau « NOM'S
  BASE » (comparaison entre joueurs).
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
  silhouette noire et « ??? » s'il n'a jamais été obtenu), total « Unlocked: x / 21 » en bas. L'Index garde les
  mannequins obtenus même vendus.
- **Réplication** : le serveur publie la collection dans des attributs du joueur (`Stock`, `BaseDummies`, `Displays`,
  `DummyIndex`, `PendingDummy` = dernier gagné), en clés « id:taille ». Le client n'envoie que des intentions (remote
  `Inventory` : Place / Sell + clé, Remove + présentoir, SellRarity + rareté, PlaceBest ; invite du pad), le serveur
  valide tout. Deux doublons sont interchangeables : le client désigne un mannequin du stock par sa clé.
- **Sauvegarde** avec les données du joueur (`Collection` : présentoirs, présentoirs achetés, stock, Index = meilleure
  taille par mannequin ; `Draws` : nombre de tirages). Migration des sauvegardes de #13 : le mannequin en main passe au
  stock, la liste des découverts devient l'Index.

## Carte (v0.3) : lobby de 4 joueurs, piste unique
- **Hub** (pelouse à damier entourée de parois en gradins) : une **base par joueur** (terrain clôturé, 6 à 10 présentoirs
  pour la collection, panneau « NOM'S BASE » et revenu au-dessus, pad d'achat de présentoir) avec son **appareil
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
- **Piste partagée** (80 studs de large, 2,4 km) au fond d'un canyon en 3 gradins : parois en briques, herbe (ou neige,
  sable…) voxel qui déborde de chaque marche, décor voxel sur les terre-pleins et au pied des parois (traversable).
- **Obstacles partagés** (`Server.Obstacles`, plan dans `Shared.TrackPlan`) : dans chaque thème, une rangée de 4 vitres
  (une par colonne, repère de distance, cadre à la couleur du thème), puis les 2 ou 3 obstacles cassables du thème à
  tour de rôle (`Server.ThemeObstacles`, un par colonne ou d'un seul tenant sur la largeur des colonnes) et son piège
  signature (section « Zones de la piste », un second piège dans les thèmes longs), sites espacés régulièrement
  (≈ 35 m, 3 à 8 par thème).
  Une pièce déplacée réapparaît à sa place **5 s après le dernier choc** subi par son obstacle, une par une de bas en haut
  (0,05 s d'écart), en grossissant depuis son centre ; jamais sur un mannequin posé dedans. Un objet projeté est compté
  pour le mannequin le plus proche (règles dans `Shared.ObstacleRules`).

## Zones de la piste (2,4 km, #33)
Douze thèmes courts au début (un changement tous les 60 à 150 m sur le premier kilomètre, où vole un joueur débutant :
un premier lancer à ≈ 145 m en traverse 3), plus longs ensuite. Chaque thème a son identité (couleur du sol, des parois,
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
Hors de cette phase, le mannequin passe sans rien. L'anneau propulseur est un cerceau néon en haut de la colonne, sur la
ligne de vol des vitres, avec un pad au sol ; entre les deux, un halo et des étincelles.

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
  Shop = équipements d'entraînement ; Dummy Shop : section « Boutique de mannequins à lancer » ; Dummies (« My
  Dummies »), vente et Index : section « Base et collection ». Les
  listes de collection défilent verticalement (grille en `ScrollingFrame` Y, #45).
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
  mannequin à lancer ; `FreshPlayer` sur
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
