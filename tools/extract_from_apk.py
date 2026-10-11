#!/usr/bin/env python3
"""Extract JuiceSSH resources from the apktool-decoded APK into Flutter-ready assets.

Source of truth: D:\\dev\\_apk\\juicessh  (apktool 3.0.3 output of JuiceSSH 3.2.2)

Produces, inside the Flutter project:
  assets/data/terminal_themes.json   the 9 terminal colour schemes (260 ints each)
  assets/data/arrays.json            res/values/arrays.xml, @string refs resolved
  assets/data/colors.json            res/values/colors.xml, refs resolved to #AARRGGBB
  assets/data/dimens.json            res/values/dimens.xml
  assets/i18n/strings_en.json        English UI strings
  assets/i18n/strings_zh.json        Simplified Chinese UI strings
  assets/fonts/*                     the 8 bundled Nerd Fonts
  lib/data/generated/terminal_palettes.g.dart   the palettes as Dart consts

Run:  python tools/extract_from_apk.py
"""

from __future__ import annotations

import json
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

APK = Path(r"D:\dev\_apk\juicessh")
PROJECT = Path(__file__).resolve().parent.parent

ASSETS = PROJECT / "assets"
OUT_DATA = ASSETS / "data"
OUT_I18N = ASSETS / "i18n"
OUT_FONTS = ASSETS / "fonts"
OUT_DART = PROJECT / "lib" / "data" / "generated"

# res/values/arrays.xml order -> terminal_theme_values 0..8
THEME_NAMES = [
    "Dark",
    "Light",
    "Solarized Dark",
    "Solarized Light",
    "80's Hacker",
    "Monokai",
    "Tiger Orange",
    "Tiger Black",
    "Bifrost",
]

# TerminalFont.java enum: display name -> asset path (see com/sonelli/aj0$a.smali)
FONT_ASSETS = {
    "Cascadia Code Mono": "fonts/Caskaydia.Cove.Regular.Nerd.Font.Complete.Mono.otf",
    "Sauce Code Pro": "fonts/Sauce.Code.Pro.Nerd.Font.Complete.ttf",
    "Inconsolata": "fonts/Inconsolata.Nerd.Font.Complete.Mono.otf",
    "Roboto Mono": "fonts/Roboto.Mono.Nerd.Font.Complete.Mono.ttf",
    "JetBrains Mono": "fonts/JetBrains.Mono.Regular.Nerd.Font.Complete.Mono.ttf",
    "Fira Code": "fonts/Fira.Code.Regular.Nerd.Font.Complete.ttf",
    "Open Dyslexic": "fonts/OpenDyslexic.Regular.Nerd.Font.Complete.Mono.otf",
    "Droid Sans Mono": "fonts/Droid.Sans.Mono.Nerd.Font.Complete.otf",
}

# Order shown in the settings list (res/values/arrays.xml font_names)
FONT_ORDER = [
    "Cascadia Code Mono",
    "Sauce Code Pro",
    "Roboto Mono",
    "JetBrains Mono",
    "Fira Code",
    "Open Dyslexic",
    "Inconsolata",
    "Droid Sans Mono",
]
DEFAULT_FONT = "Cascadia Code Mono"  # com/sonelli/aj0.smali -> aj0$a.Q

ANDROID_COLORS = {
    "black": "#FF000000",
    "white": "#FFFFFFFF",
    "transparent": "#00000000",
    "darker_gray": "#FF444444",
    "holo_blue_light": "#FF33B5E5",
}


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
_NUM = re.compile(r"^\s*(-?0x[0-9a-fA-F]+|-?\d+)\s*$")


def smali_int(token: str) -> int:
    """Parse a smali integer literal into an unsigned 32-bit value."""
    token = token.strip()
    neg = token.startswith("-")
    body = token[1:] if neg else token
    value = int(body, 16) if body.lower().startswith("0x") else int(body, 10)
    if neg:
        value = -value
    return value & 0xFFFFFFFF


def argb(value: int) -> str:
    return "#%08X" % (value & 0xFFFFFFFF)


