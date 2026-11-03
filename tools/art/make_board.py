#!/usr/bin/env python3
"""Generates the Bagh Chal brass board: mesh plus engraving textures.

The board is a cast brass plate with a raised rim. Everything engraved (the
56 playing lines, the point rings, the border band) lives in the textures, so
the lines always come from the rules' BoardDef (tools/art/boards.json, written
by tools/export_boards.gd) and never drift from where the pieces stand.

Outputs (titles/bagh_chal/art/board/):
  board.glb            plate mesh, top-projected UVs, y = 0 is the playing surface
  board_albedo.png     sRGB base color: brass, tarnish, blackened engraving fill
  board_orm.png        R occlusion, G roughness, B metallic
  board_normal.png     OpenGL-convention normal map (Godot's default)
  board_glow.png       where the "awakened" lines glow (lines only)

Run from the hunt-games root:
    python3 tools/art/make_board.py [--size 2048]
"""
from __future__ import annotations

import argparse
import json
import pathlib

import numpy as np
import trimesh
from PIL import Image
from scipy import ndimage

OUT = pathlib.Path("titles/bagh_chal/art/board")
BOARD_ID = "alquerque_5x5"

HALF = 2.7          # plate half-size (points span -2..2)
RIM_IN = 2.5        # inner edge of the raised rim
RIM_H = 0.032       # rim height above the playing surface
THICK = 0.11        # plate thickness below the playing surface
BAND = (2.18, 2.4)  # engraved border band (half-size range)


# --- Geometry ----------------------------------------------------------------
# The plate is a cross-section profile swept around the square, so every flat
# surface gets exactly flat normals (a decimated marching-cubes mesh smeared
# its edge normals across the playing field) and the mesh stays light.

def _arc(cx, cy, r, a0, a1, n, convex=True):
    """Points and outward normals along a quarter arc in the (r, y) plane."""
    out = []
    for k in range(n + 1):
        a = np.radians(a0 + (a1 - a0) * k / n)
        d = np.array([np.cos(a), np.sin(a)])
        out.append(((cx + r * d[0], cy + r * d[1]), d if convex else -d))
    return out


def profile():
    """(r, y) points from the edge of the playing field out to the rim and
    down to the bottom, with normals (nr, ny). r is distance from the center
    measured square-wise (Chebyshev)."""
    cove = 0.012
    top_r = 0.008
    outer_r = 0.02
    foot_r = 0.01
    pts = []
    pts += _arc(RIM_IN - cove, cove, cove, 270, 360, 4, convex=False)     # cove at the wall's foot
    pts += _arc(RIM_IN + top_r, RIM_H - top_r, top_r, 180, 90, 4)        # inner top edge
    pts += _arc(HALF - outer_r, RIM_H - outer_r, outer_r, 90, 0, 6)      # outer top edge
    pts += _arc(HALF - foot_r, -THICK + foot_r, foot_r, 0, -90, 3)       # bottom edge
    return pts


