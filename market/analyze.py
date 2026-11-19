"""Analyse de la base collectée : genres, percées récentes, monétisation, croissance.

Usage : python -I analyze.py [--db data/roblox.db]
Écrit reports/report-<date>.html et reports/games-<date>.csv, et affiche un résumé texte.
"""
import argparse, csv, html, re, sqlite3, statistics as st
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
YOUNG_DAYS = 90       # « récent » = créé il y a moins de 90 jours
BREAKOUT_CCU = 1000   # « percée » = au moins 1 000 joueurs simultanés
SMALL_GAMES = 5       # « petit créateur » = non vérifié et au plus 5 jeux publics
EMOJI = re.compile("[\U0001F300-\U0001FAFF☀-➿]")


def med(xs):
    # Cette méthode permet de calculer une médiane en ignorant les valeurs absentes (None si liste vide).
    xs = [x for x in xs if x is not None]
    return st.median(xs) if xs else None


def days_since(iso):
    # Cette méthode permet de convertir une date ISO Roblox en nombre de jours écoulés jusqu'à maintenant.
    if not iso:
        return None
    d = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return max((datetime.now(timezone.utc) - d).total_seconds() / 86400, 0.5)


def load(db):
    # Cette méthode permet de construire une ligne enrichie par jeu à partir du dernier snapshot,
    # avec la croissance mesurée depuis le premier snapshot où le jeu apparaît.
    snaps = db.execute("SELECT id, taken_at FROM snapshots ORDER BY id").fetchall()
    last_id, last_ts = snaps[-1]
    sorts_of, sponsored = {}, set()
    for sid, uid, sp in db.execute("SELECT sort_id, universe_id, is_sponsored FROM sort_entries WHERE snapshot_id=?", (last_id,)):
        sorts_of.setdefault(uid, set()).add(sid)
        if sp:
            sponsored.add(uid)
    passes = {}
    for uid, price in db.execute("SELECT universe_id, price FROM gamepasses WHERE for_sale=1"):
        passes.setdefault(uid, []).append(price)
    first = {uid: (ts, playing, visits) for uid, ts, playing, visits in db.execute("""
        SELECT s.universe_id, sn.taken_at, s.playing, s.visits FROM game_stats s JOIN snapshots sn ON sn.id=s.snapshot_id
        WHERE s.snapshot_id = (SELECT MIN(snapshot_id) FROM game_stats WHERE universe_id=s.universe_id)""")}
    rows = []
    for r in db.execute("""SELECT g.universe_id, g.root_place_id, g.name, g.genre_l1, g.genre_l2, g.created, g.max_players,
            g.price, g.creator_name, g.creator_type, g.creator_verified, c.members_or_followers, c.public_games,
            s.playing, s.visits, s.favorites, s.up_votes, s.down_votes, s.updated, g.passes_checked
            FROM game_stats s JOIN games g ON g.universe_id=s.universe_id
            LEFT JOIN creators c ON c.creator_id=g.creator_id AND c.creator_type=g.creator_type
            WHERE s.snapshot_id=?""", (last_id,)):
        (uid, place, name, l1, l2, created, maxp, price, cname, ctype, cver, csize, cgames,
         playing, visits, fav, up, down, updated, pchecked) = r
        age = days_since(created)
        f_ts, f_play, f_vis = first.get(uid, (last_ts, playing, visits))
        span = (datetime.fromisoformat(last_ts) - datetime.fromisoformat(f_ts)).total_seconds() / 86400
        pp = passes.get(uid, [])
        rows.append(dict(
            universe_id=uid, url=f"https://www.roblox.com/games/{place}", name=name, genre=l1 or "?", subgenre=l2 or "?",
            age_days=round(age) if age else None, playing=playing or 0, visits=visits or 0,
            visits_per_day=round(visits / age) if visits and age else 0,
            like_ratio=round(up / (up + down), 3) if up is not None and (up + down) else None,
            fav_per_1k_visits=round(fav * 1000 / visits, 1) if fav and visits else None,
            days_since_update=round(days_since(updated), 1) if updated else None,
            max_players=maxp, paid_access=price or 0,
            n_passes=len(pp) if pchecked else None, median_pass_price=med(pp) if pp else None,
            creator=cname, creator_type=ctype, creator_verified=bool(cver), creator_size=csize, creator_games=cgames,
            small_creator=(not cver) and cgames is not None and cgames <= SMALL_GAMES,
            sponsored=uid in sponsored, sorts=",".join(sorted(sorts_of.get(uid, []))),
            growth_days=round(span, 1),
            ccu_growth=(playing - f_play) if span >= 1 and f_play is not None and playing is not None else None,
            visits_per_day_measured=round((visits - f_vis) / span) if span >= 1 and f_vis and visits else None,
            emoji_title=bool(EMOJI.search(name or "")), tag_title=bool(re.search(r"[\[\(].+?[\]\)]", name or "")),
        ))
    return rows, len(snaps), last_ts