def parse_smali_arrays(path: Path) -> dict[str, list[int]]:
    """Return {'array_0': [ints...], ...} from a smali .array-data block."""
    arrays: dict[str, list[int]] = {}
    current: str | None = None
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    for line in lines:
        stripped = line.strip()
        if stripped.startswith(":array_"):
            current = stripped[1:]
            arrays[current] = []
            continue
        if stripped.startswith(".array-data"):
            continue
        if stripped.startswith(".end array-data"):
            current = None
            continue
        if current is not None and _NUM.match(stripped):
            arrays[current].append(smali_int(stripped))
    return arrays


def unescape_android(text: str) -> str:
    """Undo Android string escaping and strip resource quotes."""
    out: list[str] = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            mapping = {"n": "\n", "t": "\t", "r": "\r", "'": "'", '"': '"', "\\": "\\", "@": "@", "?": "?"}
            if nxt in mapping:
                out.append(mapping[nxt])
                i += 2
                continue
            if nxt == "u" and i + 5 < len(text):
                out.append(chr(int(text[i + 2 : i + 6], 16)))
                i += 6
                continue
            out.append(nxt)
            i += 2
            continue
        out.append(ch)
        i += 1
    result = "".join(out)
    # Android strips a fully-quoting pair of double quotes
    if len(result) >= 2 and result.startswith('"') and result.endswith('"'):
        result = result[1:-1]
    return result


def parse_string_resources(path: Path) -> dict[str, str]:
    """Parse res/values/strings.xml style files into {name: text}."""
    if not path.exists():
        return {}
    tree = ET.parse(path)
    root = tree.getroot()
    result: dict[str, str] = {}
    for node in root:
        tag = node.tag
        if tag not in ("string", "item"):
            continue
        if tag == "item" and node.get("type") not in (None, "string"):
            continue
        name = node.get("name")
        if not name:
            continue
        if tag == "string" and node.get("translatable") == "false" and node.text is None:
            continue
        raw = "".join(node.itertext())
        if raw == "":
            raw = ""
        result[name] = unescape_android(raw)
    return result


def resolve_string_refs(values: dict[str, str], all_strings: dict[str, str]) -> dict[str, str]:
    """Resolve leading @string/foo references inside array items."""
    out: dict[str, str] = {}
    for key, value in values.items():
        m = re.fullmatch(r"@string/(\w+)", value.strip())
        if m:
            out[key] = all_strings.get(m.group(1), value)
        else:
            out[key] = value
    return out


def parse_string_arrays(path: Path, all_strings: dict[str, str]) -> dict[str, list[str]]:
    if not path.exists():
        return {}
    root = ET.parse(path).getroot()
    arrays: dict[str, list[str]] = {}
    for node in root:
        if node.tag != "string-array":
            continue
        name = node.get("name")
        if not name:
            continue
        items = [unescape_android("".join(item.itertext())) for item in node.findall("item")]
        items = [
            all_strings.get(m.group(1), item) if (m := re.fullmatch(r"@string/(\w+)", item.strip())) else item
            for item in items
        ]
        arrays[name] = items
    return arrays


def parse_colors(path: Path, all_strings: dict[str, str]) -> dict[str, str]:
    """Parse colors.xml and resolve @color/... and @android:color/... chains."""
    if not path.exists():
        return {}
    root = ET.parse(path).getroot()
    raw: dict[str, str] = {}
    for node in root:
        if node.tag != "color":
            continue
        name = node.get("name")
        if not name:
            continue
        raw[name] = ("".join(node.itertext()) or "").strip()

    resolved: dict[str, str] = {}

    def resolve(name: str, seen: set[str]) -> str:
        if name in resolved:
            return resolved[name]
        if name in seen:
            return "UNRESOLVED-CYCLE"
        value = raw.get(name)
        if value is None:
            return "UNRESOLVED-MISSING"
        if value == "":
            resolved[name] = "#00000000"
            return resolved[name]
        if value.startswith("#"):
            resolved[name] = value.upper()
            return resolved[name]
        m = re.fullmatch(r"@android:color/(\w+)", value)
        if m:
            resolved[name] = ANDROID_COLORS.get(m.group(1), f"UNRESOLVED-android:{m.group(1)}")
            return resolved[name]
        m = re.fullmatch(r"@color/(\w+)", value)
        if m:
            resolved[name] = resolve(m.group(1), seen | {name})
            return resolved[name]
        m = re.fullmatch(r"@string/(\w+)", value)
        if m:
            resolved[name] = all_strings.get(m.group(1), "UNRESOLVED-string")
            return resolved[name]
        resolved[name] = value
        return resolved[name]

    for name in raw:
        resolve(name, set())
    return resolved


