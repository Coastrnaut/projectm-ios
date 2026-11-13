#!/usr/bin/env python3
"""Build the preset library index and archive (feature 002; tasks T204, T205, T214).

Inputs: the 28 Included presets (Apps/projectM-iOS/Resources/Presets, joined with its LICENSES.md),
the pinned preset-pack submodules under Vendor/presets/ (research R-21), and the committed
PresetBlocklist.json and PresetExclusions.txt in Apps/projectM-iOS/Resources. Outputs, all written
to --out by the app's build (research R-30: generated, never committed, to keep the repository
small):

  PresetIndex.json      one record per unique preset (contracts/preset-index.schema.json); a record
                        whose text the flash risk screen flags carries "flash": [rule ids]
                        (ACC-002, scripts/preset_flash_risk.py, ADR-0014)
  PresetPacks.json      one record per source
  PresetArchive.bin     the pack presets, raw-deflate compressed in chunks of 64
  PresetTextures/<pack>/...   the packs' texture images, relative paths kept

De-duplication by git blob hash, first occurrence wins in the order Included, cream-of-the-crop,
projectm-classic, milkdrop-original, en-d (FR-102); `.milk` files only (case-insensitive);
hashes in Resources/PresetBlocklist.json and ids in an --exclusions file are skipped (FR-103).

    python3 scripts/build_preset_index.py --out DIR     # skipped when the stamp is unchanged

Archive format (little-endian): "PMPA", u32 version (1), u32 preset count, u32 chunk size,
u32 chunk count; chunk table (u64 offset, u32 compressed length, u32 raw length) per chunk; preset
table (u32 chunk, u32 offset in chunk, u32 length) per pack preset, in PresetIndex.json order of
the non-Included records; then the chunks (raw deflate, RFC 1951).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import unicodedata
import zlib
from pathlib import Path

import preset_flash_risk

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Apps/projectM-iOS/Resources"
INCLUDED_DIR = RESOURCES / "Presets"
PACKS_DIR = ROOT / "Vendor/presets"

PACKS = [  # priority order after Included (FR-102)
    ("cream-of-the-crop", "Cream of the Crop"),
    ("projectm-classic", "projectM Classic"),
    ("milkdrop-original", "Milkdrop Original"),
    ("en-d", "En D"),
]
TEXTURE_PACK = ("milkdrop-texture-pack", "Milkdrop Texture Pack")
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".tga", ".bmp", ".dds"}
CHUNK_SIZE = 64
UPSTREAM = "https://github.com/projectM-visualizer/presets-{}"
NO_LICENSE = ("No license file in the repository; distributed under the projectM team's basis for "
              "these packs (assumed public domain; removed on the author's request). See ADR-0007.")


def blob_hash(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def split_author(stem: str) -> tuple[str, str]:
    if " - " in stem:
        author, title = stem.split(" - ", 1)
        if author.strip() and title.strip():
            return author.strip(), title.strip()
    return "Unknown", stem


def included_rows(included_dir: Path) -> dict[str, tuple[str, str]]:
    """file path → (display name, author) from LICENSES.md."""
    rows: dict[str, tuple[str, str]] = {}
    text = (included_dir / "LICENSES.md").read_text(encoding="utf-8")
    for line in text.splitlines():
        if not line.startswith("| ") or line.startswith("| File") or line.startswith("|---"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split(" | ")]
        if len(cells) >= 4:
            rows[cells[0]] = (cells[1], cells[3])
    return rows


def git_head(path: Path) -> str:
    try:
        return subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"], capture_output=True,
                              text=True, check=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "0" * 40


def license_text(pack_dir: Path) -> str:
    for name in ("LICENSE.md", "LICENSE", "LICENSE.txt"):
        f = pack_dir / name
        if f.is_file():
            return f.read_text(encoding="utf-8", errors="replace").strip()
    return NO_LICENSE


def flag(record: dict, data: bytes) -> dict:
    """Adds "flash" to a record whose text the flash risk screen flags (ACC-002-R1); unflagged
    records get no field (ACC-002-R13)."""
    rules = preset_flash_risk.classify(data.decode("utf-8", errors="replace"))
    if rules:
        record["flash"] = rules
    return record


def build(included_dir: Path, packs_dir: Path, blocklist: set[str], exclusions: set[str]):
    """Returns (index records, pack records, archive entries [(record, bytes)])."""
    seen: set[str] = set()
    records: list[dict] = []
    payload: dict[str, bytes] = {}
    rows = included_rows(included_dir)
    for f in sorted(p for p in included_dir.rglob("*") if p.is_file() and p.suffix.lower() == ".milk"):
        rel = f.relative_to(included_dir).as_posix()
        data = f.read_bytes()
        h = blob_hash(data)
        seen.add(h)
        name, author = rows.get(rel, (f.stem, split_author(f.stem)[0]))
        records.append(flag({"id": rel, "name": name, "author": author, "source": "included",
                             "folder": [], "path": f"Presets/{rel}", "hash": h}, data))
    pack_records = [{"id": "included", "title": "Included", "sourceURL": "https://github.com/Coastrnaut/frontend-uwp",
                     "commit": "82c468ee11a535c8fb4e864cd556fc8a59bdbaf3",
                     "license": "Per preset: Resources/Presets/LICENSES.md (LicenseRef-Milkdrop-PublicDomain-Assumed)",
                     "presetCount": len(records), "authors": sorted({r["author"] for r in records}, key=lambda a: (a.casefold(), a)),
                     "locked": False}]
    for pack, title in PACKS:
        pack_dir = packs_dir / pack
        files = sorted((p for p in pack_dir.rglob("*") if p.is_file() and p.suffix.lower() == ".milk"),
                       key=lambda p: p.relative_to(pack_dir).as_posix())
        added: list[dict] = []
        for f in files:
            data = f.read_bytes()
            h = blob_hash(data)
            rel = f.relative_to(pack_dir).as_posix()
            rid = f"{pack}/{rel}"
            if h in seen or h in blocklist:
                continue
            seen.add(h)   # an excluded preset's content stays out under every pack's id too
            if rid in exclusions:
                continue
            folder = list(f.relative_to(pack_dir).parent.parts)
            if pack == "milkdrop-original" and folder == ["Milkdrop-Original"]:
                folder = []
            author, name = split_author(f.stem)
            rec = flag({"id": rid, "name": name, "author": author, "source": pack, "folder": folder,
                        "path": rid, "hash": h}, data)
            added.append(rec)
            payload[rid] = data
        records.extend(added)
        pack_records.append({"id": pack, "title": title, "sourceURL": UPSTREAM.format(pack),
                             "commit": git_head(pack_dir), "license": license_text(pack_dir),
                             "presetCount": len(added),
                             "authors": sorted({r["author"] for r in added}, key=lambda a: (a.casefold(), a)), "locked": True})
    tex_dir = packs_dir / TEXTURE_PACK[0]
    pack_records.append({"id": TEXTURE_PACK[0], "title": TEXTURE_PACK[1], "sourceURL": UPSTREAM.format(TEXTURE_PACK[0]),
                         "commit": git_head(tex_dir), "license": license_text(tex_dir), "presetCount": 0,
                         "authors": [], "locked": False})
    order = {"included": 0, **{p: i + 1 for i, (p, _) in enumerate(PACKS)}}
    records.sort(key=lambda r: (order[r["source"]], [s.casefold() for s in r["folder"]], r["name"].casefold(), r["id"]))
    archive = [(r, payload[r["id"]]) for r in records if r["source"] != "included"]
    return records, pack_records, archive


def display_key(name: str) -> list:
    """Close to Foundation's localizedStandardCompare (case and diacritics ignored, digit runs by
    value, spaces < punctuation < digits < letters). The app sorts again with the real comparator;
    input already in (nearly) this order makes that sort a single pass (SC-101)."""
    folded = "".join(c for c in unicodedata.normalize("NFKD", name) if not unicodedata.combining(c)).casefold()
    key = []
    for token in re.findall(r"\d+|\D", folded):
        if token.isdigit():
            key.append((2, int(token), ""))
        elif token.isspace():
            key.append((0, 0, ""))
        elif token.isalpha():
            key.append((3, 0, token))
        else:
            key.append((1, 0, token))
    return key


def display_order(records: list[dict]) -> tuple[list[dict], list[int]]:
    """The index in display order (pack priority, then name), and for each archive entry (records
    in archive order, Included skipped) its position in that list."""
    order = {"included": 0, **{p: i + 1 for i, (p, _) in enumerate(PACKS)}}
    display = sorted(records, key=lambda r: (order[r["source"]], display_key(r["name"]), r["id"]))
    position = {r["id"]: i for i, r in enumerate(display)}
    return display, [position[r["id"]] for r in records if r["source"] != "included"]


def dumps(obj) -> str:
    """Compact JSON with one list item per line (small, deterministic, readable diffs)."""
    if isinstance(obj, dict):
        parts = []
        for key, value in obj.items():
            if isinstance(value, list) and value and isinstance(value[0], dict):
                items = ",\n".join(json.dumps(v, ensure_ascii=False, separators=(",", ":")) for v in value)
                parts.append(f"{json.dumps(key)}:[\n{items}\n]")
            else:
                parts.append(f"{json.dumps(key)}:{json.dumps(value, ensure_ascii=False, separators=(',', ':'))}")
        return "{" + ",\n".join(parts) + "}\n"
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n"


def write_archive(entries: list[tuple[dict, bytes]], out: Path) -> None:
    chunks: list[tuple[bytes, int]] = []
    table: list[tuple[int, int, int]] = []
    for start in range(0, len(entries), CHUNK_SIZE):
        raw = bytearray()
        for i, (_, data) in enumerate(entries[start:start + CHUNK_SIZE]):
            table.append((start // CHUNK_SIZE, len(raw), len(data)))
            raw += data
        comp = zlib.compressobj(9, zlib.DEFLATED, -15)
        chunks.append((comp.compress(bytes(raw)) + comp.flush(), len(raw)))
    header = struct.pack("<4sIIII", b"PMPA", 1, len(entries), CHUNK_SIZE, len(chunks))
    offset = len(header) + 16 * len(chunks) + 12 * len(table)
    chunk_table = bytearray()
    for comp, raw_len in chunks:
        chunk_table += struct.pack("<QII", offset, len(comp), raw_len)
        offset += len(comp)
    preset_table = b"".join(struct.pack("<III", *t) for t in table)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("wb") as f:
        f.write(header + chunk_table + preset_table)
        for comp, _ in chunks:
            f.write(comp)


def copy_textures(packs_dir: Path, out: Path) -> int:
    if out.exists():
        shutil.rmtree(out)
    count = 0
    for pack in [p for p, _ in PACKS] + [TEXTURE_PACK[0]]:
        base = packs_dir / pack
        for f in sorted(base.rglob("*")):
            if f.is_file() and f.suffix.lower() in IMAGE_SUFFIXES:
                dest = out / pack / f.relative_to(base)
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(f, dest)
                count += 1
    return count


def stamp(args, blocklist_file: Path, exclusions_file: Path) -> str:
    """Changes when anything that shapes the output changes (incremental builds)."""
    h = hashlib.sha256(Path(__file__).read_bytes())
    h.update(Path(preset_flash_risk.__file__).read_bytes())   # ACC-002: a rule change rebuilds the index
    for f in [args.included_dir / "LICENSES.md", blocklist_file, exclusions_file]:
        h.update(f.read_bytes() if f.exists() else b"-")
    for f in sorted(args.included_dir.rglob("*.milk")):
        h.update(f.name.encode() + f.read_bytes())
    for pack in [p for p, _ in PACKS] + [TEXTURE_PACK[0]]:
        h.update(git_head(args.packs_dir / pack).encode())
    return h.hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, required=True,
                        help="directory for PresetIndex.json, PresetPacks.json, PresetArchive.bin, PresetTextures/")
    parser.add_argument("--config", type=Path, default=RESOURCES,
                        help="directory holding PresetBlocklist.json and PresetExclusions.txt (committed)")
    parser.add_argument("--included-dir", type=Path, default=INCLUDED_DIR)
    parser.add_argument("--packs-dir", type=Path, default=PACKS_DIR)
    parser.add_argument("--stamp", type=Path, help="stamp file (default: <out>/.preset-index-stamp)")
    parser.add_argument("--force", action="store_true", help="ignore the stamp")
    parser.add_argument("--no-exclusions", action="store_true",
                        help="ignore PresetExclusions.txt (RendererLab's load sweep tests every preset, T236)")
    args = parser.parse_args(argv)

    blocklist_file = args.config / "PresetBlocklist.json"
    exclusions_file = args.config / "PresetExclusions.txt"
    blocklist = {e["hash"] for e in json.loads(blocklist_file.read_text())["hashes"]} if blocklist_file.exists() else set()
    if args.no_exclusions:
        exclusions_file = args.config / "-no-exclusions"   # also changes the stamp
    exclusions = ({l.strip() for l in exclusions_file.read_text().splitlines() if l.strip() and not l.startswith("#")}
                  if exclusions_file.exists() else set())
    missing = [p for p, _ in PACKS + [TEXTURE_PACK] if not (args.packs_dir / p).is_dir()]
    if missing:
        print(f"build_preset_index: missing pack submodules {missing}; run git submodule update --init", file=sys.stderr)
        return 2
    stamp_file = args.stamp or (args.out / ".preset-index-stamp")
    current = stamp(args, blocklist_file, exclusions_file)
    if not args.force and stamp_file.exists() and stamp_file.read_text() == current \
            and (args.out / "PresetArchive.bin").exists():
        print("build_preset_index: up to date")
        return 0
    records, packs, archive = build(args.included_dir, args.packs_dir, blocklist, exclusions)
    args.out.mkdir(parents=True, exist_ok=True)
    display, archive_positions = display_order(records)
    (args.out / "PresetIndex.json").write_text(
        dumps({"version": 1, "presets": display, "archive": archive_positions}), encoding="utf-8")
    (args.out / "PresetPacks.json").write_text(dumps({"version": 1, "packs": packs}), encoding="utf-8")
    write_archive(archive, args.out / "PresetArchive.bin")
    images = copy_textures(args.packs_dir, args.out / "PresetTextures")
    stamp_file.parent.mkdir(parents=True, exist_ok=True)
    stamp_file.write_text(current)
    counts = {p["id"]: p["presetCount"] for p in packs if p["presetCount"]}
    print(f"build_preset_index: {len(records)} presets {counts}, archive {len(archive)}, {images} texture files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
