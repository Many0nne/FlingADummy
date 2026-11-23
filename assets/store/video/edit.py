# Montage de la video de presentation (#225) : prises enregistrees dans Studio (video_capture du MCP, procedure dans
# assets/store/video/README.md), recadrees en 16:9, montees bout a bout, arret sur image du mannequin qui traverse le
# mur, titre « THROW A DUMMY » au style des vignettes (police LuckiestGuy du jeu, degrade, contour noir), musique du
# jeu posee d'un seul tenant sous les bruitages des prises.
# Usage : python -I assets/store/video/edit.py <dossier des prises> [--flashes] [--sheet]
#   --flashes : affiche seulement l'instant du repere magenta de chaque prise (pour caler les coupes)
#   --sheet   : ecrit aussi une planche de controle (une image par plan) a cote de la video
# Prises attendues dans le dossier : opening, throw1, crash, react, throw2, wall, music, sfx (.mp4, 1600 x 752).
# Sortie : assets/store/video/export/throw-a-dummy.mp4 (1920 x 1080, 30 i/s, H.264 + AAC).
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))  # assets/store : police et rendu du texte de compose.py
import compose  # noqa: E402
from PIL import Image, ImageEnhance, ImageFilter  # noqa: E402

EXPORT = os.path.join(HERE, "export")
OUT = os.path.join(EXPORT, "throw-a-dummy.mp4")
SIZE = (1920, 1080)
FPS = 30
TAKES = ["opening", "throw1", "crash", "react", "throw2", "wall", "music", "sfx"]

# Plans : prise, debut et fin en secondes apres le repere magenta, cadrage horizontal (0 = gauche, 0.5 = centre,
# 1 = droite) du recadrage 16:9 dans l'image de Studio (1600 x 752), volume des bruitages de la prise.
SHOTS = [
    {"take": "opening", "start": 0.45, "end": 10.0, "x": 0.5, "sfx": 1.0},  # marche, coups, chute, traine
    {"take": "throw1", "start": 2.2, "end": 3.9, "x": 0.5, "sfx": 1.0},  # tenu de dos, gros plan du geste
    {"take": "crash", "start": 1.6, "end": 4.0, "x": 0.5, "sfx": 1.0},  # vol, tracteur, crash sous les balancoires
    {"take": "react", "start": 0.3, "end": 2.3, "x": 0.5, "sfx": 1.0},  # il glousse, mannequin suivant en main
    {"take": "throw2", "start": 2.55, "end": 3.1, "x": 0.5, "sfx": 1.0},  # fouette du second lancer
    {"take": "wall", "start": 2.77, "end": 3.51, "x": 0.5, "sfx": 1.0},  # mur perce : derniere image = arret
]
FREEZE = 3.2  # duree de l'arret sur image et du titre (s)
MUSIC_GAIN = 0.55  # musique sous les bruitages
TITLE_HIT = 1.0  # instant du coup de canon dans la prise sfx (s apres le repere)
TITLE_Y = 0.8  # titre en bas de l'image : le mannequin qui traverse le mur reste visible au-dessus
FOCUS_Y = 0.35  # hauteur du mannequin dans l'image gelee (centre du rapprochement)


def run(args, capture=False):
    """Cette methode permet de lancer ffmpeg / ffprobe et d'arreter le montage a la premiere erreur lorsque une etape
    echoue."""
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr[-3000:])
        raise SystemExit("echec : " + " ".join(args[:6]))
    return result.stdout if capture else None


def flash_end(path):
    """Cette methode permet de trouver la fin du repere magenta (premiere image normale apres lui, en s) d'une prise
    lorsque l'on cale les coupes ; None sans repere."""
    out = run(
        [
            "ffprobe", "-v", "error", "-f", "lavfi",
            "-i", "movie=" + path.replace("\\", "/").replace(":", "\\\\:") + ",signalstats",
            "-show_entries", "frame=pts_time:frame_tags=lavfi.signalstats.UAVG,lavfi.signalstats.VAVG",
            "-of", "json",
        ],
        capture=True,
    )
    seen = False
    for frame in json.loads(out)["frames"]:
        tags = frame.get("tags", {})
        magenta = float(tags.get("lavfi.signalstats.UAVG", 0)) > 180 and float(tags.get("lavfi.signalstats.VAVG", 0)) > 190
        if magenta:
            seen = True
        elif seen:
            return float(frame["pts_time"])
    return None


