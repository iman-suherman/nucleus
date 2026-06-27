#!/usr/bin/env python3
"""Prepare the Nucleus app icon: remove black matte, trim, and fit macOS dock safe area."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops
except ImportError:
    print(
        "error: Pillow is required. Install with: python3 -m pip install -r requirements.txt",
        file=sys.stderr,
    )
    raise SystemExit(1) from None

# Slightly tighter than the usual 8% inset so Nucleus matches peer icon visual weight.
DEFAULT_PADDING_RATIO = 0.05
DEFAULT_INNER_TRIM = 0
DEFAULT_WHITE_THRESHOLD = 235
DEFAULT_HALO_LUMINANCE = 85
DEFAULT_HALO_SATURATION = 50


def _luminance(red: int, green: int, blue: int) -> int:
    return (red * 299 + green * 587 + blue * 114) // 1000


def _saturation(red: int, green: int, blue: int) -> int:
    maximum = max(red, green, blue)
    minimum = min(red, green, blue)
    if maximum == 0:
        return 0
    return (maximum - minimum) * 255 // maximum


def remove_near_white_background(
    image: Image.Image,
    threshold: int = DEFAULT_WHITE_THRESHOLD,
) -> Image.Image:
    """Flood-fill near-white matte and drop shadow from corners; keeps enclosed artwork (e.g. white letterforms)."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()

    def is_background(red: int, green: int, blue: int) -> bool:
        return _luminance(red, green, blue) >= threshold

    visited = [[False] * width for _ in range(height)]
    queue: list[tuple[int, int]] = []

    for x, y in ((0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)):
        red, green, blue, _alpha = pixels[x, y]
        if is_background(red, green, blue):
            visited[y][x] = True
            queue.append((x, y))

    while queue:
        x, y = queue.pop()
        pixels[x, y] = (0, 0, 0, 0)
        for next_x, next_y in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if not (0 <= next_x < width and 0 <= next_y < height):
                continue
            if visited[next_y][next_x]:
                continue
            red, green, blue, _alpha = pixels[next_x, next_y]
            if is_background(red, green, blue):
                visited[next_y][next_x] = True
                queue.append((next_x, next_y))

    return rgba


def remove_light_halo(
    image: Image.Image,
    *,
    luminance_threshold: int = DEFAULT_HALO_LUMINANCE,
    saturation_threshold: int = DEFAULT_HALO_SATURATION,
) -> Image.Image:
    """Remove neutral gray drop-shadow pixels left outside the rounded icon after matte removal."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()

    def is_halo(red: int, green: int, blue: int) -> bool:
        return (
            _luminance(red, green, blue) >= luminance_threshold
            and _saturation(red, green, blue) <= saturation_threshold
        )

    visited = [[False] * width for _ in range(height)]
    queue: list[tuple[int, int]] = []

    for y in range(height):
        for x in range(width):
            if pixels[x, y][3] != 0:
                continue
            for next_x, next_y in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if not (0 <= next_x < width and 0 <= next_y < height):
                    continue
                if visited[next_y][next_x] or pixels[next_x, next_y][3] == 0:
                    continue
                red, green, blue, _alpha = pixels[next_x, next_y]
                if is_halo(red, green, blue):
                    visited[next_y][next_x] = True
                    queue.append((next_x, next_y))

    while queue:
        x, y = queue.pop()
        red, green, blue, _alpha = pixels[x, y]
        if not is_halo(red, green, blue):
            continue
        pixels[x, y] = (0, 0, 0, 0)
        for next_x, next_y in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if not (0 <= next_x < width and 0 <= next_y < height):
                continue
            if visited[next_y][next_x] or pixels[next_x, next_y][3] == 0:
                continue
            red, green, blue, _alpha = pixels[next_x, next_y]
            if is_halo(red, green, blue):
                visited[next_y][next_x] = True
                queue.append((next_x, next_y))

    return rgba


def remove_black_background(image: Image.Image, threshold: int = 35) -> Image.Image:
    """Turn near-black pixels transparent while preserving rounded edge anti-aliasing."""
    rgba = image.convert("RGBA")
    red, green, blue, alpha = rgba.split()
    luminance = Image.merge("RGB", (red, green, blue)).convert("L")
    content_mask = luminance.point(lambda value: 255 if value > threshold else 0)
    if alpha.getextrema()[0] < 255:
        content_mask = ImageChops.multiply(content_mask, alpha)
    rgba.putalpha(content_mask)
    return rgba


def detect_background_mode(image: Image.Image) -> str:
    """Choose matte removal based on corner luminance."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    corners = (
        rgba.getpixel((0, 0)),
        rgba.getpixel((width - 1, 0)),
        rgba.getpixel((0, height - 1)),
        rgba.getpixel((width - 1, height - 1)),
    )
    average_luminance = sum(
        (red * 299 + green * 587 + blue * 114) // 1000 for red, green, blue, _alpha in corners
    ) // len(corners)
    return "white" if average_luminance >= 128 else "black"


