#!/usr/bin/env python3
"""Generates the Bagh Chal pieces (cast-brass tiger and goat figurines).

Each figure is modeled as a signed distance field: primitives joined with
smooth unions, which gives the soft, slightly blobby forms of lost-wax
casting. The field is polygonized with marching cubes, decimated, and then
every vertex gets attributes sampled back from the field:

  normal  - field gradient (smooth, no faceting)
  COLOR_0 - R: ambient occlusion (patina collects in recesses)
            G: where engraved marks may go (the shader draws the tiger stripes)
            B: edge wear (convex ridges rubbed bright by handling)

Run from the hunt-games root:
    python3 tools/art/make_pieces.py            # writes titles/bagh_chal/art/pieces/*.glb
    python3 tools/art/make_pieces.py --preview  # also writes PNG turnarounds to tools/art/previews/

Units match the board: 1.0 = the spacing between two board points. Figures
face -Z (Godot's forward) and stand on y = 0.
"""
from __future__ import annotations

import argparse
import pathlib

import numpy as np
import fast_simplification
import trimesh
from skimage import measure

OUT_DIR = pathlib.Path("titles/bagh_chal/art/pieces")


# --- SDF primitives (p: (N, 3) float32 array) --------------------------------

def sphere(p, c, r):
    return np.linalg.norm(p - np.asarray(c, np.float32), axis=1) - r


