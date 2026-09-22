#!/usr/bin/env python3
"""Frame existing captures with Apple device artwork; never launch or move the app."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile


# Canvas and screen coordinates from the matching Apple Design Resources templates.
DEVICES = {
    "iphone-18-pro": {"canvas": (1350, 2760), "screen": (1206, 2622, 72, 69), "layer": 2},
    "macbook-pro-14-silver": {"canvas": (3860, 2540), "screen": (3024, 1964, 418, 288), "layer": 1},
    "studio-display": {"canvas": (5400, 4160), "screen": (5120, 2880, 140, 140), "layer": None},
    "imac-pink": {"canvas": (4760, 4050), "screen": (4480, 2520, 140, 150), "layer": None},
}
SCREENS = ("library", "detail", "files")
SRGB = pathlib.Path("/System/Library/ColorSync/Profiles/sRGB Profile.icc")
MAC_LAYOUT = {"heightFraction": 0.85, "maxWidthFraction": 0.9, "captureWidthPoints": 1200,
              "cornerRadiusPoints": 20, "shadowOpacity": "#00000055",
              "shadowOffsetPixels": 20, "shadowBlurPixels": 24}


def magick(*args):
    subprocess.run(["magick", *map(str, args)], check=True)


def identify(path, pattern):
    return subprocess.check_output(["magick", "identify", "-format", pattern, str(path)], text=True)


def dimensions(path):
    return tuple(map(int, identify(path, "%w %h").split()))


def fingerprint(path):
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def validate_assets(device, frame, template):
    spec = DEVICES[device]
    if dimensions(frame) != spec["canvas"] or dimensions(f"{template}[0]") != spec["canvas"]:
        raise ValueError(f"Frame and PSD must match the {device} canvas: {spec['canvas']}")
    if spec["layer"] is not None:
        layer = f"{template}[{spec['layer']}]"
        label = identify(layer, "%[label]")
        geometry = tuple(map(int, identify(layer, "%w %h %X %Y").split()))
        if not label.startswith("Screen") or geometry != spec["screen"]:
            raise ValueError(f"PSD Screen layer must match {device}: {spec['screen']}")
    else:
        width, height, x, y = spec["screen"]
        # These desktop templates have a rectangular transparent opening, without a Screen layer.
        maximum = subprocess.check_output([
            "magick", str(frame), "-crop", f"{width}x{height}+{x}+{y}",
            "+repage", "-alpha", "extract", "-format", "%[fx:maxima]", "info:",
        ], text=True)
        if float(maximum) != 0:
            raise ValueError(f"The {device} screen opening must be transparent")


def render(source, destination, device, frame, template, wallpaper, work):
    spec = DEVICES[device]
    width, height, x, y = spec["screen"]
    canvas_width, canvas_height = spec["canvas"]
    screen = work / "screen.png"
    if device == "iphone-18-pro":
        magick(source, "-profile", SRGB, "-depth", 8, screen)
    else:
        source_width, source_height = dimensions(source)
        # Captures use a 1200-point-wide window. Match its native 20-point corners at either scale.
        radius = source_width / MAC_LAYOUT["captureWidthPoints"] * MAC_LAYOUT["cornerRadiusPoints"]
        mask = work / "window-mask.png"
        magick("-size", f"{source_width}x{source_height}", "xc:black", "-fill", "white",
               "-draw", f"roundrectangle 0,0 {source_width-1},{source_height-1} {radius},{radius}", mask)
        window_height = round(height * MAC_LAYOUT["heightFraction"])
        window_width = round(window_height * source_width / source_height)
        if window_width > width * MAC_LAYOUT["maxWidthFraction"]:
            window_width = round(width * MAC_LAYOUT["maxWidthFraction"])
            window_height = round(window_width * source_height / source_width)
        window = work / "window.png"
        magick(source, "-profile", SRGB, mask, "-alpha", "off", "-compose", "CopyOpacity",
               "-composite", "-resize", f"{window_width}x{window_height}", "-depth", 8, window)
        # Use actual resized dimensions to account for ImageMagick's aspect-ratio rounding.
        window_width, window_height = dimensions(window)
        left, top = (width-window_width)//2, (height-window_height)//2
        scale = window_height / source_height
        radius *= scale
        offset = round(MAC_LAYOUT["shadowOffsetPixels"] * scale)
        blur = MAC_LAYOUT["shadowBlurPixels"] * scale
        background, shadow = work / "background.png", work / "shadow.png"
        magick(wallpaper, "-profile", SRGB, "-resize", f"{width}x{height}^", "-gravity", "center",
               "-extent", f"{width}x{height}", "-depth", 8, background)
        magick("-size", f"{width}x{height}", "xc:none", "-fill", MAC_LAYOUT["shadowOpacity"], "-draw",
               f"roundrectangle {left},{top+offset} {left+window_width-1},{top+window_height-1+offset} {radius},{radius}",
               "-blur", f"0x{blur}", "-depth", 8, shadow)
        magick(background, shadow, "-compose", "Over", "-composite", window,
               "-geometry", f"+{left}+{top}", "-composite", screen)
    if spec["layer"] is not None:
        mask = work / "screen-mask.png"
        magick(f"{template}[{spec['layer']}]", "+repage", "-alpha", "extract", mask)
        magick(screen, mask, "-alpha", "off", "-compose", "CopyOpacity", "-composite", screen)
    magick("-size", f"{canvas_width}x{canvas_height}", "xc:none", screen,
           "-geometry", f"+{x}+{y}", "-compose", "Over", "-composite", frame,
           "-geometry", "+0+0", "-composite", "-profile", SRGB,
           "-depth", 8, "-define", "png:color-type=6", destination)


def publish(staged, output, replace=False):
    """Leave prior exports intact; roll back this batch if publishing fails."""
    files = sorted(staged.iterdir())
    if not replace and any((output / path.name).exists() for path in files):
        raise FileExistsError(f"Matching exports already exist in {output}; use a fresh capture directory")
    created = not output.exists()
    output.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".framing-backup-", dir=output.parent) as temporary:
        backup = pathlib.Path(temporary)
        published, saved = [], []
        try:
            for path in files:
                target = output / path.name
                if replace and target.exists():
                    if not target.is_file():
                        raise ValueError(f"Expected a file: {target}")
                    target.rename(backup / target.name)
                    saved.append(target)
                # Exclusive creation protects existing exports even if another render finishes first.
                with target.open("xb") as destination:
                    published.append(target)
                    with path.open("rb") as source:
                        shutil.copyfileobj(source, destination)
        except BaseException:
            for path in published:
                path.unlink()
            for target in saved:
                (backup / target.name).rename(target)
            if created and not any(output.iterdir()):
                output.rmdir()
            raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("captures", type=pathlib.Path)
    parser.add_argument("--device", choices=DEVICES, required=True)
    parser.add_argument("--frame", type=pathlib.Path, required=True, help="Apple hardware PNG")
    parser.add_argument("--template", type=pathlib.Path, required=True, help="Matching Apple PSD")
    parser.add_argument("--wallpaper-light", type=pathlib.Path)
    parser.add_argument("--wallpaper-dark", type=pathlib.Path)
    parser.add_argument("--screen", choices=SCREENS, action="append", help="Capture to frame; default: all three")
    parser.add_argument("--replace", action="store_true", help="Replace matching exports after rendering succeeds")
    args = parser.parse_args(argv)
    if not shutil.which("magick"):
        parser.error("ImageMagick 7 is required (brew install imagemagick)")
    version = subprocess.check_output(["magick", "-version"], text=True).splitlines()[0]
    if not version.startswith("Version: ImageMagick 7."):
        parser.error("ImageMagick 7 is required")
    captures = args.captures.resolve()
    frame, template = args.frame.resolve(), args.template.resolve()
    if not captures.is_dir():
        parser.error(f"Capture directory does not exist: {captures}")
    wallpapers = {mode: getattr(args, f"wallpaper_{mode}") for mode in ("light", "dark")}
    if args.device != "iphone-18-pro" and not all(wallpapers.values()):
        parser.error("Mac frames require --wallpaper-light and --wallpaper-dark")
    if args.device == "iphone-18-pro" and any(wallpapers.values()):
        parser.error("iPhone framing does not use wallpapers")
    wallpapers = {mode: path.resolve() if path else None for mode, path in wallpapers.items()}
    sources = [(captures / f"{screen}-{mode}.png", mode)
               for screen in dict.fromkeys(args.screen or SCREENS) for mode in ("light", "dark")]
    for path in [frame, template, SRGB, *filter(None, wallpapers.values()), *(p for p, _ in sources)]:
        if not path.is_file():
            parser.error(f"File does not exist: {path}")
    validate_assets(args.device, frame, template)
    for source, _ in sources:
        size = dimensions(source)
        if args.device == "iphone-18-pro" and size != DEVICES[args.device]["screen"][:2]:
            parser.error(f"{source.name} must match the native iPhone screen; images are never resized")
    output = captures / "framed"
    names = [f"{source.stem}-{args.device}.png" for source, _ in sources]
    manifest_name = f"{args.device}.json"
    if not args.replace and any((output / name).exists() for name in [*names, manifest_name]):
        parser.error(f"Matching exports already exist in {output}; use a fresh capture directory")
    existing = {path.name for path in output.glob(f"*-{args.device}.png")}
    if args.replace and existing - set(names):
        parser.error("--replace must include all previously framed screens for this device")
    # Render outside framed/ so a failed or interrupted render cannot expose an incomplete export.
    with tempfile.TemporaryDirectory(prefix=".framing-", dir=captures) as temporary:
        work = pathlib.Path(temporary)
        staged = work / "exports"
        staged.mkdir()
        for (source, mode), name in zip(sources, names):
            render(source, staged / name, args.device, frame, template, wallpapers[mode], work)
        metadata = {
            "device": args.device, "geometry": DEVICES[args.device], "renderer": version,
            "layout": MAC_LAYOUT if args.device != "iphone-18-pro" else {"resize": False},
            "script": fingerprint(pathlib.Path(__file__).resolve()),
            "frame": fingerprint(frame), "template": fingerprint(template),
            "wallpapers": {mode: fingerprint(path) for mode, path in wallpapers.items() if path},
            "captures": [fingerprint(source) for source, _ in sources],
            "outputs": {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in staged.iterdir()},
        }
        (staged / manifest_name).write_text(json.dumps(metadata, indent=2) + "\n")
        publish(staged, output, replace=args.replace)
    print(f"Framed screenshots: {output}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from error
