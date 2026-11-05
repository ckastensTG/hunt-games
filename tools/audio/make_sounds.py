#!/usr/bin/env python3
"""Generates the game's sounds (bible §6: Claude generates the audio).

Run from the hunt-games root:
    python3 tools/audio/make_sounds.py [--preview DIR]

Writes Ogg Vorbis files (ffmpeg with libvorbis) to
  titles/bagh_chal/audio/<look>/   piece sounds for each Bagh Chal look
  titles/common/audio/wood/        the greybox's wooden pieces (Adugo, Komikan)
  titles/bagh_chal/audio/stings/   end-of-game stings (win, lose, draw)
and, with --preview, a listening file (preview.mp3) with every sound in turn.

Piece sounds are modal synthesis: a short contact pulse rings the resonant
modes of the piece and of the board, plus contact noise, a little bounce and
the room. Each look sets the materials:
  brass   cast brass figures on an engraved brass board, a courtyard at dusk
  stone   river stones on a chalked stone slab lying on a straw mat
  modern  molded plastic figures on a molded plastic board, indoors
  wood    turned wooden pieces on a wooden slab (greybox placeholder)
Events (several takes each, the game picks one and varies pitch a little):
  place        a goat set down on a point (dropped from a hand's height)
  slide_goat / slide_tiger   a piece pushed along a line (0.25 s, the step
               animation); set_goat / set_tiger when it comes to rest
  land         a tiger landing after its jump
  capture      the jumped goat taken off the board, onto the captured pile

The stings use Nepali folk instruments, the bansuri (bamboo flute) and the
madal (hand drum), and avoid sacred ones (singing bowls, conch, temple bells).
Everything is seeded and ffmpeg runs bit-exact, so a run gives the same
files.
"""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import tempfile

import numpy as np
from scipy import signal

SR = 44100
ROOT = pathlib.Path(".")


# --- Building blocks ----------------------------------------------------------

def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * SR)) / SR


def contact_pulse(duration_ms: float) -> np.ndarray:
    """The force of one contact: a half sine. Harder materials touch for less
    time, which rings higher modes (a brighter click)."""
    n = max(2, int(duration_ms * SR / 1000.0))
    return np.sin(np.pi * np.arange(n) / n)


def mode_bank(modes: list[tuple[float, float, float]], seconds: float, rng: np.random.Generator) -> np.ndarray:
    """Impulse response of resonant modes: (frequency Hz, decay s, amplitude)."""
    t = t_axis(seconds)
    h = np.zeros_like(t)
    for f, decay, amp in modes:
        if f >= SR * 0.45:
            continue
        phase = rng.uniform(0, 2 * np.pi)
        h += amp * np.exp(-t / decay) * np.sin(2 * np.pi * f * t + phase)
    return h


def body(base: list[float], decay0: float, rng: np.random.Generator, jitter=0.03,
         tilt=0.6, amps: list[float] | None = None, scale=1.0) -> list[tuple[float, float, float]]:
    """Modes of one body with a little per-take variety. `tilt`: how much
    faster high modes die out. `scale` shifts every mode (bigger piece: lower)."""
    out = []
    f0 = base[0] * scale
    for i, f in enumerate(base):
        ff = f * scale * (1 + rng.normal(0, jitter))
        d = decay0 * (f0 / ff) ** tilt * (1 + rng.normal(0, 0.12))
        a = (amps[i] if amps else 1.0 / (1 + i * 0.35)) * np.exp(rng.normal(0, 0.25))
        out.append((ff, max(d, 0.002), a))
    return out


