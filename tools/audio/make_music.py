#!/usr/bin/env python3
"""Turns the music masters into the game's music files.

Run from the hunt-games root:
    python3 tools/audio/make_music.py MASTERS_DIR

MASTERS_DIR holds the masters as made, one FLAC (or WAV) per take, named
bagh_chal_music_<look>_<take>.flac. The first pass is in
Claude outputs/session-2026-11-03/renders/music/pass1/masters/, and its README
records how each take was made: Stable Audio 3 Medium, the prompt, the seed
and the licence (Stability AI Community License).

Writes Ogg Vorbis files (ffmpeg with libvorbis, bit-exact) to
  titles/bagh_chal/audio/music/<look>/track_<n>.ogg
for the three Bagh Chal looks (stone, brass, modern), takes a, b, c as
tracks 1, 2, 3. The game plays a look's tracks in a shuffled order with a
pause between them (MusicPlayer).

Each take is trimmed of trailing silence, given a 20 ms fade-in and a 1.5 s
fade-out, levelled to LUFS (ITU-R BS.1770 integrated loudness) and held
under -1 dBFS by a look-ahead limiter. At -22 LUFS and the default Music
volume (0.5, about -12 dB) the music sits about -34 LUFS, under the piece
sounds (default Sound volume also 0.5), which online players listen for.

Needs numpy, scipy, soundfile, pyloudnorm and ffmpeg.
"""
from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile

import numpy as np
import pyloudnorm
import soundfile
from scipy.ndimage import minimum_filter1d
from scipy.signal import lfilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "titles/bagh_chal/audio/music"
LOOKS = ("stone", "brass", "modern")
TAKES = ("a", "b", "c")
LUFS = -22.0
CEILING_DB = -1.0
QUALITY = 3       # Vorbis q3, about 112 kbit/s stereo
SILENCE_DB = -55.0


def trim_tail(x: np.ndarray, sr: int) -> np.ndarray:
    env = np.sqrt(np.convolve(x.mean(1) ** 2, np.ones(sr // 10) / (sr // 10), "same"))
    loud = np.flatnonzero(env > 10 ** (SILENCE_DB / 20))
    return x[: min(len(x), loud[-1] + sr)] if len(loud) else x


def limit(x: np.ndarray, sr: int, ceiling: float) -> np.ndarray:
    """Look-ahead peak limiter: 5 ms look-ahead, 120 ms release."""
    need = np.minimum(1.0, ceiling / np.maximum(np.abs(x).max(1), 1e-9))
    g = minimum_filter1d(need, 2 * int(0.005 * sr) + 1)
    r = np.exp(-1 / (0.12 * sr))
    g = np.minimum(g, 1 - lfilter([1 - r], [1, -r], 1 - g))
    return x * g[:, None]


def process(x: np.ndarray, sr: int) -> np.ndarray:
    x = trim_tail(x, sr)
    fi, fo = int(0.02 * sr), int(1.5 * sr)
    x = x.copy()
    x[:fi] *= np.linspace(0, 1, fi)[:, None]
    x[-fo:] *= (np.linspace(1, 0, fo) ** 2)[:, None]
    x *= 10 ** ((LUFS - pyloudnorm.Meter(sr).integrated_loudness(x)) / 20)
    return limit(x, sr, 10 ** (CEILING_DB / 20))


def write_ogg(path: pathlib.Path, x: np.ndarray, sr: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with tempfile.NamedTemporaryFile(suffix=".raw") as raw:
        raw.write(pcm.tobytes())
        raw.flush()
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(sr), "-ac", "2",
                        "-i", raw.name, "-c:a", "libvorbis", "-q:a", str(QUALITY), "-map_metadata", "-1",
                        "-fflags", "+bitexact", "-flags:a", "+bitexact", str(path)], check=True)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    masters = pathlib.Path(sys.argv[1])
    for look in LOOKS:
        for n, take in enumerate(TAKES, 1):
            src = next((p for p in (masters / f"bagh_chal_music_{look}_{take}.{ext}" for ext in ("flac", "wav")) if p.exists()), None)
            if src is None:
                print(f"missing master for {look} {take}", file=sys.stderr)
                return 1
            x, sr = soundfile.read(src, always_2d=True)
            y = process(x, sr)
            dst = OUT / look / f"track_{n}.ogg"
            write_ogg(dst, y, sr)
            print(f"{dst.relative_to(ROOT)}: {len(y) / sr:5.1f} s, {dst.stat().st_size / 1e6:4.1f} MB, "
                  f"{pyloudnorm.Meter(sr).integrated_loudness(y):5.1f} LUFS, peak {20 * np.log10(np.abs(y).max()):5.1f} dBFS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
