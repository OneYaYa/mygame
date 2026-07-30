#!/usr/bin/env python3
"""Offline, traceable pixel-art processing for TIME ECHO.

The tool only writes paths declared under res://assets/images/processed/ and never
overwrites source_art. It uses nearest-neighbour resampling and preserves aspect
ratio inside the manifest's integer display canvas.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable

try:
    from PIL import Image
except ImportError as exc:  # pragma: no cover - dependency diagnostic
    raise SystemExit("Pillow is required: python -m pip install Pillow") from exc


GODOT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = GODOT_ROOT / "data" / "art_manifest.json"
PROCESSED_ROOT = (GODOT_ROOT / "assets" / "images" / "processed").resolve()


@dataclass
class Result:
    asset_id: str
    source: str
    output: str
    source_size: list[int]
    output_size: list[int]
    alpha_bbox: list[int] | None
    residual_pink_pixels: int
    status: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Process manifest art without touching source files.")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--asset-id", action="append", default=[], help="Process one asset; repeatable.")
    parser.add_argument("--all", action="store_true", help="Process all enabled processed assets.")
    parser.add_argument("--dry-run", action="store_true", help="Report intended operations without writing.")
    parser.add_argument("--validate", action="store_true", help="Validate sources and processed outputs.")
    parser.add_argument("--remove-pink", action="store_true", help="Remove near-magenta background and edge spill.")
    parser.add_argument("--padding", type=int, default=2, help="Transparent output safety margin in pixels.")
    return parser.parse_args()


def res_to_path(value: str) -> Path:
    if not value.startswith("res://"):
        raise ValueError(f"Expected a res:// path, got {value!r}")
    return (GODOT_ROOT / value.removeprefix("res://")).resolve()


def read_manifest(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data.get("assets"), list):
        raise ValueError("art_manifest.json must contain an assets array")
    ids: set[str] = set()
    for entry in data["assets"]:
        asset_id = str(entry.get("asset_id", ""))
        if not asset_id:
            raise ValueError("Manifest entry is missing asset_id")
        if asset_id in ids:
            raise ValueError(f"Duplicate asset_id: {asset_id}")
        ids.add(asset_id)
    return data


def selected_assets(manifest: dict, wanted: set[str], process_all: bool) -> Iterable[dict]:
    found: set[str] = set()
    for entry in manifest["assets"]:
        asset_id = str(entry["asset_id"])
        explicit = asset_id in wanted
        runtime = str(entry.get("runtime_path", ""))
        eligible = "/processed/" in runtime and bool(entry.get("enabled", True))
        if explicit or (process_all and eligible):
            found.add(asset_id)
            yield entry
    missing = wanted - found
    if missing:
        raise ValueError(f"Unknown asset_id(s): {', '.join(sorted(missing))}")


def remove_magenta(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    removed: list[tuple[int, int]] = []
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            if alpha and red >= 235 and blue >= 225 and green <= 55:
                pixels[x, y] = (red, green, blue, 0)
                removed.append((x, y))
    if not removed:
        return rgba
    # Decontaminate only the translucent fringe touching removed background.
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0 or not (red > green * 1.55 and blue > green * 1.45):
                continue
            neighbours: list[tuple[int, int, int]] = []
            for oy in (-1, 0, 1):
                for ox in (-1, 0, 1):
                    nx, ny = x + ox, y + oy
                    if 0 <= nx < width and 0 <= ny < height:
                        nr, ng, nb, na = pixels[nx, ny]
                        if na > 160 and not (nr > ng * 1.55 and nb > ng * 1.45):
                            neighbours.append((nr, ng, nb))
            if neighbours:
                count = len(neighbours)
                pixels[x, y] = (
                    sum(value[0] for value in neighbours) // count,
                    sum(value[1] for value in neighbours) // count,
                    sum(value[2] for value in neighbours) // count,
                    alpha,
                )
    return rgba


def residual_pink_count(image: Image.Image) -> int:
    rgba = image.convert("RGBA")
    pixels = rgba.get_flattened_data() if hasattr(rgba, "get_flattened_data") else rgba.getdata()
    return sum(
        1
        for red, green, blue, alpha in pixels
        if alpha and red >= 245 and green <= 32 and blue >= 245
    )


def fit_to_canvas(image: Image.Image, target: tuple[int, int], padding: int, trim: bool) -> tuple[Image.Image, tuple[int, int, int, int] | None]:
    rgba = image.convert("RGBA")
    bbox = rgba.getchannel("A").getbbox() if trim else (0, 0, rgba.width, rgba.height)
    if bbox is None:
        raise ValueError("Source image has no visible pixels")
    content = rgba.crop(bbox)
    available_width = max(1, target[0] - padding * 2)
    available_height = max(1, target[1] - padding * 2)
    ratio = min(available_width / content.width, available_height / content.height)
    size = (max(1, round(content.width * ratio)), max(1, round(content.height * ratio)))
    resized = content.resize(size, Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", target, (0, 0, 0, 0))
    x = (target[0] - size[0]) // 2
    y = target[1] - padding - size[1]
    canvas.alpha_composite(resized, (x, y))
    return canvas, bbox


def validate_entry(entry: dict, require_output: bool) -> list[str]:
    errors: list[str] = []
    asset_id = str(entry.get("asset_id", "?"))
    try:
        source = res_to_path(str(entry.get("source_path", "")))
        output = res_to_path(str(entry.get("runtime_path", "")))
    except ValueError as exc:
        return [f"{asset_id}: {exc}"]
    if not source.is_file():
        errors.append(f"{asset_id}: missing source {source}")
    if "/processed/" in str(entry.get("runtime_path", "")):
        try:
            output.relative_to(PROCESSED_ROOT)
        except ValueError:
            errors.append(f"{asset_id}: processed output escapes processed root")
    if source == output:
        errors.append(f"{asset_id}: source and output paths are identical")
    size = entry.get("recommended_display_size")
    if not isinstance(size, list) or len(size) != 2 or min(int(size[0]), int(size[1])) <= 0:
        errors.append(f"{asset_id}: invalid recommended_display_size")
    if require_output and bool(entry.get("enabled", True)) and "/processed/" in str(entry.get("runtime_path", "")):
        if not output.is_file():
            errors.append(f"{asset_id}: missing processed output {output}")
        else:
            with Image.open(output) as image:
                expected = (int(size[0]), int(size[1]))
                if image.size != expected:
                    errors.append(f"{asset_id}: output {image.size} != expected {expected}")
                pink = residual_pink_count(image)
                if pink:
                    errors.append(f"{asset_id}: {pink} residual magenta pixels")
    return errors


def process(entry: dict, args: argparse.Namespace) -> Result:
    asset_id = str(entry["asset_id"])
    source = res_to_path(str(entry["source_path"]))
    output = res_to_path(str(entry["runtime_path"]))
    if not source.is_file():
        raise FileNotFoundError(f"{asset_id}: missing source {source}")
    if source == output:
        raise ValueError(f"{asset_id}: refusing to overwrite source")
    try:
        output.relative_to(PROCESSED_ROOT)
    except ValueError as exc:
        raise ValueError(f"{asset_id}: output is outside processed directory") from exc
    with Image.open(source) as opened:
        original = opened.convert("RGBA")
    prepared = remove_magenta(original) if args.remove_pink else original
    target_list = entry["recommended_display_size"]
    target = (int(target_list[0]), int(target_list[1]))
    is_surface = str(entry.get("category", "")).endswith("_texture")
    result_image, bbox = fit_to_canvas(prepared, target, 0 if is_surface else max(0, args.padding), not is_surface)
    pink = residual_pink_count(result_image)
    status = "dry-run" if args.dry_run else "written"
    if not args.dry_run:
        output.parent.mkdir(parents=True, exist_ok=True)
        result_image.save(output, format="PNG", optimize=True)
    return Result(
        asset_id=asset_id,
        source=str(source),
        output=str(output),
        source_size=list(original.size),
        output_size=list(result_image.size),
        alpha_bbox=list(bbox) if bbox else None,
        residual_pink_pixels=pink,
        status=status,
    )


def main() -> int:
    args = parse_args()
    manifest_path = args.manifest.resolve()
    manifest = read_manifest(manifest_path)
    wanted = set(args.asset_id)
    if not args.all and not wanted and not args.validate:
        raise SystemExit("Choose --all, --asset-id ASSET_ID, or --validate")
    errors: list[str] = []
    if args.validate:
        for entry in manifest["assets"]:
            errors.extend(validate_entry(entry, require_output=True))
    results: list[Result] = []
    if args.all or wanted:
        for entry in selected_assets(manifest, wanted, args.all):
            try:
                result = process(entry, args)
                results.append(result)
                print(f"{result.status:7} {result.asset_id:34} {result.source_size} -> {result.output_size} pink={result.residual_pink_pixels}")
            except (OSError, ValueError, KeyError) as exc:
                errors.append(str(exc))
    if results and not args.dry_run:
        report = {
            "manifest": str(manifest_path),
            "nearest_neighbour": True,
            "source_files_overwritten": False,
            "results": [asdict(result) for result in results],
        }
        report_path = PROCESSED_ROOT / "processing_report.json"
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"report  {report_path}")
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