def genre_table(rows, key):
    # Cette méthode permet d'agréger les jeux par genre pour comparer demande, concentration et percées récentes.
    out = []
    groups = {}
    for r in rows:
        groups.setdefault(r[key], []).append(r)
    for g, rs in groups.items():
        total = sum(r["playing"] for r in rs)
        if total == 0:
            continue
        young = [r for r in rs if r["age_days"] is not None and r["age_days"] <= YOUNG_DAYS and r["playing"] >= BREAKOUT_CCU]
        out.append(dict(
            genre=g, games=len(rs), ccu=total, median_ccu=med([r["playing"] for r in rs]),
            top_share=round(max(r["playing"] for r in rs) / total, 2),
            young_breakouts=len(young), small_breakouts=sum(r["small_creator"] for r in young),
            like=med([r["like_ratio"] for r in rs]),
        ))
    return sorted(out, key=lambda x: -x["ccu"])


def bar(v, vmax, color="var(--accent)"):
    # Cette méthode permet de dessiner une barre horizontale proportionnelle en HTML pur.
    w = 0 if not vmax else max(1, round(100 * v / vmax))
    return f'<div class="bar"><span style="width:{w}%;background:{color}"></span></div>'


RATIOS = {"like_ratio", "like", "top_share", "paid", "nopass"}


def fmt(v, key=None):
    # Cette méthode permet d'afficher un nombre lisiblement (séparateur de milliers, pourcentage si la colonne est un ratio).
    if v is None:
        return "–"
    if key in RATIOS:
        return f"{v:.0%}"
    if isinstance(v, float) and v < 10:
        return f"{v:.1f}"
    if isinstance(v, (int, float)):
        return f"{v:,.0f}".replace(",", " ")
    return html.escape(str(v))


def table(rows, cols, bar_col=None):
    # Cette méthode permet de générer un tableau HTML à partir de dictionnaires, avec une barre optionnelle.
    vmax = max((r[bar_col] or 0 for r in rows), default=0) if bar_col else 0
    head = "".join(f"<th>{html.escape(label)}</th>" for _, label in cols)
    body = ""
    for r in rows:
        cells = ""
        for k, _ in cols:
            v = r[k]
            if k == "name":
                cells += f'<td class="name"><a href="{r["url"]}">{html.escape(v or "")}</a></td>'
            elif k == bar_col:
                cells += f'<td class="num">{fmt(v, k)}{bar(v or 0, vmax)}</td>'
            elif isinstance(v, bool):
                cells += f"<td>{'oui' if v else ''}</td>"
            else:
                cells += f'<td class="{"num" if isinstance(v, (int, float)) else ""}">{fmt(v, k)}</td>'
        body += f"<tr>{cells}</tr>"
    return f'<div class="scroll"><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>'


