#!/usr/bin/env python3
"""Generates the Bagh Chal "Stone and pebbles" style (the historical look).

How the game has been played in Nepal (sources in the dev handoff): the board
scratched into the ground or chalked on a smooth surface (or carved into the
floor of a rest house), larger stones for the tigers and small pebbles for
the goats. Brass sets are a later craft, mostly made for visitors.

So this style is a dressed stone slab with the grid cut in and rubbed with
chalk, four large dark river stones and twenty small pale pebbles, on a
straw mat (sukul) bound with straw rope.

Outputs (titles/bagh_chal/art/stone/):
  board.glb                   the slab: playing surface at y = 0, uneven edge
  board_albedo.png            sRGB: weathered stone, chalk in the scratches
  board_orm.png               R occlusion, G roughness, B metallic (0)
  board_normal.png            OpenGL-convention normal map
  board_glow.png              the scratched lines, for the "awakening" glow
  side_albedo/orm/normal.png  tileable split-face stone for the slab's sides
  mat_albedo/orm/normal.png   tileable straw mat, one unit square
  rope_albedo/normal.png      the twisted rope round the mat's edge
  tiger_0..3.glb              river stones, one per tiger
  goat_0..7.glb               pebbles, cycled across the twenty goats

Vertex colors on the stones (as for the brass pieces):
  R ambient occlusion   G a quartz vein (off: it read as a seam)   B edge wear

Run from the hunt-games root (after tools/export_boards.gd):
    python3 tools/art/make_stone_set.py [--stones-only | --board-only | --mat-only]
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


def wrapped_noise_1d(n, sigma, seed):
    rng = np.random.default_rng(seed)
    a = ndimage.gaussian_filter1d(rng.standard_normal(n), sigma, mode="wrap")
    return (a / (np.abs(a).max() + 1e-9)).astype(np.float32)


def build_board_mesh(rings=24, n=512, side_rows=14):
    """The slab, in three parts that meet at hard edges:
    - the face: a polar grid out to a hand-dressed arris (normals straight up;
      the texture's normal map does the rest)
    - the edge: an irregular chamfer, then a split-face side that bulges and
      dips a little along its length and height, slightly wider at the foot
    - the underside: a flat fan (never seen)."""
    out = outline_polygon(n)
    tang = np.roll(out, -1, axis=0) - np.roll(out, 1, axis=0)
    onrm = np.stack([tang[:, 1], -tang[:, 0]], axis=1)
    onrm /= np.linalg.norm(onrm, axis=1, keepdims=True)
    if (onrm * out).sum() < 0:
        onrm = -onrm
    chamfer = (0.012 + 0.012 * (wrapped_noise_1d(n, 8, 11) * 0.5 + 0.5)
               + 0.014 * np.clip(wrapped_noise_1d(n, 2.5, 12), 0, 1) ** 2)
    inset = out - onrm * chamfer[:, None]

    parts = []   # (verts, normals or None, faces)

    # Face.
    verts = [(0.0, float(undulate(0.0, 0.0)), 0.0)]
    rings_ids = []
    for k in range(1, rings + 1):
        f = (k / rings) ** 0.8
        ids = []
        for i in range(n):
            x, z = inset[i] * f
            ids.append(len(verts))
            verts.append((x, float(undulate(x, z)), z))
        rings_ids.append(ids)
    faces = [(0, rings_ids[0][(i + 1) % n], rings_ids[0][i]) for i in range(n)]
    for a, b in zip(rings_ids[:-1], rings_ids[1:]):
        for i in range(n):
            j = (i + 1) % n
            faces += [(a[i], a[j], b[i]), (a[j], b[j], b[i])]
    v = np.array(verts, np.float32)
    parts.append((v, np.tile(np.array([[0, 1, 0]], np.float32), (len(v), 1)), np.array(faces), "up"))

    # Edge: chamfer row, then the split face.
    bulge = smooth_noise((side_rows * 4, n), (3, 6), 21)[::4]           # rows x perimeter
    fine = smooth_noise((side_rows * 4, n), (1, 1.5), 22)[::4]
    rows = [np.stack([inset[:, 0], undulate(inset[:, 0], inset[:, 1]), inset[:, 1]], axis=1)]
    top_y = -0.75 * chamfer
    for r in range(side_rows):
        t = r / (side_rows - 1)
        y = top_y + (-THICK - top_y) * t
        off = 0.014 * bulge[r] + 0.004 * fine[r] + 0.01 * t
        xz = out + onrm * off[:, None]
        rows.append(np.stack([xz[:, 0], y + undulate(out[:, 0], out[:, 1]) * (1 - t), xz[:, 1]], axis=1))
    v = np.concatenate(rows).astype(np.float32)
    faces = []
    for r in range(len(rows) - 1):
        a0, b0 = r * n, (r + 1) * n
        for i in range(n):
            j = (i + 1) % n
            faces += [(a0 + i, a0 + j, b0 + i), (a0 + j, b0 + j, b0 + i)]
    faces = np.array(faces)
    fn = np.cross(v[faces[:, 1]] - v[faces[:, 0]], v[faces[:, 2]] - v[faces[:, 0]])
    outward = np.concatenate([onrm[faces[:, 0] % n][:, 0:1], np.zeros((len(faces), 1)), onrm[faces[:, 0] % n][:, 1:2]], axis=1)
    if (fn * outward).sum() < 0:
        faces = faces[:, ::-1]
    parts.append((v, None, faces, "side"))

    # Underside.
    bottom = rows[-1]
    v = np.concatenate([np.array([[0, -THICK, 0]], np.float32), bottom]).astype(np.float32)
    faces = np.array([(0, 1 + i, 1 + (i + 1) % n) for i in range(n)])
    parts.append((v, np.tile(np.array([[0, -1, 0]], np.float32), (len(v), 1)), faces, "down"))

    all_v, all_n, all_f = [], [], []
    base = 0
    for v, nm, f, kind in parts:
        fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
        if kind == "up" and (fn[:, 1] < 0).mean() > 0.5:
            f = f[:, ::-1]
        if kind == "down" and (fn[:, 1] > 0).mean() > 0.5:
            f = f[:, ::-1]
        if nm is None:
            nm = trimesh.Trimesh(v, f, process=False).vertex_normals.astype(np.float32)
        all_v.append(v)
        all_n.append(nm)
        all_f.append(f + base)
        base += len(v)
    v = np.concatenate(all_v)
    nm = np.concatenate(all_n)
    f = np.concatenate(all_f)
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



def save_png(name, arr, mode="RGB"):
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), mode).save(OUT / name, optimize=True)
    print(f"stone/{name}")


def normals_from_height(height, px, strength=1.0):
    gz, gx = np.gradient(height * strength, px)
    nx, ny, nz = -gx, gz, np.ones_like(gx)
    nl = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / nl, ny / nl, nz / nl], axis=-1) * 0.5 + 0.5


def stone_body(shape, seed, px):
    """Height and albedo of the bare stone: a fine-grained sandstone, grey
    with warm and cool patches, mineral flecks, pecked tool marks and pits."""
    rng = np.random.default_rng(seed)
    h, w = shape
    grain = (0.55 * smooth_noise(shape, 0.7, seed + 1) + 0.3 * smooth_noise(shape, 2.0, seed + 2)
             + 0.15 * smooth_noise(shape, 6.0, seed + 3))
    height = 0.0011 * grain + 0.0016 * smooth_noise(shape, w / 25, seed + 4)
    # Pecked tool marks: many small shallow dints from dressing the face.
    dints = np.zeros(shape, np.float32)
    for _ in range(int(h * w / 2600)):
        cy, cx = rng.integers(0, h), rng.integers(0, w)
        rad = rng.uniform(2.0, 6.0)
        rr = int(rad) + 2
        ys, xs = np.ogrid[-rr:rr + 1, -rr:rr + 1]
        blob = np.clip(1 - np.hypot(ys, xs * rng.uniform(0.6, 1.0)) / rad, 0, 1) ** 1.5
        yy = (np.arange(cy - rr, cy + rr + 1) % h)[:, None]
        xx = (np.arange(cx - rr, cx + rr + 1) % w)[None, :]
        dints[yy, xx] = np.maximum(dints[yy, xx], blob * rng.uniform(0.3, 1.0))
    height -= 0.0014 * dints
    # Larger weathered pits.
    pits = np.zeros(shape, np.float32)
    for _ in range(int(h * w / 30000)):
        cy, cx = rng.integers(0, h), rng.integers(0, w)
        rad = rng.uniform(3.0, 11.0)
        rr = int(rad) + 2
        ys, xs = np.ogrid[-rr:rr + 1, -rr:rr + 1]
        blob = np.clip(1 - np.hypot(ys, xs) / rad, 0, 1) ** 0.7
        yy = (np.arange(cy - rr, cy + rr + 1) % h)[:, None]
        xx = (np.arange(cx - rr, cx + rr + 1) % w)[None, :]
        pits[yy, xx] = np.maximum(pits[yy, xx], blob)
    height -= 0.002 * pits
    # Color: grey sandstone with warm (iron) and cool patches, and flecks.
    patch_warm = np.clip(smooth_noise(shape, w / 14, seed + 5) * 1.4, 0, 1)
    patch_cool = np.clip(-smooth_noise(shape, w / 10, seed + 6) * 1.2, 0, 1)
    base = np.array([0.43, 0.41, 0.38], np.float32)
    warm = np.array([0.52, 0.44, 0.35], np.float32)
    cool = np.array([0.36, 0.38, 0.38], np.float32)
    albedo = base + (warm - base) * patch_warm[..., None] * 0.9 + (cool - base) * patch_cool[..., None] * 0.8
    albedo = albedo * (0.9 + 0.2 * grain[..., None])
    fleck = rng.random(shape)
    dark = (fleck < 0.0025).astype(np.float32)
    light = ((fleck > 0.9992)).astype(np.float32)
    dark = np.clip(ndimage.gaussian_filter(dark, 0.7) * 2.5, 0, 1)
    light = np.clip(ndimage.gaussian_filter(light, 0.7) * 2.5, 0, 1)
    albedo = albedo * (1 - 0.35 * dark[..., None]) + np.array([0.78, 0.76, 0.7], np.float32) * 0.25 * light[..., None]
    # Faint bedding: the layers the stone was split along.
    bedding = smooth_noise(shape, (w / 9, w / 120), seed + 7)
    albedo = albedo * (1 + 0.06 * bedding[..., None])
    return height, albedo, pits, dints


def build_textures(size=2048):
    board = json.loads(pathlib.Path("tools/art/boards.json").read_text())[BOARD_ID]
    pts = np.array([p["pos"] for p in board["points"]], np.float32)
    world = pts - (pts.min(0) + pts.max(0)) / 2

    px = 2 * UV_HALF / size
    coords = (np.arange(size, dtype=np.float32) + 0.5) * px - UV_HALF
    X, Z = np.meshgrid(coords, coords)
    height, albedo, pits, dints = stone_body(X.shape, 300, px)

    # The grid: V-shaped grooves cut in two or three strokes, chipped along
    # their lips, then rubbed with chalk that has partly worn away.
    groove = np.zeros_like(height)
    for i, (a, b) in enumerate(board["segments"]):
        d, w = scratched_line(X, Z, world[a], world[b], 100 + i)
        groove = np.maximum(groove, np.clip(1 - d / (w * 1.25), 0, 1))
    rng = np.random.default_rng(31)
    spall = np.zeros_like(height)
    lip = (groove > 0.02) & (groove < 0.5)
    ys, xs = np.nonzero(lip)
    pick = rng.choice(len(ys), size=min(len(ys), 2600), replace=False)
    for k in pick:
        rad = rng.uniform(1.5, 4.5)
        rr = int(rad) + 1
        y0, x0 = ys[k], xs[k]
        yy, xx = np.ogrid[max(0, y0 - rr):y0 + rr + 1, max(0, x0 - rr):x0 + rr + 1]
        blob = np.clip(1 - np.hypot(yy - y0, xx - x0) / rad, 0, 1)
        spall[yy, xx] = np.maximum(spall[yy, xx], blob)
    height -= 0.0075 * groove + 0.0018 * spall
    # Shallow cups pecked at the points, worn by stones set down on them.
    cups = np.zeros_like(height)
    for p in world:
        r = np.hypot(X - p[0], Z - p[1])
        cups = np.maximum(cups, np.clip(1 - (r / 0.075) ** 2, 0, 1))
    height -= 0.003 * cups
    # A hairline crack across one corner.
    crack = np.zeros_like(height)
    t = np.linspace(0, 1, 400)
    cx = -2.6 + 1.5 * t + 0.05 * np.sin(t * 17) + 0.02 * np.sin(t * 53)
    cz = 1.2 + 1.5 * t + 0.04 * np.sin(t * 23 + 1)
    for x0, z0 in zip(cx, cz):
        i0, j0 = int((z0 + UV_HALF) / px), int((x0 + UV_HALF) / px)
        crack[max(0, i0 - 2):i0 + 3, max(0, j0 - 2):j0 + 3] = 1
    crack = ndimage.gaussian_filter(crack, 0.8)
    height -= 0.002 * crack

    chalk_cover = np.clip(0.55 + 0.6 * smooth_noise(height.shape, 4, 6) + 0.35 * smooth_noise(height.shape, 40, 8), 0, 1)
    core = np.clip((groove - 0.35) / 0.4, 0, 1)                   # the bottom of the cut
    chalk = core ** 0.7 * chalk_cover
    smear = np.clip(ndimage.gaussian_filter(groove, 2.5) * 0.5 * np.clip(smooth_noise(height.shape, 12, 9) + 0.2, 0, 1), 0, 0.2)

    d_edge = outline_distance(X, Z)
    weather = np.clip((d_edge + 0.45) / 0.45, 0, 1)            # darker toward the edge
    worn = np.clip(1 - np.hypot(X, Z) / 2.4, 0, 1) ** 1.3       # hands polish the middle
    blur = ndimage.gaussian_filter(height, 6)
    cavity = np.clip((blur - height) / 0.004, 0, 1)
    grime = np.clip(cavity * 0.6 + pits * 0.2 + crack * 0.6 + groove * (1 - chalk) * 0.6, 0, 1)

    albedo = albedo * (1 - 0.22 * weather[..., None]) * (1 + 0.07 * worn[..., None])
    albedo = albedo * (1 - 0.45 * grime[..., None])
    chalk_col = np.array([0.88, 0.86, 0.8], np.float32)
    albedo = albedo + (chalk_col - albedo) * smear[..., None]
    albedo = albedo * (1 - chalk[..., None]) + chalk_col * chalk[..., None]

    ao = np.clip(1 - 0.55 * cavity - 0.3 * groove * (1 - chalk), 0.25, 1)
    rough = np.clip(0.86 - 0.18 * worn + 0.08 * chalk + 0.05 * grime, 0, 1)
    OUT.mkdir(parents=True, exist_ok=True)
    save_png("board_albedo.png", albedo)
    save_png("board_orm.png", np.stack([ao, rough, np.zeros_like(rough)], axis=-1))
    save_png("board_normal.png", normals_from_height(height, px, 1.6))
    save_png("board_glow.png", np.clip(groove * 1.5, 0, 1) * np.clip(chalk_cover + 0.3, 0, 1), "L")


def build_side_textures(size=512, span=1.0):
    """Tileable split-face stone for the slab's sides (mapped triplanar by
    the shader): rougher and a little darker than the dressed face."""
    px = span / size
    height, albedo, pits, dints = stone_body((size, size), 700, px)
    ridges = smooth_noise((size, size), (size / 30, size / 5), 701)      # bedding, along the side
    facets = smooth_noise((size, size), size / 18, 702)                  # broad split-face facets
    height += 0.005 * ridges + 0.008 * facets
    blur = ndimage.gaussian_filter(height, 4, mode="wrap")
    cavity = np.clip((blur - height) / 0.004, 0, 1)
    albedo = albedo * 0.86 * (1 - 0.35 * cavity[..., None])
    ao = np.clip(1 - 0.5 * cavity, 0.3, 1)
    rough = np.full_like(ao, 0.92)
    save_png("side_albedo.png", albedo)
    save_png("side_orm.png", np.stack([ao, rough, np.zeros_like(rough)], axis=-1))
    save_png("side_normal.png", normals_from_height(height, px, 0.7))


# --- The straw mat -----------------------------------------------------------

def build_mat_textures(size=1024, span=1.0):
    """A tileable patch of straw mat (sukul), `span` units square: straws laid
    side by side along U, bound across once per tile by a twisted pair of
    straw cords. Baked (with mipmaps) rather than drawn in a shader, so it
    stays smooth at a distance instead of shimmering."""
    rng = np.random.default_rng(55)
    px = span / size
    v = (np.arange(size) + 0.5) * px
    u = (np.arange(size) + 0.5) * px
    U, V = np.meshgrid(u, v)
    # Straw rows across V: widths that add up to exactly one span.
    widths = []
    while sum(widths) < span:
        widths.append(rng.uniform(0.034, 0.05))
    widths = np.array(widths) * span / sum(widths)
    edges = np.concatenate([[0], np.cumsum(widths)])
    row = np.clip(np.searchsorted(edges, v, side="right") - 1, 0, len(widths) - 1)
    across = (v - edges[row]) / widths[row]                       # 0..1 over a straw
    across2 = across[:, None] * np.ones((1, size))
    rowg = row[:, None] * np.ones((1, size), np.int64)
    roundness = np.sqrt(np.clip(1 - (across2 * 2 - 1) ** 2, 0, 1))
    gap = np.clip(1 - np.minimum(across2, 1 - across2) / 0.09, 0, 1)
    # Per straw: color, and where its joints (nodes) fall.
    palette = np.array([[0.78, 0.65, 0.42], [0.82, 0.70, 0.47], [0.73, 0.59, 0.37],
                        [0.77, 0.66, 0.44], [0.80, 0.66, 0.41]], np.float32)
    straw_col = palette[rng.integers(0, len(palette), len(widths))] * rng.uniform(0.95, 1.04, (len(widths), 1))
    col = straw_col[rowg]
    phase = rng.uniform(0, 1, len(widths))[rowg]
    period = rng.uniform(0.28, 0.5, len(widths))[rowg]
    # Joints repeat a whole number of times per span, so the tile wraps.
    period = span / np.maximum(1, np.round(span / period))
    node_t = np.mod(U / period + phase, 1.0)
    node = np.exp(-((np.minimum(node_t, 1 - node_t)) / 0.012) ** 2)
    fibers = smooth_noise((size, size), (0.6, 40), 56)                # streaks along each straw
    blotch = smooth_noise((size, size), (60, 200), 58)                 # weathering, sun, use
    height = 0.006 * roundness - 0.004 * gap + 0.0008 * node + 0.0006 * fibers
    albedo = col * (0.84 + 0.16 * roundness[..., None]) * (1 + 0.12 * fibers[..., None]) * (1 + 0.06 * blotch[..., None])
    albedo = albedo * (1 - 0.1 * node[..., None]) * (1 - 0.5 * gap[..., None])
    # Binding cords at u = 0.25 and 0.75: two strands twisted together.
    cord = np.zeros((size, size), np.float32)
    cord_h = np.zeros_like(cord)
    for c in (0.5,):
        for side, off in ((-1, -0.017), (1, 0.017)):
            du = U - (c + off)
            twist = np.mod(V / (span / 34) + side * du / 0.03 * 0.5 + (0.5 if side > 0 else 0), 1.0)
            ply = np.sqrt(np.clip(1 - (2 * twist - 1) ** 2, 0, 1))
            within = np.clip(1 - np.abs(du) / 0.017, 0, 1)
            m = (within > 0).astype(np.float32)
            cord = np.maximum(cord, m * np.clip(within * 3, 0, 1))
            cord_h = np.maximum(cord_h, m * (0.008 * np.sqrt(within) * (0.6 + 0.4 * ply)))
    shade_near = np.clip(ndimage.gaussian_filter(cord, (0, 6), mode="wrap") * 1.4 - cord, 0, 1)
    height = np.where(cord > 0.01, np.maximum(height, cord_h), height - 0.002 * shade_near)
    cord_col = np.array([0.6, 0.47, 0.28], np.float32) * (0.75 + 0.25 * (cord_h / 0.008))[..., None]
    albedo = albedo * (1 - 0.35 * shade_near[..., None])
    albedo = albedo * (1 - cord[..., None]) + cord_col * cord[..., None]
    ao = np.clip(1 - 0.5 * gap - 0.35 * shade_near, 0.3, 1)
    rough = np.clip(0.62 + 0.2 * gap + 0.15 * cord, 0, 1)
    save_png("mat_albedo.png", albedo)
    save_png("mat_orm.png", np.stack([ao, rough, np.zeros_like(rough)], axis=-1))
    save_png("mat_normal.png", normals_from_height(height, px, 1.0))
    # The rope that binds the mat's edge: a tileable strip, length along U.
    w, h = 512, 128
    uu = (np.arange(w) + 0.5) / w
    vv = (np.arange(h) + 0.5) / h
    UU, VV = np.meshgrid(uu, vv)
    strands = 3
    t = np.mod(UU * 8 + VV, 1.0)               # 8 twists per tile; seamless round the rope
    ply = np.mod(t * strands, 1.0)
    bump = np.sqrt(np.clip(1 - (2 * ply - 1) ** 2, 0, 1))
    fib = smooth_noise((h, w), (0.5, 6), 57)
    rope_h = 0.5 * bump + 0.05 * fib
    rope_col = np.array([0.56, 0.42, 0.23], np.float32) * (0.7 + 0.3 * bump[..., None]) * (1 + 0.08 * fib[..., None])
    save_png("rope_albedo.png", rope_col)
    save_png("rope_normal.png", normals_from_height(rope_h, 1.0 / 128, 0.06))


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
    if "--mat-only" in sys.argv:
        build_mat_textures()
        return
    if not only_stones:
        build_board_mesh()
        build_textures()
        build_side_textures()
        build_mat_textures()
        if "--board-only" in sys.argv:
            return
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
