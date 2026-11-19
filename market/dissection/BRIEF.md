# Brief : dissection d'un jeu Roblox à partir d'images de session

## But
Étude de marché : comprendre **ce qui fait marcher** des jeux Roblox récents qui ont percé (des dizaines de milliers de joueurs simultanés en quelques semaines). On veut des **faits observables et horodatés**, pas d'avis ni de ressenti ("c'est fun", "c'est joli" : interdit).

## Entrées (dans le dossier du jeu)
- `context.json` : données publiques (CCU, visites, likes, date de création, joueurs par serveur, créateur, description, **liste des gamepasses en vente avec prix en Robux**).
- `index.json` : liste des images avec leur instant `t` (secondes) et leur type : `accroche` (toutes les 3 s pendant 2 min), `scène` (changement d'écran), `régulier` (toutes les 30 s). Aussi `durée_s` de la vidéo.
- Les images `tMMmSS.Ss.jpg` : captures d'une **première session** sur ce jeu, sans rien acheter, en suivant ce que le jeu pousse à faire.

Lire `context.json` et `index.json`, puis **toutes** les images dans l'ordre chronologique. L'interface du joueur est en français (traduction automatique de Roblox).

## Grille (faits à relever, avec horodatage `mm:ss`)
1. **Accroche** : instant de la première action possible, de la première récompense, du premier gros chiffre / première amélioration.
2. **Tutoriel** : présent ou non, forme (flèches, texte, chemin lumineux, PNJ), durée.
3. **Boucle de jeu** : l'action répétée en une phrase (« lancer → gagner → améliorer le lancer »).
4. **Progression** : paliers atteints pendant la session (niveaux, zones, renaissances, évolutions), monnaies, rythme (gros chiffres qui grimpent ?).
5. **Rétention** : récompense de connexion / quotidienne, cadeaux au temps de jeu, codes, bonus pour like / favori / groupe, missions, événement limité, compte à rebours, collection / index.
6. **Social** : autres joueurs visibles, interaction (coop, échange, PvP, vol), classement, invitation d'amis.
7. **Monétisation** : instant de la première offre, **nombre d'offres affichées pendant la session** (pop-ups, boutiques ouvertes par le jeu), types (gamepass, produit répétable, starter pack, x2, chance), prix vus. Croiser avec la liste des gamepasses de `context.json`.
8. **Interface** : nombre approximatif de boutons permanents, place de la boutique.
9. **Moment spectaculaire** : instants qui feraient un clip court.
10. **Ce qui est reproductible** : mécaniques précises et transposables (pas de copie du thème ni des assets), en 3 à 6 puces.

Si quelque chose n'est pas visible sur les images : écrire « non observé », ne jamais inventer. Les images étant échantillonnées, préciser « au moins N offres » pour les comptages.
Si la vidéo dure moins de 15 min : le testeur a arrêté volontairement parce que continuer n'apportait plus rien ; le signaler (« session arrêtée à N min : plus rien de nouveau ») et compter offres/paliers sur la durée réelle.

## Sortie
Écrire la fiche en français dans `C:\Users\tbarillon\Documents\Obsidian Vault\Jeu Roblox\04 - Jeux disséqués\<NN> - <Nom du jeu>.md` (si l'écriture est refusée, l'écrire dans le dossier du jeu sous `fiche.md` et le dire), exactement dans ce format :

```markdown
---
tags: [jeu-disséqué, roblox]
numéro: <NN>
lien: <lien>
niche: "[[<une de : Physique et ragdoll | Formats viraux | Tycoon et Incremental>]]"
ccu: <ccu>
âge_jours: <jours depuis créé, au 2026-11-19>
joué_le: 2026-11-19
durée_session_min: <durée vidéo>
première_action_s: <nombre ou vide>
première_récompense_s: <nombre ou vide>
première_offre_s: <nombre ou vide>
offres_15min: <nombre, offres vues pendant la session>
paliers_15min: <nombre>
tutoriel: oui/non
bonus_like_favori_groupe: oui/non
récompense_temps_de_jeu: oui/non
codes: oui/non
---

# <Nom du jeu>

> <Une phrase : le concept tel qu'un joueur le comprend depuis la vignette.> Données publiques : <CCU>, <visites>, <% likes>, <joueurs/serveur>, <nb gamepasses> gamepasses (<fourchette de prix>).

## Boucle de jeu
## Accroche (horodatée)
## Progression
## Rétention
## Social
## Monétisation (offres vues, horodatées, avec prix)
## Interface
## Moment spectaculaire
## Ce qui est reproductible

Images : `<chemin du dossier>` · Lié : [[Grille de dissection]] · [[Relevé 2026-11-19]]
```

Ton court, puces, chiffres et horodatages. Pas de prose générique.

## Réponse finale (à ton commanditaire)
5 lignes maximum : chemin de la fiche, la boucle en une phrase, les 2 mécaniques les plus notables, et tout doute (image illisible, jeu non identifié…).
