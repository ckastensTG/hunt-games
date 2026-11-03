#!/usr/bin/env python3
"""Generates the Bagh Chal "Stone and pebbles" style (the historical look).

How the game has been played in Nepal (sources in the dev handoff): the board
scratched into the ground or chalked on a smooth surface (or carved into the
floor of a rest house), larger stones for the tigers and small pebbles for
the goats. Brass sets are a later craft, mostly made for visitors.

So this style is a flat stone with the grid scratched in and rubbed with
chalk, four large dark river stones and twenty small pale pebbles. The straw
mat it sits on is drawn by a shader (straw_mat.gdshader).

Outputs (titles/bagh_chal/art/stone/):
  board.glb                   the slab: playing surface at y = 0, uneven edge
  board_albedo.png            sRGB: weathered stone, chalk in the scratches
  board_orm.png               R occlusion, G roughness, B metallic (0)
  board_normal.png            OpenGL-convention normal map
  board_glow.png              the scratched lines, for the "awakening" glow
  tiger_0..3.glb              river stones, one per tiger
  goat_0..7.glb               pebbles, cycled across the twenty goats

Vertex colors on the stones (as for the brass pieces):
  R ambient occlusion   G a quartz vein (off: it read as a seam)   B edge wear

Run from the hunt-games root (after tools/export_boards.gd):
    python3 tools/art/make_stone_set.py [--stones-only]
"""
from __future__ import annotations

import json
import pathlib
import sys

import numpy as np
import fast_simplification
import trimesh
from PIL import Image
from scipy import ndimage
from skimage import measure

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from make_pieces import ellipsoid, smin, gradient, occlusion, convexity  # noqa: E402

OUT = pathlib.Path("titles/bagh_chal/art/stone")
BOARD_ID = "alquerque_5x5"

UV_HALF = 3.0        # the textures cover -3..3 (the slab and a margin)
SLAB_HALF = 2.78     # nominal half-size of the slab's outline
THICK = 0.4          # about 2.5 cm of stone


def smooth_noise(shape, sigma, seed):
    rng = np.random.default_rng(seed)
    n = ndimage.gaussian_filter(rng.standard_normal(shape).astype(np.float32), sigma, mode="wrap")
    return n / (np.abs(n).max() + 1e-9)


# --- The slab ----------------------------------------------------------------

def outline_distance(x, z):
    """Signed distance to the slab's uneven outline (negative inside)."""
    r = 0.26
    qx = np.abs(x) - (SLAB_HALF - r)
    qz = np.abs(z) - (SLAB_HALF - r)
    d = np.hypot(np.maximum(qx, 0), np.maximum(qz, 0)) + np.minimum(np.maximum(qx, qz), 0) - r
    ang = np.arctan2(z, x)
    # A dressed slab: nearly straight sides, a slight irregularity, and a few
    # chips knocked out of the edge.
    wobble = 0.018 * np.sin(ang * 3 + 0.7) + 0.01 * np.sin(ang * 7 + 2.1)
    chips = sum(0.05 * np.exp(-((np.angle(np.exp(1j * (ang - c)))) / w) ** 2)
                for c, w in ((0.4, 0.05), (2.2, 0.08), (3.9, 0.04), (5.3, 0.06)))
    return d + wobble + chips


def outline_polygon(n=256):
    """Points on the outline (where outline_distance = 0), by bisection along
    rays from the center. The rounded, chipped square is star-shaped, so each
    ray crosses it once."""
    ang = np.linspace(0, 2 * np.pi, n, endpoint=False)
    lo = np.zeros(n)
    hi = np.full(n, SLAB_HALF * 1.6)
    for _ in range(40):
        mid = (lo + hi) / 2
        inside = outline_distance(np.cos(ang) * mid, np.sin(ang) * mid) < 0
        lo = np.where(inside, mid, lo)
        hi = np.where(inside, hi, mid)
    r = (lo + hi) / 2
    return np.stack([np.cos(ang) * r, np.sin(ang) * r], axis=1)


def undulate(x, z):
    return 0.004 * np.sin(x * 0.9 + 0.4) * np.cos(z * 0.7 - 0.2)


