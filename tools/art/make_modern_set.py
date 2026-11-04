#!/usr/bin/env python3
"""Generates the Bagh Chal "Modern edition" set: what a game company might
make of it today.

  board   a molded plastic board: a teal playing field with raised sunflower
          lines and point studs, a raised coral rim, and an orange ring at the
          four corner points (where the tigers start).
  tiger   a lying tiger, head up, in glossy orange plastic, painted like a
          designer vinyl toy (stripes, white face and chest, eyes) by
          piece_modern.gdshader.
  goat    a resting kid with small swept-back horns, in white plastic.

The pieces reuse the SDF tools in make_pieces.py (smooth unions, marching
cubes, attributes sampled from the field). Their forms are simplified on
purpose: soft volumes, no base, like designer vinyl figures.

Outputs (titles/bagh_chal/art/modern/):
  board.glb            board mesh with the raised rim, top-projected UVs,
                       y = 0 is the playing surface
  board_albedo.png     sRGB: field, lines, studs, rim
  board_orm.png        R occlusion, G roughness, B metallic
  board_normal.png     OpenGL-convention normal map (the raised lines)
  board_glow.png       where the "awakened" lines glow
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

HALF = 2.75          # board half-size (points span -2..2)
CORNER = 0.42        # plan-view corner radius
EDGE = 0.07          # rounding of the outer top and bottom edges
THICK = 0.26         # thickness below the playing surface
RIM = 0.3            # width of the raised rim
LIP = 0.07           # height of the rim above the playing field
BEVEL = 0.06         # the rim's inner slope, in plan
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
    caps: the playing field at y = 0 inside the raised rim, and the bottom."""
    prof = []
    n = 6
    # The field's edge, then the rim's inner slope (creased at both ends).
    slope = np.arctan2(LIP, BEVEL)
    bevel_n = (-np.sin(slope), np.cos(slope))
    prof.append((RIM, 0.0, (0.0, 1.0)))
    prof.append((RIM, 0.0, bevel_n))
    prof.append((RIM - BEVEL, LIP, bevel_n))
    prof.append((RIM - BEVEL, LIP, (0.0, 1.0)))
    for k in range(n + 1):                       # outer top edge: quarter round
        a = np.pi / 2 - (np.pi / 2) * k / n
        prof.append((EDGE - EDGE * np.cos(a), LIP - EDGE + EDGE * np.sin(a), (np.cos(a), np.sin(a))))
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


def round_rect_sdf(X, Z, half, radius):
    """Signed distance to a rounded square (negative inside)."""
    qx = np.abs(X) - (half - radius)
    qz = np.abs(Z) - (half - radius)
    out = np.hypot(np.maximum(qx, 0), np.maximum(qz, 0))
    return out + np.minimum(np.maximum(qx, qz), 0) - radius


def molded(X, size):
    """The faint grain of a spark-eroded mold: tiny height and gloss changes."""
    return noise(X.shape, 0.8, 21) * 0.6 + noise(X.shape, 3.0, 22) * 0.4


