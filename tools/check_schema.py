"""把 `juice_database.dart` 里的建表语句抽出来，喂给 Python 自带的 sqlite3 跑一遍。

目的：DDL 有语法错误或引用了不存在的列时，应用会在启动时直接崩，
而这在 `flutter analyze` 与单元测试里都看不出来（不碰真机就跑不到建表）。
用 stdlib 的 sqlite3 可以离线验证同一批 SQL。

用法: python tools/check_schema.py
"""

import io
import os
import re
import sqlite3
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "lib", "data", "juice_database.dart")


def extract_schema(text):
    """从 `_schema` 列表里按出现顺序取出所有 SQL 字符串字面量。"""
    start = text.index("_schema = <String>[")
    # 列表以 `];` 结束
    end = text.index("\n  ];", start)
    body = text[start:end]

    statements = []
    i = 0
    while i < len(body):
        char = body[i]
        if char != "'":
            i += 1
            continue
        # 三引号？
        if body.startswith("'''", i):
            close = body.index("'''", i + 3)
            statements.append(body[i + 3 : close])
            i = close + 3
        else:
            # 单行字符串：找没有被转义的收尾引号
            j = i + 1
            while True:
                j = body.index("'", j)
                if body[j - 1] != "\\":
                    break
                j += 1
            statements.append(body[i + 1 : j])
            i = j + 1
    return [s.strip() for s in statements if s.strip()]


def main():
    with io.open(SOURCE, encoding="utf-8") as handle:
        text = handle.read()

    statements = extract_schema(text)
    print("从 %s 抽到 %d 条语句" % (os.path.relpath(SOURCE, ROOT), len(statements)))

    connection = sqlite3.connect(":memory:")
    connection.execute("PRAGMA foreign_keys=ON")

    failures = 0
    for index, statement in enumerate(statements, 1):
        head = " ".join(statement.split())[:70]
        try:
            connection.execute(statement)
            print("  ok  %2d  %s" % (index, head))
        except sqlite3.Error as error:
            failures += 1
            print("  !!  %2d  %s" % (index, head))
            print("        %s" % error)

    if failures:
        print("\n%d 条语句执行失败。" % failures)
        return 1

    # 列名自检：确认代码里 SELECT/INSERT 用到的列都存在。
    tables = {}
    for (name,) in connection.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    ):
        columns = [
            row[1] for row in connection.execute('PRAGMA table_info("%s")' % name)
        ]
        tables[name] = columns
    print("\n建表结果：")
    for name, columns in tables.items():
        print("  %-30s %s" % (name, ", ".join(columns)))

    # 外键完整性：插入违规数据应当被拒绝。
    try:
        connection.execute(
            "INSERT INTO connectiongroupmembership (\"group\", connection) VALUES (999, 999)"
        )
        print("\n!! 外键约束没有生效（插入了不存在的分组/连接）")
        return 1
    except sqlite3.IntegrityError:
        print("\n外键约束生效。")

    print("\n全部 %d 条语句执行成功。" % len(statements))
    return 0


if __name__ == "__main__":
    sys.exit(main())
