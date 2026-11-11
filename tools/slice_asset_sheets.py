#!/usr/bin/env python3
"""Slice generated 4x4 sprite sheets into transparent, tightly cropped runtime PNGs."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "game" / "art"
OUTPUT = ROOT / "assets" / "game" / "sprites"

SHEETS = {
    "colonists_sheet.png": [
        "colonist_00", "colonist_01", "colonist_02", "colonist_03",
        "colonist_04", "colonist_05", "colonist_06", "colonist_07",
        "colonist_08", "colonist_09", "colonist_10", "colonist_11",
        "colonist_12", "colonist_13", "colonist_14", "colonist_15",
    ],
    "buildings_sheet.png": [
        "cabin", "longhouse", "cookhouse", "food_shed",
        "stockpile", "workshop", "forge", "clinic",
        "farm_plot", "well", "wall", "gate",
        "watchtower", "lumber_camp", "mine", "research_desk",
    ],
    "nature_sheet.png": [
        "pine", "oak", "birch", "stump",
        "berry_bush", "soil_plot", "wheat", "pumpkin",
        "boulder", "stone_outcrop", "iron_vein", "coal_seam",
        "clay_deposit", "reeds", "mushrooms", "dead_shrub",
    ],
    "resources_sheet.png": [
        "wood", "stone", "ore", "coal",
        "clay", "berries", "fish", "meat",
        "meal", "bread", "herbs", "medicine",
        "tools", "axe", "seeds", "cloth",
    ],
    "wildlife_sheet.png": [
        "wolf_grey", "wolf_black", "bear", "boar",
        "deer_stag", "deer_doe", "rabbit", "fox",
        "badger", "beaver", "turkey", "crow",
        "owl", "trout", "snake", "raccoon",
    ],
}


def slice_sheet(path: Path, names: list[str]) -> None:
    image = Image.open(path).convert("RGBA")
    cell_w = image.width // 4
    cell_h = image.height // 4
    for index, name in enumerate(names):
        col, row = index % 4, index // 4
        cell = image.crop((col * cell_w, row * cell_h, (col + 1) * cell_w, (row + 1) * cell_h))
        alpha = cell.getchannel("A")
        bbox = alpha.getbbox()
        if bbox is None:
            raise ValueError(f"Empty sprite cell: {path.name}[{index}] {name}")
        pad = 8
        bbox = (
            max(0, bbox[0] - pad), max(0, bbox[1] - pad),
            min(cell.width, bbox[2] + pad), min(cell.height, bbox[3] + pad),
        )
        sprite = cell.crop(bbox)
        # Do not upscale; cap the longest side while retaining crisp nearest-neighbour pixels.
        if max(sprite.size) > 384:
            ratio = 384.0 / max(sprite.size)
            sprite = sprite.resize(
                (max(1, round(sprite.width * ratio)), max(1, round(sprite.height * ratio))),
                Image.Resampling.NEAREST,
            )
        sprite.save(OUTPUT / f"{name}.png", optimize=True)
        print(f"{name:18s} {sprite.width:3d}x{sprite.height:<3d}  <- {path.name}")


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for sheet_name, names in SHEETS.items():
        sheet_path = SOURCE / sheet_name
        if not sheet_path.exists():
            raise FileNotFoundError(sheet_path)
        slice_sheet(sheet_path, names)


if __name__ == "__main__":
    main()
