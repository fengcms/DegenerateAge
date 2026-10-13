"""检查第一章文案表引用与 UI 脚本中的硬编码中文。"""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data/localization.json"
CALL = re.compile(r'Localization\.tr_key\("([^"]+)"\)')
CHINESE_LITERAL = re.compile(r'"[^"\n]*[\u4e00-\u9fff][^"\n]*"')


def main() -> int:
    table = json.loads(CATALOG.read_text(encoding="utf-8"))
    issues: list[str] = []
    scripts = [*(ROOT / "scripts").rglob("*.gd"), *(ROOT / "autoload").rglob("*.gd")]
    for script in scripts:
        relative = script.relative_to(ROOT)
        for number, line in enumerate(script.read_text(encoding="utf-8").splitlines(), 1):
            for key in CALL.findall(line):
                if key not in table:
                    issues.append(f"{relative}:{number}: 缺少 key {key}")
            if script.parent == ROOT / "scripts/ui" and not line.lstrip().startswith("#"):
                if CHINESE_LITERAL.search(line):
                    issues.append(f"{relative}:{number}: UI 文案仍在代码中")
    for key, value in table.items():
        if not isinstance(key, str) or not isinstance(value, str) or not value:
            issues.append(f"文案表无效：{key!r}")
    for issue in issues:
        print(issue)
    print(f"文案表 {len(table)} 条；问题 {len(issues)} 项")
    return int(bool(issues))


if __name__ == "__main__":
    raise SystemExit(main())
