"""校验 Dart 代码里用到的 i18n 键是否都存在于生成的字符串表里。

六个并行的实现者各写了一批界面，谁也没法跑 `flutter analyze`；
缺键在运行时只会静默显示成键名本身，所以这里做一次集中体检。

用法: python tools/check_i18n_keys.py
"""

import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "lib")
EN = os.path.join(ROOT, "assets", "i18n", "strings_en.json")
ZH = os.path.join(ROOT, "assets", "i18n", "strings_zh.json")

# `s('key')`、`s.format('key', ...)`、`keyName: 'key'`、`context.s('key')`
PATTERNS = [
    re.compile(r"(?<![\w.])s\(\s*'([^']+)'"),
    re.compile(r"(?<![\w.])s\.format\(\s*'([^']+)'"),
    re.compile(r"keyName:\s*'([^']+)'"),
    re.compile(r"titleKey:\s*'([^']+)'"),
    re.compile(r"\.s\(\s*'([^']+)'"),
]

# 形如键名的东西：小写字母、数字、下划线，且不含空格。
KEY_RE = re.compile(r"^[a-z][a-z0-9_]*$")


def load_keys(path):
    if not os.path.exists(path):
        return None
    with io.open(path, encoding="utf-8") as handle:
        return set(json.load(handle).keys())


def main():
    en = load_keys(EN)
    if en is None:
        print("找不到 %s，请先运行 tools/extract_from_apk.py" % EN)
        return 1
    zh = load_keys(ZH)

    offenders = []
    total_refs = 0
    files = 0

    for dirpath, _dirnames, filenames in os.walk(LIB):
        for name in sorted(filenames):
            if not name.endswith(".dart"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT)
            with io.open(path, encoding="utf-8", errors="replace") as handle:
                lines = handle.read().splitlines()
            files += 1
            for number, line in enumerate(lines, 1):
                stripped = line.strip()
                # 跳过注释行：文档注释里会举例写 `context.s('connection_new')`。
                if stripped.startswith("//") or stripped.startswith("*"):
                    continue
                for pattern in PATTERNS:
                    for match in pattern.finditer(line):
                        key = match.group(1)
                        if not KEY_RE.match(key):
                            continue
                        total_refs += 1
                        if key not in en:
                            offenders.append((rel, number, key, line.strip()))

    print("扫描 %d 个 Dart 文件，共 %d 处字符串键引用" % (files, total_refs))
    print("英文表 %d 键" % len(en))
    if zh is not None:
        missing_zh = sorted(k for k in en if k not in zh)
        print("中文表 %d 键（英文表里有、中文表里缺的 %d 个）"
              % (len(zh), len(missing_zh)))

    if not offenders:
        print("\n全部键都存在。")
        return 0

    print("\n!! 有 %d 处引用了不存在的键：" % len(offenders))
    seen = {}
    for rel, number, key, text in offenders:
        seen.setdefault(key, []).append("%s:%d" % (rel, number))
    for key in sorted(seen):
        print("  %-45s %s" % (key, ", ".join(seen[key])))
    return 1


if __name__ == "__main__":
    sys.exit(main())
