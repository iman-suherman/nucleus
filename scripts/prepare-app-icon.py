#!/usr/bin/env python3
"""Prepare the Nucleus app icon with macOS-style rounded corners."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    print(
        "error: Pillow is required. Install with: python3 -m pip install -r requirements.txt",
        file=sys.stderr,
    )
    raise SystemExit(1) from None

# macOS squircle corner radius is ~22.37% of the icon edge.
DEFAULT_RADIUS_RATIO = 0.2237


def ensure_square(image: Image.Image, size: int) -> Image.Image:
    """Resize and center artwork on a square RGBA canvas."""
    rgba = image.convert("RGBA")
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rgba.thumbnail((size, size), Image.Resampling.LANCZOS)
    offset_x = (size - rgba.width) // 2
    offset_y = (size - rgba.height) // 2
    canvas.paste(rgba, (offset_x, offset_y), rgba)
    return canvas


def apply_rounded_corners(
    image: Image.Image,
    *,
    radius_ratio: float = DEFAULT_RADIUS_RATIO,
) -> Image.Image:
    """Clip the icon to a rounded rectangle with anti-aliased edges."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    radius = max(1, int(min(width, height) * radius_ratio))

    mask = Image.new("L", rgba.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, width - 1, height - 1), radius=radius, fill=255)

    rounded = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    rounded.paste(rgba, (0, 0), mask)
    return rounded


def prepare_icon(
    source_path: Path,
    output_path: Path,
    *,
    size: int = 1024,
    radius_ratio: float = DEFAULT_RADIUS_RATIO,
) -> None:
    source = Image.open(source_path)
    squared = ensure_square(source, size)
    rounded = apply_rounded_corners(squared, radius_ratio=radius_ratio)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    rounded.save(output_path, format="PNG", optimize=True)
    print(
        f"Prepared icon: {source_path.name} ({source.size[0]}x{source.size[1]}) "
        f"-> {output_path.name} ({rounded.size[0]}x{rounded.size[1]}, "
        f"radius={int(size * radius_ratio)}px)"
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

    parser = argparse.ArgumentParser(description="Prepare Nucleus app icon with rounded corners.")
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
    parser.add_argument(
        "--radius-ratio",
        type=float,
        default=DEFAULT_RADIUS_RATIO,
        help="Corner radius as a fraction of icon size (default: macOS squircle)",
    )
    args = parser.parse_args()

    source_path = resolve_source(assets_dir, args.source)
    if not source_path.exists():
        raise SystemExit(f"Source icon not found: {source_path}")

    prepare_icon(
        source_path,
        args.output,
        size=args.size,
        radius_ratio=args.radius_ratio,
    )


if __name__ == "__main__":
    main()