def build_mesh():
    prof = profile()
    sides = [((1, 0), (0, 1)), ((0, 1), (-1, 0)), ((-1, 0), (0, -1)), ((0, -1), (1, 0))]
    verts, norms, faces = [], [], []

    def add(x, y, z, n):
        verts.append((x, y, z))
        norms.append(n)
        return len(verts) - 1

    # Flat playing field: one quad, edges matching the swept profile (no T-junctions).
    r0 = prof[0][0][0]
    g = 1
    base = len(verts)
    for i in range(g + 1):
        for j in range(g + 1):
            add(-r0 + 2 * r0 * j / g, 0.0, -r0 + 2 * r0 * i / g, (0, 1, 0))
    for i in range(g):
        for j in range(g):
            a = base + i * (g + 1) + j
            faces += [(a, a + g + 1, a + 1), (a + 1, a + g + 1, a + g + 2)]
    # The profile swept round the four sides (mitered at the corners).
    for (dx, dz), (tx, tz) in sides:
        ring = []
        for (r, y), (nr, ny) in prof:
            n = (dx * nr, ny, dz * nr)
            ring.append((add(dx * r - tx * r, y, dz * r - tz * r, n), add(dx * r + tx * r, y, dz * r + tz * r, n)))
        for k in range(len(ring) - 1):
            a0, a1 = ring[k]
            b0, b1 = ring[k + 1]
            faces += [(a0, b0, a1), (a1, b0, b1)]
    # Bottom.
    rb = prof[-1][0][0]
    yb = prof[-1][0][1]
    c = [add(-rb, yb, -rb, (0, -1, 0)), add(rb, yb, -rb, (0, -1, 0)),
         add(rb, yb, rb, (0, -1, 0)), add(-rb, yb, rb, (0, -1, 0))]
    faces += [(c[0], c[1], c[2]), (c[0], c[2], c[3])]
    v = np.array(verts, np.float32)
    n = np.array(norms, np.float32)
    n /= np.linalg.norm(n, axis=1, keepdims=True)
    f = np.array(faces, np.int64)
    # Wind every triangle so its face normal agrees with the vertex normals.
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    flip = (fn * n[f].mean(axis=1)).sum(axis=1) < 0
    f[flip] = f[flip][:, ::-1]
    uv = np.stack([(v[:, 0] + HALF) / (2 * HALF), (v[:, 2] + HALF) / (2 * HALF)], axis=1)
    mesh = trimesh.Trimesh(v, f, vertex_normals=n, process=False)
    # UVs only: the game supplies the material (no placeholder image in the file).
    mesh.visual = trimesh.visual.TextureVisuals(
        uv=uv, material=trimesh.visual.material.PBRMaterial(baseColorFactor=[200, 150, 75, 255]))
    OUT.mkdir(parents=True, exist_ok=True)
    mesh.export(OUT / "board.glb")
    print(f"board.glb: {len(v)} verts, {len(f)} tris")


# --- Textures ----------------------------------------------------------------

def seg_dist(px, pz, a, b):
    ab = b - a
    t = np.clip(((px - a[0]) * ab[0] + (pz - a[1]) * ab[1]) / (ab @ ab), 0, 1)
    return np.hypot(px - (a[0] + t * ab[0]), pz - (a[1] + t * ab[1]))


def groove(d, half_width, depth):
    """V-groove profile with a soft floor."""
    g = np.clip(1.0 - d / half_width, 0.0, 1.0)
    return depth * np.sqrt(g)


def noise(shape, sigma, seed):
    rng = np.random.default_rng(seed)
    n = ndimage.gaussian_filter(rng.standard_normal(shape).astype(np.float32), sigma, mode="wrap")
    return n / (np.abs(n).max() + 1e-9)