def build_board_mesh(rings=24):
    """The slab: a polar grid out to the outline, then a small rounded edge,
    a near-vertical side and the underside. Crisp edges, smooth normals."""
    out = outline_polygon()
    n = len(out)
    tang = np.roll(out, -1, axis=0) - np.roll(out, 1, axis=0)
    onrm = np.stack([tang[:, 1], -tang[:, 0]], axis=1)
    onrm /= np.linalg.norm(onrm, axis=1, keepdims=True)
    if (onrm * out).sum() < 0:
        onrm = -onrm
    rr = 0.035                                       # edge rounding radius
    inset = out - onrm * rr
    verts, norms, ring_ids = [], [], []
    center = 0
    verts.append((0.0, float(undulate(0.0, 0.0)), 0.0))
    norms.append((0.0, 1.0, 0.0))
    for k in range(1, rings + 1):
        f = (k / rings) ** 0.8
        ids = []
        for i in range(n):
            x, z = inset[i] * f
            ids.append(len(verts))
            verts.append((x, float(undulate(x, z)), z))
            norms.append((0.0, 1.0, 0.0))
        ring_ids.append(ids)
    profile = []
    for a in np.linspace(0, np.pi / 2, 5)[1:]:
        profile.append((np.sin(a) * rr, -(1 - np.cos(a)) * rr, np.sin(a), np.cos(a)))
    for t in (0.35, 0.7, 1.0):
        profile.append((rr - 0.015 * t, -rr - (THICK - rr) * t, 0.98, 0.15))
    for (dr, dy, nr, ny) in profile:
        ids = []
        for i in range(n):
            x, z = inset[i] + onrm[i] * dr
            ids.append(len(verts))
            verts.append((x, dy + float(undulate(*inset[i])), z))
            norms.append((onrm[i][0] * nr, ny, onrm[i][1] * nr))
        ring_ids.append(ids)
    faces = []
    first = ring_ids[0]
    for i in range(n):
        faces.append((center, first[(i + 1) % n], first[i]))
    for a_ids, b_ids in zip(ring_ids[:-1], ring_ids[1:]):
        for i in range(n):
            j = (i + 1) % n
            faces.append((a_ids[i], a_ids[j], b_ids[i]))
            faces.append((a_ids[j], b_ids[j], b_ids[i]))
    last = ring_ids[-1]
    bottom = len(verts)
    verts.append((0.0, -THICK, 0.0))
    norms.append((0.0, -1.0, 0.0))
    under = []
    for i in last:
        under.append(len(verts))
        verts.append(verts[i])
        norms.append((0.0, -1.0, 0.0))
    for i in range(n):
        faces.append((bottom, under[i], under[(i + 1) % n]))
    v = np.array(verts, np.float32)
    nm = np.array(norms, np.float32)
    nm /= np.linalg.norm(nm, axis=1, keepdims=True)
    f = np.array(faces, np.int64)
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    flip = (fn * nm[f].mean(axis=1)).sum(axis=1) < 0
    f[flip] = f[flip][:, ::-1]
    uv = np.stack([(v[:, 0] + UV_HALF) / (2 * UV_HALF), (v[:, 2] + UV_HALF) / (2 * UV_HALF)], axis=1)
    mesh = trimesh.Trimesh(v, f, vertex_normals=nm, process=False)
    mesh.visual = trimesh.visual.TextureVisuals(
        uv=uv, material=trimesh.visual.material.PBRMaterial(baseColorFactor=[110, 105, 98, 255]))
    OUT.mkdir(parents=True, exist_ok=True)
    mesh.export(OUT / "board.glb")
    print(f"stone/board.glb: {len(v)} verts, {len(f)} tris")


# --- Textures ----------------------------------------------------------------

def scratched_line(X, Z, a, b, seed):
    """Distance to a hand-scratched line: it wanders a little, and it's cut
    in two or three overlapping strokes."""
    ab = b - a
    length = np.linalg.norm(ab)
    tdir = ab / length
    ndir = np.array([-tdir[1], tdir[0]], np.float32)
    px, pz = X - a[0], Z - a[1]
    t = px * tdir[0] + pz * tdir[1]
    s = px * ndir[0] + pz * ndir[1]
    rng = np.random.default_rng(seed)
    ph = rng.uniform(0, 6.28, 6)
    tt = np.clip(t, 0, length)
    best = np.full(X.shape, np.inf, np.float32)
    for k in range(3):
        wob = (0.009 * np.sin(tt * 2.1 + ph[k]) + 0.005 * np.sin(tt * 7.3 + ph[k + 3])
               + (k - 1) * 0.006)
        # The stroke starts and stops a little short or long of the points.
        t0, t1 = rng.uniform(-0.05, 0.04), length + rng.uniform(-0.04, 0.05)
        along = np.where(t < t0, t0 - t, np.where(t > t1, t - t1, 0.0))
        dist = np.hypot(s - wob, along)
        best = np.minimum(best, dist + k * 0.002)
    width = 0.016 + 0.004 * np.sin(tt * 1.3 + ph[0])
    return best, width


