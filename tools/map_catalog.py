"""地图目录的读写与说明维护工具。

每张地图以 data/maps/<章节>/<地图 ID>/map.json 为唯一配置源；index.json 只记录
加载顺序。生成器通过本模块保存地图，自动更新同目录 README 的参数区。
"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
START = "<!-- MAP PARAMETERS START -->"
END = "<!-- MAP PARAMETERS END -->"


def map_paths(root: Path = ROOT) -> dict[str, Path]:
    """读取有序清单并校验路径和 ID，返回地图 ID 对应的绝对配置路径。"""
    base = root / "data/maps"
    entries = json.loads((base / "index.json").read_text(encoding="utf-8"))
    if not isinstance(entries, list):
        raise ValueError("地图 index.json 必须是路径数组")
    result = {}
    for relative in entries:
        if not isinstance(relative, str):
            raise ValueError("地图索引路径必须是字符串")
        path = (base / relative).resolve()
        if not path.is_relative_to(base.resolve()) or path.name != "map.json":
            raise ValueError(f"非法地图路径：{relative}")
        map_id = path.parent.name
        if map_id in result or not path.is_file():
            raise ValueError(f"重复地图 ID 或缺失地图配置：{relative}")
        result[map_id] = path
    return result


def load_maps(root: Path = ROOT) -> list[dict]:
    """按清单顺序合并地图，维持游戏原有的地图数组语义。"""
    result = []
    for map_id, path in map_paths(root).items():
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or data.get("id") != map_id:
            raise ValueError(f"地图目录与配置 ID 不一致：{path}")
        result.append(data)
    return result


def _value(value) -> str:
    """将配置值转换为 README 表格中的短文本，不隐藏具体数值。"""
    if value is None or value == [] or value == {}:
        return "无"
    if isinstance(value, bool):
        return "是" if value else "否"
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return str(value).replace("|", "\\|")


def chapter_of(map_id: str) -> int:
    """按稳定地图 ID 推导章节，用于目录和说明，不写回运行配置。"""
    return int(map_id[1]) if map_id.startswith("c") and map_id[1:2].isdigit() else 1


def parameter_section(data: dict) -> str:
    """从地图配置生成便于阅读的参数区，详细坐标以 map.json 为准。"""
    fields = [
        ("地图 ID", "id"), ("地图名称", "name"),
        ("类型", "kind"), ("所属城镇", "hubId"), ("尺寸（格）", "size"),
        ("等级范围", "tierRange"), ("推荐等级", "recommendedLevel"),
        ("解锁条件", "requiresUnlock"), ("安全区", "safeArea"),
        ("全图安全", "safeZone"),
        ("普通怪上限", "normalCap"), ("精英上限", "eliteCap"),
        ("Boss 上限", "bossCap"),
        ("入口落点", "entrances"),
        ("马车连接", "hubLinks"), ("马车费用", "carterFare"),
        ("指定目的地费用", "carterFares"), ("马车落点", "carterArrival"),
        ("布局文件", "layoutPath"), ("布局版本", "layoutVersion"),
    ]
    rows = [f"| 章节 | 第 {chapter_of(data['id'])} 章 |"]
    rows.extend(f"| {label} | {_value(data.get(key))} |" for label, key in fields if key in data)
    points = data.get("spawnPoints", [])
    spawn_rows = [f"| {point.get('monsterId', '未配置')} | {point.get('level', '默认')} | {point.get('count', len(point.get('cells', [])))} | {point.get('respawnTime', '默认')} | {point.get('kind', '普通')} |" for point in points]
    npcs = data.get("npcs", [])
    npc_rows = [f"| {npc.get('npcName', npc.get('shopId', npc.get('npcId', '未命名')))} | {npc.get('role', '')} | {_value(npc.get('cell'))} |" for npc in npcs]
    exits = data.get("exits", [])
    exit_rows = [f"| {exit_data.get('label', exit_data.get('id', '未命名'))} | {exit_data.get('toMap', '')} | {_value(exit_data.get('cell'))} | {exit_data.get('requiresUnlock', '无')} |" for exit_data in exits]
    boss = _value(data.get("bossSpawn"))
    return (f"{START}\n\n| 参数 | 当前值 |\n|---|---|\n" + "\n".join(rows)
            + f"\n\n### 怪物刷新\n\n刷新点 {len(points)} 组；完整刷新格、区域和附加规则见 `map.json`。\n\n"
            + "| 怪物 ID | 等级 | 数量 | 重生秒数 | 类型 |\n|---|---:|---:|---:|---|\n"
            + ("\n".join(spawn_rows) or "| 无 | — | — | — | — |")
            + f"\n\nBoss 刷新：{boss}\n\n### NPC\n\n| 名称 | 职责 | 格坐标 |\n|---|---|---|\n"
            + ("\n".join(npc_rows) or "| 无 | — | — |")
            + "\n\n### 步行出口\n\n| 出口 | 目标地图 ID | 格坐标 | 解锁条件 |\n|---|---|---|---|\n"
            + ("\n".join(exit_rows) or "| 无 | — | — | — |") + f"\n\n{END}")


def refresh_readme(path: Path, data: dict) -> None:
    """只替换 README 自动参数区，保留人工维护的用途、路线和设计说明。"""
    readme = path.parent / "README.md"
    section = parameter_section(data)
    if readme.exists():
        current = readme.read_text(encoding="utf-8")
        if current.count(START) != 1 or current.count(END) != 1:
            raise ValueError(f"README 缺少唯一参数区标记：{readme}")
        before, remainder = current.split(START, 1)
        _, after = remainder.split(END, 1)
        updated = before + section + after
    else:
        purpose = data.get("desc") or f"{data['name']}是第 {chapter_of(data['id'])} 章地图，承担{ '城镇服务与跨图中转' if data.get('kind') == 'hub' else '探索、战斗与任务推进' }。"
        updated = f"# {data['name']}\n\n{purpose}\n\n配置源：`map.json`；可通行布局见 `{data.get('layoutPath', '未配置')}`。\n地图用途和设计说明可在本段人工编辑；下方参数区由工具同步。\n\n{section}\n"
    readme.write_text(updated, encoding="utf-8")


def save_maps(maps: list[dict], root: Path = ROOT) -> None:
    """按清单保存地图，只改动内容变化的配置及其 README，不增删其他地图。"""
    paths = map_paths(root)
    if set(paths) != {data["id"] for data in maps} or len(paths) != len(maps):
        raise ValueError("地图集合与 index.json 不一致；新增地图须先登记路径")
    for data in maps:
        path = paths[data["id"]]
        content = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        if path.read_text(encoding="utf-8") != content:
            path.write_text(content, encoding="utf-8")
            refresh_readme(path, data)
