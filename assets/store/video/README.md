# Vidéo de présentation de la page du jeu (#225)

Vidéo de 20 s pour la galerie de la page Roblox (1920 × 1080, 30 i/s, H.264 + AAC, −14 LUFS) :
`export/throw-a-dummy.mp4`, planche de contrôle `export/planche.jpg`. Envoi par l'utilisateur (Creator Dashboard,
3 vidéos par mois, moins de 60 s ; une vidéo refusée compte dans le quota).

| Temps | Plan | Prise |
|---|---|---|
| 0-9,5 s | l'avatar bacon hair arrive à l'appareil d'entraînement, frappe le Crash Dummy debout sur le podium (il tangue), le montre du doigt en riant, rafale, gros coup : le mannequin tombe ; il rit, l'attrape par la cheville et le traîne vers la bande | `opening` (mise en scène) |
| 9,5-11,3 s | sur la bande, mannequin au-dessus de la tête (vu de dos), gros plan du lancer | `throw1` (lancer réel, Espace) |
| 11,3-13,7 s | vol dans la Ferme (tracteur pulvérisé), crash dans les débris sous les balançoires | `crash` (mannequin de test, caméra qui suit) |
| 13,7-15,7 s | il glousse, le mannequin suivant déjà en main | `react` |
| 15,7-16,2 s | fouetté du second lancer | `throw2` (lancer réel) |
| 16,2-16,9 s | changement de plan : derrière un mur de briques, le mannequin le traverse (comme la vignette 3) | `wall` (mur de briques libres) |
| 16,9-20,1 s | arrêt sur image, flash blanc, titre « THROW A DUMMY » en rebond, coup de canon | montage |

Son : bruitages des prises (coups, chocs, briques, whoosh du jeu), musique « Funky Thing » (piste du hub,
`Shared.Music`) d'un seul tenant, fondu de sortie, coup de canon (`Shared.Sounds.Cannon`) à l'arrivée du titre.
Seuls les gestes de l'ouverture (coups, rires, traîné) n'existent pas dans le jeu : le lancer, le vol, la piste et la
casse sont ceux du jeu (Roblox refuse les vidéos qui trompent sur le contenu).

## Fichiers
| Fichier | Contexte MCP | Rôle |
|---|---|---|
| `server.luau` | Server | `_G.FadVideo` : habillage bacon hair du personnage du joueur (`dress`), mur de briques (`wall`), mannequin de test (`bot`), relevé de trajectoire (`track`) |
| `camera.luau` | Client | `_G.FadCam` : interface, panneaux flottants et flèche de l'objectif cachés, musique du jeu coupée, cadrages (`fixed`, `chase`, `release`), repère magenta (`flash`) |
| `opening.luau` | Client | `_G.FadOpening` : Crash Dummy posé sur le podium de la place 1, gestes de l'avatar (clips au format de `Shared.AnimationData`), prise d'ouverture (`setup`, `run`), gloussement (`chuckle`) |
| `edit.py` | poste | montage : repère magenta de chaque prise, coupes, recadrage 16:9, arrêt sur image, titre (rendu de `../compose.py`), mixage |

## Refaire les prises (une réservation Studio, environ 30 min)
Capture : `video_capture` du MCP (contexte Client), image de la fenêtre de Studio (1600 × 752 sur ce poste), son du
jeu compris, **30 s au plus** par prise. Chaque prise commence par `_G.FadCam.flash()` (image magenta), que `edit.py`
retrouve pour caler les coupes. Copier chaque vidéo rendue par `video_capture` sous son nom de prise dans un dossier
hors du dépôt.

1. `.\scripts\fad-worktree.ps1 <branche> -AcquireStudio -WaitStudio 20`, `workspace:SetAttribute("FreshPlayer", true)`
   (Edit), Play.
2. Coller `server.luau` (Server), puis `_G.FadVideo.track()` et `_G.FadVideo.dress()` ; coller `camera.luau`, puis
   `opening.luau` (Client).
3. `opening` : `_G.FadOpening.setup()`, démarrer l'enregistrement, `_G.FadOpening.run()`, arrêter 12 s plus tard.
4. `throw1` : `_G.FadOpening.clear()`, `_G.FadCam.release()` ; amener l'avatar sur la bande vers x = −13 (le placer
   en (−13, 3, −21), puis `character_navigation` vers (−13, 3, −6)) ; enregistrer, `flash()`, Espace 1 s plus tard,
   arrêter 3 s après.
5. `react` : de nouveau sur la bande (vers x = −15), `_G.FadCam.fixed(p + (1.9, 2.5, 6.8), p + (−0.3, 2.7, 0), 45)`
   (p = position du HumanoidRootPart) ; enregistrer, `flash()`, `_G.FadOpening.chuckle(2.2)`.
6. `throw2` : `_G.FadCam.release()`, enregistrer, `flash()`, Espace.
7. `crash` (piste intacte : avant `wall`) : `_G.FadCam.chase(Vector3.new(17, 6.5, -8), 55, 4)` ; enregistrer,
   `flash()`, puis `_G.FadVideo.bot(10)` (couloir x = −9, crash vers z = 205 sous les balançoires).
8. `wall` : `_G.FadCam.fixed(Vector3.new(-4, 6.5, 203), Vector3.new(-9.5, 8.5, 188), 52)`, `_G.FadVideo.wall()` ;
   enregistrer, `flash()`, `_G.FadVideo.clearCourse(-31, 13, 174, 214)` puis `_G.FadVideo.bot(10)`. Mesuré : le
   mannequin arrive sur le mur à 143 studs/s vers 8 studs de haut ; avec des briques plus lourdes, il ne fait qu'un trou.
9. `music` : jouer `rbxassetid://1842246698` dans un `Sound` de SoundService (hors du groupe coupé), enregistrer
   30 s, `flash()` au départ. `sfx` : `flash()`, puis `Shared.Sounds.Cannon` 1 s plus tard.
10. Stop, `workspace:SetAttribute("FreshPlayer", nil)` (Edit), `-ReleaseStudio`.

Les mannequins de test (`DebugLaunchBots`) suivent la même trajectoire quelle que soit `DebugBotsPower` (mesuré à 6 et
10) ; leur vol n'a pas de copie locale en avance, la caméra peut suivre la copie répliquée. Le mur retire le décor de
la piste autour de z = 188 jusqu'au Stop : tourner `crash` avant `wall`.

## Monter
```bash
python -I assets/store/video/edit.py <dossier des prises> --flashes   # instant du repère de chaque prise
python -I assets/store/video/edit.py <dossier des prises> --sheet     # vidéo + planche de contrôle
```
Les coupes (`SHOTS` : secondes après le repère) dépendent des prises : une nouvelle prise impose de les reprendre (images
de début et de fin à vérifier une par une). Il faut ffmpeg dans le PATH, Pillow et la police LuckiestGuy de Roblox.
