"""Relevé quotidien des classements publics Roblox (Discover) dans une base SQLite.

Usage : python -I collect.py [--db data/roblox.db]
Chaque exécution crée un snapshot : rangs dans chaque sort, puis statistiques de chaque jeu vu.
Les gamepasses et les infos créateur sont rafraîchies au plus une fois par semaine.
"""
import argparse, json, sqlite3, sys, time, urllib.error, urllib.parse, urllib.request, uuid
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
UA = {"User-Agent": "market-research-collector/0.1", "Accept": "application/json"}
EXPLORE = "https://apis.roblox.com/explore-api/v1/get-sorts"
REFRESH_DAYS = 7
PAUSE = 0.25  # secondes entre deux requêtes, pour rester poli
RETRIES = {}  # nombre de réponses 429/5xx reçues, par code, pour diagnostiquer les lenteurs

SCHEMA = """
CREATE TABLE IF NOT EXISTS snapshots (id INTEGER PRIMARY KEY, taken_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS sorts (sort_id TEXT PRIMARY KEY, display_name TEXT, info TEXT);
CREATE TABLE IF NOT EXISTS sort_entries (
  snapshot_id INTEGER, sort_id TEXT, rank INTEGER, universe_id INTEGER,
  player_count INTEGER, is_sponsored INTEGER,
  PRIMARY KEY (snapshot_id, sort_id, rank));
CREATE TABLE IF NOT EXISTS games (
  universe_id INTEGER PRIMARY KEY, root_place_id INTEGER, name TEXT, description TEXT,
  creator_id INTEGER, creator_type TEXT, creator_name TEXT, creator_verified INTEGER,
  created TEXT, genre TEXT, genre_l1 TEXT, genre_l2 TEXT, max_players INTEGER, price INTEGER,
  content_maturity TEXT, first_seen TEXT, last_seen TEXT, passes_checked TEXT);
CREATE TABLE IF NOT EXISTS game_stats (
  snapshot_id INTEGER, universe_id INTEGER, playing INTEGER, visits INTEGER,
  favorites INTEGER, up_votes INTEGER, down_votes INTEGER, updated TEXT,
  PRIMARY KEY (snapshot_id, universe_id));
CREATE TABLE IF NOT EXISTS gamepasses (
  pass_id INTEGER PRIMARY KEY, universe_id INTEGER, name TEXT, price INTEGER,
  for_sale INTEGER, created TEXT, seen_at TEXT);
CREATE TABLE IF NOT EXISTS creators (
  creator_id INTEGER, creator_type TEXT, members_or_followers INTEGER,
  public_games INTEGER, verified INTEGER, checked TEXT,
  PRIMARY KEY (creator_id, creator_type));
"""


def get(url, tries=4):
    # Cette méthode permet de faire un GET JSON avec pause et reprise sur 429/5xx,
    # et renvoie None si la ressource reste indisponible.
    for attempt in range(tries):
        time.sleep(PAUSE)
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504):
                RETRIES[e.code] = RETRIES.get(e.code, 0) + 1
                time.sleep(2 ** attempt * 3)
                continue
            return None
        except (urllib.error.URLError, TimeoutError):
            time.sleep(2 ** attempt * 3)
    return None


def now():
    # Cette méthode permet d'obtenir l'horodatage UTC courant au format ISO.
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def stale(ts):
    # Cette méthode permet de savoir si une info datée doit être rafraîchie (absente ou plus vieille que REFRESH_DAYS).
    return not ts or (datetime.now(timezone.utc) - datetime.fromisoformat(ts)).days >= REFRESH_DAYS


def fetch_sorts():
    # Cette méthode permet de parcourir toutes les pages de la page Discover
    # et de renvoyer la liste des sorts de jeux avec leur contenu.
    sid = str(uuid.uuid4())
    base = f"{EXPLORE}?sessionId={sid}&device=computer&country=all"
    sorts, token = [], None
    while True:
        d = get(base + (f"&sortsPageToken={urllib.parse.quote(token)}" if token else ""))
        if not d:
            break
        sorts += [s for s in d.get("sorts", []) if s.get("contentType") == "Games" and s.get("games")]
        token = d.get("nextSortsPageToken")
        if not token:
            break
    return sorts


def chunks(seq, n):
    # Cette méthode permet de découper une liste en paquets de n éléments pour les API par lot.
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


