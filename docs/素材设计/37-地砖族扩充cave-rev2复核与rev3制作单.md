# 37 地砖族扩充 cave rev2 复核与 rev3 制作单

日期：2026-10-17
执行方（生图）：Codex 会话「制图大师」
复核方（本文件）：我方，只做量测、复核与判据校准
依据：[35-地砖族扩充第一批复核](35-地砖族扩充第一批复核.md) §5.2（三条退改判据）、[33-地砖族扩充第一批制作单](33-地砖族扩充第一批制作单-A层变体扩充.md) §2/§6（固定文本块与验收判据）、[32-第一章地面贴图原始范式与M1偏差对照](32-第一章地面贴图原始范式与M1偏差对照.md)（原始范式）
被复核对象：`art_source/environment/ground_tiles_v1/cave_tiles_3x3_rev2.png`（承诺 1536×1536，实产 1254×1254）

## 1. 结论速览

| 项 | 结论 |
|---|---|
| cave rev2 判定 | **退回重出（rev3）** |
| 决定性依据 | ①35 号 §5.2 三条退改判据**全部未过**；②re×2 复刻打包后**菱形格线仍在**（去掉边缘融合、换两种填色都不消失）；③细密颗粒缺失，内部颗粒对比只有旧族的 **38%** |
| 附带发现 | 35 号 §5 把格线主因归为「写死填色 `#D1B787` 与源边色不匹配」**不成立**，本文件 §6 更正 |
| 附带发现 | 35 号 §5.2 的「bbox 宽 ≥410px」为绝对量判据，在生成器不吐 1536 画布时会**机械误伤**（rev2 实测占格宽 95.5%，其实通过），本文件 §8.3 改为相对量 |
| 我方责任 | rev2 的「偏白偏淡、失去颗粒」主要由我方 35 号 §5.2.1 提示词的**过度纠偏**造成，§7 如实记录 |

## 2. 复核依据与方法

- 量测工具：ImageMagick 7（`magick`）；打包复刻用 Godot 4.7 headless 跑一次性脚本，逐字复刻 [build_environment_art.gd](tools/build_environment_art.gd) `_pack_tiles` 的四步（alpha 硬阈 → `get_used_rect` trim → 点采样 resize 到 64×32 → 菱形掩码 + 平底色填隙 + cave 边缘融合）。
- 色数口径统一为 `-alpha off -format %k`（即 RGB 独立色数，不含 alpha 维度），与 35 号口径一致。
- Codex 在 [36 号回报](36-地砖族扩充cave重出回报.md) 中自测的「比例 1.735–1.770、bbox 宽 399–400、外圈色带命中率 0%、均值约 RGB(183,151,101)」与我方实测**吻合**。双方量测口径已对齐，本轮退回不是口径争议。

## 3. 实测数据

### 3.1 形态（按真实 cell 418×418 量）

| 格 | bbox | 比例 | 占格宽 |
|---|---|---|---|
| r0c0 | 400×226+10+163 | 1.770 | 0.957 |
| r0c1 | 400×227+9+163 | 1.762 | 0.957 |
| r0c2 | 399×226+9+163 | 1.765 | 0.954 |
| r1c0 | 400×227+10+96 | 1.762 | 0.957 |
| r1c1 | 400×227+9+96 | 1.762 | 0.957 |
| r1c2 | 400×227+8+96 | 1.762 | 0.957 |
| r2c0 | 399×230+10+24 | 1.735 | 0.954 |
| r2c1 | 400×230+9+24 | 1.739 | 0.957 |
| r2c2 | 400×230+8+24 | 1.739 | 0.957 |

- 比例极差 1.735–1.770（**低于 1.80 下限**）；bbox 面积极差 1.98%（通过）；九格互不相交（通过）。
- 画布 1254×1254（cell 418），**本轮没有做非整数放大**（rev1 曾 1254→1536 点采样放大），故画布偏差本身危害低。
- 对比基线（现行 2×2 源稿，cell 768×512，同口径量测）：wild 698×372 / 700×371 / 689×380 / 696×382；ash 724×400 / 726×400 / 724×403 / 726×404；cave 698×374 ×4。

### 3.2 色调与边色

