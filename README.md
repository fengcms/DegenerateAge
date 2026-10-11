# 末法纪元：最后的守护者（Degenerate Age: The Last Guardian）

一款 **2D 等距斜角（isometric）、单机、实时战斗、打怪升级（ARPG / Diablo-like）** 游戏。
首发 **macOS**，后期按规划跨 Windows / Linux。

- **引擎**：Godot 4.7（GDScript 起步，必要时引入 C#）
- **商业模式**：买断制优先、可能免费分发；**无联网 / 无账号 / 无抽卡 / 无氪金 / 无 PvP / 无交易市场**

---

## 快速开始

```bash
git clone git@github.com:fengcms/DegenerateAge.git
cd DegenerateAge
# 用 Godot 4.7 打开本目录（选择 project.godot），按 F5 运行
```

运行后控制台应打印「配置校验通过 ✅」，表示数据层与脚手架就绪。

> 详细的环境安装、工程结构与**换机复现**步骤，见
> [`docs/工程文档/01-脚手架搭建与换机复现指南.md`](docs/工程文档/01-脚手架搭建与换机复现指南.md)。

---

## 目录结构

| 目录 / 文件 | 说明 |
|---|---|
| `project.godot` | Godot 工程配置（应用、主场景、分辨率、渲染、Autoload、输入映射） |
| `scenes/` | 场景（`.tscn`） |
| `scripts/` | 玩法脚本（`.gd`） |
| `autoload/` | 全局单例：`EventBus` / `GameState` / `DataLoader` / `SaveManager` |
| `data/` | **14 个 JSON 数据配置**（装备/技能/怪物/掉落/任务/商店/升星/坐骑/如意/仓库/杂项/药水/地图/文案） |
| `assets/` | 美术与音频（占位） |
| `addons/` | Godot 插件（预留） |
| `docs/产品文档/` | **产品需求基线**（唯一权威设计来源） |
| `docs/工程文档/` | 工程实现文档（搭建、换机复现、技术约定） |

---

## 文档导航

- **产品需求基线**：`docs/产品文档/`（总纲 + 12 章 + 术语表）——设计事实源。
- **工程脚手架与换机复现**：`docs/工程文档/01-脚手架搭建与换机复现指南.md`。
- **阶段开发计划与验收标准**：`docs/工程文档/02-阶段开发计划与验收标准.md`——每阶段"可运行 + 可验证"的施工图与验收清单。

---

## 分支说明

- `master`：**现行开发分支**。
- `bak`：旧版（已弃用的 Swift / SpriteKit 实现）归档，仅供回看，**请勿在其上开发**。

---

## 开发原则

- **数据驱动**：新增装备 / 怪物 / 任务 / 地图等，只加 `data/*.json` 条目 + 图标，不改代码。
- **文本化工程**：`.tscn` / `.gd` / `.tres` / `.json` 均为文本，便于人机协作与版本管理。
- **启动校验**：数据非法时明确报错而非静默（`DataLoader.validate_all()`）。