def parse_dimens(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    root = ET.parse(path).getroot()
    out: dict[str, str] = {}
    for node in root:
        if node.tag != "dimen":
            continue
        name = node.get("name")
        if name:
            out[name] = ("".join(node.itertext()) or "").strip()
    return out


def write_json(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"  wrote {path.relative_to(PROJECT)}  ({path.stat().st_size:,} bytes)")


# --------------------------------------------------------------------------- #
# terminal colour schemes
# --------------------------------------------------------------------------- #
def extract_terminal_themes() -> list[dict]:
    """Reproduce com/sonelli/ni0.a(int) -> the 260-int palette for each theme."""
    smali = APK / "smali" / "com" / "sonelli" / "ni0.smali"
    arrays = parse_smali_arrays(smali)

    # <clinit>: field a..i <- :array_0 .. :array_8  (in order)
    fields = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
    field_to_array = {field: f"array_{i}" for i, field in enumerate(fields)}

    # ni0.a(int) packed-switch: theme index -> field
    index_to_field = {
        0: "d",
        1: "e",
        2: "g",
        3: "f",
        4: "c",
        5: "h",
        6: "b",
        7: "a",
        8: "i",
    }

    themes: list[dict] = []
    for index, name in enumerate(THEME_NAMES):
        field = index_to_field[index]
        array_name = field_to_array[field]
        values = arrays.get(array_name, [])
        if len(values) != 260:
            raise SystemExit(
                f"theme {index} ({name}): expected 260 ints in {array_name}, got {len(values)}"
            )
        themes.append(
            {
                "index": index,
                "name": name,
                "palette": [argb(v) for v in values[:256]],
                "foreground": argb(values[256]),
                "background": argb(values[257]),
                "extra": [argb(values[258]), argb(values[259])],
            }
        )
    return themes


def write_dart_palettes(themes: list[dict]) -> None:
    OUT_DART.mkdir(parents=True, exist_ok=True)
    target = OUT_DART / "terminal_palettes.g.dart"
    lines: list[str] = [
        "// GENERATED by tools/extract_from_apk.py -- do not edit by hand.",
        "// Source: JuiceSSH 3.2.2 com/sonelli/ni0.smali (Colors.java), arrays :array_0 .. :array_8.",
        "//",
        "// Each palette holds 260 ARGB values: 0..255 are the terminal palette,",
        "// 256 is the default foreground and 257 the default background.",
        "",
        "/// Number of entries in a palette: 256 colours + foreground + background.",
        "const int kPaletteLength = 260;",
        "",
    ]
    for theme in themes:
        const_name = "kPalette" + re.sub(r"[^A-Za-z0-9]", "", theme["name"].title().replace("'", ""))
        lines.append(f"/// Theme {theme['index']}: {theme['name']!r}")
        lines.append(f"const List<int> {const_name} = <int>[")
        values = theme["palette"] + [theme["foreground"], theme["background"]] + theme["extra"]
        for start in range(0, len(values), 8):
            chunk = ", ".join("0x" + v.lstrip("#") for v in values[start : start + 8])
            lines.append(f"  {chunk},")
        lines.append("];")
        lines.append("")
        theme["constName"] = const_name

    names = ", ".join(t["constName"] for t in themes)
    lines.append("/// All palettes in `terminal_theme_values` order (0..8).")
    lines.append(f"const List<List<int>> kTerminalPalettes = <List<int>>[{names}];")
    lines.append("")
    lines.append("/// Display names in `terminal_theme_values` order (0..8).")
    literal_names = ", ".join(json.dumps(t["name"], ensure_ascii=False) for t in themes)
    lines.append(f"const List<String> kTerminalThemeNames = <String>[{literal_names}];")
    lines.append("")
    target.write_text("\n".join(lines), encoding="utf-8")
    print(f"  wrote {target.relative_to(PROJECT)}  ({target.stat().st_size:,} bytes)")


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main() -> int:
    if not APK.exists():
        print(f"ERROR: decoded APK not found at {APK}", file=sys.stderr)
        return 1

    values_dir = APK / "res" / "values"
    print("Extracting JuiceSSH resources from", APK)

    print("[1/6] UI strings")
    en = parse_string_resources(values_dir / "strings.xml")
    zh = parse_string_resources(APK / "res" / "values-zh-rCN" / "strings.xml")
    write_json(OUT_I18N / "strings_en.json", en)
    write_json(OUT_I18N / "strings_zh.json", zh)
    print(f"  en={len(en)} keys, zh={len(zh)} keys")

    print("[2/6] string arrays")
    arrays = parse_string_arrays(values_dir / "arrays.xml", en)
    write_json(OUT_DATA / "arrays.json", arrays)
    for key in ("font_names", "terminal_theme_names", "terminal_typeTitles"):
        print(f"  {key} = {arrays.get(key)}")

    print("[3/6] colours")
    colors = parse_colors(values_dir / "colors.xml", en)
    write_json(OUT_DATA / "colors.json", colors)
    unresolved = {k: v for k, v in colors.items() if v.startswith("UNRESOLVED")}
    print(f"  {len(colors)} colours, {len(unresolved)} unresolved"
          + (f" -> {sorted(unresolved)[:8]}" if unresolved else ""))
    for key in ("primary_bold", "juicessh_yellow", "accent_bold", "accent_darker",
                "accent_lighter", "titlebar_background", "log_viewer_background",
                "log_viewer_foreground", "pinlock_background", "table_row_highlight"):
        print(f"  {key:24} = {colors.get(key)}")

    print("[4/6] dimens")
    dimens = parse_dimens(values_dir / "dimens.xml")
    write_json(OUT_DATA / "dimens.json", dimens)

    print("[5/6] terminal colour schemes")
    themes = extract_terminal_themes()
    write_json(OUT_DATA / "terminal_themes.json", themes)
    write_dart_palettes(themes)
    for theme in themes:
        print(f"  {theme['index']} {theme['name']:16} fg={theme['foreground']} bg={theme['background']}")

    print("[6/6] fonts")
    OUT_FONTS.mkdir(parents=True, exist_ok=True)
    src_fonts = APK / "assets" / "fonts"
    copied = []
    for name, asset_path in FONT_ASSETS.items():
        src = APK / "assets" / asset_path
        if not src.exists():
            print(f"  MISSING {asset_path}")
            continue
        shutil.copy2(src, OUT_FONTS / src.name)
        copied.append(src.name)
    # FontAwesome is used for the app's own icon glyphs (FontAwesomeTextView)
    fa = src_fonts / "fontawesome-webfont.ttf"
    if fa.exists():
        shutil.copy2(fa, OUT_FONTS / fa.name)
        copied.append(fa.name)
    print(f"  copied {len(copied)} font files: {', '.join(copied)}")

    manifest = {
        "app": "JuiceSSH",
        "versionName": "3.2.2",
        "versionCode": 200,
        "package": "com.sonelli.juicessh",
        "minSdkVersion": 26,
        "targetSdkVersion": 29,
        "defaultFont": DEFAULT_FONT,
        "fontOrder": FONT_ORDER,
        "fontAssets": {name: Path(p).name for name, p in FONT_ASSETS.items()},
        "defaultTerminalThemeIndex": 0,
        "defaultFontSize": 8,
    }
    write_json(OUT_DATA / "apk_manifest.json", manifest)

    print("\nDone.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