| 项 | 现行 cave 源 `cave_tiles_v2.png` | rev2 |
|---|---|---|
| 内容均值 | (185.6, 155.8, 113.1) | (209.8, 187.2, 150.7) |
| 与外圈填色关系 | 边色 ≈ 填色 `#D1B787`(209,183,135)，差 ≤ 6 | 边色均值 (189,160,114)，比 `#D1B787` **暗约 −20/−23/−21** |

rev2 内容均值比现行源亮 **Δ ≈ +24 / +31 / +38**——整体偏白、偏淡，与「同一族、同一值带」这一硬约束冲突。

### 3.3 颗粒（决定性证据）

对**打包后**的 64×32 单块，取内部安全区 `24x12+20+10`（288 px，避开掩码与边缘融合带）量灰度标准差，即「颗粒起伏强度」：

| 旧族（assets/tiles/cave/tile_0..3） | rev2（复刻打包 tile_0..8） |
|---|---|
| 24.55 / 25.06 / 29.10 / 19.67 | 5.46 / 7.96 / 8.75 / 13.01 / 9.39 / 8.21 / 13.26 / 10.86 / 10.31 |
| 中位 **24.8**，下限 19.7 | 中位 **9.4**，上限 13.3 |

rev2 的颗粒对比只有旧族的 **约 38%**：不再是「细密粗糙颗粒」，而是「浅淡平底 + 稀疏斑点」。

### 3.4 限定色数（`-alpha off`）

| 源/产物 | RGB 独立色数 |
|---|---|
| 现行 cave 源 `cave_tiles_v2.png` | 53420 |
| 现行打包件 `assets/tiles/cave/tile_0.png` | 949 |
| rev1 源 `cave_tiles_3x3.png` | 13285 |
| rev2 源 `cave_tiles_3x3_rev2.png` | 15202 |
| rev1 打包件 `_packed/cave/tile_0.png` | 390 |
| rev2 打包件 `_packed/cave_rev2/tile_0.png` | 323 |

rev2 源色数与 rev1 **同量级**（15202 vs 13285）→ 说明问题不在「色数不足」，而在**色块的形态**：rev1/rev2 的色块是柔和的大面积涂抹与稀疏点，旧族是小而硬、均匀密布的高对比颗粒簇。打包缩放后 rev2 进一步降到 323 色，细节被压平。

## 4. 逐条对照 35 号 §5.2 三条退改判据

| # | 35 号 §5.2 判据 | 实测 | 判定 |
|---|---|---|---|
| 1 | 菱形外圈色带须落在 `#CBB182`–`#D1B787`，或与现行 cave 边色一致 | 外圈 6px 带 (189.4,160.3,113.9)，命中目标区间 **0%**（与 Codex 自测一致） | **未过** |
| 2 | 九格必须收在同一族值带，不得明显偏白/偏灰 | 内容均值比现行源亮 Δ+24/+31/+38；内部颗粒对比仅 38% | **未过** |
| 3 | 每格 bbox 宽高比 ≥ 1.80 | 1.735–1.770 | **未过** |

三条全未过 → 退回，无需争议。`bbox 宽 ≥410px` 一项经复核为**误判项**（见 §8.3）。

## 5. 目视证据

### 5.1 [cave_rev2_old4_vs_rev2_8x.png](art_source/environment/ground_tiles_v1/_verify/cave_rev2_old4_vs_rev2_8x.png)（上＝旧 4 块，下＝rev2 九块，8×）

- 旧族：暖棕底 + **均匀密布**的 1–2px 深色颗粒，质地面密度高，像脏砂石。
- rev2：显著更淡、更干净；颗粒更稀、更大（2–4px，部分带亮圈像「孔」），并出现多块 **大面积柔和白晕**（下排第 2/第 3 行右侧数块）。柔和涂抹违反 33 号 §2 `[风格锁定]` 的「hard square pixel edges, no blur, no soft shading」。

### 5.2 [cave_rev2_iso_paving_5rows_2x.png](art_source/environment/ground_tiles_v1/_verify/cave_rev2_iso_paving_5rows_2x.png)（等距铺装五行，同图同角色同接地影）

自上而下：①旧 4 块 ②rev2·旧填色 `#D1B787` ③rev2·**去掉边缘融合** ④rev2·紧带自动填色(188,156,106) ⑤rev2·宽带自动填色(203,180,142)。

