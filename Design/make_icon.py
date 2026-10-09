"""Builds Scope/AppIcon.icon from the design in 'Scope Icon - Frame.svg'.

Run `python3 Design/make_icon.py` after changing the artwork below, then check the result in
Icon Composer or with `ictool`.

The original draws a finished icon on the old macOS grid: an 824 pt rounded square inside a
1024 canvas, with shadows, blur, sheen and highlights baked in. Liquid Glass icons instead fill
the whole 1024 canvas with flat artwork, and the system adds the shape, glass, blur and lighting.
So every layer is scaled up by 1024/824 around the centre and drawn without effects. The frosted
window is real glass now: macOS blurs the colour blobs behind it.

Opacity is set with `opacity`, because the icon renderer ignores `fill-opacity` and `stroke-opacity`.
"""
import json, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Scope", "AppIcon.icon")
SCALE = 1024 / 824
C = 512

def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<g transform="translate({C} {C}) scale({SCALE:.6f}) translate({-C} {-C})">{body}</g></svg>')

layers = {
    # Behind the window: the colourful "screen content" it's capturing.
    "blobs": svg(
        '<circle cx="372" cy="430" r="160" fill="#FF5C8A"/>'
        '<circle cx="650" cy="580" r="180" fill="#FFB02E"/>'
        '<circle cx="590" cy="350" r="120" fill="#8C5CFF"/>'),
    # The window: a plain card. Its frosting, rim light and shadow come from the glass.
    "window": svg('<rect x="232" y="292" width="560" height="440" rx="60" fill="#FFF6EE"/>'),
    "window-controls": svg(
        '<line x1="232" y1="388" x2="792" y2="388" stroke="#FFFFFF" stroke-width="2" opacity=".7"/>'
        '<circle cx="298" cy="340" r="14" fill="#FF6159"/>'
        '<circle cx="342" cy="340" r="14" fill="#FFBD2E"/>'
        '<circle cx="386" cy="340" r="14" fill="#28C840"/>'),
    "brackets": svg(
        '<g fill="none" stroke="#FF3D5A" stroke-width="16" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M190 330 V250 H270"/><path d="M754 250 H834 V330"/>'
        '<path d="M834 694 V774 H754"/><path d="M270 774 H190 V694"/></g>'),
    # The record button: a white ring with a flat red dot; the system adds the shine.
    "record-ring": svg('<circle cx="700" cy="660" r="122" fill="#FFFFFF"/>'),
    "record-dot": svg('<circle cx="700" cy="660" r="84" fill="#F2223F"/>'),
}

def group(name, layer_names, *, glass, translucency=None, blur=None, shadow="neutral", shadow_opacity=0.5, specular=True, opacity=None):
    layers_json = []
    for layer in layer_names:
        entry = {"image-name": f"{layer}.svg", "name": layer, "glass": glass}
        if opacity and layer in opacity:
            entry["opacity"] = opacity[layer]
        layers_json.append(entry)
    g = {"layers": layers_json, "name": name, "shadow": {"kind": shadow, "opacity": shadow_opacity}, "specular": specular}
    if translucency is not None:
        g["translucency"] = {"enabled": True, "value": translucency}
    if blur is not None:
        g["blur-material"] = blur
    return g

icon = {
    # Front to back, as Icon Composer lists them.
    "groups": [
        group("Record", ["record-dot", "record-ring"], glass=True, shadow="layer-color", shadow_opacity=0.5,
              opacity={"record-ring": 0.75}),
        group("Brackets", ["brackets"], glass=False, shadow="layer-color", shadow_opacity=0.25, specular=False),
        # Frosted: blurs the blobs behind it, softly enough that their colours still show.
        group("Window", ["window-controls", "window"], glass=True, translucency=0.6, blur=0.3, shadow_opacity=0.35),
        group("Blobs", ["blobs"], glass=False, shadow_opacity=0, specular=False),
    ],
    "fill": {"linear-gradient": ["srgb:1.00000,0.97255,0.93333,1.00000", "srgb:1.00000,0.85098,0.74118,1.00000"]},
    "supported-platforms": {"squares": ["macOS"]},
}

os.makedirs(f"{OUT}/Assets", exist_ok=True)
for name, content in layers.items():
    with open(f"{OUT}/Assets/{name}.svg", "w") as f:
        f.write(content)
with open(f"{OUT}/icon.json", "w") as f:
    json.dump(icon, f, indent=2)
print("wrote", sorted(os.listdir(f"{OUT}/Assets")))
