#!/usr/bin/env python3
"""Renders the watercolor illustrations in Assets.xcassets (Art*.imageset).

Same technique and palette as `marketing/src/Watercolor.tsx`: soft discs whose edges are torn by
fractal noise, pigment pooling at the rim, a granulation pass, multiply blending. Each piece is
described below in points; it is drawn as SVG and rasterised by headless Chrome at 3x on a
transparent background, then downsampled to 2x with `sips`.

Usage:  python3 Tools/generate_art.py            (run from ios/; needs Google Chrome)
Change a composition here and re-run; never edit the PNGs by hand.
"""
import json
import os
import subprocess
import sys
import tempfile

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Tempo", "Resources", "Assets.xcassets")

BLUSH, SAGE, BUTTER, SKY, LILAC, ACCENT = "#F3B3A2", "#A9D2B8", "#F2D98A", "#A9C6E8", "#C5B4E3", "#E4532F"


def wash(x, y, r, color, seed, opacity=0.85, squash=1.0, rotate=0.0, dense=False, wobble=0.42):
    return dict(x=x, y=y, r=r, color=color, seed=seed, opacity=opacity, squash=squash, rotate=rotate,
                dense=dense, wobble=wobble)


# name -> (width pt, height pt, washes)
ART = {
    # Welcome: a tall loose cluster filling the open middle of the screen, weighted right.
    "ArtWelcome": (354, 330, [
        wash(236, 120, 118, BLUSH, 5, squash=0.9, rotate=-8),
        wash(128, 214, 92, SAGE, 23, squash=0.84, rotate=16),
        wash(290, 238, 76, BUTTER, 13, squash=0.94),
        wash(206, 190, 40, ACCENT, 33, opacity=0.8),
        wash(322, 52, 38, LILAC, 43),
        wash(52, 82, 44, SKY, 53, opacity=0.6, squash=0.76),
    ]),
    # Match moment: one wash behind each portrait and a small one where they meet.
    "ArtMutual": (320, 240, [
        wash(112, 108, 86, BLUSH, 7, squash=0.94, rotate=-10),
        wash(206, 112, 90, SAGE, 27, squash=0.9, rotate=14),
        wash(158, 186, 44, BUTTER, 17),
    ]),
    # Behind the icon of an empty state.
    "ArtSpot": (112, 104, [
        wash(50, 50, 40, BLUSH, 9, squash=0.9, rotate=-10),
        wash(78, 66, 24, BUTTER, 19),
    ]),
    # Single washes, one per hue, each centred in a 220 pt square (radius 80). `BlotField` layers
    # and moves these live, so the paint can drift. Multiply-blend them over white.
    "BlotBlush": (220, 220, [wash(110, 110, 80, BLUSH, 3, squash=0.9)]),
    "BlotButter": (220, 220, [wash(110, 110, 80, BUTTER, 11, squash=0.92)]),
    "BlotSage": (220, 220, [wash(110, 110, 80, SAGE, 21, squash=0.86)]),
    "BlotLilac": (220, 220, [wash(110, 110, 80, LILAC, 41)]),
    "BlotSky": (220, 220, [wash(110, 110, 80, SKY, 51, opacity=0.7, squash=0.8)]),
    "BlotAccent": (220, 220, [wash(110, 110, 80, ACCENT, 31, opacity=0.8)]),
    # Corner washes for the cards on Tonight: one hue each, weighted to the trailing edge. Every
    # wash ends inside the canvas (or runs off the top/trailing edge, which the card clips).
    "ArtCardSage": (354, 170, [wash(306, 62, 62, SAGE, 71, squash=0.86, rotate=14), wash(236, 118, 20, BUTTER, 72, opacity=0.7)]),
    "ArtCardButter": (354, 170, [wash(302, 66, 60, BUTTER, 73, squash=0.9, rotate=-8), wash(346, 14, 24, BLUSH, 74, opacity=0.7)]),
    "ArtCardBlush": (354, 170, [wash(308, 62, 62, BLUSH, 75, squash=0.86, rotate=-12), wash(240, 120, 20, LILAC, 76, opacity=0.7)]),
    "ArtCardLilac": (354, 170, [wash(304, 64, 60, LILAC, 77, squash=0.9, rotate=10), wash(338, 128, 20, SKY, 78, opacity=0.7)]),
    "ArtCardSky": (354, 170, [wash(306, 62, 60, SKY, 79, squash=0.84, rotate=-6), wash(250, 14, 24, SAGE, 80, opacity=0.7)]),
    # Bodies of the agent characters: one dense wash per colour, each torn differently (its own
    # seed and wobble), centred in a 220 pt square (radius 80). `AgentBuddy` draws a face on top.
    "BuddyBlush": (220, 220, [wash(110, 110, 80, "#F3B3A2", 101, opacity=1, dense=True, wobble=0.5)]),
    "BuddyButter": (220, 220, [wash(110, 110, 80, "#F2D98A", 117, opacity=1, dense=True, wobble=0.38)]),
    "BuddySage": (220, 220, [wash(110, 110, 80, "#A9D2B8", 123, opacity=1, dense=True, wobble=0.56)]),
    "BuddyLilac": (220, 220, [wash(110, 110, 80, "#C5B4E3", 139, opacity=1, dense=True, wobble=0.44)]),
    "BuddySky": (220, 220, [wash(110, 110, 80, "#A9C6E8", 145, opacity=1, dense=True, wobble=0.6)]),
    "BuddyCoral": (220, 220, [wash(110, 110, 80, "#F08F7A", 151, opacity=1, dense=True, wobble=0.4)]),
    "BuddyMint": (220, 220, [wash(110, 110, 80, "#8FD6C4", 167, opacity=1, dense=True, wobble=0.52)]),
    "BuddyPeach": (220, 220, [wash(110, 110, 80, "#F6C59A", 173, opacity=1, dense=True, wobble=0.36)]),
    "BuddyPeriwinkle": (220, 220, [wash(110, 110, 80, "#9FB0EC", 189, opacity=1, dense=True, wobble=0.58)]),
    "BuddyRose": (220, 220, [wash(110, 110, 80, "#EBA6C6", 195, opacity=1, dense=True, wobble=0.46)]),
    # The yes/no answers: thin, see-through washes of light red and light green, like glass.
    "ChoiceNo": (220, 220, [wash(110, 110, 80, "#F0847C", 211, opacity=1, wobble=0.5)]),
    "ChoiceYes": (220, 220, [wash(110, 110, 80, "#76C898", 227, opacity=1, wobble=0.46)]),
    # Paywall header and other gold moments.
    "ArtGold": (354, 150, [
        wash(270, 66, 74, BUTTER, 15, squash=0.82, rotate=-6),
        wash(330, 112, 40, BLUSH, 25, opacity=0.7),
        wash(236, 126, 28, LILAC, 45, opacity=0.7),
    ]),
}


