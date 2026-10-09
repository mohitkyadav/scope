"""Builds Scope/AppIcon.icon from the design in 'Scope Icon.svg'.

Run `python3 Design/make_icon.py` after changing the artwork below, then check the result in
Icon Composer or with `ictool`.

The original draws a finished icon on the old macOS grid: an 824 pt rounded square inside a
1024 canvas, with shadows, glow, refraction and highlights baked in. Liquid Glass icons instead
fill the whole 1024 canvas with flat artwork, and the system adds the shape, glass and lighting.
So every layer is scaled up by 1024/824 around the centre and drawn without effects.
"""
import json, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Scope", "AppIcon.icon")
SCALE = 1024 / 824
C = 512            # centre in the original's coordinates
LENS_R = 226       # lens radius in the original
MAGNIFY = 1.32     # how much the lens magnifies in the original

def svg(body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{defs}</defs>'
            f'<g transform="translate({C} {C}) scale({SCALE:.6f}) translate({-C} {-C})">{body}</g></svg>')

def line(x1, y1, x2, y2, width, opacity=1):
    o = f' opacity="{opacity}"' if opacity != 1 else ""
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke-width="{width}"{o}/>'

# Tick marks along the crosshair, every 20 pt from the centre; every fifth one is longer.
def ticks(keep):
    out = []
    for d in range(60, 360, 20):
        if not keep(d):
            continue
        half = 14 if (d - 100) % 100 == 0 else 7
        for sign in (1, -1):
            p = C + sign * d
            out.append(line(p, C - half, p, C + half, 1.6, 0.38))
            out.append(line(C - half, p, C + half, p, 1.6, 0.38))
    return out

STROKE = 'fill="none" stroke="#E8EEFA" stroke-linecap="round"'

def reticle_center():
    return [
        f'<circle cx="{C}" cy="{C}" r="34" stroke-width="3"/>',
        f'<circle cx="{C}" cy="{C}" r="4.5" fill="#E8EEFA" stroke="none"/>',
        line(512, 450, 512, 490, 3), line(512, 534, 512, 574, 3),
        line(450, 512, 490, 512, 3), line(534, 512, 574, 512, 3),
    ]

def reticle_full():
    return reticle_center() + [
        line(512, 160, 512, 430, 1.6, 0.45), line(512, 594, 512, 864, 1.6, 0.45),
        line(160, 512, 430, 512, 1.6, 0.45), line(594, 512, 864, 512, 1.6, 0.45),
    ] + ticks(lambda d: True)

# 1. Crosshair outside the lens. The lens covers the rest, so stop at its edge instead of masking.
edge = LENS_R + 4
outside = [
    line(512, 160, 512, C - edge, 1.6, 0.45), line(512, C + edge, 512, 864, 1.6, 0.45),
    line(160, 512, C - edge, 512, 1.6, 0.45), line(C + edge, 512, 864, 512, 1.6, 0.45),
] + ticks(lambda d: d > edge)
crosshair = svg(f'<g {STROKE}>{"".join(outside)}</g>')

# 2. The two cyan rings, without the neon blur.
rings = svg(
    '<g fill="none" stroke="#00F0FF">'
    f'<circle cx="{C}" cy="{C}" r="268" stroke-width="3" opacity=".6"/>'
    f'<circle cx="{C}" cy="{C}" r="318" stroke-width="2.5" opacity=".2"/>'
    '</g>')

# 3. The lens: a dark disc with the crosshair magnified inside it. Glass, refraction, rim light,
#    highlights and the colour fringing are left to the system.
magnified = (f'<g transform="translate({C} {C}) scale({MAGNIFY}) translate({-C} {-C})">'
             f'<g {STROKE}>{"".join(reticle_full())}</g></g>')
lens = svg(
    f'<circle cx="{C}" cy="{C}" r="{LENS_R}" fill="url(#lens)"/>'
    f'<g clip-path="url(#lens-clip)">{magnified}</g>',
    defs=(f'<clipPath id="lens-clip"><circle cx="{C}" cy="{C}" r="{LENS_R}"/></clipPath>'
          f'<radialGradient id="lens" cx="{C}" cy="{C}" r="{LENS_R}" gradientUnits="userSpaceOnUse">'
          '<stop offset="0" stop-color="#1A2133"/><stop offset=".75" stop-color="#1E2740"/>'
          '<stop offset="1" stop-color="#34446E"/></radialGradient>'))

# 4. The cursor, on its own layer so it floats above the lens. In the original the lens clips it;
#    here it's magnified a little less (1.25 instead of 1.32) so it stays inside the lens instead.
cursor = svg(
    f'<g transform="translate({C} {C}) scale(1.25) translate({-C} {-C})">'
    '<path d="M520 520 L520 666 L556 632 L581 690 L607 678 L582 621 L632 621 Z" '
    'fill="#FFFFFF" stroke="#0E1220" stroke-width="7" stroke-linejoin="round"/></g>')

layers = {"crosshair": crosshair, "rings": rings, "lens": lens, "cursor": cursor}
for name, content in layers.items():
    os.makedirs(f"{OUT}/Assets", exist_ok=True)
    with open(f"{OUT}/Assets/{name}.svg", "w") as f:
        f.write(content)

def group(name, *, glass, translucency=None, shadow="neutral", shadow_opacity=0.5, specular=True):
    g = {
        "layers": [{"image-name": f"{name}.svg", "name": name, "glass": glass}],
        "name": name.capitalize(),
        "shadow": {"kind": shadow, "opacity": shadow_opacity},
        "specular": specular,
    }
    if translucency is not None:
        g["translucency"] = {"enabled": True, "value": translucency}
    return g

icon = {
    # Front to back, as Icon Composer lists them.
    "groups": [
        group("cursor", glass=True, shadow_opacity=0.6),
        group("lens", glass=True, translucency=0.4, shadow_opacity=0.6),
        group("rings", glass=False, shadow="layer-color", shadow_opacity=0.3, specular=False),
        group("crosshair", glass=False, shadow_opacity=0, specular=False),
    ],
    "fill": {"linear-gradient": ["srgb:0.13725,0.16471,0.23137,1.00000", "srgb:0.05882,0.06667,0.10196,1.00000"]},
    "supported-platforms": {"squares": ["macOS"]},
}
with open(f"{OUT}/icon.json", "w") as f:
    json.dump(icon, f, indent=2)
print("wrote", sorted(os.listdir(f"{OUT}/Assets")))
