# Page du jeu (#178) : proposition avant sortie

Tout ce qui se publie sur l'expérience (universe 10777904551, place 88580736516669). **Rien n'est publié sans l'accord
de l'utilisateur.**

## Publication (2026-11-23, proposition validée)
- Open Cloud (relu après écriture) : nom « Throw a Dummy » (nom de la place racine, repris par l'expérience),
  description ci-dessous, 4 joueurs par serveur, ordinateur / téléphone / tablette oui, console et VR non, chat vocal
  désactivé.
- Icônes dessinées (`assets/icons/export/`) posées par `PATCH` sur 5 passes (Strong Arms déjà bon) et 13 produits.
- Creator Dashboard (par l'utilisateur, pas d'API Open Cloud) : icône, 4 vignettes, genre, questionnaire de maturité.
- Reste privée : passage en public par l'utilisateur, après son dernier test.

État avant publication, relevé par Open Cloud le 2026-11-23 : nom « Fling a dummy », description vide, privée, chat
vocal activé, classement 13+, ordinateur / téléphone / tablette / VR activés, console désactivée, 50 joueurs par
serveur (#142).

## Titre
Vérifié par la recherche Roblox (omni-search) et le web le 2026-11-23 ; « Fling » est pris par plusieurs jeux (#7).

| Rang | Titre | Vérification |
|---|---|---|
| 1 (recommandé) | **Throw a Dummy** | aucun jeu homonyme ; même moule que *Throw a Seed* (09) et *Throw Food For Animals* (01), le mot « Throw » est celui que cherchent les joueurs du genre ; 13 caractères, lisible sur une vignette de téléphone |
| 2 | Toss a Dummy | aucun jeu homonyme ; « toss » est moins cherché |
| 3 | Yeet a Dummy | aucun jeu homonyme ; moule connu (*Yeet A Friend!*), mais argot |
| écarté | Launch a Dummy | déjà pris (« [💥] LAUNCH A DUMMY », sans joueurs) |
| écarté | Fling a Dummy | « Fling » saturé : *Fling Things and People* (≈ 24 K joueurs), *Fling Arena*, *Fling Playground* |

Concurrent direct à surveiller : *Ragdoll Lab [CRASH TEST]* (on y lance aussi des mannequins). Le titre n'est affiché
nulle part dans le jeu : rien à changer dans le code.

## Description (anglais)
Au moule de 09 (une phrase d'accroche, trois paragraphes courts à emoji, une liste de chiffres, une question finale).
Chaque affirmation existe dans le jeu (pas de récompense quotidienne, de revenu hors ligne ni de codes : non cités).

```
🧨 Throw a crash test dummy down the canyon and smash everything in its way!

🎯 Tap at the right moment to throw. Every zone your dummy flies through boosts your luck, from the Meadow all the way to the Galaxy ✨ Smash bricks, break bones and bounce off traps on the way!

🍀 When it lands, you win a collectible dummy. Will it be a common Crash Dummy or a 1 in 100T Infinite Crash King? 👑

💰 Put your dummies on display in your base and watch the cash roll in. Lift weights to get stronger, upgrade your training gear and unlock new dummies to throw.

🗺️ 18 zones to fly through
🤖 64 collectible dummies across 11 rarities, from Common to Infinity
📏 Huge and Giant sizes
🌟 Rebirth for permanent extra luck
📖 Collect them all in the Index

🚀 How far can you throw?
```

## Icône et vignettes
`assets/store/export/` (procédure : `assets/store/README.md`), comparaison avec 01 / 02 / 09 :
`docs/captures/sortie-178/comparaison.jpg`. Ordre de publication : vignette 1 (lancer, « 1 IN 100T »), 2 (mystère),
3 (« SMASH! »), 4 (collection, « $540M/S »).

## Vidéo (#225)
`assets/store/video/export/throw-a-dummy.mp4` (20 s, 1920 × 1080, −14 LUFS) : l'avatar bacon hair frappe le Crash
Dummy à l'appareil d'entraînement, le traîne par la cheville jusqu'à la bande, le lance (crash dans la Ferme), en lance
un second qui traverse un mur de briques (plan de la vignette 3), arrêt sur image et titre « THROW A DUMMY ». Tournée
dans Studio avec le vrai jeu, procédure et montage : `assets/store/video/README.md`. À placer en tête de galerie, avant
la vignette 1 (Creator Dashboard, par l'utilisateur ; 3 envois par mois, une vidéo refusée compte).

## Réglages
| Réglage | Proposé | Pourquoi |
|---|---|---|
| Genre | Simulation > Incremental Simulator | celui de 09 (01 et 02 : Tycoon) |
| Joueurs par serveur | **4** (aujourd'hui 50) | 4 bases dans le hub (`SLOT_COUNT`) ; au-delà, le joueur attend dans le hub (#142) |
| Ordinateur, téléphone, tablette | oui | souris, clavier et tactile gérés (#19) |
| Console | **non** | le lancer ne se fait qu'à la souris, au toucher ou à l'espace (`ThrowController`), menus non navigables à la manette |
| VR | **non** (aujourd'hui oui) | jamais testé ; jauge et menus en 2D |
| Chat vocal | **non** (aujourd'hui oui) | jeu solo en lobby, public jeune ; le classement 13+ actuel vient sans doute de là |
| Visibilité | publique, après publication de la page | |

## Questionnaire de maturité (réponses proposées)
| Question | Réponse | Pourquoi |
|---|---|---|
| Violence | légère et irréaliste | un mannequin de crash-test se casse des « os » (compteur BONES, rayons X), sans sang ni humain blessé |
| Sang | non | |
| Peur, horreur | non (Haunted Castle : décor de citrouilles, sans frayeur) | |
| Humour grossier, langage, contenu romantique, alcool, drogues | non | |
| Jeux d'argent | non | aucun pari d'argent réel ni de Robux |
| **Objets aléatoires payants** | **oui** | les Lucky Throws et les potions de chance (Robux) augmentent la chance d'un tirage aléatoire de mannequin ; les cotes sont affichées (« 1 IN N ») |
| Chat libre, contenus créés par les joueurs | chat textuel Roblox par défaut, rien d'autre | |

Classement attendu : **Minimal** (celui de 01, 02 et 09), tous publics.

## Passes et produits (#172) : écarts avec la boutique
Relevé le 2026-11-23 (Open Cloud et API publiques). Noms, descriptions, prix et mise en vente des 6 passes et
13 produits sont **identiques** à `Store.ITEMS`. Seules les icônes diffèrent : celles publiées sont les icônes
provisoires de #175 (date de mise à jour = date de création), jamais remplacées par les icônes dessinées de #173.

| Article | Icône publiée (provisoire) | Icône de la boutique (`art`) | Écart |
|---|---|---|---|
| 2x Luck | mannequin orange | clover | oui |
| 2x Money | liasse | moneybag | oui |
| VIP | Crash King | crown | oui |
| Strong Arms | biceps | power | non |
| Big Base | mannequin jaune | house | oui |
| Rainbow Dummy | Prism Diamond | rainbow | oui |
| Starter Pack | mannequin | shop | oui |
| 8 boosts (potions, Server Luck, Lucky Throws) | provisoires de #175, vignette encore « Pending » | potion, globe, dice | oui (à confirmer quand la vignette sera générée) |
| 4 Cash | provisoire, vignette « Pending » | cash | probablement non (liasse dans les deux) |

Correction proposée (après accord) : téléverser les icônes de `assets/icons/export/` (`clover`, `moneybag`, `crown`,
`house`, `rainbow`, `shop`, `potion`, `globe`, `dice`) et les poser par `PATCH` sur chaque passe et produit
(Open Cloud, scopes `game-pass:write` et `developer-product:write`), sans recréer les articles.