def monetization(rows):
    # Cette méthode permet de comparer la monétisation des jeux Top Earning à celle de l'ensemble des jeux relevés.
    def stats(rs):
        rs = [r for r in rs if r["n_passes"] is not None]
        return dict(games=len(rs), passes=med([r["n_passes"] for r in rs]),
                    price=med([r["median_pass_price"] for r in rs]),
                    paid=round(sum(1 for r in rs if r["paid_access"]) / len(rs), 2) if rs else None,
                    nopass=round(sum(1 for r in rs if r["n_passes"] == 0) / len(rs), 2) if rs else None)
    top = [r for r in rows if "top-earning" in r["sorts"].split(",")]
    young = [r for r in rows if r["age_days"] and r["age_days"] <= YOUNG_DAYS and r["playing"] >= BREAKOUT_CCU]
    return [dict(group="Top Earning", **stats(top)), dict(group="Percées récentes", **stats(young)),
            dict(group="Tous les jeux relevés", **stats(rows))]


CSS = """
:root{--bg:#fbfaf7;--fg:#1d1d1b;--muted:#6b6a65;--line:#e4e2dc;--accent:#2f6fdb;--accent2:#d9822b;--card:#fff}
@media (prefers-color-scheme:dark){:root{--bg:#161615;--fg:#ecebe6;--muted:#a3a29c;--line:#33322f;--accent:#6ea0ff;--accent2:#f0a35a;--card:#1f1f1d}}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:1150px;margin:0 auto;padding:24px 16px 64px}
h1{font-size:26px;margin:0 0 4px}h2{font-size:19px;margin:36px 0 6px}p.note{color:var(--muted);margin:0 0 12px;max-width:80ch}
.kpis{display:flex;flex-wrap:wrap;gap:12px;margin:18px 0}.kpi{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 14px}
.kpi b{display:block;font-size:22px}.kpi span{color:var(--muted);font-size:13px}
.scroll{overflow-x:auto;border:1px solid var(--line);border-radius:10px;background:var(--card)}
table{border-collapse:collapse;width:100%;font-size:13.5px}th,td{padding:6px 10px;border-bottom:1px solid var(--line);text-align:left;white-space:nowrap}
th{color:var(--muted);font-weight:600;position:sticky;top:0;background:var(--card)}td.num{text-align:right;font-variant-numeric:tabular-nums}
td.name{max-width:320px;overflow:hidden;text-overflow:ellipsis}a{color:var(--accent);text-decoration:none}
.bar{height:5px;background:var(--line);border-radius:3px;margin-top:3px;min-width:80px}.bar span{display:block;height:100%;border-radius:3px}
"""


FAMILIES = {
    "Physique / ragdoll": r"ragdoll|physic|crash|fling|destruct|bonebox|dummy|sandbox|playground",
    "Verbe + objet (Throw a …)": r"^(\[.*?\]\s*)?(throw|cut|pull|net|break|clean|sweep|shred|harpoon|cast|charge|flat|sell|run|raise|build)\b",
    "Steal a …": r"steal a",
    "+1 … / Evolution": r"\+1|evolution",
    "Don't / Do Not …": r"\bdon.?t\b|do not",
    "Can You …?": r"can you",
    "Duo / 2 joueurs": r"duo|2 player|1-2",
    "[Anomaly]": r"anomaly",
    "Ranked / PvP": r"ranked|pvp",
}


def families(organic, young):
    # Cette méthode permet de mesurer, pour chaque famille de concept repérée dans les titres,
    # combien de jeux en relèvent et quelle part a percé récemment.
    out = []
    for name, pat in FAMILIES.items():
        p = re.compile(pat, re.I)
        y = [r for r in young if p.search(r["name"] or "")]
        a = [r for r in organic if p.search(r["name"] or "")]
        out.append(dict(family=name, breakouts=len(y), games=len(a), rate=len(y) / len(a) if a else 0,
                        ccu=sum(r["playing"] for r in y), small=sum(r["small_creator"] for r in y)))
    return out


def md_name(r):
    # Cette méthode permet d'écrire le nom d'un jeu comme lien Markdown sûr dans un tableau Obsidian.
    name = (r["name"] or "").replace("|", "∣").replace("[", "(").replace("]", ")").strip()
    return f"[{name}]({r['url']})"


