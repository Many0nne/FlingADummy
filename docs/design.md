# Fling a Dummy — document de conception

Titre provisoire (à tester avant publication). Origine du concept : vault Obsidian, `Jeu Roblox/05 - Concepts/Concepts candidats.md`
(concept A) et `Jeu Roblox/La recette.md` (ce qui fait percer un jeu Roblox).

## Le jeu en une phrase
On charge un canon, on relâche, un mannequin de crash-test traverse un parcours d'obstacles cassables. On gagne selon la
distance, les os cassés et les objets détruits, puis on améliore le canon et la valeur du mannequin.

## Cibles (mesurées sur les jeux qui percent)
| Moment | Cible |
|---|---|
| Première action | 0 s (le canon est prêt dès l'arrivée) |
| Première récompense | < 25 s |
| Première offre payante | ≈ 1 min (v2) |
| Première renaissance | < 3 min (v1) |

## Boucle (≈ 10 s)
1. **Charger** : maintenir clic, toucher ou Espace ; une aiguille fait l'aller-retour sur la jauge. Zone « PERFECT » en haut.
2. **Relâcher** : vitesse = puissance du canon × (0,55 + 0,45 × jauge). PERFECT (jauge ≥ 0,9) : gains × 1,2.
3. **Vol** : caméra qui suit le mannequin ; compteurs en direct (distance, os, objets).
4. **Résultat** : gains = (distance + 10 × os + 5 × objets) × valeur du mannequin (× 1,2 si PERFECT). Couloir remis à neuf.

## Deux courbes
- **Puissance** : vitesse de lancer × 1,12 par niveau (niveau max 15 sur le premier parcours).
- **Valeur du mannequin** : multiplicateur + 0,25 par niveau.

## Dégâts lisibles
Chaque membre (10 pièces) suit les chocs : une variation brusque de vitesse au-delà d'un seuil casse un os (2 au-delà d'un
second seuil), au plus 3 par membre, soit 30 os. Le membre vire du jaune au rouge.

## Architecture
- Tout est **simulé par le serveur** (propriétaire réseau `nil`) : le joueur ne pilote pas le mannequin en vol, la latence
  ne se voit donc pas, le score est fiable et les autres joueurs voient les lancers des voisins.
- 6 couloirs côte à côte (6 joueurs par serveur), un par joueur, reconstruits après chaque lancer.
- Le décor est généré par le code (`CourseBuilder`) : rien à exporter depuis Studio.

## Feuille de route
- **v0 (prototype)** : boucle complète, 2 améliorations, sauvegarde. ← en cours
- **v1** : variantes « 1 en N » révélées en cinématique (verre, caoutchouc, doré, géant), renaissance avec nouveau parcours,
  sons, ralenti des records, récompense quotidienne sur 7 jours.
- **v2** : produits Robux (passer, x2, lancer auto), événement avec compte à rebours, vignette et page du jeu.