def ellipsoid(p, c, radii):
    q = (p - np.asarray(c, np.float32)) / np.asarray(radii, np.float32)
    k0 = np.linalg.norm(q, axis=1)
    k1 = np.linalg.norm(q / np.asarray(radii, np.float32), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def round_cone(p, a, b, r1, r2):
    """Capsule whose radius goes from r1 at a to r2 at b."""
    a = np.asarray(a, np.float32)
    b = np.asarray(b, np.float32)
    ba = b - a
    pa = p - a
    h = np.clip(pa @ ba / (ba @ ba), 0.0, 1.0)
    r = r1 + (r2 - r1) * h
    return np.linalg.norm(pa - np.outer(h, ba), axis=1) - r


def chain(p, pts, r0, r1):
    """Round cones along a polyline, radius tapering from r0 to r1."""
    n = len(pts) - 1
    d = None
    for i in range(n):
        ra = r0 + (r1 - r0) * i / n
        rb = r0 + (r1 - r0) * (i + 1) / n
        di = round_cone(p, pts[i], pts[i + 1], ra, rb)
        d = di if d is None else smin(d, di, 0.006)
    return d


def rounded_cylinder(p, c, r, h, rounding):
    q = p - np.asarray(c, np.float32)
    dx = np.sqrt(q[:, 0] ** 2 + q[:, 2] ** 2) - (r - rounding)
    dy = np.abs(q[:, 1]) - (h / 2 - rounding)
    outside = np.sqrt(np.maximum(dx, 0) ** 2 + np.maximum(dy, 0) ** 2)
    inside = np.minimum(np.maximum(dx, dy), 0)
    return outside + inside - rounding


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def mirror_x(p):
    q = p.copy()
    q[:, 0] = np.abs(q[:, 0])
    return q


# --- Shared base -------------------------------------------------------------

def base(p, radius, height):
    """Round cast base with a beaded rim, standing on y = 0."""
    d = rounded_cylinder(p, (0, height / 2, 0), radius, height, 0.008)
    # Beads around the top edge (angular repetition).
    n = int(round(2 * np.pi * radius / 0.034))
    ang = np.arctan2(p[:, 2], p[:, 0])
    step = 2 * np.pi / n
    a = np.round(ang / step) * step
    rb = radius - 0.013
    bead_c = np.stack([np.cos(a) * rb, np.full_like(a, height), np.sin(a) * rb], axis=1)
    beads = np.linalg.norm(p - bead_c, axis=1) - 0.0095
    return np.minimum(d, beads)


# --- Figures -----------------------------------------------------------------

def tiger(p):
    """A stalking tiger: long low body, shoulders up, broad head level and
    forward, one forepaw stepping, a long tail low then flicked up."""
    m = mirror_x(p)
    body = ellipsoid(p, (0, 0.182, 0.02), (0.08, 0.066, 0.19))
    body = smin(body, sphere(p, (0, 0.198, -0.118), 0.078), 0.05)        # shoulders
    body = smin(body, sphere(p, (0, 0.19, 0.128), 0.072), 0.05)          # haunches
    body = smin(body, ellipsoid(p, (0, 0.152, 0.0), (0.056, 0.04, 0.13)), 0.04)   # belly
    body = smin(body, ellipsoid(m, (0.05, 0.228, -0.118), (0.028, 0.03, 0.05)), 0.03)  # shoulder blades
    # Head: broad and flat-topped, with the cheek ruff that makes a tiger.
    hx = 0.014
    head = ellipsoid(p, (hx, 0.218, -0.262), (0.084, 0.064, 0.07))
    head = smin(head, ellipsoid(p, (hx, 0.2, -0.256), (0.108, 0.05, 0.046)), 0.022)    # ruff
    head = smin(head, ellipsoid(p, (hx * 1.4, 0.196, -0.322), (0.046, 0.036, 0.04)), 0.02)  # muzzle
    head = smin(head, sphere(p, (hx * 1.5, 0.208, -0.358), 0.015), 0.012)  # nose
    ears = np.minimum(
        ellipsoid(p, (hx + 0.058, 0.276, -0.248), (0.024, 0.032, 0.012)),
        ellipsoid(p, (hx - 0.058, 0.276, -0.248), (0.024, 0.032, 0.012)))
    head = smin(head, ears, 0.01)
    d = smin(body, head, 0.045)
    # Forelegs: the left paw steps forward, the right one carries weight.
    fl = round_cone(p, (0.054, 0.17, -0.13), (0.06, 0.045, -0.225), 0.036, 0.024)
    fl = smin(fl, ellipsoid(p, (0.06, 0.042, -0.238), (0.03, 0.019, 0.038)), 0.015)
    fr = round_cone(p, (-0.054, 0.17, -0.12), (-0.056, 0.045, -0.14), 0.036, 0.024)
    fr = smin(fr, ellipsoid(p, (-0.056, 0.042, -0.155), (0.03, 0.019, 0.038)), 0.015)
    # Hind legs: thigh, hock, paw.
    rear = round_cone(m, (0.058, 0.18, 0.13), (0.06, 0.095, 0.18), 0.05, 0.029)
    rear = smin(rear, round_cone(m, (0.06, 0.095, 0.18), (0.058, 0.045, 0.135), 0.027, 0.023), 0.02)
    rear = smin(rear, ellipsoid(m, (0.058, 0.042, 0.122), (0.029, 0.019, 0.036)), 0.015)
    d = smin(d, smin(np.minimum(fl, fr), rear, 0.01), 0.03)
    # Tail: low off the rump, a long sweep, then the flick.
    tail = chain(p, [(0, 0.2, 0.19), (0.0, 0.165, 0.27), (0.02, 0.15, 0.34),
                     (0.06, 0.175, 0.385), (0.09, 0.23, 0.385), (0.095, 0.275, 0.35)], 0.026, 0.015)
    d = smin(d, tail, 0.02)
    return np.minimum(d, base(p, 0.205, 0.036))


def goat(p):
    """A standing goat, head up, horns sweeping back."""
    m = mirror_x(p)
    body = ellipsoid(p, (0, 0.175, 0.01), (0.06, 0.058, 0.115))
    body = smin(body, sphere(p, (0, 0.183, -0.065), 0.056), 0.04)        # chest
    body = smin(body, sphere(p, (0, 0.185, 0.075), 0.053), 0.04)         # rump
    neck = round_cone(p, (0, 0.2, -0.075), (0, 0.268, -0.118), 0.04, 0.029)
    head = ellipsoid(p, (0, 0.285, -0.137), (0.033, 0.036, 0.048))
    head = smin(head, ellipsoid(p, (0, 0.265, -0.18), (0.023, 0.025, 0.034)), 0.015)  # muzzle
    ears = ellipsoid(m, (0.044, 0.296, -0.118), (0.03, 0.01, 0.016))
    horns = chain(m, [(0.017, 0.312, -0.13), (0.028, 0.345, -0.108), (0.038, 0.358, -0.072),
                      (0.044, 0.345, -0.04), (0.046, 0.322, -0.028)], 0.0135, 0.006)
    beard = round_cone(p, (0, 0.252, -0.172), (0, 0.222, -0.168), 0.011, 0.004)
    head = smin(smin(smin(head, ears, 0.008), horns, 0.006), beard, 0.008)
    d = smin(smin(body, neck, 0.03), head, 0.02)
    front = round_cone(m, (0.034, 0.16, -0.07), (0.034, 0.034, -0.078), 0.02, 0.0135)
    rear = round_cone(m, (0.036, 0.17, 0.075), (0.034, 0.1, 0.098), 0.026, 0.016)
    rear = smin(rear, round_cone(m, (0.034, 0.1, 0.098), (0.034, 0.034, 0.08), 0.015, 0.0135), 0.01)
    d = smin(d, np.minimum(front, rear), 0.02)
    tail = round_cone(p, (0, 0.205, 0.118), (0, 0.235, 0.14), 0.013, 0.007)
    d = smin(d, tail, 0.01)
    return np.minimum(d, base(p, 0.158, 0.03))


# --- Surface attributes ------------------------------------------------------

def gradient(f, v, eps=1e-4):
    e = np.eye(3, dtype=np.float32) * eps
    g = np.stack([f(v + e[i]) - f(v - e[i]) for i in range(3)], axis=1)
    return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)