- ①旧：细节密、**无可见格线**。
- ②⑤：出现整片**亮**菱形格线。
- ③（去掉 `edge<0.22` 边缘融合）：**格线依然存在**，且边界处多一圈细暗线。
- ④（填色改为与源边色一致的暗色）：格线**转成暗色**，并未消失。

### 5.3 逐像素证据（打包后 tile_0 左顶点，y=15，x=1..9）

| | 像素序列（R 通道） | 起伏 |
|---|---|---|
| 旧族 | 206, 216, 204, 194, 187, 168, 234, 237, 226 | 极差 **69** |
| rev2 | 209, 211, 211, 212, 213, 215, 215, 216, 216 | 极差 **7** |

rev2 的第 1 像素 ≈ 填色本身（`#D1B788`），随后是**单调平滑渐变**：外圈没有任何颗粒。旧族在同一位置仍是强起伏（168–237），所以边缘融合在旧族上「看不见」，在 rev2 上被放大成一条数学平滑的带。

## 6. 根因归因修正（更正 35 号 §5）

35 号 §5 把格线主因写成「写死填色 `#D1B787` 与 rev1 新源边色 `#BFAF98` 不匹配」。本轮四组对照实验证明该归因**不成立**，正确归因是：

1. **主因（源稿侧）**：rev2 每块菱形自带一圈**平坦、低颗粒的外缘**（§5.3 极差 7 vs 旧族 69），铺装后各块的外缘首尾相接，连成整片格线。**去掉边缘融合后格线仍在**（§5.2 第③行）即为直接反证。
2. **放大器（管线侧）**：`_pack_tiles` 的 cave 分支 `edge < 0.22 → lerp(color, fill, 1 − edge/0.22)`：在 edge→0 处混合系数→1，会把外圈像素**全部压成同一个常量色**，方差归零。旧族外圈均值本就 ≈ 填色，故肉眼不可见；rev2 外圈颗粒薄，于是一条完全平滑的带在颗粒内部旁暴露出来。
3. **次要因素（常量侧）**：写死填色只决定格线的**明暗方向**（填色比源边色亮→亮格线；紧带取样取到更暗→暗格线），**不决定格线是否存在**。

对我方 35 号 §5.3 的连带更正：**「填色自动取样」不是本症的根治**，它只消除「写死常量」的脆弱性（换族/换色板时不必改代码）。本症必须在源稿侧解决（§8.1 新增第 4 条硬约束）。

## 7. 我方责任复盘（如实记录）

rev2「偏白偏淡、失去细密颗粒、出现柔和白晕」在很大程度上是**我方 35 号 §5.2.1 提示词过度纠偏**造成的，不是 Codex 独立跑偏：

1. 我在 §5.2.1 删掉了 33 号 §4.2 原文的 `over packed grey rock dust`——这正是旧族「细密颗粒、脏砂石感」的来源措辞。
2. 我删掉了 `heavily stained` 与 `darker grey patches` 两档，并把族基色从「灰岩」改写为 `warm pale limestone`——直接把整体亮度上推了 Δ+24/+31/+38。
3. 净效果：去掉了「灰底 + 密颗粒」，换成了「浅米底 + 稀疏亮斑 + 柔和涂抹」。

**教训（拟写入项目规则）**：提示词的整改必须**单轴推进**——修一个问题时不得同时改动族基色与材质密度措辞，其余段落一字不改并加锁；凡是「把某个措辞删掉」的改动，都要先确认它是既往通过稿的成因之一。

## 8. rev3 制作单

### 8.1 相对 rev2 的四条改动

1. **补参考图 2 = 材质锚点（关键）**：把**现行已通过**的 `art_source/environment/cave_tiles_v2.png` 作为第二参考图。两轮文字描述都漂，改用图锚定：九块是**那张图那套材质**的新变体，不是新材质。
2. **恢复颗粒措辞 + 色调锁**：恢复 33 号 §4.2 的 `fine mineral staining over packed grey rock dust` 与 `heavily stained` 档；不再使用 `pale warm limestone` 作族基色；明文写死「不得比参考图 2 更亮、更干净」。
3. **新增硬约束——菱形外圈不得自带平坦带或描边**（本轮退回的直接成因）。
4. **形态与画布**：画布尺寸不再作为判据（生成器不提供尺寸参数）；改为**相对量**——每格菱形 bbox 宽 ≥ 0.90×格宽、**宽高比 ≥ 1.86**（对齐现行 cave 基线 698:374）。禁止二次放大、rotate、镜像、单轴压缩。

