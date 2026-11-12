#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Twarge LLC
# SPDX-License-Identifier: Apache-2.0
"""Writes the app icon as an Icon Composer bundle.

    python3 Scripts/make-app-icon.py

The output is Resources/AppIcon.icon: icon.json plus one SVG per layer. The
iOS/macOS app and the watch app both compile it. Xcode's asset compiler turns
it into every size each platform needs and applies the system shape (rounded
square, or circle on the watch) and the glass, dark and tinted treatments, so
the artwork here is full bleed and carries no mask, rim or shadow of its own.

The picture is the original Geomagnetic icon's chart, split into layers from
back to front: a night-blue background with a faint grid (Grid), a magnetogram
running from edge to edge through three reconnection episodes (Glow under
Trace), and a reading marked on it (Dot). The original's rim, which followed
each platform's icon shape, is left out.

The bundle is committed, so this only needs running when the design changes.
To look at the result without building:

    "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \\
        Resources/AppIcon.icon --export-image --output-file icon.png \\
        --platform watchOS --rendition Default --width 512 --height 512 --scale 2
"""
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources", "AppIcon.icon")

SIZE = 1024
# The watch draws the same layers centred on a 1088 point canvas, so artwork
# that should reach the edge of the circle has to overhang the square by this.
BLEED = 32

# Colours.
# The chart background, top and bottom. In the dark appearance the system
# would swap it for its own charcoal; SKY_DARK keeps it blue, a step deeper.
SKY = [(0.06, 0.18, 0.36), (0.02, 0.04, 0.09)]
SKY_DARK = [(0.035, 0.105, 0.225), (0.01, 0.02, 0.055)]
GRID = "#9EC2FF"      # grid lines, drawn faint
GRID_OPACITY = 0.12
GLOW = "#4DB8FF"      # halo around the trace
GLOW_OPACITY = 0.45
TRACE = "#DEF5FF"     # the trace itself
DOT = "#FFFFFF"       # the marked reading

# Geometry, on the 1024 x 1024 canvas with y downward.
GRID_COLS, GRID_ROWS = 8, 6
GRID_WIDTH = 4
GLOW_WIDTH = 51
TRACE_WIDTH = 22.5
DOT_RADIUS = 27

# The trace: three reconnection episodes (substorms) as a ground observatory
# records them. At each onset the ionospheric electrojet switches on and the
# horizontal field drops within minutes, rings briefly, then recovers slowly.
QUIET = 292           # y of the undisturbed field
# One row per episode: x of the onset, depth of the drop, length of the recovery.
EPISODES = [(140, 300, 105), (440, 425, 125), (735, 345, 115)]
GROWTH = 0.14         # share of the depth lost slowly before the onset
ONSET = 34            # how far the trace travels in x during the drop
DOT_X = 884           # where the reading marker rides the trace
STEP = 2.5            # x spacing of the trace's points


def field(x):
    """The trace's y at canvas x."""
    y = QUIET
    for onset, depth, recovery in EPISODES:
        u = x - onset
        if u < 0:
            y += depth * GROWTH * math.exp(u / 80)
        elif u < ONSET:
            s = u / ONSET
            y += depth * (GROWTH + (1 - GROWTH) * s * s * (3 - 2 * s))
        else:
            v = u - ONSET
            y += depth * (math.exp(-v / recovery)
                          + 0.11 * math.exp(-v / 55) * math.sin(2 * math.pi * v / 42))
    # The restless fine structure every magnetogram has.
    return y + 9 * math.sin(2 * math.pi * x / 58 + 1.2) + 5 * math.sin(2 * math.pi * x / 29 + 0.3)


def trace_points():
    # From beyond one edge to beyond the other, so no end shows in the square
    # or in the watch's circle.
    lo, hi = -BLEED - GLOW_WIDTH, SIZE + BLEED + GLOW_WIDTH
    n = int(round((hi - lo) / STEP))
    return [(x, field(x)) for x in (lo + (hi - lo) * i / n for i in range(n + 1))]


def svg(body, bleed=0):
    side = SIZE + 2 * bleed
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%d %d %d %d">\n'
            % (side, side, -bleed, -bleed, side, side) + "".join("  %s\n" % line for line in body) + "</svg>\n")


def grid():
    lo, hi = -BLEED, SIZE + BLEED
    d = []
    for i in range(1, GRID_COLS):
        d.append("M%g,%dV%d" % (SIZE * i / GRID_COLS, lo, hi))
    for j in range(1, GRID_ROWS):
        d.append("M%d,%.1fH%d" % (lo, SIZE * j / GRID_ROWS, hi))
    return ['<path d="%s" fill="none" stroke="%s" stroke-opacity="%g" stroke-width="%g"/>'
            % ("".join(d), GRID, GRID_OPACITY, GRID_WIDTH)]


def trace(color, width, opacity=None):
    pts = trace_points()
    d = "M%.1f,%.1f" % pts[0] + "".join("L%.1f,%.1f" % p for p in pts[1:])
    extra = "" if opacity is None else ' stroke-opacity="%g"' % opacity
    return ['<path d="%s" fill="none" stroke="%s"%s stroke-width="%g" '
            'stroke-linecap="round" stroke-linejoin="round"/>' % (d, color, extra, width)]


def dot():
    return ['<circle cx="%.1f" cy="%.1f" r="%g" fill="%s"/>' % (DOT_X, field(DOT_X), DOT_RADIUS, DOT)]


# Layers from front to back, the order icon.json lists them: name, artwork,
# overhang, glass, shadow opacity. The chart stays flat (no glass on the grid
# or the halo); the trace and the dot are the glass pieces.
LAYERS = [
    ("Dot", dot(), 0, True, 0.5),
    ("Trace", trace(TRACE, TRACE_WIDTH), BLEED, True, 0.5),
    ("Glow", trace(GLOW, GLOW_WIDTH, GLOW_OPACITY), BLEED, False, 0.0),
    ("Grid", grid(), BLEED, False, 0.0),
]


def gradient(stops):
    return {"linear-gradient": ["extended-srgb:%.5f,%.5f,%.5f,1.00000" % rgb for rgb in stops]}


def main():
    os.makedirs(os.path.join(OUT, "Assets"), exist_ok=True)
    groups = []
    for name, body, bleed, glass, shadow in LAYERS:
        with open(os.path.join(OUT, "Assets", name + ".svg"), "w") as f:
            f.write(svg(body, bleed))
        layer = {"image-name": name + ".svg", "name": name}
        if not glass:
            layer["glass"] = False
        groups.append({
            "layers": [layer],
            "shadow": {"kind": "neutral", "opacity": shadow},
            "translucency": {"enabled": False, "value": 0.5},
        })
    doc = {
        "fill-specializations": [{"value": gradient(SKY)},
                                 {"appearance": "dark", "value": gradient(SKY_DARK)}],
        "groups": groups,
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    with open(os.path.join(OUT, "icon.json"), "w") as f:
        json.dump(doc, f, indent=2, sort_keys=True)
        f.write("\n")
    print("wrote", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