def collect(db_path):
    # Cette méthode permet de réaliser un snapshot complet : sorts, stats des jeux,
    # puis rafraîchissement hebdomadaire des gamepasses et des créateurs.
    db = sqlite3.connect(db_path)
    db.executescript(SCHEMA)
    ts = now()
    sorts = fetch_sorts()
    if not sorts:
        sys.exit("Aucun sort récupéré : API Discover indisponible ou modifiée.")
    snap = db.execute("INSERT INTO snapshots (taken_at) VALUES (?)", (ts,)).lastrowid

    maturity = {}
    for s in sorts:
        info = (s.get("topicLayoutData") or {}).get("infoText")
        db.execute("INSERT OR REPLACE INTO sorts VALUES (?,?,?)", (s["sortId"], s.get("sortDisplayName"), info))
        for rank, g in enumerate(s["games"], 1):
            db.execute("INSERT OR REPLACE INTO sort_entries VALUES (?,?,?,?,?,?)",
                       (snap, s["sortId"], rank, g["universeId"], g.get("playerCount"), int(bool(g.get("isSponsored")))))
            maturity[g["universeId"]] = g.get("contentMaturity")
    ids = list(maturity)
    print(f"{len(sorts)} sorts, {len(ids)} jeux uniques")

    votes = {}
    for batch in chunks(ids, 50):
        for v in (get("https://games.roblox.com/v1/games/votes?universeIds=" + ",".join(map(str, batch))) or {}).get("data", []):
            votes[v["id"]] = (v.get("upVotes"), v.get("downVotes"))

    for batch in chunks(ids, 50):
        for g in (get("https://games.roblox.com/v1/games?universeIds=" + ",".join(map(str, batch))) or {}).get("data", []):
            c = g.get("creator") or {}
            db.execute("""INSERT INTO games (universe_id, root_place_id, name, description, creator_id, creator_type,
                creator_name, creator_verified, created, genre, genre_l1, genre_l2, max_players, price,
                content_maturity, first_seen, last_seen) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(universe_id) DO UPDATE SET name=excluded.name, description=excluded.description,
                creator_verified=excluded.creator_verified, genre=excluded.genre, genre_l1=excluded.genre_l1,
                genre_l2=excluded.genre_l2, max_players=excluded.max_players, price=excluded.price,
                content_maturity=excluded.content_maturity, last_seen=excluded.last_seen""",
                       (g["id"], g.get("rootPlaceId"), g.get("name"), g.get("description"), c.get("id"), c.get("type"),
                        c.get("name"), int(bool(c.get("hasVerifiedBadge"))), g.get("created"), g.get("genre"),
                        g.get("genre_l1"), g.get("genre_l2"), g.get("maxPlayers"), g.get("price"),
                        maturity.get(g["id"]), ts, ts))
            up, down = votes.get(g["id"], (None, None))
            db.execute("INSERT OR REPLACE INTO game_stats VALUES (?,?,?,?,?,?,?,?)",
                       (snap, g["id"], g.get("playing"), g.get("visits"), g.get("favoritedCount"), up, down, g.get("updated")))
    db.commit()

    todo = [r[0] for r in db.execute("SELECT universe_id, passes_checked FROM games WHERE last_seen=?", (ts,)) if stale(r[1])]
    print(f"gamepasses à rafraîchir : {len(todo)}")
    for i, uid in enumerate(todo, 1):
        token = ""
        while True:
            d = get(f"https://apis.roblox.com/game-passes/v1/universes/{uid}/game-passes?passView=Full&pageSize=100"
                    + (f"&pageToken={urllib.parse.quote(token)}" if token else ""))
            if d is None:
                break
            for p in d.get("gamePasses", []):
                db.execute("INSERT OR REPLACE INTO gamepasses VALUES (?,?,?,?,?,?,?)",
                           (p["id"], uid, p.get("displayName") or p.get("name"), p.get("price"),
                            int(bool(p.get("isForSale"))), p.get("created"), ts))
            token = d.get("nextPageToken")
            if not token:
                break
        if d is not None:
            db.execute("UPDATE games SET passes_checked=? WHERE universe_id=?", (ts, uid))
        if i % 100 == 0:
            db.commit()
            print(f"  {i}/{len(todo)}")
    db.commit()
    refresh_creators(db, ts)
    print(f"snapshot {snap} terminé ({ts})")


def refresh_creators(db, ts):
    # Cette méthode permet de rafraîchir taille, nombre de jeux et badge des créateurs des jeux vus au relevé ts,
    # en enregistrant au fil de l'eau pour qu'une interruption ne perde rien.
    creators = db.execute("""SELECT g.creator_id, g.creator_type, MAX(g.creator_verified), c.checked FROM games g
        LEFT JOIN creators c ON c.creator_id=g.creator_id AND c.creator_type=g.creator_type
        WHERE g.last_seen=? GROUP BY g.creator_id, g.creator_type""", (ts,)).fetchall()
    todo = [(cid, ctype, ver) for cid, ctype, ver, checked in creators if cid and stale(checked)]
    print(f"créateurs à rafraîchir : {len(todo)}", flush=True)
    t0 = time.time()
    for i, (cid, ctype, verified) in enumerate(todo, 1):
        if ctype == "Group":
            size = (get(f"https://groups.roblox.com/v1/groups/{cid}") or {}).get("memberCount")
            games = get(f"https://games.roblox.com/v2/groups/{cid}/games?accessFilter=Public&limit=50")
        else:
            size = (get(f"https://friends.roblox.com/v1/users/{cid}/followers/count") or {}).get("count")
            games = get(f"https://games.roblox.com/v2/users/{cid}/games?accessFilter=Public&limit=50")
        n_games = len(games.get("data", [])) if games else None
        db.execute("INSERT OR REPLACE INTO creators VALUES (?,?,?,?,?,?)",
                   (cid, ctype, size, n_games, int(bool(verified)), ts))
        if i % 20 == 0:
            db.commit()
            print(f"  créateurs {i}/{len(todo)} ({time.time() - t0:.0f}s, reprises {RETRIES})", flush=True)
    db.commit()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(HERE / "data" / "roblox.db"))
    ap.add_argument("--creators-only", action="store_true", help="reprend seulement l'étape créateurs du dernier relevé")
    args = ap.parse_args()
    Path(args.db).parent.mkdir(parents=True, exist_ok=True)
    if args.creators_only:
        conn = sqlite3.connect(args.db)
        refresh_creators(conn, conn.execute("SELECT MAX(last_seen) FROM games").fetchone()[0])
    else:
        collect(args.db)
