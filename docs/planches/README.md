# Planches de référence (#121)

Tout ce que le joueur peut obtenir, visible sans jouer, capturé dans le jeu (Studio) :

| Planche | Contenu |
|---|---|
| [`collection.jpg`](collection.jpg) | les mannequins de collection, une rangée par rareté (Common → Infinity) : nom, cote « 1 IN N » et revenu en taille Normal, aura comprise |
| [`a-lancer.jpg`](a-lancer.jpg) | les mannequins à lancer : nom, prix, chance |
| [`base.jpg`](base.jpg) | les paliers visuels de la base (Wood → Golden), même cadrage, présentoirs achetés du palier |
| [`entrainement.jpg`](entrainement.jpg) | les paliers de l'appareil d'entraînement (Training Gear) : podium, râtelier et ses mannequins, même cadrage |

`manifest.json` décrit chaque prise de vue et chaque case (texte, empreinte de l'apparence). Un test de
`tools/check.sh` (`tests/specs/Planches.spec.luau`) le compare au catalogue : un mannequin, un palier ajouté ou retiré,
un look ou un habillage modifié sans planches régénérées fait échouer la CI. Règle : `CLAUDE.md`, section Qualité.

## Régénérer

Une seule réservation Studio, pour toutes les planches ou une seule. Chaîne : `Shared.PlanchePlan` (prises de vue) →
`Server.PhotoStudio` (scène, Studio seulement) et `Client.PhotoCamera` (cadrage) → captures du MCP Studio →
`tools/planches.py` (découpe et assemblage).

1. Manifeste (hors Studio), depuis le worktree :
   ```bash
   lune run tools/planches-manifest.luau
   python -I tools/planches.py shots [planche...]   # prises à faire, dans l'ordre
   ```
2. Studio : `.\scripts\fad-worktree.ps1 <branche> -AcquireStudio -WaitStudio 20`, puis Play (MCP `start_stop_play`).
   Ne pas redimensionner la fenêtre de Studio pendant la séance (toutes les captures à la même taille).
3. Pour chaque prise, dans l'ordre donné par `shots` (≈ 2 s entre les deux appels, le temps que l'aura s'allume) :
   - `execute_luau` contexte `Server` : `workspace:SetAttribute("PhotoShot", "<prise>")` (la console du serveur écrit
     « [planches] <prise> prête », celle du client « caméra sur <prise> ») ;
   - `screen_capture` (sans position de caméra) : l'image arrive dans `%LOCALAPPDATA%\Roblox\tmp-capture-storage`.

   Une prise ratée se refait tout de suite (même prise, nouvelle capture) puis `python -I tools/planches.py grab <prise>`
   à la place de `collect` pour cette prise.
4. Fin : `workspace:SetAttribute("PhotoShot", nil)` (scène retirée, place libre rendue vide), Stop, puis
   `.\scripts\fad-worktree.ps1 <branche> -ReleaseStudio`. La séance ne touche pas à la sauvegarde du joueur : base et
   appareil photographiés sur une place libre.
5. Assemblage (hors Studio) :
   ```bash
   python -I tools/planches.py collect [planche...]  # les N dernières captures -> prises, dans l'ordre (%TEMP%\fad-planches)
   python -I tools/planches.py build [planche...]    # docs/planches/<planche>.jpg (1 600 px, < 1 Mo)
   ```
   Regarder chaque planche avant de committer, et joindre l'avant / après à la PR.

Nombre de prises : collection 11 (une par rareté), à lancer 4 (rangées de 6), base 5, entraînement 12, soit 32.

## Cadrage

- Mannequins : échelle 1 (les plus rares sont plus grands en jeu, `Collection.RARITY_SCALE`), construits comme en jeu
  (`DummyShape.buildVisual`, déclinaison et aura de `Collection.variant`), en rangée de 6 cases de 7 × 11 studs devant
  un fond neutre au-dessus du hub, caméra du côté du soleil (champ de 30°) : la rangée remplit toute la largeur de
  l'image, `planches.py` la coupe en 6 cases égales.
- Base et appareil : la dernière place libre du lobby, habillée palier par palier (`BaseService.showcase`,
  `CourseBuilder.styleStation`), vue de 3/4 depuis l'entrée ; l'appareil est recadré au centre en 4:3.
