"""在独立 Godot 项目名和 user:// 下运行测试，保护真实存档。

默认集（DEFAULT_TESTS）只是 tests/ 下全部测试场景中的**常用子集**（当前 75 项），
不代表全量覆盖；需要跑全量时用 `--all`，它扫描 `tests/*.tscn` 并排除：
`FIXTURE_SCENES`（仅作夹具）、`RENDER_ONLY_SCENES`（必须 `--rendered`），
以及单列打印但不计入退出码的 `KNOWN_ART_DEBT`（断言正确、素材过时的美术欠账）。

默认集已为第四/五/六章各纳入 1 个**地图数据契约场景**（ChapterFour/ Five/ SixMapTest），
使裸跑默认回归即可触达 31—60 级交付的核心契约（登记/预算/首领/出口/跨章门户）；
其余 12 个章内场景（Routes/Combat/Quests/Loot）仍由定向复跑或 `--all` 触达。
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT = Path("/Applications/Godot.app/Contents/MacOS/Godot")
DEFAULT_TESTS = [
    "EquipmentAxesTest",
    "SettingsTest", "PotionAccessibilityTest", "AudioCuesTest", "FlowFeedbackTest",
    "DeathChoiceTest", "DeathDropTest", "RandomTicketTest", "TownScrollTest",
    "HotbarConfigTest", "HotbarUiTest", "InputFeedbackTest", "MenuFlowTest",
    "SkillCombatTest", "AutoControlAcceptance", "AutoExplorationSurvival",
    "BluePotionDropTest",
    # 工程 69 §6.3 的有牙用例：绕障追击期间「与目标的直线距离不降、但角色在沿路径推进」不得拉黑改选。
    "CaveAutoBattleTest",
    "CaveNavigationTest", "ReviewRegressionTest", "SaveTransferTest",
    "BossReviewTest", "BossActionTest", "QuestRewardPlanTest", "MapGateTest",
    "MapRouteOverlayTest", "MinimapViewportTest",
    "ChapterOneAcceptance",
    # 营地四项长期不在默认集，等发现时已集体腐烂（硬编码画布坐标 / PASS 不独占行尾 /
    # 无头守卫只包住第一个循环）。全部修好后收回默认集，防止再次静默失效。
    # CampMapEditorTest：编辑器契约 —— 整体平移 / 道路 / 地面笔刷 / 碰撞顶点 / 撤销重做。
    "CampMapEditorTest",
    # CampLiveIntegrationTest：正式营地装配 + 每个实体内部不可走且有整体物理碰撞 + 旧档迁移。
    "CampLiveIntegrationTest",
    # CampFullArtAcceptanceTest：全图 11 个整体实体、开放外围、固定 NPC 与四条实走路线。
    "CampFullArtAcceptanceTest",
    # CampWhiteboxAcceptance：白盒可走格、9 个目标的规划与真实移动。
    "CampWhiteboxAcceptance",
    # 地面砖族选择与道路索引契约：锁定 wild 9 / ash 8 / cave 9 / camp 4 四套变体与道路中心解耦规则。
    "GroundTileThemeTest",
    # 第四/五/六章各 1 个地图契约场景，令默认回归覆盖 31—60 级交付核心契约。
    "ChapterFourMapTest", "ChapterFiveMapTest", "ChapterSixMapTest",
    # M10-0 数值地基：三条曲线 + 1–60 逐位不变 + 1000 级存档可读 + 读档幂等对齐。
    "BalanceTest",
    # M10-1 动态等级装备：61+ 实例生成数值 + v5 存读放行 + v4 等级校验不许被放宽。
    "DynamicEquipTest",
    # M10-2 循环掉落：levelFromBoss 取等级 + source_level 透传 + 静态表逐字节不变。
    "ArenaDropTest",
    # M10-3 循环 Boss 图：拓扑/布局连通 + 10 点装配 + 等级每次现算 + norm 数值 + 经验曲线。
    "ArenaMapTest",
    # 第七章双循环分支：动态门槛、96/100 席装配、收益和超软上限奖励保全。
    "EndgameCycleMapTest",
    # 工程 91 孤王绝域：单席 / 血 ×20 重生 1800 / 双门槛（100 级 + 全身紫装）/
    # 十倍件数逐组比值 / 掉落 levelOffset=10（101 与 110 必须同时出现）/ 回廊第四出口。
    "SoloBossFieldTest",
    # 工程 94 百首禁域承伤：**结果**层面的契约（不是配置层面）。用真实存档快照
    # （140 级 / 防御 41,857 / 血 408,288）+ 真实例化 Boss 算每击、破防余量、60 秒掉血。
    # 守的是「Boss 打得疼」这件事，配置写成 3.0 但玩家防御涨过它就红。
    "BossFieldDamageTest",
    # 工程 95 挂机自动维护：自动修复（阈值/1.5× 便利费/只修身上/金币不足一件不修）
    # + 自动四金合紫（只吃背包 0 星未收藏同档料 / 收服务费 / 铁匠仍免费）。
    "AutoMaintenanceTest",
    # 工程 96 保星产物穿不上：产物等级口径（十个部位 vs 真造实例）+ 预览/确认/toast 三层提示
    # + 身上件被吃的叠加警告。守的是「玩家知道自己拿到的是什么、什么时候能穿」。
    "StarTransferLevelHintTest",
    # M10-3b 多目标血条：实例分条 + 不重排 + 逐条过期/死亡 + current_bosses + 音频按实例。
    "BossMultiTargetTest",
    # M10-4 能力层：useType=panel 分发 + PanelRouter ready 表 + 任务等级门槛（发放任务在 M10-7）。
    "PortableToolsTest",
    # M10-5 追猎令牌：行集/过滤/倒计时同源 + ordinal 真进 key + 等级跟随 + 与 Spawner 序号一致
    # + _map_has_monster 认 bossSpawns + travel_anywhere / fee_anywhere + 落地意图。
    "BossTokenTest",
    # M10-6 随身商店：14 种精确集合 + 逐项价格 + 三条排除规则 + 购买链路 + 面板点亮 + 如意说明。
    "PortableShopTest",
    # 工程 60 出售页布局：长名单必须换行、不得出现横向滚动条、托盘必须仍居中。
    # 断的是「内容最小宽 ≤ 视口宽」——只看 size 会被父容器钳住，那是假绿。
    "PortableShopLayoutTest",
    # 工程 61 暴力预设：全选可售装备 / 收藏与任务物品仍不卖 / 一次点击成交 / 暴力不落档
    # + CHOICE_VALUES 不得收编（那会让「40 格全勾」的默认态回到玩家面前）。
    "SellPresetBrutalTest",
    # 工程 63 拾取自动出售：只对拾取生效（add_item 不受影响）/ 60 级运行时门槛 / 收藏与更好装备不卖
    # / **金币满与空槽位两条专属否决** / 积极档不卖史诗 / 新键不 bump schema / 摘要追加段。
    "AutoSellPickupTest",
    # M10-7 随身车夫：七分组（c7_arena 落 60+ 而非 51-60）+ 跨章 35 行 + 面板双模式
    # + C6S07 等级门槛 60 与三件发奖 + 三件全能用与存档往返（unlocks 白名单）。
    "PortableCarterTest",
    # M10-8 装备重铸：费用四点 + 除词条外逐键不变 + 条数/区间/实例等级缩放 + 扣费与三种拒绝
    # + 穿戴/背包广播 + **随机流快照（重构安全网）** + D-15 回收价三段与不外溢。
    "ReforgeTest",
    # 工程 81 重铸词条锁定：**空锁定逐字节同结果（随机数红线）** / 锁定条目连数值一起保留
    # / 结果不得出现重复 stat / 百分比锁定必须跳过 randf 判定 / 条数守恒 / **全锁与非法 stat 拒绝**
    # / 费用按锁定数**实扣** / lockFactor 真接线 / 已穿戴加成变化只来自未锁定部分
    # / **锁定不落档** / UI 锁按钮数与词条数一致 + 换装备即清空。
    "ReforgeLockTest",
    # 工程 86 重铸精炼：档位折算（同档 1 / 高档 2 / 低一档 0.5 / 低两档 0.25 / 12★ +1）
    # / 有效件数封顶 4 + 下限 60% / 可投判定 / ratio=1.0 时区间压成一点 / 锁定不吃下限
    # / 结算同批扣材料与金币 + 拒绝路径一件不扣 / UI 材料格与提示。
    "RefineTest",
    # 工程 87 重铸会话：重铸 ↔ 背包双向并开 / 开重铸自动开背包 / 关重铸保留背包
    # / 关背包同步关重铸 / 人物面板打开时自动关闭 / 随机放入填满 4 格且背包不变。
    "ReforgeSessionTest",
    # 工程 90 重铸评分：当前分与 `Equipment.score` 同源 / 重铸前后差值（基准只在成功分支写、
    # 关面板即清）/ 破损件按基底算且必须解释 / 无候选整行隐藏 / 内容超高时收敛到可用区并出滚动条。
    "ReforgeScoreTest",
    # M10-9 升级节奏：60→70 经验链端到端击杀数 + 每级上下界 + 八档战斗不变量 + LevelGap 真生效。
    "PaceTest",
    # M10-9 经济节奏：单只产出 + D-15 比值 + **四档重铸频率落 5–9** + 参数真接线 + GOLD_CAP + 金币不缩放。
    "EconomyTest",
    # M10-10 药水百分比：**L≤60 与装备品质无关**（方案 B 的等级守护）+ 三档比例 + use 真按比例回血
    # + pick_index 用实际量（用固定值必选错档）+ 满值/截断两条 M2.5 回归。
    "PotionRestoreTest",
    # E6-1 整链：主线 67 节点单链 + 第三～六章 50 个逐节点接取/交付 + campaign_complete
    # + 无残留 + 支线零扰动。断的是「`prev` 被改坏 / 交付人换图 / 解锁字段写成单数」。
    "CampaignChainTest",
    # R4 Lv25/40 接线：穿防 ×0.7 防御 / 3 段独立结算 / 破甲状态机 / 单体语义 / 自动战斗评分
    # + 可装备列表与 skills.json 全量一致。
    "SkillCapabilityTest",
    # 工程 66 套装加成：全 common 恒 0（PaceTest 的守护）/ 品质与星级四档 / 最低档决定
    # / 空槽不成套 / **加法得 40% 而非乘法的 44%** / **max_hp 只放大一次不是 1.96 倍**
    # / 反向属性（攻击间隔）用除法。
    "SetBonusTest",
    # 工程 77 装备耐久：新实例满耐久 / 旧档无字段通过 / 损耗分档 1/4/12 / 破损跳过属性汇总
    # / **套装 pct 不变（核心）** / 修理费四点与比例取整 / 金币不足一件不磨 / 存档往返不判毁档。
    "DurabilityTest",
    # 工程 78 浮层样式统一：外壳不透明 + 人物装备槽结构化卡（含评分行）/ 空槽仍原生
    # / 文案卡零改动 / **背包对比多卡零回退** / 托盘售价行优先 / 仓库与合成走结构化卡。
    "TooltipStyleTest",
    # 工程 79 随身工具补领：**解锁键未置不补（新档不白送）** / 已拥有不补（防重复刷）
    # / 背包满走仓库 / 两处都满记 failed / 读档自愈端到端（物品真进 GameState）/ 齐全时不打扰。
    "ToolReclaimTest",
    # 工程 80 随身三件套：**放行口径与执行层同源（未实现 useType 不放行）** / 三件工具格内简称互不相同
    # / panel 类不显示角标 / 缺件提示区分背包与仓库 / 车夫折叠**只改可见性不改 row_count**
    # / 默认展开组跟着等级走 / 令牌过滤与折叠**不回写 BossToken.rows()** / 手风琴同时最多一组。
    "PortableToolsHotbarTest",
    # 工程 82 打金图超杀保护 + 金脉守卫：**技能不再一刀秒（1→2 击）** / **弱装逐值不变**
    # / **Boss 档击数逐值不变** / cap 纯函数六条边界 / take_hit 是唯一入口且不改写 result
    # / spawner 按地图字段透传（Boss 零泄漏）/ 守卫血×6 与金币×4 比值 / 多段技能每段各自受 cap。
    "GoldFieldCapTest",
    # 工程 87 紫装献祭换经验：**按装备需求等级计价（L80 武器 = 71 档，不是 80）** / 12★ 1.96 倍
    # / 白名单（收藏·金装·药水·非法星级）/ plan 低档优先与单次 20 件上限 / 结算守恒与旁观件不动
    # / 穿戴件被拒 / L60 不开放 / **任一件不合规整批不扣** / 升级结转分毫不差。
    "PurpleSacrificeTest",
    # 工程 87：铁匠菜单结构 **长期不在默认集**，工程 77 加维护组后三条断言就陈旧了（服务数 4→5、
    # 网格 2 组→3 组、100% 缩放下已需要滚动）却无人发现。修好后纳入默认集，防止再次腐烂。
    "EquipmentFusionUiTest",
    # 工程 89 拖拽丢弃：**投放区常态 IGNORE / 拖拽期接管 / 松手当帧恢复**（漏切会让全屏控件
    # 常驻拦截，点地走路全失灵）+ 任务物品·随身工具·收藏三类拒绝且文案对得上真实原因
    # + 工具判定先于 quest（三件工具都带 questItem）+ token 失效不丢件
    # + 落点三条兜底（不可走 → 脚边 / 超 6 格 → 脚边；**必须采用解析后的点，不是原始点**）
    # + 堆叠整堆落地 + manual_only 不被捡回（含「普通未认领物必被捡走」的反向对照）。
    "DropToGroundTest",
    # 工程 93 掉落铺格：**一件一格（任意两件不得同格）** / 落点精确等于目标格心
    # / 圈数按件数自动扩展（`1+4r(r+1)` 六档边界）/ 内侧优先（传说占中心格）
    # / 不可走格被跳过且不丢件 / 越界格被拒（否则会被 clamp 挤成一堆）/ 超容量循环复用
    # / 名字降噪阈值 20 件 / 排布确定性。
    "LootGridTest",
    # 工程 98 法师职业（P1—P3 契约）：**职业框架**（默认职业全 1.0 / 派生层级 / 旧档迁移 /
    # 技能归属过滤 / 快捷栏清理双向）+ **远程普攻**（3.9 格能打 4.1 格不能打 / 投射物纯视觉
    # 不二次结算）+ **百分比蓝耗**（按 max_mp 算 / 蓝差 1 点不放且不进 CD / 武士固定蓝耗不变）
    # + **魔法盾**（扣血与扣蓝两侧夹逼 / 断蓝即全额 / 升阶真生效 / 武士逐位不变）
    # + **减速**（移速乘子与到期恢复 / Boss 时长减半 / 未命中不减速）。
    "ClassFrameTest",
    "MageResourceGrowthTest",
    "MageRangedTest",
    "MageManaTest",
    "MagicShieldTest",
    "MageSlowTest",
    # 工程 98 §5.1 平衡判据：击杀耗时比 / 开盾掉血比 / 断盾掉血比 / 蓝药瓶数 / 金币收益比。
    # 玩家侧用**实测快照常数**（造装备算不出真人承伤，工程 94 老坑），Boss 侧真实例化。
    "ClassBalanceTest",
    # 工程 98 修订：技能 CD 压到攻击间隔级（雷电 0.6s / AOE 2.8—3.8s），系数同步降到
    # 单次 0.5—0.65 倍 —— 守「CD 变短但强度不暴涨」这条数学对价，魔法盾排除在外。
    "MageRotationTest",
    # 工程 102：魔法盾 HUD 活动提示，以及实际敌群位置下的法师挂机技能与卡位回退。
    "HudBuffTest",
    "MageAutoSkillsTest",
    # 工程 100 任务目标精英刷新提示：`tombstone` 是纯数据字段，漏配不报错、不影响刷怪，
    # 但会让任务箭头常亮指向一格空地。守「kill 任务引用的精英必须有墓碑」+ 文案不再写死
    # Boss + Boss 侧 17 处不被波及 + 真标记冷却后原地长出墓碑的行为往返。
    "QuestTargetRespawnHintTest",
    # 工程 101 面板不再阻断挂机：A 12 类业务面板都不切「对话中暂停」/ B 行为层真在移动
    # / C 真暂停仍冻结（守边界，别把暂停一起放开）/ D 面板打开时自动拾取仍生效
    # / E 死亡仍关挂机。前身 NpcAutoBattleTest 的断言已按需求反向。
    "NpcAutoBattleTest",
    "PanelAutoBattleTest",
    # 工程 102 同部位额度：单槽/双槽额度、金紫占额度但不卖（口径 B）、星级硬保护优先、
    # 端到端透传（防「额度上下文漏传 ⇒ 静默退回旧口径」）、同分排序稳定、空槽与破损口径不变、
    # 拾取驱逐与让位（含同分让位）。
    "SellGearQuotaTest",
    # 工程 103 怪物重叠：追击与攻击两阶段都保持同类最小间距 / Boss 不可被推动但会挤开普通怪
    # / 碰撞层不变（玩家仍可穿过怪群，ActorCollisionTest 的断言继续成立）。
    "MonsterCrowdTest",
    # 工程 104 地面掉落积压：装饰环走预渲染纹理（技能圈仍走折线）/ 背包满早退 +
    # 只在背包满时节流 / 距离门控（远处静止件零重绘、悬停仍每帧）/ ClickArea 不参与重叠检测。
    "GroundLootPerfTest",
    # 工程 105 单体技能不画范围提示：`single` 一次地面几何都不画（逻辑 + 行为两层）/
    # `circle`+`cone` 照常画（防一刀切）/ 雷电术按 skills.json 的 fx 分派、不产生飞行投射物 /
    # 未知 shape 不画（防 else 兜底复活）。
    "SkillFxShapeTest",
    "SmokeTest",
]

## 仅作夹具、自身不输出成功完成标记的场景，不纳入 `--all`。
FIXTURE_SCENES = {"CampWhitebox", "CampStyleSample", "CampStyleBenchmark"}

## 必须 `--rendered` 才有意义：headless 下 `get_viewport().get_texture()` 取不到图，
## 或性能基准拿不到真实帧时间。它们在无头 `--all` 里**必然假红**，不是功能缺陷。
## 单独复核：`python3 tools/run_isolated_tests.py --rendered ChapterOneMapArtCapture`。
RENDER_ONLY_SCENES = {"MapRenderBenchmark", "ChapterOneMapArtCapture"}

## 已知美术欠账：**断言本身是对的，红的原因是素材/布局数据过时**，需要重做美术而不是改代码。
## `--all` 时单独打印 SKIP 且不计入退出码，保证「既不被当成新回归，也不会悄悄消失」。
## 修好一条就从这里删除并确认复绿；新增条目必须写明「缺什么素材 + 对应文档」。
KNOWN_ART_DEBT = {
    "CampStyleSampleTest": "A/B 局部样板的 manifest 仍为 camp_whitebox_v1，正式营地已升 v2"
                           "（tools/build_camp_style_sample.py 的 LAYOUT 与 OBJECTS 是 v1 手工标注）"
                           "⇒ 需按 v2 重做样板美术。见素材设计 17/18。",
    "CampStyleTraversalTest": "同上：依赖 `tests/CampStyleSample.tscn`，样板过时导致装配断言先失败。",
    "QualityFrameTest": "`SampleArt.decorate()` 固定 icon_max_width=34，与格宽 46/52 不符；"
                        "图标裁透明边也未做 ⇒ 需重做槽位图标裁边。见素材设计 48。",
}

## 成功完成标记只认**行尾**形态，避免无关文本里裸含 "PASS" 被误命中。
## 覆盖两种既有打印约定：`[XxxTest] 全部通过 ✅` 与 `XxxTest: PASS` / `[XxxTest] PASS`。
_COMPLETION_TAIL = re.compile(r"(?:全部通过|全部断言通过|✅)$|(?:^|[\]\[:\s])PASS$")


def has_completion_marker(output: str) -> bool:
    """输出中是否存在位于**行尾**的成功完成标记（行中裸含 PASS 不算通过）。"""
    return any(_COMPLETION_TAIL.search(line.rstrip()) for line in output.splitlines())


def discover_all_tests() -> list[str]:
    """全量入口：枚举 tests/*.tscn 的测试场景名（排除夹具与渲染专用场景）。"""
    return sorted(path.stem for path in (ROOT / "tests").glob("*.tscn")
                  if path.stem not in FIXTURE_SCENES and path.stem not in RENDER_ONLY_SCENES)


def run(project: Path, args: list[str], timeout: int = 180, rendered: bool = False) -> tuple[bool, str]:
    process = subprocess.Popen(
        [str(GODOT), *([] if rendered else ["--headless"]), "--path", str(project), *args],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    lines: list[str] = []

    def collect() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            lines.append(line)
            # An aborted GDScript coroutine otherwise leaves the scene running
            # until the frame cap, with no opportunity to call get_tree().quit().
            if "SCRIPT ERROR:" in line:
                process.terminate()

    reader = threading.Thread(target=collect, daemon=True)
    reader.start()
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        lines.append("FAIL: Godot test timed out\n")
    reader.join()
    output = "".join(lines)
    failed = process.returncode != 0 or "SCRIPT ERROR:" in output or "FAIL" in output
    return not failed, output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", default=DEFAULT_TESTS)
    parser.add_argument("--all", action="store_true", help="运行 tests/ 下全部测试场景；默认集只是常用子集")
    parser.add_argument("--committed-tree", action="store_true", help="用已提交的稳定快照隔离并行美术试作")
    parser.add_argument("--rendered", action="store_true", help="以实际窗口运行指定测试，用于渲染采样")
    args = parser.parse_args()
    if args.all:
        args.tests = discover_all_tests()
    if not GODOT.is_file():
        print(f"Godot 未找到：{GODOT}", file=sys.stderr)
        return 2
    name = "DegenerateAge-Test-" + uuid.uuid4().hex[:12]
    # Godot macOS 默认 user:// 目录。只清理本次随机项目名；永不指向正式游戏名。
    user_data = Path.home() / "Library/Application Support/Godot/app_userdata" / name
    try:
        with tempfile.TemporaryDirectory(prefix="degenerateage-test-") as temporary:
            project = Path(temporary)
            if args.committed_tree:
                archive = subprocess.Popen(["git", "archive", "HEAD"], cwd=ROOT, stdout=subprocess.PIPE)
                assert archive.stdout is not None
                subprocess.run(["tar", "-x", "-C", str(project)], stdin=archive.stdout, check=True)
                archive.stdout.close()
                if archive.wait() != 0:
                    raise RuntimeError("无法读取已提交快照")
                print("使用已提交的稳定快照；工作区美术试作不参与本轮功能回归")
            else:
                for item in ROOT.iterdir():
                    if item.name.startswith(".") or item.name in {"project.godot", "build", "docs", "art_source"}:
                        continue
                    if item.name in {"scripts", "autoload", "data", "scenes", "tests", "addons"}:
                        # Freeze code/data so concurrent edits cannot invalidate an imported class cache.
                        shutil.copytree(item, project / item.name)
                    else:
                        (project / item.name).symlink_to(item, target_is_directory=item.is_dir())
            config = (project / "project.godot" if args.committed_tree else ROOT / "project.godot").read_text(encoding="utf-8")
            config = config.replace('config/name="末法纪元：最后的守护者"', f'config/name="{name}"', 1)
            (project / "project.godot").write_text(config, encoding="utf-8")
            ok, output = run(project, ["--editor", "--quit"])
            if not ok:
                print("资源导入失败\n" + output[-4000:], file=sys.stderr)
                return 1
            failures = []
            skipped: list[str] = []
            for test in args.tests:
                # 已知美术欠账只在 `--all` 里跳过；显式点名时照跑，方便复查是否已修好。
                if args.all and test in KNOWN_ART_DEBT:
                    skipped.append(test)
                    print(f"{test}: SKIP · 已知美术欠账（不计入退出码）：{KNOWN_ART_DEBT[test]}")
                    continue
                scene = f"res://tests/{test}.tscn"
                # Async physics tests must finish, not silently hit a render-frame cap.
                ok, output = run(project, ["--scene", scene, "--max-fps", "120",
                                           "--quit-after", "14400"], timeout=240, rendered=args.rendered)
                completed = has_completion_marker(output)
                ok = ok and completed
                if not completed:
                    output += "\nFAIL: 测试未输出成功完成标记，不能视为通过\n"
                evidence = [line for line in output.splitlines() if "[PERF]" in line or "PASS" in line or "全部通过" in line or "全部断言通过" in line or "失败" in line or "FAIL" in line]
                print(f"{test}: {'PASS' if ok else 'FAIL'}" + (" · " + " | ".join(evidence[-24:]) if evidence else ""))
                if not ok:
                    failures.append(test)
                    diagnostics = [line for line in output.splitlines()
                                   if "SCRIPT ERROR:" in line or "ERROR:" in line or "失败：" in line]
                    for line in list(dict.fromkeys(diagnostics))[:12]:
                        print(line, file=sys.stderr)
            if skipped:
                print(f"\n已知美术欠账跳过 {len(skipped)} 项：{', '.join(skipped)}"
                      f"（明细见 KNOWN_ART_DEBT；修好后必须从集合里删除并复绿）")
            return int(bool(failures))
    finally:
        if user_data.is_dir():
            shutil.rmtree(user_data)


if __name__ == "__main__":
    raise SystemExit(main())
