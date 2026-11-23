# Icône et vignettes de la page du jeu (#178)

Scènes 3D montées dans le jeu (Studio) avec les vrais modèles (mannequins de `Shared.DummyShape`, décor du canyon) et
un avatar **bacon hair** (corps R15 par défaut, coiffure « Pal Hair », tête classique souriante), puis composées par
script : couleurs poussées, recadrage, silhouette « ? » et « !! », traînée jaune du lancer, gros texte à contour
(police LuckiestGuy du jeu). Proposition complète de la page : `docs/page-du-jeu.md`.

| Fichier | Contenu |
|---|---|
| `studio/stage.luau` | mise en scène (contexte Server) : `_G.FadStore.shot("<prise>")` |
| `studio/camera.luau` | caméra et interface cachée (contexte Client) |
| `captures/<prise>.jpg` | captures brutes de Studio (1614 × 759, fenêtre de Studio du poste) |
| `compose.py` | composition des images finales et de la planche de comparaison |
| `export/icon.png` | icône 512 × 512 |
| `export/thumb-1.png` … `thumb-4.png` | vignettes 1920 × 1080 : lancer « 1 IN 100T », mystère, « SMASH! », collection « $540M/S » |

## Refaire les captures (une réservation Studio)
1. `.\scripts\fad-worktree.ps1 <branche> -AcquireStudio -WaitStudio 20`, `Workspace.FreshPlayer = true` (contexte
   Edit), Play (`start_stop_play`).
2. Coller `studio/stage.luau` (Server), puis `studio/camera.luau` (Client).
3. Pour chaque prise (`icon`, `mystery`, `arc`, `smash`, `collection`) : `_G.FadStore.shot("<prise>")` (Server), puis
   `screen_capture`, et copier l'image dans `captures/<prise>.jpg`. `shot` retire les obstacles devant la caméra
   juste avant la capture : ils réapparaissent seuls quelques secondes plus tard.
4. Stop, `FreshPlayer` retiré (Edit), `-ReleaseStudio`.

Les positions du texte, de l'arc et de la silhouette (`compose.py`, en pixels de l'image finale) dépendent du cadrage :
une capture d'une autre taille ou d'un autre cadrage impose de les reprendre.

## Composer
```bash
python -I assets/store/compose.py [--refs <dossier>] [icon thumb-1 …]
```
`--refs` : icônes et vignettes publiées de 01 / 02 / 09 (`<placeId>_icon.png`, `<placeId>_thumb<n>.png`, API
thumbnails publique) pour `docs/captures/sortie-178/comparaison.jpg`. Police : LuckiestGuy de l'installation de
Roblox (`FAD_FONT` pour une autre).
