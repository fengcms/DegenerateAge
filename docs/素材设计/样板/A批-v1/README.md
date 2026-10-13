# A批视觉样板 v1

日期：2026-10-13。使用内置 image_gen 生成，未使用CLI/API密钥流程。

## 文件

- guardian_sample.png：守护者正面侧前、背面侧后和攻击关键姿态。
- wolf_sample.png：腐化野狼站立、背面和扑击姿态。
- camp_items_ui_board.png：四种地面、营地局部、短刃/红药/灵能碎片，以及HUD局部风格。

## 状态与检查

这些是风格审阅大图，尚未获用户确认，未接入游戏。不是按64×80、80×80、48×48或64×32导出的正式资源，也不是具有固定锚点与一致帧格的动画图集。三姿态仅用于比较轮廓，不能直接当连续动画播放。风格板中的4格快捷栏仅展示组件，正式HUD仍为16格。

已逐图目视检查：完整主体、暖灰人类与紫色腐化/青白灵能区分、地形与图标主题符合规范。待修整项：生成细节密度较高，正式小尺寸须简化；守护者剑偏长，需要向短刃收敛；HUD装饰尖角可减量；风格板头像与角色表存在脸部差异，正式头像应统一。地砖尚未完成实际64×32边缘拼接检验。尚未进行小尺寸、动画或Godot接入验收。

下一轮先依据用户意见确定造型与细节密度，再制作精确尺寸、固定锚点、可拼接纹理和完整八向动作。

## 最终生成提示词

### guardian

透明背景请求：是。

```text
Use case: stylized-concept. Asset type: game character style sample sheet for Degenerate Age, a retro pixel art 2D isometric dark fantasy ARPG. Create ONE young spirit-blade guardian shown in THREE separated static poses across a horizontal sheet: front three-quarter facing screen southeast, rear three-quarter facing northwest, and an attack key pose facing southeast. Same character and proportions in every pose. Clear truly blocky pixel clusters, designed like a 48 pixel tall character enlarged with nearest-neighbor blocks, limited approximately 18-color palette, no antialiasing, no soft rendering. Medium build, short dark hair, short worn tan shoulder cape, layered leather and cloth, a few old iron armor plates, wrapped short straight single-handed sword, a tiny cyan-white spirit engraving on the sword guard. Human survival clothing with restrained East Asian artifact motifs, no ornate samurai armor. Fixed top-left lighting. Colors #171A21 #353B46 #687078 #A89978 #E6DDC6 with tiny #78D8D0 accent. Full body and sword visible, strong compact silhouette, no ground shadow baked in, no floor, no labels, no text, no borders, no scenery. Consistent isometric elevated view appropriate for 64x32 2:1 ground tiles. Transparent background. This is a visual style sample, not an animation sprite atlas.
```

### wolf

透明背景请求：是。

```text
Use case: stylized-concept. Asset type: ONE corrupted wolf game enemy style sample sheet for Degenerate Age, retro pixel art 2D isometric dark fantasy ARPG. Horizontal sheet with THREE separated static poses of the SAME wolf: standing three-quarter facing southeast, rear three-quarter facing northwest, and a low pouncing attack pose facing southeast. Truly blocky pixel art with crisp visible square pixel clusters, drawn as if each wolf is about 48 pixels wide then enlarged with nearest-neighbor blocks, about 16 solid colors, no soft gradients no antialiasing. Low elongated body, sharp ears, long tail, lean gray-brown fur, dark paws, a few irregular violet corruption fissures on shoulder and flank, one tiny violet eye. Readable canine anatomy and fast melee silhouette, restrained bone growth not a giant boss, no gore. Top-left light consistent across all poses, charcoal #171A21 iron #353B46 gray #687078 tan #A89978 bone #E6DDC6 purple #8656B4. Full paws and tail visible, no ground no baked shadow no text no labels no borders no scenery, transparent background. Same pixel density and restrained worn survival fantasy aesthetic as a leather-clad guardian. Elevated isometric camera for 64x32 diamond ground. This is a visual style sample, not a production animation atlas.
```

### camp_items_ui_board

透明背景请求：否。

```text
Use case: ui-mockup. Asset type: compact art direction sample board for Degenerate Age retro pixel isometric dark fantasy ARPG, a SINGLE beautifully arranged sample review image. Dark matte charcoal #171A21 background, crisp blocky pixel art, restrained warm worn-earth aesthetic, top-left light, no smooth illustration or 3D. Four clearly separated visual sections without labels or words: upper-left four different FLAT 2:1 diamond ground tile samples (packed brown soil, soil with sparse grass, small pale gravel, worn cobbled road), these are flat game tiles not thick floating cubes. Upper-right a small assembled 5 by 5 isometric diamond camp ground patch reusing the tile designs, with a modest campfire, a wooden crate and a weathered road sign; simple low-contrast environment, no characters. Lower-left THREE clearly separated large pixel ITEM ICON samples: old iron guardian short blade with wrapped grip diagonally lower-left to upper-right and tiny cyan engraved guard; SMALL RED POTION round glass bottle with cork and restrained square highlights; spirit shard an asymmetric cyan-white crystal fragment with ancient short linear engraving. Each icon has a strong silhouette as if designed at 48x48 logical pixels, no quality border no letters no quantities no numbers. Lower-right a small HUD component STYLE mockup: dark old-iron frame, circular guardian portrait with short dark hair and tan cape, clearly red health and blue mana horizontal bars; underneath exactly four square shortcut cells with sword, red potion, cyan crystal, and empty slot, dark interior and subtle bone-white frame. No text, no logos, no labels, no watermarks, no screen-filling decoration. Palette #171A21 #353B46 #687078 #A89978 #E6DDC6 #D99A52 #78D8D0 #CF4A4A #4AA3E0. This is a STYLE REVIEW BOARD not a ready-to-import game sprite atlas. Consistent chunky readable pixel density across subjects.
```