def crop_filter(x):
    """Cette methode permet de construire le filtre qui recadre l'image de Studio en 16:9 (cadrage horizontal `x`),
    la met en 1920 x 1080 et pousse un peu les couleurs lorsque l'on extrait un plan."""
    return (
        "crop=trunc(ih*16/9/2)*2:ih:(iw-trunc(ih*16/9/2)*2)*{x}:0,"
        "scale={w}:{h}:flags=lanczos,eq=saturation=1.12:contrast=1.04,fps={fps},format=yuv420p"
    ).format(x=x, w=SIZE[0], h=SIZE[1], fps=FPS)


def title_frames(still, folder, seconds):
    """Cette methode permet de rendre l'arret sur image (leger zoom, flash blanc) et l'arrivee du titre en rebond
    image par image lorsque la video se termine ; elle renvoie le motif des images ecrites."""
    base = Image.open(still).convert("RGB")
    base = compose.vivid(base, color=1.15, contrast=1.05, bright=1.0)
    title = compose.text_layer("THROW A DUMMY", 175, (compose.YELLOW, compose.ORANGE))
    count = int(seconds * FPS)
    for i in range(count):
        t = i / FPS
        # Lent rapprochement centre sur le mannequin (haut de l'image)
        zoom = 1 + 0.05 * min(t / seconds, 1)
        w, h = int(SIZE[0] * zoom), int(SIZE[1] * zoom)
        x0, y0 = int((w - SIZE[0]) * 0.5), int((h - SIZE[1]) * FOCUS_Y)
        frame = base.resize((w, h), Image.LANCZOS).crop((x0, y0, x0 + SIZE[0], y0 + SIZE[1]))
        # Fond un peu assombri et flou a l'arrivee du titre, comme une vignette
        dim = min(max((t - 0.25) / 0.3, 0), 1)
        if dim > 0:
            soft = ImageEnhance.Brightness(frame.filter(ImageFilter.GaussianBlur(1.5 * dim))).enhance(1 - 0.1 * dim)
            frame = Image.blend(frame, soft, dim)
        frame = frame.convert("RGBA")
        # Flash blanc au gel de l'image
        if t < 0.12:
            white = Image.new("RGBA", SIZE, (255, 255, 255, int(200 * (1 - t / 0.12))))
            frame.alpha_composite(white)
        # Titre : arrive en grand puis rebondit a sa taille (de 0,3 s a 0,7 s)
        k = (t - 0.3) / 0.4
        if k > 0:
            k = min(k, 1)
            scale = 1 + 1.6 * (1 - k) ** 3 - 0.12 * (1 - abs(1 - 2 * k)) if k < 1 else 1
            layer = title.resize((max(1, int(title.width * scale)), max(1, int(title.height * scale))), Image.LANCZOS)
            compose.put(frame, layer, (SIZE[0] // 2, int(SIZE[1] * TITLE_Y)), angle=-4)
        frame.convert("RGB").save(os.path.join(folder, "t%04d.png" % i))
    return os.path.join(folder, "t%04d.png")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("takes")
    parser.add_argument("--flashes", action="store_true")
    parser.add_argument("--sheet", action="store_true")
    args = parser.parse_args()
    paths = {name: os.path.join(args.takes, name + ".mp4") for name in TAKES}
    marks = {name: flash_end(path) for name, path in paths.items()}
    if args.flashes:
        for name in TAKES:
            print("%-8s repere fini a %s s" % (name, marks[name]))
        return
    missing = [name for name in TAKES if marks[name] is None]
    if missing:
        raise SystemExit("repere magenta introuvable : " + ", ".join(missing))

    work = tempfile.mkdtemp(prefix="fad-video-")
    try:
        parts = []
        timeline = 0.0
        sfx_inputs = []
        for n, shot in enumerate(SHOTS):
            start = marks[shot["take"]] + shot["start"]
            length = shot["end"] - shot["start"]
            part = os.path.join(work, "p%02d.mp4" % n)
            run([
                "ffmpeg", "-v", "error", "-y", "-ss", "%.3f" % start, "-t", "%.3f" % length, "-i", paths[shot["take"]],
                "-vf", crop_filter(shot["x"]), "-af", "aresample=48000,volume=%.2f" % shot["sfx"],
                "-c:v", "libx264", "-crf", "16", "-preset", "medium", "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2", part.replace(".mp4", ".mov"),
            ])
            parts.append(part.replace(".mp4", ".mov"))
            sfx_inputs.append((timeline, length))
            timeline += length
        # Arret sur image : derniere image du dernier plan
        last = SHOTS[-1]
        still = os.path.join(work, "still.png")
        run([
            "ffmpeg", "-v", "error", "-y", "-ss", "%.3f" % (marks[last["take"]] + last["end"] - 1 / FPS), "-i", paths[last["take"]],
            "-frames:v", "1", "-vf", crop_filter(last["x"]).replace(",format=yuv420p", ""), still,
        ])
        frames = os.path.join(work, "title")
        os.makedirs(frames)
        pattern = title_frames(still, frames, FREEZE)
        title = os.path.join(work, "title.mov")
        run([
            "ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", pattern,
            "-f", "lavfi", "-t", "%.3f" % FREEZE, "-i", "anullsrc=r=48000:cl=stereo",
            "-c:v", "libx264", "-crf", "16", "-pix_fmt", "yuv420p", "-c:a", "pcm_s16le", "-shortest", title,
        ])
        parts.append(title)
        total = timeline + FREEZE
        # Bout a bout (images et bruitages des prises)
        listing = os.path.join(work, "list.txt")
        with open(listing, "w") as f:
            for p in parts:
                f.write("file '%s'\n" % p.replace("\\", "/"))
        joined = os.path.join(work, "joined.mov")
        run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing, "-c", "copy", joined])
        # Mixage : bruitages des prises + musique continue (fondu de sortie) + coup de canon a l'arrivee du titre,
        # volume ramene a -14 LUFS (niveau courant des videos en ligne)
        music_start = marks["music"]
        hit_start = marks["sfx"] + TITLE_HIT - 0.05
        hit_at = int((timeline + 0.3) * 1000)
        os.makedirs(EXPORT, exist_ok=True)
        run([
            "ffmpeg", "-v", "error", "-y", "-i", joined,
            "-ss", "%.3f" % music_start, "-t", "%.3f" % total, "-i", paths["music"],
            "-ss", "%.3f" % hit_start, "-t", "1.8", "-i", paths["sfx"],
            "-filter_complex",
            "[1:a]aresample=48000,volume=%.2f,afade=t=out:st=%.3f:d=1.2[m];"
            "[2:a]aresample=48000,volume=1.3,adelay=%d|%d[h];"
            "[0:a][m][h]amix=inputs=3:normalize=0,loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[a]"
            % (MUSIC_GAIN, total - 1.2, hit_at, hit_at),
            "-map", "0:v", "-map", "[a]", "-c:v", "libx264", "-crf", "18", "-preset", "slow", "-pix_fmt", "yuv420p",
            "-movflags", "+faststart", "-c:a", "aac", "-b:a", "192k", "-t", "%.3f" % total, OUT,
        ])
        if args.sheet:
            sheet = os.path.join(EXPORT, "planche.jpg")
            run(["ffmpeg", "-v", "error", "-y", "-i", OUT, "-vf", "fps=1.5,scale=384:-1,tile=6x5", "-frames:v", "1", sheet])
        print("video : %s (%.1f s)" % (OUT, total))
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