def wash_svg(w, wid):
    wobble = w["r"] * w.get("wobble", 0.42)
    # Dense washes hold more pigment in the middle, so a face drawn on top stays readable.
    inner, mid, rim = (0.62, 0.68, 0.8) if w.get("dense") else (0.3, 0.42, 0.62)
    return f"""
<g style="mix-blend-mode:multiply" opacity="{w['opacity']}">
  <defs>
    <radialGradient id="{wid}-g">
      <stop offset="0" stop-color="{w['color']}" stop-opacity="{inner}"/>
      <stop offset="0.55" stop-color="{w['color']}" stop-opacity="{mid}"/>
      <stop offset="0.86" stop-color="{w['color']}" stop-opacity="{rim}"/>
      <stop offset="0.97" stop-color="{w['color']}" stop-opacity="0.95"/>
      <stop offset="1" stop-color="{w['color']}" stop-opacity="0"/>
    </radialGradient>
    <filter id="{wid}-f" x="-60%" y="-60%" width="220%" height="220%" color-interpolation-filters="sRGB">
      <feTurbulence type="fractalNoise" baseFrequency="0.0065" numOctaves="4" seed="{w['seed']}" result="big"/>
      <feDisplacementMap in="SourceGraphic" in2="big" scale="{wobble}" xChannelSelector="R" yChannelSelector="G" result="torn"/>
      <feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="2" seed="{w['seed'] + 7}" result="fine"/>
      <feDisplacementMap in="torn" in2="fine" scale="{w['r'] * 0.05}" xChannelSelector="G" yChannelSelector="B" result="edge"/>
      <feGaussianBlur in="edge" stdDeviation="1.1" result="soft"/>
      <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="{w['seed'] + 13}" result="grain"/>
      <feColorMatrix in="grain" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0.9 0.9 0 0 0.25" result="grainA"/>
      <feComposite in="soft" in2="grainA" operator="in"/>
    </filter>
  </defs>
  <ellipse cx="{w['x']}" cy="{w['y']}" rx="{w['r']}" ry="{w['r'] * w['squash']}"
           transform="rotate({w['rotate']} {w['x']} {w['y']})" fill="url(#{wid}-g)" filter="url(#{wid}-f)"/>
</g>"""


