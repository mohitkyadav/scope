"""Builds Scope/AppIcon.icon from the design in 'Scope Icon - Frame.svg', and Scope/AppIcon-Local.icon,
the same icon with a blue LOCAL ribbon across the top-right corner for Debug builds.

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

SCOPE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Scope")
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

groups = [
    group("Record", ["record-dot", "record-ring"], glass=True, shadow="layer-color", shadow_opacity=0.5,
          opacity={"record-ring": 0.75}),
    group("Brackets", ["brackets"], glass=False, shadow="layer-color", shadow_opacity=0.25, specular=False),
    # Frosted: blurs the blobs behind it, softly enough that their colours still show.
    group("Window", ["window-controls", "window"], glass=True, translucency=0.6, blur=0.3, shadow_opacity=0.35),
    group("Blobs", ["blobs"], glass=False, shadow_opacity=0, specular=False),
]

# "LOCAL" in SF Pro Rounded Heavy as outlines, centred on (0, 0), so it doesn't depend on fonts.
# Made with `xcrun swift Design/text_path.swift LOCAL 84 6`.
LOCAL_TEXT = "M-140.7 29.6Q-144.3 29.6 -146.2 27.5Q-148.2 25.5 -148.2 21.7L-148.2 -22.7Q-148.2 -26.4 -146.2 -28.5Q-144.3 -30.5 -140.7 -30.5Q-137.1 -30.5 -135.2 -28.5Q-133.2 -26.4 -133.2 -22.7L-133.2 17.4L-114.6 17.4Q-111.6 17.4 -109.8 19.0Q-107.9 20.6 -107.9 23.5Q-107.9 26.4 -109.8 28.0Q-111.6 29.6 -114.6 29.6ZM-68.2 30.6Q-77.2 30.6 -83.7 26.9Q-90.3 23.2 -93.9 16.3Q-97.4 9.4 -97.4 0.0Q-97.4 -9.4 -93.8 -16.3Q-90.3 -23.2 -83.7 -26.9Q-77.2 -30.6 -68.2 -30.6Q-59.2 -30.6 -52.7 -26.9Q-46.1 -23.2 -42.6 -16.3Q-39.0 -9.4 -39.0 0.0Q-39.0 9.4 -42.6 16.3Q-46.1 23.2 -52.7 26.9Q-59.2 30.6 -68.2 30.6ZM-68.2 18.4Q-64.0 18.4 -60.9 16.2Q-57.7 13.9 -56.0 9.8Q-54.3 5.6 -54.3 0.0Q-54.3 -5.6 -56.0 -9.8Q-57.8 -13.9 -60.9 -16.2Q-64.0 -18.4 -68.2 -18.4Q-72.4 -18.4 -75.5 -16.2Q-78.6 -13.9 -80.4 -9.8Q-82.1 -5.6 -82.1 0.0Q-82.1 5.6 -80.4 9.8Q-78.7 13.9 -75.5 16.2Q-72.4 18.4 -68.2 18.4ZM1.8 30.6Q-7.3 30.6 -13.8 27.0Q-20.3 23.4 -23.8 16.5Q-27.3 9.7 -27.3 -0.0Q-27.3 -9.7 -23.8 -16.5Q-20.3 -23.3 -13.9 -27.0Q-7.5 -30.6 1.3 -30.6Q6.9 -30.6 11.5 -29.1Q16.1 -27.6 19.6 -24.7Q23.1 -21.8 25.3 -17.6Q26.9 -14.9 26.9 -12.1Q26.9 -9.2 25.1 -7.5Q23.3 -5.7 20.3 -5.7Q17.8 -5.7 16.2 -6.8Q14.6 -7.9 13.3 -10.4Q12.0 -13.2 10.2 -15.0Q8.4 -16.8 6.2 -17.7Q4.1 -18.6 1.4 -18.6Q-2.6 -18.6 -5.6 -16.3Q-8.7 -14.1 -10.3 -10.0Q-12.0 -5.8 -12.0 -0.1Q-12.0 5.7 -10.3 9.9Q-8.7 14.1 -5.7 16.3Q-2.6 18.6 1.5 18.6Q4.2 18.6 6.4 17.7Q8.7 16.8 10.4 15.0Q12.2 13.2 13.5 10.4Q14.6 7.9 16.1 6.9Q17.6 5.8 20.0 5.8Q23.2 5.8 25.2 7.6Q27.1 9.5 27.1 12.5Q27.1 14.6 26.1 16.8Q24.4 21.0 20.8 24.1Q17.2 27.2 12.3 28.9Q7.5 30.6 1.8 30.6ZM47.2 30.5Q43.7 30.5 41.7 28.6Q39.6 26.7 39.6 23.3Q39.6 21.2 40.6 18.4L55.3 -21.7Q56.9 -26.2 59.7 -28.4Q62.5 -30.5 66.9 -30.5Q71.6 -30.5 74.4 -28.4Q77.3 -26.3 79.0 -21.7L93.7 18.4Q94.7 21.1 94.7 23.3Q94.7 26.4 92.6 28.5Q90.4 30.5 87.2 30.5Q83.9 30.5 82.1 28.9Q80.2 27.3 79.2 23.7L77.2 17.1L57.0 17.1L55.0 23.5Q53.9 27.2 52.1 28.9Q50.3 30.5 47.2 30.5ZM60.0 5.8L73.9 5.8L67.0 -17.0L66.7 -17.0ZM115.5 29.6Q111.9 29.6 109.9 27.5Q107.9 25.5 107.9 21.7L107.9 -22.7Q107.9 -26.4 109.9 -28.5Q111.9 -30.5 115.5 -30.5Q119.0 -30.5 121.0 -28.5Q123.0 -26.4 123.0 -22.7L123.0 17.4L141.5 17.4Q144.5 17.4 146.4 19.0Q148.2 20.6 148.2 23.5Q148.2 26.4 146.4 28.0Q144.6 29.6 141.5 29.6Z"

# A sash across the top-right corner. It's drawn on the full canvas, not the scaled artwork, and the
# system clips it to the icon's shape. Its centre line runs from (680, 0) to (1024, 344).
RIBBON = 'transform="translate(852 172) rotate(45)"'
badge_layers = {
    "ribbon": '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
              f'<g {RIBBON}><rect x="-420" y="-64" width="840" height="128" fill="#2F6BF2"/></g></svg>',
    "ribbon-text": '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
                   f'<g {RIBBON}><path d="{LOCAL_TEXT}" fill="#FFFFFF"/></g></svg>',
}
# Icons can have at most four groups, so the ribbon joins the brackets, in front of them.
local_groups = [group("Brackets", ["ribbon-text", "ribbon", "brackets"], glass=False, shadow="layer-color",
                      shadow_opacity=0.25, specular=False) if g["name"] == "Brackets" else g for g in groups]

def write_icon(name, layers, groups):
    out = os.path.join(SCOPE, name)
    os.makedirs(f"{out}/Assets", exist_ok=True)
    for layer, content in layers.items():
        with open(f"{out}/Assets/{layer}.svg", "w") as f:
            f.write(content)
    icon = {
        # Front to back, as Icon Composer lists them.
        "groups": groups,
        "fill": {"linear-gradient": ["srgb:1.00000,0.97255,0.93333,1.00000", "srgb:1.00000,0.85098,0.74118,1.00000"]},
        "supported-platforms": {"squares": ["macOS"]},
    }
    with open(f"{out}/icon.json", "w") as f:
        json.dump(icon, f, indent=2)
    print("wrote", name, sorted(os.listdir(f"{out}/Assets")))

write_icon("AppIcon.icon", layers, groups)
write_icon("AppIcon-Local.icon", {**layers, **badge_layers}, local_groups)