def bandpass(x: np.ndarray, lo: float, hi: float, order=2) -> np.ndarray:
    sos = signal.butter(order, [lo, min(hi, SR * 0.45)], btype="bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x: np.ndarray, f: float, order=2) -> np.ndarray:
    sos = signal.butter(order, min(f, SR * 0.45), btype="lowpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x: np.ndarray, f: float, order=2) -> np.ndarray:
    sos = signal.butter(order, f, btype="highpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def place_at(out: np.ndarray, x: np.ndarray, at: float, gain=1.0) -> None:
    i = int(at * SR)
    n = min(len(x), len(out) - i)
    if n > 0:
        out[i:i + n] += gain * x[:n]


def room_ir(rt60: float, seconds: float, rng: np.random.Generator, damping_hz: float,
            early: list[tuple[float, float]], stereo=False) -> np.ndarray:
    """A small synthetic room: a few early reflections and a decaying,
    darkening noise tail."""
    t = t_axis(seconds)
    chans = []
    for _ in range(2 if stereo else 1):
        tail = rng.normal(0, 1, len(t)) * np.exp(-6.9 * t / rt60)
        tail = lowpass(tail, damping_hz)
        tail *= np.clip(t / 0.012, 0, 1)
        for at, g in early:
            i = int((at + rng.uniform(-0.0015, 0.0015)) * SR)
            if i < len(tail):
                tail[i] += g * 8.0 * rng.choice([-1, 1])
        tail /= np.sqrt(np.sum(tail ** 2)) + 1e-9
        chans.append(tail)
    return np.stack(chans) if stereo else chans[0]


def reverb(x: np.ndarray, ir: np.ndarray, wet: float) -> np.ndarray:
    if ir.ndim == 1:
        y = signal.fftconvolve(x, ir)[: len(x)]
        return x + wet * y
    left = x + wet * signal.fftconvolve(x, ir[0])[: len(x)]
    right = x + wet * signal.fftconvolve(x, ir[1])[: len(x)]
    return np.stack([left, right])


def fade_tail(x: np.ndarray, ms=12.0) -> np.ndarray:
    n = int(ms * SR / 1000.0)
    x = x.copy()
    if x.ndim == 1:
        x[-n:] *= np.linspace(1, 0, n)
    else:
        x[:, -n:] *= np.linspace(1, 0, n)
    return x


def trim(x: np.ndarray, floor_db=-62.0) -> np.ndarray:
    """Cuts the silent end (the tail below `floor_db` of the peak)."""
    mono = np.abs(x if x.ndim == 1 else x.max(axis=0))
    peak = mono.max() + 1e-12
    above = np.nonzero(mono > peak * 10 ** (floor_db / 20))[0]
    end = min(len(mono), (above[-1] if len(above) else len(mono)) + int(0.01 * SR))
    return fade_tail(x[..., :end] if x.ndim > 1 else x[:end])


def normalize(x: np.ndarray, peak_db: float) -> np.ndarray:
    return x * (10 ** (peak_db / 20) / (np.abs(x).max() + 1e-12))


# --- Materials ------------------------------------------------------------------

class Material:
    """One look's piece and board materials and its room."""

    def __init__(self, name: str, **kw):
        self.name = name
        self.__dict__.update(kw)


MATERIALS = {
    # Cast brass figures on a brass plate (the plate rests on a stone plinth,
    # so it rings briefly), outdoors: a short, open reverb.
    "brass": Material(
        "brass",
        piece_modes=[2650, 4100, 5480, 6900, 8800, 10900],
        piece_decay=0.045, piece_tilt=0.5,
        board_modes=[610, 1180, 1730, 2390, 3150, 4020],
        board_decay=0.09, board_tilt=0.55, board_gain=0.35,
        thud_hz=150, thud_decay=0.015, thud_gain=0.25,
        contact_ms=0.1, noise_band=(3500, 12000), noise_gain=0.12, noise_ms=4,
        bounce=(0.55, 0.012), grit=0.0,
        slide_band=(1500, 7500), slide_gain=0.55, slide_ring=0.45,
        rt60=0.45, room_damp=5200, room_wet=0.16,
        early=[(0.011, 0.5), (0.019, 0.35), (0.031, 0.2)],
        tiger_scale=0.78,
    ),
    # River stones on a stone slab lying on a straw mat (the mat damps the
    # slab), in a rest house: dry, short and gritty.
    "stone": Material(
        "stone",
        piece_modes=[3900, 6100, 7900, 9800, 12100],
        piece_decay=0.010, piece_tilt=0.4,
        board_modes=[420, 860, 1350, 1900, 2600],
        board_decay=0.018, board_tilt=0.4, board_gain=0.45,
        thud_hz=120, thud_decay=0.016, thud_gain=0.35,
        contact_ms=0.15, noise_band=(2000, 11000), noise_gain=0.35, noise_ms=6,
        bounce=(0.3, 0.008), grit=1.0,
        slide_band=(800, 6000), slide_gain=1.0, slide_ring=0.15,
        rt60=0.32, room_damp=3800, room_wet=0.13,
        early=[(0.006, 0.6), (0.013, 0.4), (0.022, 0.25)],
        tiger_scale=0.72,
    ),
    # Molded plastic figures on a molded plastic board on a wooden table,
    # indoors: a hollow tock.
    "modern": Material(
        "modern",
        piece_modes=[1450, 2380, 3300, 4600, 6100],
        piece_decay=0.028, piece_tilt=0.7,
        board_modes=[330, 690, 1080, 1560, 2150],
        board_decay=0.04, board_tilt=0.6, board_gain=0.6,
        thud_hz=110, thud_decay=0.025, thud_gain=0.4,
        contact_ms=0.35, noise_band=(1500, 7000), noise_gain=0.1, noise_ms=5,
        bounce=(0.35, 0.010), grit=0.0,
        slide_band=(500, 4000), slide_gain=0.6, slide_ring=0.3,
        rt60=0.38, room_damp=4200, room_wet=0.12,
        early=[(0.005, 0.5), (0.009, 0.4), (0.017, 0.3)],
        tiger_scale=0.82,
    ),
    # Turned wooden pieces on a wooden slab (the greybox).
    "wood": Material(
        "wood",
        piece_modes=[1900, 3100, 4400, 5900],
        piece_decay=0.016, piece_tilt=0.7,
        board_modes=[260, 540, 880, 1300, 1800],
        board_decay=0.035, board_tilt=0.6, board_gain=0.6,
        thud_hz=95, thud_decay=0.025, thud_gain=0.45,
        contact_ms=0.3, noise_band=(1500, 8000), noise_gain=0.15, noise_ms=5,
        bounce=(0.3, 0.009), grit=0.2,
        slide_band=(400, 4000), slide_gain=0.7, slide_ring=0.22,
        rt60=0.35, room_damp=4000, room_wet=0.12,
        early=[(0.006, 0.5), (0.012, 0.4), (0.02, 0.25)],
        tiger_scale=0.8,
    ),
}


def strike(m: Material, rng: np.random.Generator, force=1.0, scale=1.0, board_gain=1.0,
           piece_only=False, length=0.5) -> np.ndarray:
    """One contact: the piece's and the board's modes, a low thud, and
    contact noise."""
    pulse = contact_pulse(m.contact_ms * (1.0 + 0.4 * (1 - force)) * rng.uniform(0.85, 1.15))
    piece = mode_bank(body(m.piece_modes, m.piece_decay, rng, tilt=m.piece_tilt, scale=scale), length, rng)
    out = signal.fftconvolve(pulse, piece)
    if not piece_only:
        board = mode_bank(body(m.board_modes, m.board_decay, rng, tilt=m.board_tilt), length, rng)
        thud = mode_bank([(m.thud_hz * rng.uniform(0.9, 1.1), m.thud_decay, 1.0)], length, rng)
        out = out + signal.fftconvolve(pulse, m.board_gain * board_gain * board + m.thud_gain * thud)[: len(out)]
    noise_n = int(m.noise_ms * SR / 1000)
    noise = bandpass(rng.normal(0, 1, noise_n), *m.noise_band) * np.exp(-np.arange(noise_n) / (noise_n / 3))
    out[:noise_n] += m.noise_gain * noise * np.abs(out).max() / (np.abs(noise).max() + 1e-9)
    if m.grit > 0:
        # A stone never sits flat at once: a few tiny ticks as it settles.
        for _ in range(rng.integers(1, 4)):
            tick = signal.fftconvolve(contact_pulse(0.15), mode_bank(
                body(m.piece_modes, m.piece_decay * 0.6, rng, scale=scale), 0.05, rng))
            place_at(out, tick, rng.uniform(0.003, 0.02), m.grit * rng.uniform(0.04, 0.12) * np.abs(out).max() / (np.abs(tick).max() + 1e-9))
    return force * out / (np.abs(out).max() + 1e-12)


def drop(m: Material, rng: np.random.Generator, force=1.0, scale=1.0, bounces=2) -> np.ndarray:
    """A piece set down: the main contact and a small bounce or two."""
    out = np.zeros(int(0.6 * SR))
    place_at(out, strike(m, rng, force, scale), 0.0)
    gain, gap = m.bounce
    at = 0.0
    for b in range(bounces):
        at += gap * rng.uniform(0.8, 1.25) * (0.75 ** b)
        g = force * gain * (0.45 ** b) * rng.uniform(0.7, 1.1)
        place_at(out, strike(m, rng, g, scale, board_gain=0.6), at)
    return out


def slide(m: Material, rng: np.random.Generator, scale=1.0, seconds=0.25) -> np.ndarray:
    """A piece pushed along the board: friction noise shaped by the speed
    (the animation's ease in and out), coloured by the piece's modes."""
    t = t_axis(seconds + 0.05)
    speed = np.where(t < seconds, np.sin(np.pi * np.clip(t / seconds, 0, 1)), 0.0)
    noise = rng.normal(0, 1, len(t))
    if m.grit > 0:
        # Stone on stone: grains catching and letting go.
        grains = (rng.random(len(t)) < 0.004 * speed) * rng.normal(0, 6, len(t))
        noise = noise * 0.5 + grains * m.grit
    # Scraping, not hissing: the friction comes and goes with the surface.
    grain = lowpass(np.abs(rng.normal(0, 1, len(t))), 120)
    grain /= grain.max() + 1e-9
    rough = bandpass(noise, *m.slide_band) * speed ** 0.8 * (0.35 + grain)
    ring = mode_bank(body(m.piece_modes, m.piece_decay * 0.5, rng, scale=scale), 0.08, rng)
    rung = signal.fftconvolve(rough, ring)[: len(t)]
    out = rough + m.slide_ring * rung / (np.abs(rung).max() + 1e-9) * np.abs(rough).max()
    return lowpass(out, m.slide_band[1] * 0.9) * m.slide_gain


def capture(m: Material, rng: np.random.Generator) -> np.ndarray:
    """The jumped goat taken off the board and dropped on the captured pile:
    a firm knock, then the piece rattling against the others."""
    out = np.zeros(int(0.8 * SR))
    place_at(out, strike(m, rng, 1.0, 0.95, board_gain=1.2), 0.0)
    at, gain = 0.07, 0.75
    for k in range(4):
        hit = strike(m, rng, gain, rng.uniform(0.95, 1.12), board_gain=0.25 if k else 0.4, piece_only=k > 1)
        place_at(out, hit, at)
        at += rng.uniform(0.035, 0.055) * (0.8 ** k)
        gain *= rng.uniform(0.5, 0.65)
    return out


def finish(x: np.ndarray, m: Material, rng: np.random.Generator, peak_db: float) -> np.ndarray:
    ir = room_ir(m.rt60, m.rt60 * 1.4, rng, m.room_damp, m.early)
    y = reverb(np.concatenate([x, np.zeros(int(m.rt60 * SR))]), ir, m.room_wet)
    y = highpass(y, 45)
    return normalize(trim(y), peak_db)


def piece_sounds(m: Material, seed: int) -> dict[str, np.ndarray]:
    rng = np.random.default_rng(seed)
    out: dict[str, np.ndarray] = {}
    for i in range(4):
        out[f"place_{i + 1}"] = finish(drop(m, rng, 1.0, rng.uniform(0.97, 1.03)), m, rng, -7.0)
        out[f"set_goat_{i + 1}"] = finish(drop(m, rng, 0.8, rng.uniform(0.97, 1.03), bounces=1), m, rng, -12.0)
        out[f"set_tiger_{i + 1}"] = finish(drop(m, rng, 0.85, m.tiger_scale, bounces=1), m, rng, -11.0)
        out[f"land_{i + 1}"] = finish(drop(m, rng, 1.0, m.tiger_scale * rng.uniform(0.97, 1.03)), m, rng, -5.5)
        out[f"capture_{i + 1}"] = finish(capture(m, rng), m, rng, -4.5)
    for i in range(3):
        out[f"slide_goat_{i + 1}"] = finish(slide(m, rng, 1.0), m, rng, -21.0)
        out[f"slide_tiger_{i + 1}"] = finish(slide(m, rng, m.tiger_scale), m, rng, -19.0)
    return out


# --- Stings: bansuri and madal ---------------------------------------------------

def bansuri(notes: list[tuple[float, float, bool]], rng: np.random.Generator, breath=0.14) -> np.ndarray:
    """A bamboo flute line: (frequency, seconds, glide into the next note).
    Soft attack with a breathy chiff, a nearly pure tone, vibrato on long
    notes, and meend (a glide) where a note slides into the next."""
    release = 0.45
    total = sum(d for _, d, _ in notes) + release + 0.05
    t = t_axis(total)
    freq = np.zeros_like(t)
    amp = np.zeros_like(t)
    at = 0.0
    for k, (f, d, glide) in enumerate(notes):
        last = k + 1 == len(notes)
        i0, i1 = int(at * SR), int((at + d + (release if last else 0.0)) * SR)
        seg = np.full(i1 - i0, f)
        if glide and k + 1 < len(notes):
            g = int(min(0.09, d * 0.4) * SR)
            nxt = notes[k + 1][0]
            seg[-g:] = f * (nxt / f) ** (np.linspace(0, 1, g) ** 2)
        local = np.arange(i1 - i0) / SR
        vib = np.where(local > 0.18, 0.0045 * np.sin(2 * np.pi * 5.3 * local) * np.clip((local - 0.18) / 0.2, 0, 1), 0)
        freq[i0:i1] = seg * (1 + vib)
        # Tongued notes start softly; slurred ones carry on.
        attack = 0.05 if k == 0 or not notes[k - 1][2] else 0.015
        env = np.clip(local / attack, 0, 1) * (0.92 + 0.08 * np.clip(local / 0.3, 0, 1))
        if last:
            # The last note dies away over the release, never cut.
            env *= np.clip((d + release - local) / (release + 0.15), 0, 1) ** 1.5
        elif not glide:
            env *= np.clip((d - local) / 0.07, 0, 1)
        amp[i0:i1] = env
        at += d
    phase = 2 * np.pi * np.cumsum(freq) / SR
    tone = np.zeros_like(t)
    for h, a in enumerate([1.0, 0.32, 0.12, 0.06, 0.035, 0.02]):
        tone += a * np.sin((h + 1) * phase + rng.uniform(0, 2 * np.pi))
    air = rng.normal(0, 1, len(t))
    breathy = bandpass(air, 1500, 9000) * 0.5 + lowpass(highpass(air, 300), 2500) * 0.5
    # A chiff at each tongued onset.
    chiff = np.zeros_like(t)
    at = 0.0
    for k, (_, d, _) in enumerate(notes):
        if k == 0 or not notes[k - 1][2]:
            i0 = int(at * SR)
            n = int(0.035 * SR)
            chiff[i0:i0 + n] += np.exp(-np.arange(n) / (n / 4))[: len(chiff) - i0]
        at += d
    out = amp * (tone + breath * breathy) + 0.25 * chiff * bandpass(air, 2000, 7000)
    return lowpass(out, 7500)


def madal(strokes: list[tuple[float, str, float]], seconds: float, rng: np.random.Generator) -> np.ndarray:
    """The madal: a two-headed hand drum. 'dhin' is the bass head (a boom that
    sinks in pitch), 'ta' the treble head (a bright ringing slap), 'ka' a
    muted bass slap. (time, stroke, loudness)."""
    out = np.zeros(int(seconds * SR))
    ratios = [1.0, 1.59, 2.14, 2.30, 2.65, 2.92, 3.16, 3.50]
    for at, kind, g in strokes:
        tt = t_axis(0.8)
        if kind == "dhin":
            f0 = 108 * rng.uniform(0.98, 1.02)
            bend = 1 + 0.22 * np.exp(-tt / 0.05)
            x = np.zeros_like(tt)
            for i, r in enumerate(ratios[:5]):
                ph = 2 * np.pi * np.cumsum(f0 * r * bend) / SR
                x += (0.9 ** i) / (1 + 2 * i) * np.exp(-tt / (0.38 / (1 + i))) * np.sin(ph)
            slap = bandpass(rng.normal(0, 1, len(tt)), 300, 2500) * np.exp(-tt / 0.008) * 0.25
            x = x + slap
        elif kind == "ta":
            f0 = 410 * rng.uniform(0.98, 1.02)
            x = np.zeros_like(tt)
            for i, r in enumerate(ratios):
                x += (1.0 / (1 + 0.6 * i)) * np.exp(-tt / (0.11 / (1 + 0.35 * i))) * np.sin(2 * np.pi * f0 * r * tt + rng.uniform(0, 6.3))
            slap = bandpass(rng.normal(0, 1, len(tt)), 2000, 9000) * np.exp(-tt / 0.006) * 0.6
            x = x + slap
        else:  # "ka"
            x = bandpass(rng.normal(0, 1, len(tt)), 400, 3000) * np.exp(-tt / 0.012)
            x += 0.5 * np.exp(-tt / 0.03) * np.sin(2 * np.pi * 180 * tt)
        place_at(out, g * x / (np.abs(x).max() + 1e-9), at)
    return out


NOTE = {"D4": 293.66, "E4": 329.63, "F4": 349.23, "F#4": 369.99, "G4": 392.00, "A4": 440.0,
        "B4": 493.88, "C5": 523.25, "D5": 587.33, "E5": 659.25, "F#5": 739.99, "A5": 880.0}


def sting(kind: str, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = NOTE
    if kind == "win":
        # Up the major pentatonic and home, over a little madal flourish.
        line = [(n["A4"], 0.16, False), (n["B4"], 0.16, False), (n["D5"], 0.16, False),
                (n["E5"], 0.2, True), (n["F#5"], 0.52, True), (n["E5"], 0.12, True), (n["D5"], 0.95, False)]
        drum = [(0.0, "dhin", 1.0), (0.16, "ta", 0.55), (0.32, "ta", 0.5), (0.48, "dhin", 0.8),
                (0.68, "ta", 0.5), (0.88, "ta", 0.45), (1.2, "dhin", 1.0), (1.32, "ta", 0.6)]
    elif kind == "lose":
        # Down to the low tonic, slowly, with one soft drum stroke.
        line = [(n["D5"], 0.28, True), (n["C5"], 0.26, False), (n["A4"], 0.32, True),
                (n["G4"], 0.26, False), (n["F4"], 0.3, True), (n["E4"], 0.16, True), (n["D4"], 1.0, False)]
        drum = [(0.0, "ka", 0.35), (1.58, "dhin", 0.75)]
    else:  # draw
        # Up a fifth and back, ending open.
        line = [(n["D5"], 0.3, False), (n["A4"], 0.3, True), (n["B4"], 0.18, True), (n["A4"], 0.9, False)]
        drum = [(0.0, "ta", 0.5), (0.3, "ta", 0.4), (0.6, "dhin", 0.6)]
    flute = bansuri(line, rng)
    drums = madal(drum, len(flute) / SR, rng)
    mix = 0.75 * flute / (np.abs(flute).max() + 1e-9) + 0.6 * drums / (np.abs(drums).max() + 1e-9)
    mix = np.concatenate([mix, np.zeros(int(1.0 * SR))])
    ir = room_ir(1.1, 1.6, rng, 4500, [(0.017, 0.5), (0.029, 0.4), (0.043, 0.3)], stereo=True)
    st = reverb(mix, ir, 0.28)
    # A little width: the drum a touch left, the flute a touch right.
    st = highpass(st, 50)
    return normalize(trim(st, -60), -9.0)


# --- Output -------------------------------------------------------------------------

def write_ogg(path: pathlib.Path, x: np.ndarray, quality=4) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = x.T if x.ndim == 2 else x[:, None]
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    channels = pcm.shape[1]
    with tempfile.NamedTemporaryFile(suffix=".raw") as raw:
        raw.write(pcm.tobytes())
        raw.flush()
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR),
                        "-ac", str(channels), "-i", raw.name, "-c:a", "libvorbis",
                        "-q:a", str(quality), "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(path)], check=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", help="also write DIR/preview.mp3 with every sound")
    args = ap.parse_args()
    sets = {
        "brass": ROOT / "titles/bagh_chal/audio/brass",
        "stone": ROOT / "titles/bagh_chal/audio/stone",
        "modern": ROOT / "titles/bagh_chal/audio/modern",
        "wood": ROOT / "titles/common/audio/wood",
    }
    made: dict[str, dict[str, np.ndarray]] = {}
    for k, (name, folder) in enumerate(sets.items()):
        made[name] = piece_sounds(MATERIALS[name], 1000 + k)
        for event, x in made[name].items():
            write_ogg(folder / f"{event}.ogg", x)
        print(f"{name}: {len(made[name])} sounds in {folder}")
    stings = {kind: sting(kind, 77 + i) for i, kind in enumerate(["win", "lose", "draw"])}
    for kind, x in stings.items():
        write_ogg(ROOT / f"titles/bagh_chal/audio/stings/{kind}.ogg", x, quality=5)
    print("stings: win, lose, draw")
    if args.preview:
        write_preview(pathlib.Path(args.preview), made, stings)
    return 0


def write_preview(folder: pathlib.Path, made: dict, stings: dict) -> None:
    """Every look in turn: two goats placed, a goat and a tiger stepping,
    a tiger's jump and the capture; then the three stings."""
    gap = np.zeros(int(0.45 * SR))
    parts = []
    for name in ["brass", "stone", "modern", "wood"]:
        s = made[name]
        seq = [s["place_1"], gap, s["place_3"], gap]
        for who in ["goat", "tiger"]:
            step = np.zeros(int(0.45 * SR))
            place_at(step, s[f"slide_{who}_1"], 0.0)
            place_at(step, s[f"set_{who}_2"], 0.25)
            seq += [step, gap]
        jump = np.zeros(int(1.2 * SR))
        place_at(jump, s["land_1"], 0.28)
        place_at(jump, s["capture_1"], 0.43)
        seq += [jump, np.zeros(int(0.9 * SR))]
        parts.append(np.concatenate(seq))
    mono = np.concatenate(parts)
    stereo = np.stack([mono, mono])
    tail = [np.concatenate([stings[k], np.zeros((2, int(0.8 * SR)))], axis=1) for k in ["win", "lose", "draw"]]
    full = np.concatenate([stereo] + tail, axis=1)
    folder.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(full.T, -1, 1) * 32767).astype("<i2")
    with tempfile.NamedTemporaryFile(suffix=".raw") as raw:
        raw.write(pcm.tobytes())
        raw.flush()
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2",
                        "-i", raw.name, "-c:a", "libmp3lame", "-q:a", "2", str(folder / "preview.mp3")], check=True)
    print(f"preview: {folder / 'preview.mp3'}")


if __name__ == "__main__":
    sys.exit(main())
