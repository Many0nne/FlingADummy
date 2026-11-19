"""Prépare un lot de dissection : images de chaque vidéo + contexte tiré de la base (stats, description, gamepasses).

Usage : python prepare_lot.py lot1.json
lot1.json : [{"num": "01", "slug": "...", "universe_id": 123, "video": "C:/.../x.mp4"}, ...]
"""
import json, sqlite3, sys
from pathlib import Path

from frames import extract

HERE = Path(__file__).resolve().parent


def context(db, uid):
    # Cette méthode permet de rassembler les données publiques connues d'un jeu (dernier relevé, créateur, gamepasses).
    g = db.execute("""SELECT g.name, g.description, g.genre_l1, g.genre_l2, g.created, g.max_players, g.creator_name,
        g.creator_type, c.members_or_followers, c.public_games, s.playing, s.visits, s.favorites, s.up_votes, s.down_votes, s.updated,
        g.root_place_id FROM games g JOIN game_stats s ON s.universe_id=g.universe_id
        LEFT JOIN creators c ON c.creator_id=g.creator_id AND c.creator_type=g.creator_type
        WHERE g.universe_id=? ORDER BY s.snapshot_id DESC LIMIT 1""", (uid,)).fetchone()
    keys = ["nom", "description", "genre", "sous_genre", "créé", "joueurs_par_serveur", "créateur", "type_créateur",
            "membres_ou_abonnés", "jeux_publics_du_créateur", "ccu", "visites", "favoris", "likes", "dislikes", "mis_à_jour", "place_id"]
    ctx = dict(zip(keys, g))
    ctx["lien"] = f"https://www.roblox.com/games/{ctx.pop('place_id')}"
    ctx["gamepasses"] = [dict(nom=n, prix=p) for n, p in db.execute(
        "SELECT name, price FROM gamepasses WHERE universe_id=? AND for_sale=1 ORDER BY price", (uid,))]
    return ctx


def resolve(db, name):
    # Cette méthode permet de retrouver l'identifiant d'un jeu à partir d'un morceau de son nom (le plus joué l'emporte).
    row = db.execute("""SELECT g.universe_id FROM games g JOIN game_stats s ON s.universe_id=g.universe_id
        WHERE g.name LIKE ? ORDER BY s.playing DESC LIMIT 1""", (f"%{name}%",)).fetchone()
    if not row:
        sys.exit(f"Jeu introuvable dans la base : {name}")
    return row[0]


def main(lot_file):
    # Cette méthode permet de produire, pour chaque jeu du lot, son dossier d'images horodatées et son context.json.
    db = sqlite3.connect(HERE / "data" / "roblox.db")
    for item in json.loads(Path(lot_file).read_text(encoding="utf-8")):
        if not item.get("universe_id"):
            item["universe_id"] = resolve(db, item["name"])
        out = HERE / "dissection" / f"{item['num']}-{item['slug']}"
        if (out / "index.json").exists() and (out / "context.json").exists() and "--force" not in sys.argv:
            print(f"déjà prêt : {out.name}")
            continue
        extract(Path(item["video"]), out, 80)
        (out / "context.json").write_text(json.dumps(context(db, item["universe_id"]), ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1])