def occlusion(f, v, n):
    """Classic SDF ambient occlusion: how much the field closes in along n."""
    occ = np.zeros(len(v), np.float32)
    w = 1.0
    for i in range(1, 6):
        h = 0.006 * i
        occ += w * (h - f(v + n * h))
        w *= 0.6
    return np.clip(1.0 - 9.0 * occ, 0.0, 1.0)


def convexity(f, v, n, h=0.004):
    """Positive on ridges, negative in creases (from the field's Laplacian)."""
    e = np.eye(3, dtype=np.float32) * h
    lap = sum(f(v + e[i]) + f(v - e[i]) for i in range(3)) - 6.0 * f(v)
    return lap / (h * h)


def hash_noise(p, scale):
    """Cheap smooth value noise for organic jitter."""
    q = p * scale
    return (np.sin(q[:, 0] * 1.7 + np.sin(q[:, 2] * 2.3)) * np.sin(q[:, 1] * 2.1 + q[:, 2] * 0.7)
            + 0.5 * np.sin(q[:, 0] * 3.1 - q[:, 1] * 2.7 + q[:, 2] * 1.9)) / 1.5


def tiger_marks(v, n):
    """Where the engraved stripes may go: fur on the back, flanks, head and
    tail, fading out toward the belly and off the base. The stripe pattern
    itself is drawn per pixel in piece_brass.gdshader from object position,
    so it stays crisp at any mesh density."""
    y = v[:, 1]
    up = np.clip((n[:, 1] + 0.55) / 0.5, 0.0, 1.0)
    above_base = np.clip((y - 0.075) / 0.04, 0.0, 1.0)
    return (up * above_base).astype(np.float32)


# --- Meshing -----------------------------------------------------------------

def build(name, f, bounds, voxel, target_tris, marks=None):
    lo = np.array(bounds[0], np.float32)
    hi = np.array(bounds[1], np.float32)
    shape = np.ceil((hi - lo) / voxel).astype(int) + 1
    axes = [lo[i] + np.arange(shape[i], dtype=np.float32) * voxel for i in range(3)]
    vol = np.empty(shape, np.float32)
    for i, x in enumerate(axes[0]):  # one slab at a time keeps memory small
        yy, zz = np.meshgrid(axes[1], axes[2], indexing="ij")
        pts = np.stack([np.full(yy.size, x, np.float32), yy.ravel(), zz.ravel()], axis=1)
        vol[i] = f(pts).reshape(yy.shape)
    verts, faces, _, _ = measure.marching_cubes(vol, 0.0, spacing=(voxel,) * 3)
    verts = verts.astype(np.float32) + lo
    verts, faces = fast_simplification.simplify(
        verts, faces, 1.0 - min(1.0, target_tris / len(faces)), agg=7)
    verts = verts.astype(np.float32)
    # Snap the bottom flat after decimation.
    verts[:, 1] = np.where(verts[:, 1] < 0.002, 0.0, verts[:, 1])
    n = gradient(f, verts)
    ao = occlusion(f, verts, n)
    cv = convexity(f, verts, n)
    wear = np.clip(cv / 60.0, 0.0, 1.0)
    mk = marks(verts, n) if marks else np.zeros(len(verts), np.float32)
    color = np.stack([ao, mk, wear, np.ones_like(ao)], axis=1)
    mesh = trimesh.Trimesh(verts, faces, vertex_normals=n, process=False)
    mesh.visual = trimesh.visual.ColorVisuals(mesh, vertex_colors=(color * 255).astype(np.uint8))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"{name}.glb"
    mesh.export(path)
    print(f"{path}: {len(verts)} verts, {len(faces)} tris, "
          f"bounds {np.round(verts.min(0), 3)} .. {np.round(verts.max(0), 3)}")
    return mesh


