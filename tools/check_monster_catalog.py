#!/usr/bin/env python3
"""检查怪物章节索引、全局 ID 和 README 清单是否与 JSON 一致。"""

from monster_catalog import check_catalog, load_monsters


def main() -> int:
    """只读验证整个目录，返回非零码供提交前和构建脚本使用。"""
    try:
        issues = check_catalog()
        total = len(load_monsters())
    except (OSError, ValueError, KeyError) as exc:
        print(f"怪物目录校验失败：{exc}")
        return 1
    for issue in issues:
        print(f"- {issue}")
    print(f"怪物目录：{total} 种，{len(issues)} 项问题")
    return int(bool(issues))


if __name__ == "__main__":
    raise SystemExit(main())
