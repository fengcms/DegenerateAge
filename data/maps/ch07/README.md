# 第 7 章地图

本目录集中第 7 章各地图的独立配置；具体用途、参数与编辑规则见各地图目录的 README。修改地图时同步更新对应 README。

本章只含满级后的循环内容，不设新的普通刷怪章节地图。

| 地图 | ID | 用途 | 等级范围 |
|---|---|---|---|
| [无尽回廊](c7_arena/README.md) | `c7_arena` | 满级后循环 Boss 挑战场（车夫直达） | 60–60 |

`data/maps/index.json` 仅登记加载顺序与相对路径，`ch07/c7_arena/map.json` 排在其末尾，地图属性仍只写在各自 `map.json` 内。

与相邻章节的衔接：`c7_arena` 是第 6 章城镇枢纽 `c6_map00`（镇脉前哨）的支线（`kind: spoke`、`hubId: c6_map00`），唯一出入口走 `c7_arena_exit01` / `c6_map00_exit03` 同格对开，解锁条件 `campaign_complete`（由 C6Q12 任务产出），因此本章不产出新的主线探索地图。