### 8.2 rev3 可直接粘贴提示词

```text
Use case: stylized-concept. Asset type: production terrain atlas for a 2D isometric pixel-art
dark-fantasy RPG. Match supplied reference image 1 for palette, pixel chunkiness and lighting.

MATERIAL ANCHOR (highest priority): supplied reference image 2 is the APPROVED cave ground of this
same game. The nine tiles you draw are NEW VARIANTS OF THAT EXACT MATERIAL — same grey-brown
balance, same grain size, same speckle density, same edge tone, same overall darkness. Never invent
a new, lighter, cleaner or smoother material. If in doubt, copy reference image 2.

Match supplied reference image 1 exactly: deliberate chunky pixel clusters with hard square
pixel edges, strict limited palette of about 16 flat colors (deep ink #171A21, iron grey #353B46,
grey rock #687078, worn cloth #A89978, bone white #E6DDC6, muted moss green, campfire orange
#D99A52 accents), upper-left light source, quiet low-contrast terrain so player characters read
clearly on top. No gradient, no blur, no soft shading, no antialiasing, no photographic texture.

Create ONE atlas: strict 3 columns by 3 rows, nine SEPARATE FLAT 2:1 diamond isometric ground
tiles on a truly transparent background. Every cell is an equal square. Inside each cell place
exactly ONE diamond ground tile, centred horizontally, spanning the full cell width, about half
the cell height, with clear empty transparent gap above and below it. No tile may touch, overlap
or bleed into a neighbouring cell. Each diamond is a flat ground patch only. Do not draw grid
lines, borders, labels, numbers or letters between cells.

Subject: nine variations of ONE single ground material — damp pale limestone cave floor with fine
mineral staining over packed grey rock dust. All nine tiles must obviously be the SAME material and
must sit inside the SAME narrow value band as supplied reference image 2: sharing one palette and
one edge tone. They differ ONLY along three narrow axes: (1) staining density, from almost clean
stone to heavily stained; (2) dampness, from dry matte to a faint cool sheen; (3) amount of tiny
rubble specks, from none to a light scatter. The overall darkness and cleanliness must match
reference image 2 — no tile may be brighter, paler or cleaner than reference image 2. Keep the fine
dense mineral grain (1-2 pixel hard specks at high contrast) across the WHOLE surface of every
tile; never replace the grain with large smooth pale smudges.
Spread across the nine cells in roughly this order: clean-ish / dry / no specks; clean-ish /
dry / few specks; light staining / dry / few specks; light staining / slightly damp / moderate
specks; medium staining / slightly damp / no specks; medium staining / damp sheen / no specks;
heavy staining / damp sheen / few specks; medium / damp with darker grey patches / no specks;
light staining / dry / moderate specks. Ground tiles only: flat, no height, no objects, no glowing
crystals and no violet veins rising above the ground surface.

The ground pattern must continue uniformly all the way to the diamond's outer edge: NO pale flat
margin, NO darker outline traced around the diamond, NO smooth untextured border band, NO bevel.
The outermost row of pixels of every diamond must carry the same grain and the same average tone as
its interior, so that any two tiles can sit side by side without a visible seam.

LOW resolution pixel clusters appropriate for final 64x32 tiles enlarged with nearest neighbour:
chunky readable clusters, hard square pixel edges, no antialiased or painterly blur.
Screen-upper-left light, muted low-contrast palette so player characters read clearly on top.
Ground features must not cross the tile boundary: no large rock, no tall grass tuft, no slab
sticking out of a diamond. No cube sides, no drop shadow, no outline drawn around the diamond.

No text, no letters, no numbers, no watermark, no border frame, no grid. Not smooth vector, not
photorealistic, no high-contrast lighting, no vignette. No creatures, no characters, no UI, no
items. No objects with height: no trees, bushes, walls, buildings, carts, fences, ruins, rocks
standing out of the ground. No soft blurred blobs, no feathered or antialiased diamond edges, no
large smooth pale smudges, no washed-out bright floor, no colour shift towards white or cream,
no uniform flat plain with only sparse dots. No water, no sand, no cobblestone, no road markings.

GEOMETRY: one square canvas, strict 3 columns x 3 rows, nine equal square cells. Inside each cell
draw ONE flat diamond whose width is at least 90% of the cell width and whose WIDTH:HEIGHT ratio is
about 1.86 : 1 — in the approved reference image 2 the diamond measures 698 wide by 374 high; match
that proportion. Do not draw the diamond taller or more square than that. Output at 1536x1536 if
your pipeline allows; otherwise output the native size and do NOT upscale, do NOT rotate, do NOT
mirror, do NOT squeeze on one axis.
```

