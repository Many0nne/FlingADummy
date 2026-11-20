---
name: delegation-fad
description: Regles de delegation propres au depot Fling a Dummy (Roblox) - creer le worktree avec scripts/fad-worktree.ps1, classer chaque tache selon son besoin de Studio, au plus 2 taches Studio en parallele, une seule reservation Studio par tache, en fin de tache. Use when delegating or parallelizing Fling a Dummy tasks (/delegate, /triage, lots d'issues de la refonte), or when writing a brief for a Fling a Dummy worktree.
---

# Delegation dans le depot Fling a Dummy

Complete `/delegate` et `/triage` (skills globaux) pour ce depot : une seule place Studio (placeId 88580736516669) sert
tous les worktrees (verrou `worktrees/.run/studio.lock`, cf. « Studio et Blender partages » du `CLAUDE.md`). Quand trop
de taches en ont besoin en meme temps, elles attendent le verrou 20 a 30 min, puis renvoient la verification en jeu a
l'utilisateur.

## 1. Creer le worktree avant de lancer la session

Depuis la racine du checkout principal :

1. `.\scripts\fad-worktree.ps1 <branche> -NoUp -NoRegister` : cree (ou reprend) `worktrees/fad-<slug>/`, attribue le
   slot et ecrit `.claude/settings.local.json` (ecriture dans `worktrees/.briefs` et `%TEMP%`). A faire **avant** de
   lancer la session : elle lit ce fichier au demarrage.
2. Brief dans `worktrees/.briefs/fad-<slug>.md`, avec la commande de demarrage `.\scripts\fad-worktree.ps1 <branche>`
   (lance Rojo, verifie `[OK (200)]`) et le port affiche.
3. Thread T3 cree : `.\scripts\fad-worktree.ps1 <branche> -RegisterThread <threadId>` (nettoyage automatique).

## 2. Classer chaque tache avant de la lancer

| Classe | Critere | Exemples |
|---|---|---|
| `sans-studio` | verifiable par `check.sh`, tests Lune, `rojo build`, Blender `-b` | doc, outillage, logique pure testee (`src/shared`), economie chiffree |
| `studio` | verification en jeu (MCP, `DebugLaunch`, capture) ou avis de l'utilisateur dans Studio | carte, lancer, game feel, UI, mannequin, cinematique |

Doute : `studio`. Indiquer la classe dans le rapport de `/triage` et en tete du brief (`Studio : oui/non`).

## 3. Limiter le parallelisme

- Au plus **2 taches `studio`** en cours en meme temps : une qui verifie dans Studio pendant que l'autre code.
- Les taches `sans-studio` ne comptent pas dans cette limite.
- Une tache `studio` qui attend l'avis de l'utilisateur garde le verrou : elle compte jusqu'a son retour. Lancer la
  suivante seulement quand une des deux a libere Studio (thread ferme, ou `-StudioStatus` montre un autre detenteur).
- Taches qui touchent les memes fichiers (ex. `ThrowController`, `FlightCamera`) : en sequence, pas en parallele.

## 4. Ce que le brief d'une tache `studio` impose

Ajouter au brief, section regles :

- Tout faire sans Studio d'abord (code, `bash tools/check.sh` lu en entier, tests Lune, `rojo build`).
- **Une seule reservation Studio, en fin de tache** : `.\scripts\fad-worktree.ps1 <branche> -AcquireStudio -WaitStudio 20`,
  connecter le plugin Rojo au port affiche (mode Edit), puis toutes les verifications en jeu d'un coup (playtest,
  captures, mesures avant/apres), puis `-ReleaseStudio` immediatement. Pas de reservation « pour voir » en cours de tache.
- Verification qui echoue : liberer Studio, corriger hors Studio, puis une nouvelle reservation (2 au plus ; au-dela,
  statut `BLOQUE` avec ce qui echoue).
- Avis de l'utilisateur necessaire : regrouper toutes les questions dans une seule demande, faite pendant la reservation
  finale (protocole : port Rojo connecte, etapes, quoi observer), et garder le verrou jusqu'a la reponse.
- `-WaitStudio` expire (code 2) : ne pas renvoyer la verification a l'utilisateur par defaut ; noter dans le compte rendu
  ce qui reste a verifier en jeu et le scenario exact, statut `BLOQUE`.

## 5. Compte rendu

Le script de worktree autorise la session a ecrire dans `worktrees/.briefs` et `%TEMP%` : le compte rendu s'ecrit a la
fin du brief, sans script de contournement. Si l'ecriture est quand meme refusee : verifier que
`.claude/settings.local.json` du worktree liste bien ces dossiers (sinon relancer `.\scripts\fad-worktree.ps1 <branche> -NoUp`
depuis la racine), puis relancer la session (le fichier n'est lu qu'au demarrage) ; ne pas contourner par un script.