def build_textures(size=2048):
    board = json.loads(pathlib.Path("tools/art/boards.json").read_text())[BOARD_ID]
    pts = np.array([p["pos"] for p in board["points"]], np.float32)
    world = pts - (pts.min(0) + pts.max(0)) / 2

    px = 2 * UV_HALF / size
    coords = (np.arange(size, dtype=np.float32) + 0.5) * px - UV_HALF
    X, Z = np.meshgrid(coords, coords)
    height = np.zeros((size, size), np.float32)
    line = np.zeros_like(height)
    for i, (a, b) in enumerate(board["segments"]):
        d, w = scratched_line(X, Z, world[a], world[b], 100 + i)
        line = np.maximum(line, np.clip(1 - d / w, 0, 1) ** 0.7)
    height -= 0.008 * line
    pits = np.zeros_like(height)
    for w in world:
        r = np.hypot(X - w[0], Z - w[1])
        pits = np.maximum(pits, np.clip(1 - r / 0.045, 0, 1) ** 1.2)
    height -= 0.01 * pits

    # The stone: grain, small pits, a little undulation.
    grain = smooth_noise(height.shape, 1.2, 1) * 0.6 + smooth_noise(height.shape, 4, 2) * 0.4
    height += 0.0012 * grain
    rng = np.random.default_rng(7)
    pocks = np.zeros_like(height)
    for _ in range(900):
        cx, cz = rng.uniform(-UV_HALF, UV_HALF, 2)
        rad = rng.uniform(0.008, 0.03)
        i0 = int((cz + UV_HALF) / px)
        j0 = int((cx + UV_HALF) / px)
        rr = int(rad / px) + 2
        sl = (slice(max(0, i0 - rr), i0 + rr), slice(max(0, j0 - rr), j0 + rr))
        dd = np.hypot(X[sl] - cx, Z[sl] - cz)
        pocks[sl] = np.maximum(pocks[sl], np.clip(1 - dd / rad, 0, 1) ** 2)
    height -= 0.003 * pocks

    d_edge = outline_distance(X, Z)
    mottle = np.clip(0.5 + 0.6 * smooth_noise(height.shape, size / 30, 3) + 0.3 * smooth_noise(height.shape, size / 9, 4), 0, 1)
    speck = smooth_noise(height.shape, 0.8, 5)
    weather = np.clip((d_edge + 0.6) / 0.6, 0, 1)            # darker toward the edge
    worn = np.clip(1 - np.hypot(X, Z) / 2.6, 0, 1) ** 1.5     # hands polish the middle
    chalk_cover = np.clip(0.75 + 0.35 * smooth_noise(height.shape, 3, 6) + 0.2 * smooth_noise(height.shape, 25, 8), 0, 1)
    chalk = np.clip(line * 1.4, 0, 1) * chalk_cover
    smudge = np.clip(ndimage.gaussian_filter(line, size / 300) * 0.5, 0, 0.25)

    gray = np.array([0.42, 0.415, 0.40], np.float32)
    warm = np.array([0.5, 0.45, 0.38], np.float32)
    albedo = gray * (1 - mottle[..., None] * 0.6) + warm * (mottle[..., None] * 0.6)
    albedo *= (0.9 + 0.12 * speck[..., None])
    albedo *= (1 - 0.25 * weather[..., None]) * (1 + 0.06 * worn[..., None])
    albedo *= (1 - 0.35 * pocks[..., None])
    albedo = albedo * (1 - 0.5 * pits[..., None])
    chalk_col = np.array([0.9, 0.88, 0.82], np.float32)
    albedo = albedo + (chalk_col - albedo) * smudge[..., None]
    albedo = albedo * (1 - chalk[..., None]) + chalk_col * chalk[..., None]

    blur = ndimage.gaussian_filter(height, size / 500)
    cavity = np.clip((blur - height) / 0.005, 0, 1)
    ao = np.clip(1 - 0.5 * cavity - 0.4 * pits, 0.3, 1)
    rough = np.clip(0.84 - 0.16 * worn + 0.1 * chalk, 0, 1)
    metal = np.zeros_like(rough)

    gz, gx = np.gradient(height, px)
    nx, ny, nz = -gx, gz, np.ones_like(gx)
    nl = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / nl, ny / nl, nz / nl], axis=-1) * 0.5 + 0.5

    def save(name, arr, mode="RGB"):
        Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), mode).save(OUT / name, optimize=True)
        print(f"stone/{name}")

    OUT.mkdir(parents=True, exist_ok=True)
    save("board_albedo.png", albedo)
    save("board_orm.png", np.stack([ao, rough, metal], axis=-1))
    save("board_normal.png", normal)
    save("board_glow.png", np.clip(line * 1.2, 0, 1), "L")