### 8.3 验收判据校准（rev3 起生效，并回溯用于 B 层）

| 检查 | 35 号旧判据 | **校准后判据** | 理由 |
|---|---|---|---|
| 画布 | 必须 1536×1536 | **不作为判据**（禁止二次放大即可） | 生成器无尺寸参数，两轮均吐 1254；非整数放大反而伤像素 |
| 占格宽 | ≥410px 绝对值 | **≥ 0.90 × 实际格宽** | 绝对值在 1254 画布下机械误伤；rev2 实测 0.955 通过 |
| 2:1 形态 | 比例 ∈[1.70,2.10] | **比例 ≥ 1.86**，且与同族基线差 ≤ 2% | 现行 cave 基线 1.866；rev2 1.735–1.770 |
| 面积极差 | ≤15% | 不变（rev2 通过：1.98%） | — |
| 颗粒密度 | 目视 | **打包后单块内部灰度 std ≥ 15** | 旧族 19.7–29.1；rev2 5.5–13.3 |
| 边色 | 匹配填色 | **匹配填色，且外圈与内部同颗粒** | §5.3/§6 |

### 8.4 回报模板新增项

```text
菱形外圈是否与内部同颗粒（是/否，并给出外圈与内部灰度 std）：____
菱形是否有自带亮边 / 描边 / 平滑带（有/无）：____
每格 bbox 占格宽与宽高比：____
```

## 9. 处置清单与待确认

| # | 事项 | 状态 |
|---|---|---|
| 1 | 本复核文档 37 号 | 已产出（本文件） |
| 2 | rev2 判定退回、按 §8 下发 rev3 | **待你确认** |
| 3 | `_packed/cave_rev2/`、`_packed/cave_rev2_autotight/`、`_packed/cave_rev2_norim/`（本轮归因实验产物） | **待你确认**是否入库（建议入库 `norim` 一版作为反证留痕，或全部只留证据图） |
| 4 | `_verify/` 下 3 张证据图 + 源稿 `cave_tiles_3x3_rev2.png` | **待你确认**是否入库 |
| 5 | `_review_pack_rev2.gd` 等临时脚本、临时图 | 复核完成即删（项目硬约束） |
| 6 | 33 号 §7 打包泛化与 `ground.gd` 选砖接入 | rev3 通过后再动 |

## 10. 证据文件清单

| 文件 | 说明 |
|---|---|
| `art_source/environment/ground_tiles_v1/cave_tiles_3x3_rev2.png` | 被复核源稿（1254×1254） |
| `_verify/cave_rev2_old4_vs_rev2_8x.png` | 旧 4 块 vs rev2 九块，8× 单块对照（§5.1） |
| `_verify/cave_rev2_iso_paving_5rows_2x.png` | 等距铺装五行归因实验（§5.2） |
| `_packed/cave_rev2/` | rev2 按现行口径打包（复现格线） |
| `_packed/cave_rev2_norim/` | rev2 去掉 cave 边缘融合（格线仍在 → 反证 §6） |
| `_packed/cave_rev2_autotight/` | rev2 紧带自动填色（格线转暗 → 反证 §6） |
| `_packed/cave_rev2_autofill/` | rev2 宽带自动填色（与旧填色无差别） |
| `_verify/cave_rev2_iso_paving_3rows_2x.png` | 已删除（被五行版取代） |