def remove_matte_background(image: Image.Image, *, threshold: int = 35) -> Image.Image:
    if detect_background_mode(image) == "white":
        cleaned = remove_near_white_background(image, threshold=max(threshold, DEFAULT_WHITE_THRESHOLD))
        return remove_light_halo(cleaned)
    return remove_black_background(image, threshold=threshold)


def trim_transparent_bounds(
    image: Image.Image,
    margin: int = 0,
    inner_trim: int = 0,
) -> Image.Image:
    """Crop to visible content, optionally shaving an inner matte bezel."""
    alpha = image.split()[3]
    bbox = alpha.point(lambda value: 255 if value > 8 else 0).getbbox()
    if bbox is None:
        return image

    left, top, right, bottom = bbox
    left = max(0, left - margin + inner_trim)
    top = max(0, top - margin + inner_trim)
    right = min(image.width, right + margin - inner_trim)
    bottom = min(image.height, bottom + margin - inner_trim)
    if right <= left or bottom <= top:
        return image
    return image.crop((left, top, right, bottom))


def fit_to_dock_canvas(
    image: Image.Image,
    size: int = 1024,
    padding_ratio: float = DEFAULT_PADDING_RATIO,
) -> Image.Image:
    """
    Center icon content on a transparent square canvas.

    macOS applies its own squircle mask in the Dock, so we keep a small inset to
    avoid clipping the artwork's rounded corners.
    """
    content_limit = int(size * (1 - (padding_ratio * 2)))
    content = image.copy()
    content.thumbnail((content_limit, content_limit), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset_x = (size - content.width) // 2
    offset_y = (size - content.height) // 2
    canvas.paste(content, (offset_x, offset_y), content)
    return canvas


def fit_to_full_bleed_canvas(image: Image.Image, size: int = 1024) -> Image.Image:
    """Scale artwork to cover the full square — iOS applies its own rounded mask."""
    content = image.convert("RGBA")
    scale = max(size / content.width, size / content.height)
    new_width = max(1, round(content.width * scale))
    new_height = max(1, round(content.height * scale))
    resized = content.resize((new_width, new_height), Image.Resampling.LANCZOS)
    left = (new_width - size) // 2
    top = (new_height - size) // 2
    return resized.crop((left, top, left + size, top + size))


def background_color_for_flatten(image: Image.Image) -> tuple[int, int, int]:
    """Pick a fill color from opaque edge pixels so anti-aliased corners stay seamless."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    samples: list[tuple[int, int, int]] = []

    for x in range(width):
        for y in (0, height - 1):
            red, green, blue, alpha = rgba.getpixel((x, y))
            if alpha > 200:
                samples.append((red, green, blue))
    for y in range(1, height - 1):
        for x in (0, width - 1):
            red, green, blue, alpha = rgba.getpixel((x, y))
            if alpha > 200:
                samples.append((red, green, blue))

    if not samples:
        red, green, blue, _alpha = rgba.getpixel((width // 2, height // 2))
        return (red, green, blue)

    return (
        sum(color[0] for color in samples) // len(samples),
        sum(color[1] for color in samples) // len(samples),
        sum(color[2] for color in samples) // len(samples),
    )


def flatten_for_app_store(image: Image.Image) -> Image.Image:
    """Remove alpha using the icon's own background color (never white matte)."""
    rgba = image.convert("RGBA")
    background = Image.new("RGBA", rgba.size, (*background_color_for_flatten(rgba), 255))
    background.paste(rgba, mask=rgba.split()[3])
    return background.convert("RGB")


def prepare_icon(
    source_path: Path,
    output_path: Path,
    *,
    size: int = 1024,
    threshold: int = 35,
    padding_ratio: float = DEFAULT_PADDING_RATIO,
    inner_trim: int = DEFAULT_INNER_TRIM,
) -> None:
    source = Image.open(source_path)
    cleaned = remove_matte_background(source, threshold=threshold)
    trimmed = trim_transparent_bounds(cleaned, margin=0, inner_trim=inner_trim)
    prepared = fit_to_dock_canvas(trimmed, size=size, padding_ratio=padding_ratio)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    prepared.save(output_path, format="PNG", optimize=True)
    print(
        f"Prepared icon: {source_path.name} ({source.size[0]}x{source.size[1]}) "
        f"-> {output_path.name} ({prepared.size[0]}x{prepared.size[1]}, "
        f"padding={padding_ratio:.1%}, inner_trim={inner_trim}px)"
    )


def prepare_ios_icon(
    source_path: Path,
    output_path: Path,
    *,
    size: int = 1024,
    threshold: int = 35,
    inner_trim: int = DEFAULT_INNER_TRIM,
) -> None:
    source = Image.open(source_path)
    cleaned = remove_matte_background(source, threshold=threshold)
    trimmed = trim_transparent_bounds(cleaned, margin=0, inner_trim=inner_trim)
    filled = fit_to_full_bleed_canvas(trimmed, size=size)
    prepared = flatten_for_app_store(filled)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    prepared.save(output_path, format="PNG", optimize=True)
    print(
        f"Prepared iOS icon: {source_path.name} ({source.size[0]}x{source.size[1]}) "
        f"-> {output_path.name} ({prepared.size[0]}x{prepared.size[1]}, full bleed)"
    )


def resolve_source(assets_dir: Path, explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit

    raw = assets_dir / "AppIconSource.raw.png"
    uploaded = assets_dir / "AppIconSource.png"

    if raw.exists():
        return raw
    if uploaded.exists():
        return uploaded
    raise SystemExit(f"No icon source found in {assets_dir}")


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    assets_dir = repo_root / "app" / "Nucleus" / "Assets"

    parser = argparse.ArgumentParser(description="Prepare Nucleus app icon for macOS.")
    parser.add_argument(
        "--source",
        type=Path,
        default=None,
        help="Master icon (defaults to AppIconSource.raw.png, then AppIconSource.png)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=assets_dir / "AppIconSource.png",
        help="Prepared icon used by the Swift icon generator",
    )
    parser.add_argument("--size", type=int, default=1024)
    parser.add_argument("--threshold", type=int, default=35)
    parser.add_argument(
        "--padding-ratio",
        type=float,
        default=DEFAULT_PADDING_RATIO,
        help="Inset from each edge as a fraction of icon size (default: 5.5%%)",
    )
    parser.add_argument(
        "--inner-trim",
        type=int,
        default=DEFAULT_INNER_TRIM,
        help="Pixels to crop inside the outer matte bezel (default: 0)",
    )
    parser.add_argument(
        "--ios-output",
        type=Path,
        default=None,
        help="Write a full-bleed App Store icon PNG (no dock inset, no white matte)",
    )
    parser.add_argument(
        "--ios-logo-output",
        type=Path,
        default=None,
        help="Optional second output for in-app logo artwork",
    )
    args = parser.parse_args()

    source_path = resolve_source(assets_dir, args.source)
    if not source_path.exists():
        raise SystemExit(f"Source icon not found: {source_path}")

    if args.ios_output:
        prepare_ios_icon(
            source_path,
            args.ios_output,
            size=args.size,
            threshold=args.threshold,
            inner_trim=args.inner_trim,
        )
        if args.ios_logo_output:
            prepare_ios_icon(
                source_path,
                args.ios_logo_output,
                size=args.size,
                threshold=args.threshold,
                inner_trim=args.inner_trim,
            )
        return

    prepare_icon(
        source_path,
        args.output,
        size=args.size,
        threshold=args.threshold,
        padding_ratio=args.padding_ratio,
        inner_trim=args.inner_trim,
    )


if __name__ == "__main__":
    main()
