#!/usr/bin/env python3
"""Generates the Bagh Chal "Modern edition" set: what a design studio might
make of the game today.

  board   a slab of pale white oak with soft rounded edges; the playing lines
          and points are a matte charcoal inlay, flush with the wood. The
          corner points (where the tigers start) get a fine inlaid ring.
  tiger   a lying tiger, head up, in a glazed burnt-orange ceramic; the bold
          graphic stripes are drawn by piece_modern.gdshader.
  goat    a resting kid with small swept-back horns, in matte cream ceramic.

The pieces reuse the SDF tools in make_pieces.py (smooth unions, marching
cubes, attributes sampled from the field). Their forms are simplified on
purpose: soft volumes, no base, as in contemporary ceramic figurines.

Outputs (titles/bagh_chal/art/modern/):
  board.glb            slab mesh, top-projected UVs, y = 0 is the playing surface
  board_albedo.png     sRGB: oak and the charcoal inlay
  board_orm.png        R occlusion, G roughness, B metallic
  board_normal.png     OpenGL-convention normal map
  board_glow.png       where the "awakened" inlay glows
  tiger.glb, goat.glb  COLOR_0: R occlusion, G stripe area (tiger), B edge
  mug.glb              set dressing: a stoneware mug (same vertex colors)

Run from the hunt-games root:
    python3 tools/art/make_modern_set.py [--board-only | --pieces-only] [--preview]
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

import numpy as np
import trimesh
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import make_pieces as mp  # noqa: E402

OUT = pathlib.Path("titles/bagh_chal/art/modern")
BOARD_ID = "alquerque_5x5"

HALF = 2.75          # slab half-size (points span -2..2)
CORNER = 0.42        # plan-view corner radius
EDGE = 0.07          # rounding of the top and bottom edges
THICK = 0.26         # slab thickness below the playing surface
UV_HALF = HALF       # texture covers -HALF..HALF


# --- Board mesh ----------------------------------------------------------------

def rounded_rect(half, radius, per_corner=12):
    """Closed path (x, z) of a rounded square, counter-clockwise from +x."""
    pts = []
    centers = [(half - radius, half - radius), (-(half - radius), half - radius),
               (-(half - radius), -(half - radius)), (half - radius, -(half - radius))]
    for c, (cx, cz) in enumerate(centers):
        for k in range(per_corner + 1):
            a = np.pi * 0.5 * c + np.pi * 0.5 * k / per_corner
            pts.append((cx + radius * np.cos(a), cz + radius * np.sin(a), np.cos(a), np.sin(a)))
    return pts


def build_board_mesh():
    """A profile (inset, y, normal) swept round the rounded square, plus flat
    top and bottom caps."""
    prof = []
    n = 6
    for k in range(n + 1):                       # top edge: quarter round
        a = np.pi / 2 - (np.pi / 2) * k / n
        prof.append((EDGE - EDGE * np.cos(a), -EDGE + EDGE * np.sin(a), (np.cos(a), np.sin(a))))
    for k in range(n + 1):                       # bottom edge
        a = -(np.pi / 2) * k / n
        prof.append((EDGE - EDGE * np.cos(a), -THICK + EDGE + EDGE * np.sin(a), (np.cos(a), np.sin(a))))
    path = rounded_rect(HALF, CORNER)
    verts, norms, faces = [], [], []
    rings = []
    for (inset, y, (nr, ny)) in prof:
        ring = []
        for (x, z, ox, oz) in path:
            verts.append((x - ox * inset, y, z - oz * inset))
            norms.append((ox * nr, ny, oz * nr))
            ring.append(len(verts) - 1)
        rings.append(ring)
    m = len(path)
    for r in range(len(rings) - 1):
        for i in range(m):                       # closed loop: the last side joins the first
            j = (i + 1) % m
            a, b = rings[r][i], rings[r][j]
            c, d = rings[r + 1][i], rings[r + 1][j]
            faces += [(a, c, b), (b, c, d)]
    # Caps: fans from the center (the outline is convex).
    for ring, y, ny in ((rings[0], 0.0, 1.0), (rings[-1], -THICK, -1.0)):
        verts.append((0.0, y, 0.0))
        norms.append((0.0, ny, 0.0))
        c = len(verts) - 1
        for i in range(m):
            j = (i + 1) % m
            faces.append((c, ring[i], ring[j]) if ny > 0 else (c, ring[j], ring[i]))
    v = np.array(verts, np.float32)
    nn = np.array(norms, np.float32)
    nn /= np.linalg.norm(nn, axis=1, keepdims=True)
    f = np.array(faces, np.int64)
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    flip = (fn * nn[f].mean(axis=1)).sum(axis=1) < 0
    f[flip] = f[flip][:, ::-1]
    uv = np.stack([(v[:, 0] + UV_HALF) / (2 * UV_HALF), (v[:, 2] + UV_HALF) / (2 * UV_HALF)], axis=1)
    mesh = trimesh.Trimesh(v, f, vertex_normals=nn, process=False)
    mesh.visual = trimesh.visual.TextureVisuals(
        uv=uv, material=trimesh.visual.material.PBRMaterial(baseColorFactor=[214, 186, 150, 255]))
    OUT.mkdir(parents=True, exist_ok=True)
    mesh.export(OUT / "board.glb")
    print(f"board.glb: {len(v)} verts, {len(f)} tris")


# --- Board textures ------------------------------------------------------------

def noise(shape, sigma, seed):
    rng = np.random.default_rng(seed)
    n = ndimage.gaussian_filter(rng.standard_normal(shape).astype(np.float32), sigma, mode="wrap")
    return n / (np.abs(n).max() + 1e-9)


def seg_dist(px, pz, a, b):
    ab = b - a
    t = np.clip(((px - a[0]) * ab[0] + (pz - a[1]) * ab[1]) / (ab @ ab), 0, 1)
    return np.hypot(px - (a[0] + t * ab[0]), pz - (a[1] + t * ab[1]))


def oak(X, Z, size):
    """Quartersawn white oak, grain along x: straight growth lines a little
    unevenly spaced, fine fibres, the pale ray flecks oak is known for, and
    five glued boards each a touch different in tone."""
    board = np.clip(np.floor((Z + HALF) / (2 * HALF) * 5).astype(int), 0, 4)
    offset = np.array([0.0, 0.37, 0.81, 0.15, 0.6], np.float32)[board]
    warp = 0.018 * noise(X.shape, size / 7, 11) + 0.004 * noise(X.shape, size / 40, 12)
    g = Z + warp + offset
    # Growth lines: spacing drifts slowly, so they never look ruled.
    phase = g * 64.0 + 2.5 * noise(X.shape, (size / 3, size / 30), 13)
    ring = 0.5 + 0.5 * np.sin(phase)
    late = np.clip((ring - 0.78) / 0.22, 0, 1) ** 2
    fibre = noise(X.shape, (size / 3000, size / 40), 14)
    rays = noise(X.shape, (size / 1200, size / 90), 15)
    flecks = np.clip((rays - 0.45) / 0.35, 0, 1) * np.clip(noise(X.shape, size / 30, 16) + 0.2, 0, 1)
    tone = np.array([0.0, 0.03, -0.025, 0.02, -0.012], np.float32)[board]
    drift = 0.03 * noise(X.shape, size / 5, 17) + tone
    base = np.array([0.79, 0.67, 0.51], np.float32)
    dark = np.array([0.66, 0.53, 0.38], np.float32)
    light = np.array([0.86, 0.77, 0.63], np.float32)
    col = base * (1 + drift[..., None] + 0.035 * fibre[..., None])
    col = col * (1 - 0.32 * late[..., None]) + dark * (0.32 * late[..., None])
    col = col * (1 - 0.3 * flecks[..., None]) + light * (0.3 * flecks[..., None])
    height = 0.00025 * late + 0.00012 * fibre - 0.00015 * flecks
    seams = ((Z + HALF) / (2 * HALF) * 5) % 1.0
    seam = np.clip(1 - np.minimum(seams, 1 - seams) * (2 * HALF / 5) / 0.003, 0, 1)
    col = col * (1 - 0.06 * seam[..., None])
    return col, height, late, flecks


def build_textures(size):
    board = json.loads(pathlib.Path("tools/art/boards.json").read_text())[BOARD_ID]
    pts = np.array([p["pos"] for p in board["points"]], np.float32)
    center = (pts.min(0) + pts.max(0)) / 2
    world = pts - center
    corner = np.array(["corner" in p["tags"] for p in board["points"]])

    px = 2 * UV_HALF / size
    coords = (np.arange(size, dtype=np.float32) + 0.5) * px - UV_HALF
    X, Z = np.meshgrid(coords, coords)
    wood_col, height, late, flecks = oak(X, Z, size)

    # The inlay: crisp edges, antialiased over about a pixel.
    def cover(d, half_width):
        return np.clip((half_width - d) / px + 0.5, 0, 1)

    line_d = np.full(X.shape, 1e9, np.float32)
    for a, b in board["segments"]:
        line_d = np.minimum(line_d, seg_dist(X, Z, world[a], world[b]))
    inlay = cover(line_d, 0.017)
    glow = cover(line_d, 0.012)
    for w, is_corner in zip(world, corner):
        r = np.hypot(X - w[0], Z - w[1])
        inlay = np.maximum(inlay, cover(r, 0.062))                 # point dot
        glow = np.maximum(glow, cover(r, 0.045))
        if is_corner:
            inlay = np.maximum(inlay, cover(np.abs(r - 0.15), 0.008))
    charcoal = np.array([0.075, 0.07, 0.068], np.float32)
    albedo = wood_col * (1 - inlay[..., None]) + charcoal * inlay[..., None]
    # Flush inlay with a hairline seam where it meets the wood.
    edge = np.clip(1 - np.abs(inlay - 0.5) * 2, 0, 1)
    height = height * (1 - inlay) - 0.0003 * edge
    rough = 0.52 + 0.08 * late - 0.06 * flecks
    rough = rough * (1 - inlay) + 0.38 * inlay                    # the inlay is lacquered
    blur = ndimage.gaussian_filter(height, 2.0)
    ao = np.clip(1.0 - np.clip((blur - height) / 0.0006, 0, 1) * 0.3, 0.6, 1.0)
    metal = np.zeros_like(ao)

    gz, gx = np.gradient(height, px)
    nx, ny = -gx, gz
    nz = np.ones_like(nx)
    nl = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / nl, ny / nl, nz / nl], axis=-1) * 0.5 + 0.5

    def save(name, arr, mode="RGB", out_size=None):
        img = Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), mode)
        if out_size and out_size != img.size[0]:
            img = img.resize((out_size, out_size), Image.LANCZOS)
        img.save(OUT / name, optimize=True)
        print(f"{name}: {img.size}")

    OUT.mkdir(parents=True, exist_ok=True)
    save("board_albedo.png", albedo)
    half = size // 2
    save("board_orm.png", np.stack([ao, rough, metal], axis=-1), out_size=half)
    save("board_normal.png", normal, out_size=half)
    save("board_glow.png", glow, "L", out_size=half)


# --- Pieces --------------------------------------------------------------------

def _flat(p, d):
    """Cut flat at y = 0: the figure sits on the board."""
    return np.maximum(d, -p[:, 1])


def tiger(p):
    """A tiger lying down, head raised and alert: one soft volume."""
    m = mp.mirror_x(p)
    body = mp.ellipsoid(p, (0, 0.1, 0.035), (0.105, 0.098, 0.175))
    body = mp.smin(body, mp.sphere(p, (0, 0.105, 0.11), 0.1), 0.06)            # haunches
    body = mp.smin(body, mp.ellipsoid(p, (0, 0.13, -0.07), (0.098, 0.09, 0.09)), 0.06)  # shoulders
    head = mp.ellipsoid(p, (0, 0.2, -0.155), (0.088, 0.08, 0.078))
    head = mp.smin(head, mp.ellipsoid(p, (0, 0.17, -0.222), (0.052, 0.04, 0.04)), 0.03)  # muzzle
    head = mp.smin(head, mp.ellipsoid(p, (0, 0.185, -0.15), (0.1, 0.058, 0.058)), 0.03)  # cheeks
    ears = mp.ellipsoid(m, (0.06, 0.272, -0.15), (0.03, 0.03, 0.016))
    head = mp.smin(head, ears, 0.022)
    d = mp.smin(body, head, 0.05)
    legs = mp.round_cone(m, (0.05, 0.1, -0.1), (0.052, 0.035, -0.19), 0.04, 0.03)
    paws = mp.ellipsoid(m, (0.052, 0.028, -0.215), (0.037, 0.028, 0.05))
    d = mp.smin(d, mp.smin(legs, paws, 0.03), 0.04)
    tail = mp.chain(p, [(0.03, 0.08, 0.16), (0.1, 0.045, 0.18), (0.145, 0.035, 0.09), (0.14, 0.03, -0.03)],
                    0.027, 0.019)
    d = mp.smin(d, tail, 0.035)
    return _flat(p, d)


def tiger_marks(v, n):
    """The stripes may go on the back, flanks, head and tail; never on the
    underside or the paws."""
    y = v[:, 1]
    up = np.clip((n[:, 1] + 0.6) / 0.5, 0.0, 1.0)
    above = np.clip((y - 0.045) / 0.03, 0.0, 1.0)
    paws = (v[:, 2] < -0.17) & (y < 0.07)
    return (up * above * ~paws).astype(np.float32)


def goat(p):
    """A resting kid, legs folded under, neck up, short horns curving back."""
    m = mp.mirror_x(p)
    body = mp.ellipsoid(p, (0, 0.07, 0.03), (0.085, 0.07, 0.135))
    body = mp.smin(body, mp.sphere(p, (0, 0.075, 0.09), 0.068), 0.05)          # rump
    neck = mp.round_cone(p, (0, 0.09, -0.06), (0, 0.15, -0.105), 0.05, 0.036)
    head = mp.ellipsoid(p, (0, 0.17, -0.125), (0.042, 0.045, 0.052))
    head = mp.smin(head, mp.ellipsoid(p, (0, 0.152, -0.172), (0.027, 0.028, 0.032)), 0.02)  # muzzle
    ears = mp.ellipsoid(m, (0.05, 0.172, -0.11), (0.03, 0.01, 0.016))
    horns = mp.chain(m, [(0.018, 0.205, -0.125), (0.026, 0.232, -0.11), (0.032, 0.244, -0.082),
                         (0.034, 0.236, -0.058)], 0.016, 0.009)
    head = mp.smin(mp.smin(head, ears, 0.012), horns, 0.012)
    d = mp.smin(mp.smin(body, neck, 0.04), head, 0.025)
    legs = mp.ellipsoid(m, (0.045, 0.025, -0.07), (0.03, 0.025, 0.045))     # folded forelegs
    d = mp.smin(d, legs, 0.03)
    return _flat(p, d)


def mug(p):
    """A stoneware mug for the table: straight walls, a thin rounded rim, a
    loop handle on +x. About 8 cm across and 9 cm tall (1 = 6 cm)."""
    outer = mp.rounded_cylinder(p, (0, 0.72, 0), 0.62, 1.44, 0.07)
    inner = mp.rounded_cylinder(p, (0, 0.88, 0), 0.55, 1.52, 0.06)
    body = np.maximum(outer, -inner)
    q = p - np.array([0.62, 0.74, 0.0], np.float32)
    ring = np.sqrt(q[:, 0] ** 2 + q[:, 1] ** 2) - 0.3
    torus = np.sqrt(ring ** 2 + q[:, 2] ** 2) - 0.07
    handle = np.maximum(torus, 0.56 - p[:, 0])
    return mp.smin(body, handle, 0.05)


def build_pieces(preview):
    mp.OUT_DIR = OUT
    t = mp.build("tiger", tiger, ((-0.2, -0.002, -0.3), (0.2, 0.31, 0.27)), 0.002, 9000, marks=tiger_marks)
    g = mp.build("goat", goat, ((-0.13, -0.002, -0.22), (0.13, 0.27, 0.19)), 0.0016, 7000)
    mp.build("mug", mug, ((-0.66, -0.002, -0.66), (1.04, 1.48, 0.66)), 0.008, 12000)
    if preview:
        prev = pathlib.Path("tools/art/previews")
        prev.mkdir(parents=True, exist_ok=True)
        (prev / ".gdignore").touch()
        mp.preview(t, prev / "modern_tiger_preview.png")
        mp.preview(g, prev / "modern_goat_preview.png")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--board-only", action="store_true")
    ap.add_argument("--pieces-only", action="store_true")
    ap.add_argument("--size", type=int, default=2048)
    ap.add_argument("--preview", action="store_true")
    args = ap.parse_args()
    if not args.pieces_only:
        build_board_mesh()
        build_textures(args.size)
    if not args.board_only:
        build_pieces(args.preview)


if __name__ == "__main__":
    main()