def md_table(header, lines):
    # Cette méthode permet de produire un tableau Markdown à partir d'un en-tête et de lignes déjà formatées.
    out = ["| " + " | ".join(header) + " |", "|" + "|".join("---" for _ in header) + "|"]
    out += ["| " + " | ".join(str(c) for c in line) + " |" for line in lines]
    return "\n".join(out)


def write_note(vault, day, rows, organic, young, small, g2, money, n_snaps, report_path):
    # Cette méthode permet d'écrire (ou réécrire) la note Obsidian du relevé du jour dans « 02 - Relevés »,
    # avec indicateurs, sous-genres, familles de concepts, percées et monétisation.
    folder = vault / "Jeu Roblox" / "02 - Relevés"
    folder.mkdir(parents=True, exist_ok=True)
    base = len(young) / len(organic) if organic else 0
    subs = sorted([g for g in g2 if g["games"] >= 10 and g["genre"] != "?"], key=lambda g: -g["young_breakouts"] / g["games"])
    fam = families(organic, young)
    growth = ""
    if n_snaps > 1:
        gr = sorted([r for r in organic if r["ccu_growth"] is not None], key=lambda r: -r["ccu_growth"])[:20]
        growth = "\n## Plus fortes progressions depuis le premier relevé\n\n" + md_table(
            ["Jeu", "Δ CCU", "CCU", "Sur (j)", "Visites/jour mesurées", "Genre", "Âge (j)"],
            [[md_name(r), fmt(r["ccu_growth"]), fmt(r["playing"]), fmt(r["growth_days"]), fmt(r["visits_per_day_measured"]),
              r["genre"], fmt(r["age_days"])] for r in gr]) + "\n"
    text = f"""---
tags: [relevé, roblox]
date: {day}
jeux: {len(rows)}
percées: {len(young)}
percées_petits_créateurs: {len(small)}
relevés_cumulés: {n_snaps}
---

# Relevé du {day}

> Note générée par `analyze.py`. Ne pas modifier à la main : elle est réécrite à chaque analyse du même jour.
> Rapport complet (tous les tableaux) : [report-{day}.html](<file:///{report_path.as_posix()}>). Définitions : [[Définitions et indicateurs]].

## Indicateurs
- **{len(rows)}** jeux relevés dans les classements Discover, **{sum(r["sponsored"] for r in rows)}** sponsorisés écartés.
- **{len(young)}** percées récentes (moins de {YOUNG_DAYS} jours, {BREAKOUT_CCU}+ joueurs simultanés), soit **{base:.0%}** des jeux.
- dont **{len(small)}** par de petits créateurs.
- Relevés cumulés : {n_snaps}{" (pas encore de courbe de croissance)" if n_snaps < 2 else ""}.

## Sous-genres classés par taux de percée
Moyenne tous genres : {base:.0%}. Sous-genres d'au moins 10 jeux.

{md_table(["Sous-genre", "Taux de percée", "Percées / jeux", "dont petits", "CCU total", "Part du n°1"],
          [[g["genre"], f"{g['young_breakouts'] / g['games']:.0%}", f"{g['young_breakouts']}/{g['games']}", g["small_breakouts"],
            fmt(g["ccu"]), fmt(g["top_share"], "top_share")] for g in subs])}

## Familles de concepts (repérées dans les titres)
{md_table(["Famille", "Taux de percée", "Percées / jeux", "CCU des percées", "dont petits"],
          [[f["family"], f"{f['rate']:.0%}", f"{f['breakouts']}/{f['games']}", fmt(f["ccu"]), f["small"]] for f in fam])}

## 30 premières percées récentes
{md_table(["Jeu", "CCU", "Âge (j)", "Sous-genre", "Likes", "Joueurs/serveur", "Gamepasses", "Prix médian (R$)", "Petit créateur"],
          [[md_name(r), fmt(r["playing"]), fmt(r["age_days"]), r["subgenre"], fmt(r["like_ratio"], "like_ratio"), fmt(r["max_players"]),
            fmt(r["n_passes"]), fmt(r["median_pass_price"]), "oui" if r["small_creator"] else ""] for r in young[:30]])}
{growth}
## Monétisation
{md_table(["Groupe", "Jeux", "Gamepasses (médiane)", "Prix médian (R$)", "Accès payant", "Sans gamepass"],
          [[m["group"], m["games"], fmt(m["passes"]), fmt(m["price"]), fmt(m["paid"], "paid"), fmt(m["nopass"], "nopass")] for m in money])}

Lié : [[00 - Accueil Roblox]] · [[La recette]]
"""
    path = folder / f"Relevé {day}.md"
    path.write_text(text, encoding="utf-8")
    return path