def build_textures(size):
    board = json.loads(pathlib.Path("tools/art/boards.json").read_text())[BOARD_ID]
    pts = np.array([p["pos"] for p in board["points"]], np.float32)
    center = (pts.min(0) + pts.max(0)) / 2
    world = pts - center                                   # layout (x, row) -> world (x, z)
    corner = np.array(["corner" in p["tags"] for p in board["points"]])

    px_size = 2 * HALF / size
    coords = (np.arange(size, dtype=np.float32) + 0.5) * px_size - HALF
    X, Z = np.meshgrid(coords, coords)                     # row index -> z, column -> x
    height = np.zeros((size, size), np.float32)
    line_mask = np.zeros_like(height)
    fill = np.zeros_like(height)

    # Playing lines: the main engraving, filled dark so they read at a glance.
    for a, b in board["segments"]:
        d = seg_dist(X, Z, world[a], world[b])
        g = groove(d, 0.021, 1.0)
        line_mask = np.maximum(line_mask, g)
    height -= 0.006 * line_mask
    fill = np.maximum(fill, np.clip(line_mask * 1.6, 0, 1))

    # Points: a cup for the piece to sit in, ringed by a fine engraved circle.
    # The four corners (where the tigers start) get a second ring.
    for w, is_corner in zip(world, corner):
        r = np.hypot(X - w[0], Z - w[1])
        ring = groove(np.abs(r - 0.1), 0.007, 1.0)
        if is_corner:
            ring = np.maximum(ring, groove(np.abs(r - 0.135), 0.006, 1.0))
        cup = np.clip(1.0 - r / 0.05, 0, 1) ** 1.5
        height -= 0.003 * ring + 0.004 * cup
        fill = np.maximum(fill, np.clip(ring * 1.5, 0, 1))

    # Border band: two fillet lines with a running zigzag and dots between them.
    s = np.maximum(np.abs(X), np.abs(Z))
    band = np.zeros_like(height)
    for edge in BAND:
        band = np.maximum(band, groove(np.abs(s - edge), 0.008, 1.0))
    along = np.where(np.abs(X) > np.abs(Z), Z, X)          # coordinate along the side
    across = s - BAND[0]                                   # 0 .. band width
    width = BAND[1] - BAND[0]
    period = 0.2
    tri = np.abs(((along / period) % 1.0) * 2 - 1)         # 0..1 triangle wave
    target = 0.035 + (width - 0.07) * tri
    zig = groove(np.abs(across - target) * 0.75, 0.006, 1.0)
    in_band = (s > BAND[0] + 0.012) & (s < BAND[1] - 0.012) & (np.minimum(np.abs(X), np.abs(Z)) < BAND[0])
    band = np.maximum(band, zig * in_band)
    # Dots in the triangles the zigzag leaves: outer ones between its peaks,
    # inner ones between its valleys.
    for offset, frac in ((0.5, 0.72), (0.0, 0.28)):
        dot_along = (np.round(along / period - offset) + offset) * period
        dd = np.hypot(along - dot_along, across - frac * width)
        band = np.maximum(band, (np.clip(1 - dd / 0.016, 0, 1) ** 0.7) * in_band)
    # Corner blocks: a ring and dot where the band turns.
    for cx in (-1, 1):
        for cz in (-1, 1):
            c = np.array([cx, cz], np.float32) * (BAND[0] + width / 2)
            r = np.hypot(X - c[0], Z - c[1])
            band = np.maximum(band, groove(np.abs(r - 0.075), 0.007, 1.0))
            band = np.maximum(band, np.clip(1 - r / 0.025, 0, 1) ** 0.7)
    height -= 0.003 * band
    fill = np.maximum(fill, np.clip(band * 1.4, 0, 1))

    # Hand-finished surface: planishing undulation and fine scratches.
    height += 0.0006 * noise(height.shape, size / 160, 1) + 0.00025 * noise(height.shape, size / 600, 2)
    scratches = ndimage.gaussian_filter(np.random.default_rng(3).standard_normal(height.shape), (0.6, 14))
    height += 0.00008 * scratches / np.abs(scratches).max()

    # Tarnish: darker, rougher patches, more toward the rim and in recesses.
    tarnish = np.clip(0.5 + 0.9 * noise(height.shape, size / 40, 4) + 0.4 * noise(height.shape, size / 12, 5), 0, 1)
    tarnish = np.clip(tarnish * 0.55 + 0.35 * np.clip((s - 1.6) / 1.0, 0, 1), 0, 1)
    rim = s > RIM_IN - 0.02

    # Occlusion from the height field (cavity).
    blur = ndimage.gaussian_filter(height, size / 600)
    cavity = np.clip((blur - height) / 0.004, 0, 1)
    ao = np.clip(1.0 - 0.6 * cavity - 0.5 * fill, 0.25, 1.0)

    brass = np.array([0.78, 0.57, 0.27], np.float32)
    dark_brass = np.array([0.42, 0.29, 0.13], np.float32)
    niello = np.array([0.055, 0.045, 0.035], np.float32)
    albedo = brass * (1 - 0.35 * tarnish[..., None]) + dark_brass * (0.35 * tarnish[..., None])
    albedo = albedo * (1 - fill[..., None]) + niello * fill[..., None]
    rough = 0.3 + 0.18 * tarnish + 0.5 * fill
    rough = np.where(rim, rough * 0.8, rough)
    metal = 1.0 - 0.85 * fill

    # Normal map (OpenGL convention: green = up in the image).
    gz, gx = np.gradient(height, px_size)
    nx, ny = -gx, gz
    nz = np.ones_like(nx)
    nl = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / nl, ny / nl, nz / nl], axis=-1) * 0.5 + 0.5

    def save(name, arr, mode="RGB"):
        img = Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), mode)
        img.save(OUT / name, optimize=True)
        print(f"{name}: {img.size}")

    OUT.mkdir(parents=True, exist_ok=True)
    save("board_albedo.png", albedo)                     # colors above are sRGB
    save("board_orm.png", np.stack([ao, rough, metal], axis=-1))
    save("board_normal.png", normal)
    save("board_glow.png", np.clip(line_mask * 1.3, 0, 1), "L")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=2048)
    ap.add_argument("--no-mesh", action="store_true")
    args = ap.parse_args()
    if not args.no_mesh:
        build_mesh()
    build_textures(args.size)


if __name__ == "__main__":
    main()
