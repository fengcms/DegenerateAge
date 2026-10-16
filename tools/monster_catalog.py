"""怪物章节配置的读写与说明维护入口。

按 data/monsters/index.json 聚合具体怪物；写入时仅修改所属章节及其 README 清单，
供数值工具和内容生成器复用，不触碰其他章节或运行存档。
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
START = "<!-- MONSTER LIST START -->"
END = "<!-- MONSTER LIST END -->"
KINDS = {"normal": "普通", "elite": "精英", "boss": "首领"}


def chapter_paths(root: Path = ROOT) -> dict[str, Path]:
    """校验章节索引路径、目录及文件唯一性，返回按索引顺序排列的配置路径。"""
    base = root / "data/monsters"
    entries = json.loads((base / "index.json").read_text(encoding="utf-8"))
    if not isinstance(entries, list):
        raise ValueError("怪物 index.json 必须是路径数组")
    result: dict[str, Path] = {}
    for relative in entries:
        if not isinstance(relative, str):
            raise ValueError(f"非法怪物索引路径：{relative}")
        path = (base / relative).resolve()
        chapter = path.parent.name
        if not path.is_relative_to(base.resolve()) or path.name != "monsters.json" or not chapter.startswith("ch") or len(chapter) != 4 or not chapter[2:].isdigit():
            raise ValueError(f"非法怪物索引路径：{relative}")
        if chapter in result or not path.is_file():
            raise ValueError(f"重复章节或缺失怪物配置：{relative}")
        result[chapter] = path
    return result


def load_chapter(chapter: str, root: Path = ROOT) -> list[dict]:
    """读取一个已登记章节并校验数组与怪物 ID；供单章生成器调用。"""
    path = chapter_paths(root)[chapter]
    rows = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(rows, list) or any(not isinstance(row, dict) or not isinstance(row.get("id"), str) or not row["id"] for row in rows):
        raise ValueError(f"章节怪物配置格式错误：{path}")
    return rows


def load_monsters(root: Path = ROOT) -> list[dict]:
    """按索引顺序合并所有章节，并拒绝跨文件重复怪物 ID。"""
    result: list[dict] = []
    seen: set[str] = set()
    for chapter in chapter_paths(root):
        for row in load_chapter(chapter, root):
            if row["id"] in seen:
                raise ValueError(f"跨章节重复怪物 ID：{row['id']}")
            seen.add(row["id"])
            result.append(row)
    return result


def list_section(rows: list[dict]) -> str:
    """生成章节 README 的怪物清单区，数值仅供浏览并以 JSON 为准。"""
    lines = [START, "", "| ID | 名称 | 模板等级 | 类型 | 掉落表 |", "|---|---|---:|---|---|"]
    for row in rows:
        values = (str(row.get("id", "")), str(row.get("name", "")), str(row.get("level", "")),
                  KINDS.get(str(row.get("kind", "normal")), str(row.get("kind", "normal"))), str(row.get("dropTableId", "")))
        lines.append("| `%s` | %s | %s | %s | `%s` |" % values)
    lines += ["", END]
    return "\n".join(lines)


def refresh_readme(chapter: str, rows: list[dict], root: Path = ROOT, *, write: bool = True) -> bool:
    """保持人工说明不变，只同步清单标记区；返回是否存在漂移。"""
    readme = chapter_paths(root)[chapter].parent / "README.md"
    current = readme.read_text(encoding="utf-8")
    if current.count(START) != 1 or current.count(END) != 1:
        raise ValueError(f"章节 README 缺少唯一清单标记：{readme}")
    before, rest = current.split(START, 1)
    _, after = rest.split(END, 1)
    updated = before + list_section(rows) + after
    changed = updated != current
    if write and changed:
        readme.write_text(updated, encoding="utf-8")
    return changed


def save_chapter(chapter: str, rows: list[dict], root: Path = ROOT) -> None:
    """仅保存已登记章节，并同步 README；拒绝写入其他章节 ID 与重复 ID。"""
    path = chapter_paths(root)[chapter]
    ids = [row.get("id") for row in rows]
    if any(not isinstance(id, str) or not id or (chapter == "ch01" and id.startswith("c") and id[1:2].isdigit())
           or (chapter != "ch01" and not id.startswith(f"c{int(chapter[2:])}_")) for id in ids):
        raise ValueError(f"怪物 ID 与章节归属不符：{chapter}")
    if len(ids) != len(set(ids)):
        raise ValueError(f"同章重复怪物 ID：{chapter}")
    refresh_readme(chapter, rows, root, write=False)
    encoded = json.dumps(rows, ensure_ascii=False, indent=2) + "\n"
    if path.read_text(encoding="utf-8") != encoded:
        path.write_text(encoded, encoding="utf-8")
    refresh_readme(chapter, rows, root)


def check_catalog(root: Path = ROOT) -> list[str]:
    """检查全局 ID 与章节清单是否一致，不修改文件。"""
    issues: list[str] = []
    for chapter in chapter_paths(root):
        rows = load_chapter(chapter, root)
        for row in rows:
            id = row["id"]
            expected = "ch01" if not (id.startswith("c") and id[1:2].isdigit()) else f"ch0{id[1]}"
            if expected != chapter:
                issues.append(f"{id} 归属 {chapter}，期望 {expected}")
        if refresh_readme(chapter, rows, root, write=False):
            issues.append(f"{chapter}/README.md 清单与 JSON 不一致")
    load_monsters(root)
    return issues
