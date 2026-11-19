"""Extrait d'une vidéo de session de jeu un jeu d'images horodatées, prêtes à analyser.

Usage : python -I frames.py <video.mp4> [--out dissection/<nom>] [--max 80]
- 0 à 120 s : une image toutes les 3 s (accroche, premières offres).
- ensuite : une image à chaque changement de scène (menu, boutique, nouvelle zone), plus une image toutes les 30 s.
Le total est plafonné à --max images, réparties uniformément si besoin. Images en 768 px de large.
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOOK_END = 120      # durée de la phase d'accroche, en secondes
HOOK_STEP = 3       # pas d'échantillonnage pendant l'accroche
FIXED_STEP = 30     # pas d'échantillonnage de secours après l'accroche
SCENE = 0.30        # seuil de changement de scène ffmpeg (0 à 1)
MIN_GAP = 4         # écart minimal entre deux images de scène, en secondes
SCENE_SLOTS = 20    # nombre minimal d'images réservées aux changements de scène


def ffmpeg_bin(name):
    # Cette méthode permet de trouver ffmpeg/ffprobe dans le PATH, sinon dans le dossier d'installation winget
    # (le PATH n'est mis à jour que pour les nouveaux terminaux).
    found = shutil.which(name)
    if found:
        return found
    winget = Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft" / "WinGet"
    for candidate in [winget / "Links" / f"{name}.exe", *sorted(winget.glob(f"Packages/Gyan.FFmpeg*/*/bin/{name}.exe"))]:
        if candidate.exists():
            return str(candidate)
    sys.exit(f"{name} introuvable : installer ffmpeg (winget install Gyan.FFmpeg).")


def duration(video):
    # Cette méthode permet de lire la durée de la vidéo en secondes avec ffprobe.
    out = subprocess.run([ffmpeg_bin("ffprobe"), "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(video)],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def scene_times(video, start):
    # Cette méthode permet de détecter les instants de changement de scène après l'accroche, en ignorant les rafales trop proches.
    proc = subprocess.run([ffmpeg_bin("ffmpeg"), "-hide_banner", "-ss", str(start), "-i", str(video), "-vf",
                           f"scale=320:-1,select='gt(scene,{SCENE})',showinfo", "-an", "-f", "null", "-"],
                          capture_output=True, text=True)
    times, last = [], -MIN_GAP
    for m in re.finditer(r"pts_time:([0-9.]+)", proc.stderr):
        t = start + float(m.group(1))
        if t - last >= MIN_GAP:
            times.append(t)
            last = t
    return times


def thin(times, keep):
    # Cette méthode permet de réduire une liste d'instants à `keep` éléments répartis uniformément.
    if keep <= 0:
        return []
    if len(times) <= keep:
        return times
    step = len(times) / keep
    return [times[int(i * step)] for i in range(keep)]


def extract(video, out, max_frames):
    # Cette méthode permet de calculer les instants à capturer, d'extraire les images et d'écrire un index JSON horodaté.
    total = duration(video)
    hook = [float(t) for t in range(0, int(min(HOOK_END, total)), HOOK_STEP)]
    # pas régulier élargi si la vidéo est longue, pour garder au moins SCENE_SLOTS images de changement de scène
    fixed_slots = max(max_frames - len(hook) - SCENE_SLOTS, 1)
    step = max(FIXED_STEP, int((total - HOOK_END) / fixed_slots) + 1)
    later_fixed = [float(t) for t in range(HOOK_END, int(total), step)]
    scenes = scene_times(video, HOOK_END) if total > HOOK_END else []
    budget = max(max_frames - len(hook) - len(later_fixed), 0)
    plan = sorted({round(t, 1): kind for kind, ts in (("accroche", hook), ("régulier", later_fixed), ("scène", thin(scenes, budget)))
                   for t in ts}.items())
    out.mkdir(parents=True, exist_ok=True)
    index = []
    for t, kind in plan:
        name = f"t{int(t) // 60:02d}m{t % 60:04.1f}s.jpg"
        subprocess.run([ffmpeg_bin("ffmpeg"), "-hide_banner", "-loglevel", "error", "-y", "-ss", str(t), "-i", str(video),
                        "-frames:v", "1", "-vf", "scale=768:-2", "-q:v", "5", str(out / name)], check=True)
        index.append({"t": t, "type": kind, "file": name})
    (out / "index.json").write_text(json.dumps({"video": str(video), "durée_s": round(total), "images": index},
                                               ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(index)} images ({len(hook)} accroche, {len(later_fixed)} régulières, "
          f"{sum(1 for i in index if i['type'] == 'scène')} scènes sur {len(scenes)} détectées) → {out}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--out")
    ap.add_argument("--max", type=int, default=80)
    a = ap.parse_args()
    v = Path(a.video)
    extract(v, Path(a.out) if a.out else HERE / "dissection" / v.stem, a.max)
