"""Fabrique une planche de vignettes (4 instants) par vidéo, pour identifier rapidement le jeu filmé.

Usage : python -I contact_sheet.py <sortie_dossier> <video1> <video2> ...
"""
import subprocess, sys
from pathlib import Path

from frames import ffmpeg_bin, duration  # noqa: E402  (même dossier)


def sheet(video, out):
    # Cette méthode permet de produire une image 2x2 de vignettes prises à 10 %, 30 %, 55 % et 80 % de la vidéo.
    d = duration(video)
    inputs, labels = [], []
    for i, frac in enumerate((0.10, 0.30, 0.55, 0.80)):
        inputs += ["-ss", f"{d * frac:.1f}", "-i", str(video)]
    filt = ";".join(f"[{i}:v]scale=480:-2,trim=end_frame=1[v{i}]" for i in range(4))
    filt += ";[v0][v1]hstack[top];[v2][v3]hstack[bot];[top][bot]vstack[out]"
    subprocess.run([ffmpeg_bin("ffmpeg"), "-hide_banner", "-loglevel", "error", "-y", *inputs, "-filter_complex", filt,
                    "-map", "[out]", "-frames:v", "1", "-q:v", "6", str(out)], check=True)


if __name__ == "__main__":
    dst = Path(sys.argv[1])
    dst.mkdir(parents=True, exist_ok=True)
    for i, v in enumerate(sys.argv[2:], 1):
        sheet(Path(v), dst / f"{i:02d}.jpg")
        print(f"{i:02d} {v}")
