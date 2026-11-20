# Animations de l'avatar : modifier et publier

Le jeu joue les animations **publiées** (`Shared.Assets.ANIMATIONS`, ids d'assets Roblox), pas les clips du dépôt
(`src/shared/AnimationData.luau`). Modifier un clip ne change donc rien en jeu tant que l'asset n'est pas republié.

| Fichier | Rôle |
|---|---|
| `src/shared/AnimationData.luau` | clips (poses, temps, marqueurs), source de vérité |
| `assets/anim/export/<Nom>.rbxm` | `KeyframeSequence` exportée, générée par `tools/build-anims.luau` |
| `assets/anim/published.json` | pour chaque clip : id de l'asset et SHA-256 du `.rbxm` publié |
| `src/shared/Assets.luau` (`ANIMATIONS`) | ids chargés par le jeu |

Le test `assets/anim/published.json (clips republiés)` (`tests/specs/AnimationData.spec.luau`, lancé par
`bash tools/check.sh` et la CI) échoue si l'empreinte d'un `.rbxm` exporté diffère de `published.json`, si un clip n'y
figure pas, ou si un id diffère de `Assets.ANIMATIONS`.

## Republier un clip existant

1. Modifier le clip dans `AnimationData.luau`.
2. Exporter : `lune run tools/build-anims.luau` (réécrit `assets/anim/export/<Nom>.rbxm`).
3. Publier sous le verrou Studio (`.\scripts\fad-worktree.ps1 <branche> -AcquireStudio`), par le MCP Roblox Studio
   `open_cloud_invoke` : `PATCH /assets/v1/assets/<id>` avec `fileContent` = le `.rbxm` (`model/x-rbxm`), scopes
   `asset:read` et `asset:write`. L'opération renvoyée donne une **nouvelle révision du même asset** : l'id de
   `Assets.ANIMATIONS` ne change pas.
4. Vérifier en jeu : `Animator:GetPlayingAnimationTracks()` renvoie la piste de l'asset pendant le geste (la copie en
   Play ne prend pas les changements : relancer le playtest).
5. Enregistrer la publication, seulement si l'opération Open Cloud est `done` (l'interroger) et sans réexporter ni
   modifier le clip depuis l'étape 3 : `lune run tools/build-anims.luau --published` (réécrit `published.json` à partir des
   `.rbxm` exportés et de `Assets.ANIMATIONS`, sans réexporter). Committer `published.json` avec les `.rbxm`.
6. Libérer Studio (`-ReleaseStudio`).

## Créer une nouvelle animation

1. Ajouter le clip à `AnimationData.CLIPS`, puis exporter (étape 2 ci-dessus).
2. Publier : `POST /assets/v1/assets` (`open_cloud_invoke`, mêmes scopes) avec `assetType` `Animation`, un nom, le
   créateur (utilisateur **434916384**) et `fileContent` = le `.rbxm` (`model/x-rbxm`). Interroger l'opération
   renvoyée jusqu'à `done` : la réponse donne l'id de l'asset.
3. Ajouter l'id dans `Assets.ANIMATIONS` (`src/shared/Assets.luau`).
4. Vérifier en jeu (étape 4), puis `lune run tools/build-anims.luau --published` (étape 5).

## Si le test échoue

- « .rbxm exporté différent du .rbxm publié » : un clip a été modifié et réexporté sans republication. Republier
  (étapes 3 à 5), ou annuler la modification.
- « absent de published.json » ou « id différent » : clip ajouté ou id changé sans étape 5.
