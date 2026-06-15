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


def remove_near_white_background(
    image: Image.Image,
    threshold: int = DEFAULT_WHITE_THRESHOLD,
) -> Image.Image:
    """Flood-fill near-white matte and drop shadow from corners; keeps enclosed artwork (e.g. white letterforms)."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()

    def is_background(red: int, green: int, blue: int) -> bool:
        luminance = (red * 299 + green * 587 + blue * 114) // 1000
        return luminance >= threshold

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
        return remove_near_white_background(image, threshold=max(threshold, DEFAULT_WHITE_THRESHOLD))
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
    args = parser.parse_args()

    source_path = resolve_source(assets_dir, args.source)
    if not source_path.exists():
        raise SystemExit(f"Source icon not found: {source_path}")

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