# --- Stones and pebbles ------------------------------------------------------

def stone_sdf(radii, seed, vein):
    rng = np.random.default_rng(seed)
    ph = rng.uniform(0, 6.28, 9)
    amp = rng.uniform(0.6, 1.0)
    vein_dir = rng.normal(size=3)
    vein_dir[1] *= 0.3
    vein_dir /= np.linalg.norm(vein_dir)
    rx, ry, rz = radii

    def f(p):
        q = p - np.array([0, ry * 0.92, 0], np.float32)
        d = ellipsoid(q, (0, 0, 0), radii)
        # Water-worn lumps: low-frequency only, so the stone stays smooth.
        lump = (np.sin(p[:, 0] / rx * 2.1 + ph[0]) * np.sin(p[:, 2] / rz * 1.7 + ph[1])
                + 0.6 * np.sin(p[:, 0] / rx * 3.3 + p[:, 2] / rz * 2.9 + ph[2])
                + 0.4 * np.sin(p[:, 1] / ry * 2.7 + ph[3]))
        d = d + amp * 0.06 * min(radii) * lump
        # Sits flat: a gently rounded underside.
        return -smin(-d, p[:, 1], 0.03 * min(radii) / 0.1)    # smooth max(d, -y)

    def vein_mask(v):
        if not vein:
            return np.zeros(len(v), np.float32)
        s = (v - np.array([0, ry, 0], np.float32)) @ vein_dir
        wob = 0.01 * np.sin(v[:, 0] * 40 + ph[4]) + 0.008 * np.sin(v[:, 2] * 55 + ph[5])
        return np.clip(1 - np.abs(s - ph[6] * 0.004 + wob) / 0.012, 0, 1).astype(np.float32)

    return f, vein_mask


def build_stone(name, radii, seed, vein, target):
    f, vein_mask = stone_sdf(radii, seed, vein)
    pad = 0.04
    lo = np.array([-radii[0] * 1.3 - pad, -0.004, -radii[2] * 1.3 - pad], np.float32)
    hi = np.array([radii[0] * 1.3 + pad, radii[1] * 2.3 + pad, radii[2] * 1.3 + pad], np.float32)
    voxel = min(radii) / 28.0
    shape = np.ceil((hi - lo) / voxel).astype(int) + 1
    axes = [lo[i] + np.arange(shape[i], dtype=np.float32) * voxel for i in range(3)]
    vol = np.empty(shape, np.float32)
    yy, zz = np.meshgrid(axes[1], axes[2], indexing="ij")
    for i, x in enumerate(axes[0]):
        pts = np.stack([np.full(yy.size, x, np.float32), yy.ravel(), zz.ravel()], axis=1)
        vol[i] = f(pts).reshape(yy.shape)
    v, fc, _, _ = measure.marching_cubes(vol, 0.0, spacing=(voxel,) * 3)
    v = v.astype(np.float32) + lo
    v, fc = fast_simplification.simplify(v, fc, 1.0 - min(1.0, target / len(fc)), agg=7)
    v = v.astype(np.float32)
    v[:, 1] = np.maximum(v[:, 1] - v[:, 1].min(), 0.0)      # stand on y = 0
    n = gradient(f, v)
    ao = occlusion(f, v, n)
    wear = np.clip(convexity(f, v, n) / 80.0, 0, 1)
    col = np.stack([ao, vein_mask(v), wear, np.ones_like(ao)], axis=1)
    mesh = trimesh.Trimesh(v, fc, vertex_normals=n, process=False)
    mesh.visual = trimesh.visual.ColorVisuals(mesh, vertex_colors=(col * 255).astype(np.uint8))
    mesh.export(OUT / f"{name}.glb")
    print(f"stone/{name}.glb: {len(v)} verts, {len(fc)} tris, size {np.round(v.max(0) - v.min(0), 3)}")


def main():
    only_stones = "--stones-only" in sys.argv
    if not only_stones:
        build_board_mesh()
        build_textures()
    rng = np.random.default_rng(1876)
    # Tigers: big, dark river stones. Goats: small pale pebbles. They differ in
    # size and in value, so they read apart for colorblind players too.
    for i in range(4):
        radii = (rng.uniform(0.2, 0.24), rng.uniform(0.11, 0.135), rng.uniform(0.17, 0.2))
        build_stone(f"tiger_{i}", radii, 10 + i, vein=False, target=3000)
    for i in range(8):
        radii = (rng.uniform(0.12, 0.145), rng.uniform(0.07, 0.085), rng.uniform(0.1, 0.125))
        build_stone(f"goat_{i}", radii, 50 + i, vein=False, target=1600)


if __name__ == "__main__":
    main()