def report(rows, n_snaps, last_ts, out_dir, vault=None):
    # Cette méthode permet d'écrire le rapport HTML et l'export CSV, puis de renvoyer un résumé texte.
    organic = [r for r in rows if not r["sponsored"]]
    young = sorted([r for r in organic if r["age_days"] is not None and r["age_days"] <= YOUNG_DAYS
                    and r["playing"] >= BREAKOUT_CCU], key=lambda r: -r["playing"])
    small = [r for r in young if r["small_creator"]]
    g1, g2 = genre_table(organic, "genre"), genre_table(organic, "subgenre")
    money = monetization(organic)
    day = last_ts[:10]
    out_dir.mkdir(parents=True, exist_ok=True)
    with open(out_dir / f"games-{day}.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(sorted(rows, key=lambda r: -r["playing"]))

    gcols = [("genre", "Genre"), ("ccu", "Joueurs simultanés"), ("games", "Jeux"), ("median_ccu", "CCU médian"),
             ("top_share", "Part du n°1"), ("young_breakouts", "Percées <90 j"), ("small_breakouts", "dont petits créateurs"),
             ("like", "Likes médian")]
    ycols = [("name", "Jeu"), ("playing", "CCU"), ("age_days", "Âge (j)"), ("genre", "Genre"), ("subgenre", "Sous-genre"),
             ("like_ratio", "Likes"), ("max_players", "Joueurs/serveur"), ("n_passes", "Gamepasses"),
             ("median_pass_price", "Prix médian (R$)"), ("days_since_update", "MAJ il y a (j)"), ("creator", "Créateur"),
             ("creator_games", "Jeux du créateur"), ("small_creator", "Petit créateur")]
    mcols = [("group", "Groupe"), ("games", "Jeux"), ("passes", "Gamepasses (médiane)"), ("price", "Prix médian d'un pass (R$)"),
             ("paid", "Accès payant"), ("nopass", "Sans gamepass")]
    growth = ""
    if n_snaps > 1:
        gr = sorted([r for r in organic if r["ccu_growth"] is not None], key=lambda r: -r["ccu_growth"])[:40]
        growth = ("<h2>Plus fortes progressions depuis le premier relevé</h2><p class='note'>Écart de joueurs simultanés "
                  "entre le premier et le dernier relevé du jeu. Sensible à l'heure de la journée tant qu'il y a peu de relevés.</p>"
                  + table(gr, [("name", "Jeu"), ("ccu_growth", "Δ CCU"), ("playing", "CCU"), ("growth_days", "Sur (j)"),
                               ("visits_per_day_measured", "Visites/jour mesurées"), ("genre", "Genre"), ("age_days", "Âge (j)")], "ccu_growth"))
    kpis = [(len(rows), "jeux relevés"), (n_snaps, "relevé(s)"), (len(young), f"percées de moins de {YOUNG_DAYS} jours"),
            (len(small), "dont par de petits créateurs"), (sum(r["sponsored"] for r in rows), "jeux sponsorisés écartés")]
    page = f"""<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Marché Roblox {day}</title><style>{CSS}</style></head><body><main>
<h1>Marché Roblox — relevé du {day}</h1>
<p class="note">Source : classements publics de la page Discover (Trending, Up-and-Coming, Top Earning, tendances par genre…),
toutes plateformes et tous pays. Les jeux sponsorisés sont écartés des analyses. « Petit créateur » = compte ou groupe non vérifié
avec {SMALL_GAMES} jeux publics ou moins (approximation : un studio expérimenté peut publier sous un nouveau groupe).</p>
<div class="kpis">{"".join(f'<div class="kpi"><b>{fmt(v)}</b><span>{l}</span></div>' for v, l in kpis)}</div>
<h2>Genres : demande et concentration</h2><p class="note">Une niche intéressante combine de la demande (joueurs simultanés),
une faible part du n°1 (le genre n'appartient pas à un seul jeu) et des percées récentes (des nouveaux arrivent encore à percer).</p>
{table(g1, gcols, "ccu")}
<h2>Sous-genres</h2>{table(g2, gcols, "ccu")}
<h2>Percées récentes (moins de {YOUNG_DAYS} jours, {BREAKOUT_CCU}+ joueurs simultanés)</h2>
<p class="note">Ce sont les jeux à disséquer en priorité, surtout ceux des petits créateurs.</p>{table(young, ycols, "playing")}
{growth}
<h2>Monétisation</h2><p class="note">Gamepasses en vente uniquement (les produits consommables in-game ne sont pas visibles publiquement).</p>
{table(money, mcols)}
</main></body></html>"""
    path = out_dir / f"report-{day}.html"
    path.write_text(page, encoding="utf-8")
    if vault:
        note = write_note(Path(vault), day, rows, organic, young, small, g2, money, n_snaps, path)
        print(f"Note Obsidian : {note}")

    lines = [f"Rapport : {path}", f"{len(rows)} jeux, {n_snaps} relevé(s), {len(young)} percées <{YOUNG_DAYS} j dont {len(small)} petits créateurs", "",
             "GENRES (ccu, jeux, part n°1, percées, dont petits)"]
    lines += [f"  {g['genre']:<28} {g['ccu']:>9} {g['games']:>4} {g['top_share']:>5} {g['young_breakouts']:>3} {g['small_breakouts']:>3}" for g in g1]
    lines += ["", "SOUS-GENRES"] + [f"  {g['genre']:<28} {g['ccu']:>9} {g['games']:>4} {g['top_share']:>5} {g['young_breakouts']:>3} {g['small_breakouts']:>3}" for g in g2]
    lines += ["", "PERCÉES RÉCENTES (ccu, âge, sous-genre, likes, joueurs/serveur, passes, prix médian, créateur, jeux créateur, MAJ il y a)"]
    lines += [f"  {r['playing']:>7} {r['age_days']:>4}j {r['subgenre'][:22]:<22} {fmt(r['like_ratio'], 'like_ratio'):>4} {r['max_players']:>3} "
              f"{fmt(r['n_passes']):>3} {fmt(r['median_pass_price']):>5} {'*' if r['small_creator'] else ' '} {r['creator'][:22]:<22} "
              f"{fmt(r['creator_games']):>3} {fmt(r['days_since_update']):>4} | {r['name'][:60]}" for r in young]
    lines += ["", "MONÉTISATION"] + [f"  {m}" for m in money]
    young_set = {r["universe_id"] for r in young}
    others = [r for r in organic if r["universe_id"] not in young_set]
    for label, rs in (("percées", young), ("autres", others)):
        if rs:
            lines.append(f"  titres {label}: emoji {sum(r['emoji_title'] for r in rs)/len(rs):.0%}, [tag] {sum(r['tag_title'] for r in rs)/len(rs):.0%}, "
                         f"joueurs/serveur médian {med([r['max_players'] for r in rs])}, MAJ médiane il y a {med([r['days_since_update'] for r in rs])} j")
    return "\n".join(lines)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=str(HERE / "data" / "roblox.db"))
    ap.add_argument("--obsidian", help="chemin du coffre Obsidian où écrire la note du relevé")
    args = ap.parse_args()
    db = sqlite3.connect(args.db)
    rows, n, ts = load(db)
    print(report(rows, n, ts, HERE / "reports", args.obsidian))
