"""临时辅助脚本：从反编译产物里提取 MainActivity 的卡片菜单定义。

不参与应用构建，仅供逆向核对使用。
"""

import io
import re

SMALI = (
    r"D:\dev\_apk\juicessh\smali\com\sonelli\juicessh\activities\MainActivity.smali"
)
PUBLIC = r"D:\dev\_apk\juicessh\res\values\public.xml"
STRINGS = r"D:\dev\_apk\juicessh\res\values\strings.xml"


def load_id_map():
    text = io.open(PUBLIC, encoding="utf-8", errors="replace").read()
    mapping = {}
    for m in re.finditer(
        r'<public type="(\w+)" name="([^"]+)" id="(0x[0-9a-f]+)"', text
    ):
        mapping[int(m.group(3), 16)] = (m.group(1), m.group(2))
    return mapping


def load_strings():
    text = io.open(STRINGS, encoding="utf-8", errors="replace").read()
    out = {}
    for m in re.finditer(r'<string name="([^"]+)"[^>]*>(.*?)</string>', text, re.S):
        out[m.group(1)] = " ".join(m.group(2).split())[:100]
    return out


def describe_string(name, strings):
    """把字符串资源描述成「原文 + 码点」，图标类资源重点是码点。"""
    raw = strings.get(name)
    if raw is None:
        return "?"
    cps = " ".join("U+%04X" % ord(c) for c in raw if ord(c) > 0x7F)
    if cps:
        return "%s   [%s]" % (raw, cps)
    return '"%s"' % raw


def main():
    lines = (
        io.open(SMALI, encoding="utf-8", errors="replace").read().splitlines()
    )
    id_map = load_id_map()
    strings = load_strings()

    # 只汇报卡片属性：按 gh0;->a( 的添加顺序整理成表格。
    adds = [i for i, l in enumerate(lines) if "gh0;->a(Lcom/sonelli/juicessh/views/CardListItem;)V" in l]
    print("card add sites (1-based):", [a + 1 for a in adds])
    print("=" * 110)

    # 所有 CardListItem 的 setter 调用，按行号排序，便于回溯。
    # 注意 smali 的 invoke-virtual {v0, v1}, ...->t(...) 里
    # 第一个寄存器是对象自身，**最后一个**才是实参。
    setters = []
    for i, l in enumerate(lines):
        m = re.search(
            r"invoke-virtual \{([^}]+)\}, "
            r"Lcom/sonelli/juicessh/views/CardListItem;->([rstpo])\(",
            l,
        )
        if m:
            regs = [r.strip() for r in m.group(1).split(",")]
            setters.append((i, m.group(2), regs[-1]))

    def const_for(reg, before):
        """向上找某寄存器最近一次的 const 赋值。"""
        for i in range(before, max(0, before - 40), -1):
            t = lines[i].strip()
            m = re.match(r'const(?:-string)? (%s), (.+)$' % re.escape(reg), t)
            if m:
                return i, m.group(2)
        return None, None

    for n, a in enumerate(adds, 1):
        # 该卡片对应的 setter 调用：在本次 add 之前、上一次 add 之后。
        lo = adds[n - 2] if n >= 2 else 0
        mine = [s for s in setters if lo < s[0] < a]
        info = {}
        for line_no, code, reg in mine:
            _, value = const_for(reg, line_no)
            if value is None:
                value = "(寄存器未在附近常量赋值)"
            info[code] = (line_no, value)

        print()
        print("########## CARD %d  (add at line %d) ##########" % (n, a + 1))
        for code, label in (("t", "标题"), ("s", "副标题"), ("p", "图标")):
            if code not in info:
                continue
            line_no, value = info[code]
            if value.startswith("0x7f"):
                rid = int(value, 16)
                typ, name = id_map.get(rid, ("?", "?"))
                if typ == "string":
                    print("  %s: %s" % (label, describe_string(name, strings)))
                    print("       (%s/%s, line %d)" % (typ, name, line_no + 1))
                else:
                    print("  %s: %s/%s  (%s, line %d)" % (label, typ, name, value, line_no + 1))
            else:
                print("  %s: %s  (line %d)" % (label, value, line_no + 1))
        if "r" in info:
            print("  点击行为: 设置了 OnClickListener（line %d）" % (info["r"][0] + 1))
        extra = [l.strip() for l in lines[lo:a] if "new-instance" in l and "CardListItem" not in l]
        if extra:
            print("  附加视图: %s" % "; ".join(extra))


if __name__ == "__main__":
    main()