def render(name, width, height, washes, workdir):
    # The marketing art is authored at about 3.4x these point sizes; scaling the drawing rather than
    # the numbers keeps the noise frequencies, and so the look of the torn edges, identical.
    scale = 3.4
    body = "".join(wash_svg({**w, "x": w["x"] * scale, "y": w["y"] * scale, "r": w["r"] * scale}, f"w{i}")
                   for i, w in enumerate(washes))
    px_w, px_h = round(width * 3), round(height * 3)
    html = f"""<!doctype html><html><head><style>html,body{{margin:0;background:transparent}}</style></head><body>
<svg xmlns="http://www.w3.org/2000/svg" width="{px_w}" height="{px_h}" viewBox="0 0 {width * scale} {height * scale}"
     style="display:block;isolation:isolate">{body}</svg></body></html>"""
    page = os.path.join(workdir, f"{name}.html")
    with open(page, "w") as handle:
        handle.write(html)

    imageset = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(imageset, exist_ok=True)
    out3 = os.path.join(imageset, f"{name}@3x.png")
    out2 = os.path.join(imageset, f"{name}@2x.png")
    subprocess.run([
        CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
        "--default-background-color=00000000", f"--window-size={px_w},{px_h}", f"--screenshot={out3}",
        f"file://{page}",
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["sips", "--resampleWidth", str(round(width * 2)), out3, "--out", out2],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    contents = {
        "images": [
            {"idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x", "filename": f"{name}@2x.png"},
            {"idiom": "universal", "scale": "3x", "filename": f"{name}@3x.png"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(imageset, "Contents.json"), "w") as handle:
        json.dump(contents, handle, indent=2)
        handle.write("\n")
    print(f"{name}: {px_w}x{px_h}")


def _mark_layer(i, shape, color, seed, r, wobble=0.42, opacity=0.9, dense=True):
    """One wash of the brand mark. Like `wash_svg`, but for any SVG shape (the body is a path)."""
    inner, mid, rim = (0.62, 0.68, 0.8) if dense else (0.3, 0.42, 0.62)
    filled = shape.replace("/>", f' fill="url(#mg{i})" filter="url(#mf{i})"/>')
    return f"""
<g style="mix-blend-mode:multiply" opacity="{opacity}"><defs>
<radialGradient id="mg{i}">
  <stop offset="0" stop-color="{color}" stop-opacity="{inner}"/>
  <stop offset="0.55" stop-color="{color}" stop-opacity="{mid}"/>
  <stop offset="0.86" stop-color="{color}" stop-opacity="{rim}"/>
  <stop offset="0.97" stop-color="{color}" stop-opacity="0.95"/>
  <stop offset="1" stop-color="{color}" stop-opacity="0"/>
</radialGradient>
<filter id="mf{i}" x="-60%" y="-60%" width="220%" height="220%" color-interpolation-filters="sRGB">
  <feTurbulence type="fractalNoise" baseFrequency="0.0065" numOctaves="4" seed="{seed}" result="big"/>
  <feDisplacementMap in="SourceGraphic" in2="big" scale="{r * wobble}" xChannelSelector="R" yChannelSelector="G" result="torn"/>
  <feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="2" seed="{seed + 7}" result="fine"/>
  <feDisplacementMap in="torn" in2="fine" scale="{r * 0.05}" xChannelSelector="G" yChannelSelector="B" result="edge"/>
  <feGaussianBlur in="edge" stdDeviation="1.1" result="soft"/>
  <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="{seed + 13}" result="grain"/>
  <feColorMatrix in="grain" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0.9 0.9 0 0 0.25" result="grainA"/>
  <feComposite in="soft" in2="grainA" operator="in"/>
</filter></defs>{filled}</g>"""


def mark_svg(size):
    """The Passionfruit mark: two thin washes, rose and blue, laid almost on top of each other so
    the fruit is the purple they make, with a faint fringe of each colour; one painted leaf."""
    layers = [
        _mark_layer(0, '<ellipse cx="498" cy="557" rx="290" ry="284" transform="rotate(-14 498 557)"/>',
                     "#EFADCB", 7, 290, wobble=0.3, opacity=0.9, dense=False),
        _mark_layer(1, '<ellipse cx="526" cy="551" rx="284" ry="290" transform="rotate(16 526 551)"/>',
                     "#A6B6F0", 27, 290, wobble=0.3, opacity=0.9, dense=False),
        _mark_layer(2, '<path d="M 520 270 C 560 170, 690 120, 800 150 C 770 250, 650 310, 520 270 Z"/>',
                     "#9CCFAE", 33, 150, wobble=0.14, opacity=0.9, dense=False),
    ]
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="60 40 940 940" '
            f'style="display:block;isolation:isolate">{"".join(layers)}</svg>')


def _chrome(page, out, size, transparent):
    args = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
            f"--window-size={size},{size}", f"--screenshot={out}"]
    if transparent:
        args.append("--default-background-color=00000000")
    subprocess.run(args + [f"file://{page}"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def render_icon():
    """The app icon: the Passionfruit mark on paper."""
    size = 1024
    html = (f'<!doctype html><html><body style="margin:0;background:#FDFCFA">{mark_svg(size)}</body></html>')
    with tempfile.TemporaryDirectory() as workdir:
        page = os.path.join(workdir, "icon.html")
        with open(page, "w") as handle:
            handle.write(html)
        out = os.path.join(ASSETS, "AppIcon.appiconset", "AppIcon-1024.png")
        _chrome(page, out, size, transparent=False)
        # App icons may not carry an alpha channel.
        flat = os.path.join(workdir, "flat.jpg")
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "100", out, "--out", flat],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["sips", "-s", "format", "png", flat, "--out", out],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"AppIcon: {size}x{size}")


def render_mark():
    """`BrandFruit`: the same mark on a transparent background, for use inside the app (120 pt)."""
    points = 120
    imageset = os.path.join(ASSETS, "BrandFruit.imageset")
    os.makedirs(imageset, exist_ok=True)
    with tempfile.TemporaryDirectory() as workdir:
        for scale in (2, 3):
            px = points * scale
            page = os.path.join(workdir, f"mark{scale}.html")
            with open(page, "w") as handle:
                handle.write(f'<!doctype html><html><body style="margin:0;background:transparent">{mark_svg(px)}</body></html>')
            _chrome(page, os.path.join(imageset, f"BrandFruit@{scale}x.png"), px, transparent=True)
    contents = {
        "images": [
            {"idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x", "filename": "BrandFruit@2x.png"},
            {"idiom": "universal", "scale": "3x", "filename": "BrandFruit@3x.png"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(imageset, "Contents.json"), "w") as handle:
        json.dump(contents, handle, indent=2)
        handle.write("\n")
    print("BrandFruit: 360x360")


def main():
    if not os.path.exists(CHROME):
        sys.exit("Google Chrome is needed to rasterise the SVG filters.")
    with tempfile.TemporaryDirectory() as workdir:
        for name, (width, height, washes) in ART.items():
            render(name, width, height, washes, workdir)
    render_icon()
    render_mark()


if __name__ == "__main__":
    main()
