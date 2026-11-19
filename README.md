# Fling a Dummy

Jeu Roblox : charger le canon, lancer un mannequin de crash-test à travers un parcours cassable, améliorer, recommencer.

```bash
rokit install                          # outils (rojo, stylua, selene, luau-lsp, lune)
rojo serve                             # port 34900, puis Connect dans le plugin Rojo de Studio
bash tools/check.sh                    # lint, format, typecheck, tests
rojo build -o FlingADummy.rbxlx        # place autonome
```

Conception : `docs/design.md`. Règles de travail : `CLAUDE.md`.
