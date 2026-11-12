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
back to front: a night-blue background with a faint grid (Grid), a recorded
magnetogram of three reconnection episodes running from edge to edge (Glow
under Trace), and its lowest reading marked (Dot). The original's rim, which
followed each platform's icon shape, is left out.

The bundle is committed, so this only needs running when the design changes.
To look at the result without building:

    "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \\
        Resources/AppIcon.icon --export-image --output-file icon.png \\
        --platform watchOS --rendition Default --width 512 --height 512 --scale 2
"""
import json
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
DOT = "#FFFFFF"       # the marked lowest reading

# Geometry, on the 1024 x 1024 canvas with y downward.
GRID_COLS, GRID_ROWS = 8, 6
GRID_WIDTH = 4
GLOW_WIDTH = 51
TRACE_WIDTH = 22.5
DOT_RADIUS = 27

# The trace: a recorded magnetogram of three reconnection episodes, each a
# sharp drop in the field and a slower recovery. The points were traced from
# a screenshot of the chart and are in that screenshot's pixels (it was
# RECORD_WIDTH wide, y downward).
RECORD_WIDTH = 990
RECORD = [
    (0, 133), (3, 124), (16, 150), (23, 128), (26, 141), (29, 132), (38, 150), (45, 155),
    (52, 152), (56, 146), (60, 143), (65, 138), (68, 141), (73, 122), (75, 119), (78, 126),
    (84, 121), (92, 108), (96, 115), (100, 106), (103, 114), (110, 105), (115, 99), (117, 113),
    (119, 111), (122, 118), (125, 134), (128, 121), (136, 99), (139, 99), (145, 121),
    # First episode.
    (153, 200), (158, 260), (163, 315), (168, 355), (172, 388), (178, 427), (181, 392),
    (185, 365), (189, 340), (193, 308), (198, 313), (205, 292), (207, 299), (211, 260),
    (216, 213), (221, 190), (226, 172), (229, 160), (237, 175), (244, 174), (252, 156),
    (257, 128), (260, 112), (262, 108),
    (267, 123), (275, 122), (276, 112), (281, 121), (290, 103), (294, 110), (298, 105),
    (305, 125), (308, 123), (314, 135), (319, 130), (325, 137), (329, 139), (334, 132),
    (338, 149), (347, 145), (352, 129), (358, 132), (366, 125), (370, 120), (375, 113),
    (378, 115), (383, 103), (386, 103), (391, 91), (396, 90), (403, 103), (408, 106),
    (411, 99), (415, 100), (420, 111), (424, 123), (430, 135), (432, 142),
    # Second episode.
    (438, 168), (442, 195), (447, 235), (448, 212), (452, 250), (456, 286), (458, 288),
    (466, 313), (470, 350), (475, 395), (479, 422), (483, 447), (486, 455), (491, 476),
    (494, 463), (498, 430), (501, 402), (510, 355), (514, 315), (519, 270), (523, 245),
    (528, 220), (532, 198), (536, 178), (538, 176), (545, 153), (548, 158), (554, 128),
    (558, 120), (565, 103),
    (571, 116), (579, 108), (585, 111), (592, 123), (597, 134), (601, 129), (607, 145),
    (613, 128), (615, 141), (620, 128), (624, 116), (629, 117), (635, 127), (640, 129),
    (644, 123), (647, 134), (653, 129), (657, 137), (665, 137), (670, 127), (675, 112),
    (679, 98), (684, 98), (688, 91), (690, 95), (694, 87), (700, 95), (704, 75), (707, 84),
    (715, 100), (719, 100), (723, 93), (726, 91),
    # Third episode.
    (730, 115), (735, 150), (739, 185), (742, 215), (743, 208), (751, 240), (754, 290),
    (756, 320), (759, 360), (761, 377), (762, 362), (765, 402), (770, 373), (775, 356),
    (779, 370), (783, 330), (788, 358), (792, 378), (796, 345), (798, 310), (800, 280),
    (803, 225), (804, 213), (806, 210), (810, 180), (813, 150), (816, 182), (819, 155),
    (822, 128), (826, 108), (831, 80), (836, 77), (839, 86), (841, 78), (845, 100),
    (849, 122), (858, 97), (863, 78), (865, 103), (868, 91), (873, 120), (879, 124),
    (887, 105), (890, 125), (894, 147), (900, 158), (907, 170), (913, 139), (917, 148),
    (920, 145), (926, 155), (934, 141), (938, 160), (943, 200), (947, 160), (955, 143),
    (965, 121), (969, 133), (973, 108), (978, 118), (982, 105), (985, 106), (990, 130),
]
# The record is scaled evenly to run from just beyond one edge of the watch's
# canvas to just beyond the other, so no end shows in the square or the circle.
TRACE_LEFT = -BLEED - 4
TRACE_SCALE = (SIZE + 2 * BLEED + 8) / RECORD_WIDTH
TRACE_TOP = 298       # y of the record's highest point


def trace_points():
    top = min(y for _, y in RECORD)
    return [(TRACE_LEFT + x * TRACE_SCALE, TRACE_TOP + (y - top) * TRACE_SCALE) for x, y in RECORD]


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
    # On the record's lowest reading, the bottom of the deepest episode.
    x, y = max(trace_points(), key=lambda p: p[1])
    return ['<circle cx="%.1f" cy="%.1f" r="%g" fill="%s"/>' % (x, y, DOT_RADIUS, DOT)]


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
