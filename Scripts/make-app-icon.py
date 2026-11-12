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

The picture is the original Geomagnetic icon, split into layers from back to
front: a night-blue chart with a faint grid (Grid), a couple of days of field
variation (Glow under Trace), and the latest reading (Dot). The original's rim,
which followed each platform's icon shape, is left out.

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
DOT = "#FFFFFF"       # latest reading

# Geometry, on the 1024 x 1024 canvas with y downward.
GRID_COLS, GRID_ROWS = 8, 6
GRID_WIDTH = 4
PLOT_INSET_X, PLOT_INSET_Y = 0.13, 0.22   # the trace's box, as fractions of the canvas
SAMPLES = 260
GLOW_WIDTH = 51
TRACE_WIDTH = 22.5
DOT_RADIUS = 27


def variation(t):
    """A couple of days of plausible field variation: two diurnal cycles plus ripples."""
    return (0.55 * math.sin(2 * math.pi * 2 * t - math.pi / 2)
            + 0.17 * math.sin(2 * math.pi * 5 * t + 0.6)
            + 0.10 * math.sin(2 * math.pi * 13 * t + 1.2)
            + 0.05 * math.sin(2 * math.pi * 27 * t + 0.3))


def trace_points():
    left = SIZE * PLOT_INSET_X
    width = SIZE * (1 - 2 * PLOT_INSET_X)
    half = SIZE * (1 - 2 * PLOT_INSET_Y) / 2
    return [(left + width * i / SAMPLES, SIZE / 2 - half * variation(i / SAMPLES))
            for i in range(SAMPLES + 1)]


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
    x, y = trace_points()[-1]
    return ['<circle cx="%.1f" cy="%.1f" r="%g" fill="%s"/>' % (x, y, DOT_RADIUS, DOT)]


# Layers from front to back, the order icon.json lists them: name, artwork,
# overhang, glass, shadow opacity. The chart stays flat (no glass on the grid
# or the halo); the trace and the dot are the glass pieces.
LAYERS = [
    ("Dot", dot(), 0, True, 0.5),
    ("Trace", trace(TRACE, TRACE_WIDTH), 0, True, 0.5),
    ("Glow", trace(GLOW, GLOW_WIDTH, GLOW_OPACITY), 0, False, 0.0),
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
