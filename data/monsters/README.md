# 怪物配置目录

本目录保存具体怪物模板。`index.json` 按章节登记加载路径，`DataLoader` 聚合为既有 `monsters` 表；地图刷新、任务和掉落继续引用稳定的怪物 `id`。

编辑怪物时，在所属章节的 `monsters.json` 修改，并同步更新章节 `README.md` 的用途、等级与清单。新增章节须登记索引；同一个怪物 ID 只能定义一次。章节归属按设计归属，不按地图刷新等级迁移。JSON 不写注释，设计原因写在 README。

生成器使用 `tools/monster_catalog.py::load_chapter` / `save_chapter`，只更新所属章节及其 README 清单。手工编辑后运行 `python3 tools/check_monster_catalog.py`；清单不一致时可调用同模块的 `refresh_readme` 同步，人工说明仍需维护。

怪物数值与掉落规则属于此处；表现资源与动作元数据将独立放在 `data/monster_appearances/`。战斗伤害、技能冷却不应放进美术档案。
