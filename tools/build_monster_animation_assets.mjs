/**
 * 已审核的正式怪物动画构建器：按清单复制图集并生成运行库。
 * 用法：node tools/build_monster_animation_assets.mjs [--check]。
 * --check 只核对现有产物；脚本不代替人工检查八向画面质量。
 */
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const checkOnly = process.argv.includes('--check');
const directions = ['s', 'sw', 'w', 'nw', 'n', 'ne', 'e', 'se'];
const requiredStates = ['idle', 'attack', 'hit', 'death'];

/** 读取仓库内的 JSON 文件；解析失败直接中止构建。 */
function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

/** 读取 PNG 头中的尺寸及颜色类型，避免错误图集进入运行库。 */
function pngInfo(file) {
  const header = fs.readFileSync(file).subarray(0, 26);
  if (header.length < 26 || header.toString('hex', 0, 8) !== '89504e470d0a1a0a' || header.toString('ascii', 12, 16) !== 'IHDR') {
    throw new Error(`不是 PNG：${file}`);
  }
  return [header.readUInt32BE(16), header.readUInt32BE(20), header[25]];
}

/** 校验单包元数据与逐状态图集；定点怪允许不提供 walk。 */
function buildPack(entry) {
  const { id, source: sourcePath } = entry;
  const legacySource = sourcePath.startsWith('docs/素材/monsters/');
  const chapterSource = /^art_source\/chapters\/ch0[2-6]\/monsters\/[a-z0-9_]+\/animation\/animations_v1\/animation\.json$/.test(sourcePath);
  if (!/^[a-z][a-z0-9_]*$/.test(id) || (!legacySource && !chapterSource) || sourcePath.includes('..')) throw new Error(`清单条目无效：${id}`);
  const sourceFile = path.join(root, sourcePath);
  const sourceDir = path.dirname(sourceFile);
  const outputDir = path.join(root, 'assets/sprites/monsters', id);
  const source = readJson(sourceFile);
  if (source.id && source.id !== id) throw new Error(`${id}：源稿 ID 不一致`);
  if (JSON.stringify(source.directions) !== JSON.stringify(directions)) throw new Error(`${id}：八方向顺序错误`);
  const frameSize = source.frame_size;
  const pivot = source.pivot;
  if (!Array.isArray(frameSize) || frameSize.length !== 2 || frameSize.some(n => !Number.isInteger(n) || n <= 0)) throw new Error(`${id}：帧尺寸错误`);
  if (!Array.isArray(pivot) || pivot.length !== 2 || pivot.some(n => !Number.isInteger(n) || n < 0) || pivot[0] >= frameSize[0] || pivot[1] >= frameSize[1]) throw new Error(`${id}：脚底锚点错误`);
  if (requiredStates.some(state => !source.states?.[state])) throw new Error(`${id}：缺少基础状态`);
  const match = /^c([2-6])_/.exec(id);
  if (match) {
    const chapter = `ch${match[1].padStart(2, '0')}`;
    const monster = readJson(path.join(root, 'data/monsters', chapter, 'monsters.json')).find(row => row.id === id);
    if (!monster || monster.appearanceId !== id) throw new Error(`${id}：怪物或外观 ID 不匹配`);
    if (Number(monster.moveSpeed) > 0 && !source.states.walk) throw new Error(`${id}：可移动怪缺少 walk`);
  }
  const runtime = { id, pivot, frameSize, directions, states: {} };
  for (const [state, def] of Object.entries(source.states)) {
    const frames = def.frames_per_direction;
    const contact = def.visual_contact_frame ?? 0;
    if (!/^[a-z][a-z0-9_]*$/.test(state) || !Number.isInteger(frames) || frames < 1 || !Number.isFinite(def.fps) || def.fps <= 0 || typeof def.loop !== 'boolean' || !Number.isInteger(contact) || contact < 0 || contact >= frames) throw new Error(`${id}/${state}：状态元数据错误`);
    const filename = `${state}_atlas.png`;
    const sourcePng = path.join(sourceDir, filename);
    const outputPng = path.join(outputDir, filename);
    const [width, height, color] = pngInfo(sourcePng);
    if (width !== frameSize[0] * frames || height !== frameSize[1] * 8 || color !== 6) throw new Error(`${id}/${state}：PNG 宽高或 RGBA 类型错误`);
    if (checkOnly) {
      if (!fs.existsSync(outputPng) || !fs.readFileSync(sourcePng).equals(fs.readFileSync(outputPng))) throw new Error(`${id}/${state}：运行图与审核源稿不同`);
    } else {
      fs.mkdirSync(outputDir, { recursive: true });
      fs.copyFileSync(sourcePng, outputPng);
    }
    runtime.states[state] = { texture: `res://assets/sprites/monsters/${id}/${filename}`, frames, fps: def.fps, loop: def.loop, contact };
  }
  const outputMeta = path.join(outputDir, 'animations.json');
  const metadata = `${JSON.stringify(runtime, null, 2)}\n`;
  if (checkOnly) {
    if (!fs.existsSync(outputMeta) || fs.readFileSync(outputMeta, 'utf8') !== metadata) throw new Error(`${id}：运行元数据不同`);
  } else {
    fs.writeFileSync(outputMeta, metadata);
  }
  return runtime;
}

/** 根据清单生成格式稳定的 GDScript 路径索引；运行时按地图载入纹理。 */
function renderLibrary(packs) {
  let output = 'class_name MonsterAnimationLibrary\nextends RefCounted\n## 由 tools/build_monster_animation_assets.mjs 生成；只保存已审核图集的路径和帧元数据。\n## 纹理由 MonsterAnimationCache 按当前地图载入，不在脚本初始化时全局预载。\nconst PACKS := {\n';
  for (const pack of packs) {
    output += `\t${JSON.stringify(pack.id)}: {"pivot": ${JSON.stringify(pack.pivot)}, "frameSize": ${JSON.stringify(pack.frameSize)}, "states": {\n`;
    for (const [state, def] of Object.entries(pack.states)) {
      output += `\t\t${JSON.stringify(state)}: {"texture": ${JSON.stringify(def.texture)}, "frames": ${def.frames}, "fps": ${def.fps}, "loop": ${def.loop}, "contact": ${def.contact}},\n`;
    }
    output += '\t}},\n';
  }
  return `${output}}\n`;
}

/** 构建全部已审核包，或验证清单、源稿和已有运行资源完全一致。 */
function main() {
  const registry = readJson(path.join(root, 'data/monster_animation_packs.json'));
  if (!Array.isArray(registry) || new Set(registry.map(row => row.id)).size !== registry.length) throw new Error('动画包清单 ID 重复或格式错误');
  const packs = registry.map(buildPack);
  const libraryFile = path.join(root, 'scripts/entities/monster_animation_library.gd');
  const library = renderLibrary(packs);
  if (checkOnly) {
    if (fs.readFileSync(libraryFile, 'utf8') !== library) throw new Error('生成库与清单不一致');
  } else {
    fs.writeFileSync(libraryFile, library);
  }
  console.log(`正式动画包 ${packs.length} 个：${checkOnly ? '校验通过' : '构建完成'}`);
}

main();