def build_textures(size):
    board = json.loads(pathlib.Path("tools/art/boards.json").read_text())[BOARD_ID]
    pts = np.array([p["pos"] for p in board["points"]], np.float32)
    center = (pts.min(0) + pts.max(0)) / 2
    world = pts - center
    corner = np.array(["corner" in p["tags"] for p in board["points"]])

    px = 2 * UV_HALF / size
    coords = (np.arange(size, dtype=np.float32) + 0.5) * px - UV_HALF
    X, Z = np.meshgrid(coords, coords)

    def cover(d, half_width):
        """Crisp coverage, antialiased over about a pixel."""
        return np.clip((half_width - d) / px + 0.5, 0, 1)

    def rib(d, half_width, h):
        """A raised rib with a rounded top: height falls off toward its edges."""
        t = np.clip(1 - d / half_width, 0, 1)
        return h * np.sqrt(t * (2 - t))

    field = np.array([0.02, 0.42, 0.47], np.float32)      # teal
    line_c = np.array([0.98, 0.74, 0.16], np.float32)     # sunflower
    rim_c = np.array([0.92, 0.38, 0.32], np.float32)      # coral
    home_c = np.array([0.97, 0.5, 0.12], np.float32)      # orange: the tigers' corners

    grain = molded(X, size)
    rim_sdf = round_rect_sdf(X, Z, HALF - RIM, CORNER - RIM)
    on_rim = cover(-rim_sdf, 0.0)                          # 1 on the rim and its slope

    line_d = np.full(X.shape, 1e9, np.float32)
    for a, b in board["segments"]:
        line_d = np.minimum(line_d, seg_dist(X, Z, world[a], world[b]))
    lines = cover(line_d, 0.026)
    height = rib(line_d, 0.03, 0.01)
    glow = cover(line_d, 0.016)
    studs = np.zeros_like(X)
    home = np.zeros_like(X)
    for w, is_corner in zip(world, corner):
        r = np.hypot(X - w[0], Z - w[1])
        studs = np.maximum(studs, cover(r, 0.085))
        height = np.maximum(height, rib(r, 0.09, 0.016))
        glow = np.maximum(glow, cover(r, 0.06))
        if is_corner:
            ring = np.abs(r - 0.2)
            home = np.maximum(home, cover(ring, 0.028))
            height = np.maximum(height, rib(ring, 0.032, 0.009))
    marks = np.maximum(lines, studs)
    albedo = field * (1 + 0.012 * grain[..., None])
    albedo = albedo * (1 - marks[..., None]) + line_c * marks[..., None]
    albedo = albedo * (1 - home[..., None]) + home_c * home[..., None]
    albedo = albedo * (1 - on_rim[..., None]) + rim_c * on_rim[..., None]
    height = height * (1 - on_rim) + 0.00006 * grain
    rough = 0.36 + 0.03 * grain
    rough = rough * (1 - np.maximum(marks, home)) + 0.26 * np.maximum(marks, home)   # glossier lines
    rough = rough * (1 - on_rim) + 0.32 * on_rim
    blur = ndimage.gaussian_filter(height, 3.0)
    ao = np.clip(1.0 - np.clip((blur - height) / 0.006, 0, 1) * 0.35, 0.6, 1.0)
    metal = np.zeros_like(ao)
    glow = glow * (1 - on_rim)

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
    """A tiger lying in the sphinx pose, head up, front legs stretched out,
    tail curled round to the front: toy proportions (a big round head, big
    paws, soft volumes), so it reads at a glance on the board. The markings
    are painted by piece_modern.gdshader, which knows where the face is."""
    m = mp.mirror_x(p)
    chest = mp.ellipsoid(p, (0, 0.108, -0.055), (0.092, 0.092, 0.085))
    belly = mp.ellipsoid(p, (0, 0.085, 0.05), (0.088, 0.075, 0.12))
    hips = mp.ellipsoid(m, (0.042, 0.088, 0.13), (0.058, 0.075, 0.072))
    body = mp.smin(mp.smin(chest, belly, 0.05), hips, 0.04)
    thigh = mp.ellipsoid(m, (0.082, 0.062, 0.115), (0.036, 0.052, 0.066))     # folded hind legs
    hpaw = mp.ellipsoid(m, (0.088, 0.017, 0.062), (0.028, 0.017, 0.04))
    body = mp.smin(body, mp.smin(thigh, hpaw, 0.035), 0.025)
    fleg = mp.round_cone(m, (0.05, 0.08, -0.085), (0.046, 0.03, -0.195), 0.03, 0.023)
    fpaw = mp.ellipsoid(m, (0.046, 0.022, -0.222), (0.031, 0.022, 0.04))
    body = mp.smin(body, mp.smin(fleg, fpaw, 0.022), 0.03)
    skull = mp.ellipsoid(p, (0, 0.222, -0.16), (0.085, 0.076, 0.072))
    ruff = mp.ellipsoid(m, (0.052, 0.19, -0.165), (0.045, 0.042, 0.045))       # cheek fur
    muzzle = mp.ellipsoid(p, (0, 0.19, -0.226), (0.048, 0.036, 0.038))
    chin = mp.ellipsoid(p, (0, 0.166, -0.208), (0.03, 0.022, 0.03))
    head = mp.smin(mp.smin(skull, ruff, 0.03), mp.smin(muzzle, chin, 0.02), 0.022)
    ears = mp.ellipsoid(m, (0.06, 0.29, -0.145), (0.032, 0.03, 0.014))
    head = mp.smin(head, ears, 0.014)
    neck = mp.round_cone(p, (0, 0.12, -0.085), (0, 0.18, -0.145), 0.066, 0.055)
    d = mp.smin(body, mp.smin(neck, head, 0.03), 0.03)
    tail = mp.chain(p, [(0.03, 0.07, 0.19), (0.095, 0.04, 0.215), (0.142, 0.026, 0.13),
                        (0.14, 0.022, 0.01), (0.122, 0.02, -0.055)], 0.024, 0.016)
    d = mp.smin(d, tail, 0.02)
    return _flat(p, d)


def tiger_marks(v, n):
    """Where stripes may go: not on the underside or the soles of the paws.
    The shader keeps them off the white face and chest itself."""
    up = np.clip((n[:, 1] + 0.7) / 0.5, 0.0, 1.0)
    above = np.clip((v[:, 1] - 0.02) / 0.02, 0.0, 1.0)
    return (up * above).astype(np.float32)


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
    t = mp.build("tiger", tiger, ((-0.2, -0.002, -0.3), (0.2, 0.33, 0.27)), 0.0018, 20000, marks=tiger_marks, smooth=8)
    g = mp.build("goat", goat, ((-0.13, -0.002, -0.22), (0.13, 0.27, 0.19)), 0.0016, 9000, smooth=8)
    mp.build("mug", mug, ((-0.66, -0.002, -0.66), (1.04, 1.48, 0.66)), 0.008, 16000, smooth=8)
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