def stripe_pattern(v):
    """Same pattern as piece_brass.gdshader (stripes()), for the previews."""
    x, y, z = v[:, 0], v[:, 1], v[:, 2]
    w = np.sin(x * 23.0 + z * 11.0) * 0.5 + np.sin(z * 37.0 - y * 19.0) * 0.25
    flank = np.abs(np.sin(z * 31.0 + np.abs(x) * 10.0 + w * 1.6))
    width = 0.80 + 0.12 * np.clip((y - 0.11) / 0.12, 0, 1)
    s = (flank > width) & (z > -0.21) & (z < 0.19)
    head = (z < -0.21) & (np.abs(np.sin(x * 64.0 + w * 2.0)) > 0.86) & (z > -0.31) & (y > 0.21)
    td = np.linalg.norm(v - np.array([0.0, 0.19, 0.19], np.float32), axis=1)
    tail = (z > 0.21) & (np.abs(np.sin(td * 52.0)) > 0.72)
    return (s | head | tail).astype(np.float32)


def preview(mesh, path):
    """Quick software turnaround (four views, AO-shaded) for checking forms."""
    from PIL import Image, ImageDraw
    v = np.asarray(mesh.vertices)
    fc = np.asarray(mesh.faces)
    col = np.asarray(mesh.visual.vertex_colors)[:, :3].astype(np.float32) / 255.0
    size = 360
    sheet = Image.new("RGB", (size * 4, size), (24, 22, 20))
    for k, yaw in enumerate([0, 90, 200, 300]):
        a = np.radians(yaw)
        rot = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]], np.float32)
        tilt = np.radians(-25)
        rx = np.array([[1, 0, 0], [0, np.cos(tilt), -np.sin(tilt)], [0, np.sin(tilt), np.cos(tilt)]], np.float32)
        q = v @ rot.T @ rx.T
        nrm = np.asarray(mesh.vertex_normals) @ rot.T @ rx.T
        light = np.clip(nrm @ np.array([-0.4, 0.7, 0.6]) / 1.0, 0.1, 1.0)
        stripe = stripe_pattern(v) * col[:, 1]
        shade = light * (0.35 + 0.65 * col[:, 0]) * (1 - 0.75 * stripe)
        sc = size * 1.25
        xy = np.stack([q[:, 0] * sc + size / 2, -q[:, 1] * sc + size * 0.78], axis=1)
        order = np.argsort(q[fc].mean(axis=1)[:, 2])
        img = Image.new("RGB", (size, size), (24, 22, 20))
        dr = ImageDraw.Draw(img)
        for t in order:
            s = shade[fc[t]].mean()
            c = (int(220 * s), int(170 * s), int(80 * s))
            dr.polygon([tuple(xy[i]) for i in fc[t]], fill=c)
        sheet.paste(img, (size * k, 0))
    sheet.save(path)
    print(f"preview: {path}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true")
    args = ap.parse_args()
    t = build("tiger", tiger, ((-0.23, -0.002, -0.39), (0.23, 0.32, 0.42)), 0.0022, 14000,
              marks=tiger_marks)
    g = build("goat", goat, ((-0.18, -0.002, -0.2), (0.18, 0.38, 0.18)), 0.0018, 9000)
    if args.preview:
        prev = pathlib.Path("tools/art/previews")   # has a .gdignore: not game assets
        prev.mkdir(parents=True, exist_ok=True)
        (prev / ".gdignore").touch()
        preview(t, prev / "tiger_preview.png")
        preview(g, prev / "goat_preview.png")


if __name__ == "__main__":
    main()
