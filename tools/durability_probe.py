#!/usr/bin/env python3
"""耐久失效三态数值探针（工程 88 的分析工具，不进游戏运行时）。

对比「满耐久 / 现状破损（全清）/ 新方案破损（仅砍词条）」的攻击、防御、最大生命与挨打击数。

⚠ 与 `Balance` / `GameState` **同源但不是权威**：公式抄自
   `balance.gd`（base_attack / base_defense / scale）、`game_state.gd`（max_hp / max_mp）、
   `monster.gd::_min_hit_on_player`、`combat.gd::resolve`。
   改任何一个，必须同步本文件的 `scale` / `base_attack` / `base_defense` / `min_hit`，
   否则下次按错表算数值（与 `tools/balance_check.py` 同一条纪律）。

用法：python3 tools/durability_probe.py
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAVE_DIR = os.path.expanduser("~/Library/Application Support/Godot/app_userdata/末法纪元：最后的守护者/saves")

BASE_HP, HP_PER_LV, HP_PER_ATK, HP_PER_DEF = 50.0, 8.0, 2.0, 4.0
BASE_MP, MP_PER_LV = 30.0, 5.0
BASE_ATTACK_60, BASE_DEFENSE_60, SOFTCAP = 130, 64, 60

QUALITIES = ["common", "uncommon", "rare", "epic", "legendary"]


def scale(delta):
    d = max(0, delta)
    return 1.0 + 0.12 * d + 0.0022 * max(0, d - 12) ** 2


def base_attack(level):
    if level <= SOFTCAP:
        return 12 + (level - 1) * 2
    return int(round(BASE_ATTACK_60 * scale(level - SOFTCAP)))


def base_defense(level):
    if level <= SOFTCAP:
        return 5 + (level - 1)
    return int(round(BASE_DEFENSE_60 * scale(level - SOFTCAP)))


RULES = json.load(open(os.path.join(ROOT, "data/equipmentRules.json"), encoding="utf-8"))
SB = RULES["setBonus"]


def star_factor(it):
    return 1.0 + float(it.get("star", 0)) * float(it.get("starMultiplierSnapshot", 0.0))


def base_attrs(it):
    raw = it.get("rawBaseAttrs", {}) or {}
    f = float(it.get("qualityMultiplierSnapshot", 1.0)) * star_factor(it)
    return {k: float(v) * f for k, v in raw.items()}


def effective_attrs(it):
    r = dict(base_attrs(it))
    f = star_factor(it)
    for key in ("affixes", "pctAttrs"):
        for e in (it.get(key) or []):
            if isinstance(e, dict):
                r[e["stat"]] = r.get(e["stat"], 0.0) + float(e["value"]) * f
    return r


KEYS = ["atk", "def", "hp", "mp", "hpPercent", "mpPercent", "criticalChance",
        "criticalMultiplier", "dodge", "block", "cdr", "movementSpeed"]


def sum_bonus(slots, mode):
    b = {k: 0.0 for k in KEYS}
    for it in slots.values():
        if not isinstance(it, dict):
            continue
        src = {} if mode == "none" else (base_attrs(it) if mode == "base" else effective_attrs(it))
        for k, v in src.items():
            if k in b:
                b[k] += float(v)
    return b


def set_bonus_pct(slots):
    worn, min_rank, min_star = 0, len(QUALITIES), 0
    for it in slots.values():
        if not isinstance(it, dict):
            continue
        worn += 1
        q = it.get("quality", "common")
        min_rank = min(min_rank, QUALITIES.index(q) if q in QUALITIES else 0)
        min_star = int(it.get("star", 0)) if worn == 1 else min(min_star, int(it.get("star", 0)))
    if worn < int(SB.get("requiredSlots", 14)):
        return 0.0, "common", 0
    qpct = float(SB["quality"].get(QUALITIES[min_rank], 0.0))
    spct = 0.0
    step = 0
    for k, v in SB["star"].items():
        if min_star >= int(k):
            step, spct = int(k), float(v)
    return qpct + spct, QUALITIES[min_rank], step


def derive(player, slots, mode):
    pct, q, star = set_bonus_pct(slots)
    b = sum_bonus(slots, mode)
    b_atk = int(base_attack(player["level"])) if mode == "none" and False else None
    atk_base = int(player["attack"]) + int(round(b["atk"]))
    def_base = int(player["defense"]) + int(round(b["def"]))
    total_atk = int(round(atk_base * (1 + pct)))
    total_def = int(round(def_base * (1 + pct)))
    hp_base = BASE_HP + player["level"] * HP_PER_LV + atk_base * HP_PER_ATK + def_base * HP_PER_DEF
    hp_pct = float(player.get("hpPercent", 0.0)) + b["hpPercent"]
    hp_flat = float(player.get("hpFlat", 0.0)) + b["hp"]
    max_hp = int(round((1 + pct) * (hp_base * (1 + hp_pct) + hp_flat)))
    mp_base = BASE_MP + player["level"] * MP_PER_LV
    mp_pct = float(player.get("mpPercent", 0.0)) + b["mpPercent"]
    mp_flat = float(player.get("mpFlat", 0.0)) + b["mp"]
    max_mp = int(round((1 + pct) * (mp_base * (1 + mp_pct) + mp_flat)))
    return {"atk": total_atk, "def": total_def, "hp": max_hp, "mp": max_mp,
            "setpct": pct, "quality": q, "star": star, "bonus": b}


def min_hit(max_hp):
    return max(10, min(60, int(round(max_hp * 0.0025))))


def hits_to_die(max_hp, atk_eff, defense, level_gap=1.0, coeff=1.0):
    raw = atk_eff * coeff * level_gap - defense * 0.5
    dmg = raw if raw > 0 else max(1, min_hit(max_hp))
    return dmg, max_hp / dmg if dmg > 0 else float("inf")


def tier_sweep(save_slot="slot_3"):
    """按「品质 × 星级」扫一遍破损态可挨打击数（工程 88 §4.4 的复算入口）。

    装备本体的 norm 值从给定存档的 14 件 `rawBaseAttrs` 反推（除以 S），
    再按目标档位重乘 `品质 × (1 + 星级 × starMult) × S`。
    词条按实测比例折算（`AFFIX_FIX` 固定词条 / 本体、`AFFIX_PCT` 百分比词条合计）。
    """
    path = os.path.join(SAVE_DIR, save_slot + ".json")
    d = json.load(open(path, encoding="utf-8"))
    p = d["player"]
    lv = int(p["level"])
    sc = scale(lv - SOFTCAP)
    norm = {k: 0.0 for k in KEYS}
    for it in d.get("equipment", {}).values():
        if isinstance(it, dict):
            for k, v in (it.get("rawBaseAttrs") or {}).items():
                if k in norm:
                    norm[k] += float(v) / sc

    rules = json.load(open(os.path.join(ROOT, "data/equipmentRules.json"), encoding="utf-8"))
    q_mult = {q: float(cfg.get("baseMultiplier", 1.0)) for q, cfg in rules["qualities"].items()}
    star_mult = float(rules.get("starMult", 0.1))
    sb = rules["setBonus"]
    monsters = json.load(open(os.path.join(ROOT, "data/endgame.json"), encoding="utf-8"))["goldFieldNormals"]
    atk_norms = [float(m["norm"]["atk"]) for m in monsters]
    worst, avg = max(atk_norms), sum(atk_norms) / len(atk_norms)

    from_game = d["player"]
    pa = int(from_game["attack"])
    pd = int(from_game["defense"])
    affix_fix = 0.62   # 固定词条 / 本体（实测 def 3,760 / 6,077）
    affix_pct = 0.273  # hpPercent 词条合计（实测 27.3%）

    def state(q, star, mode):
        f = q_mult[q] * (1.0 + star * star_mult)
        pct = float(sb["quality"].get(q, 0.0)) + float(sb["star"].get(str(star), 0.0))
        ba, bd, bh = norm["atk"] * f * sc, norm["def"] * f * sc, norm["hp"] * f * sc
        if mode == "full":
            ab, db, hb, hp_p = pa + ba * (1 + affix_fix), pd + bd * (1 + affix_fix), bh * (1 + affix_fix), affix_pct
        elif mode == "base":
            ab, db, hb, hp_p = pa + ba, pd + bd, bh, 0.0
        else:
            ab, db, hb, hp_p = pa, pd, 0.0, 0.0
        hp = (1 + pct) * ((BASE_HP + lv * HP_PER_LV + ab * HP_PER_ATK + db * HP_PER_DEF) * (1 + hp_p) + hb)
        dfn = db * (1 + pct)

        def dmg(a):
            raw = a - dfn * 0.5
            return raw if raw > 0 else min_hit(hp)
        return hp, dfn, dmg(worst * sc), dmg(avg * sc)

    print("=" * 78)
    print(f"档位扫描（{save_slot} 玩家 L{lv}，基础攻防 {pa}/{pd}，金脉怪 最凶 {worst*sc:.0f} / 均值 {avg*sc:.0f}）")
    print(f"{'配装档位':<14}{'破损血池':>10}{'破损防御':>10}{'均值伤害':>10}{'可挨打':>12}{'最凶伤害':>10}{'现状可挨打':>12}")
    print("-" * 78)
    for q in ("common", "rare", "epic", "legendary"):
        for star in (0, 6, 12):
            hn, dn, dw, dm = state(q, star, "base")
            ho, _, _, om = state(q, star, "none")
            print(f"{q + '/' + str(star) + '★':<14}{hn:>10.0f}{dn:>10.0f}{dm:>10.0f}"
                  f"{hn / dm:>10.1f} 击{dw:>10.0f}{ho / om:>10.1f} 击")
    print("-" * 78)
    print("（伤害标 60 = 已进入不破防保底区；现状可挨打指耐久全清后的击数）")


def main():
    monsters = json.load(open(os.path.join(ROOT, "data/endgame.json"), encoding="utf-8"))["goldFieldNormals"]
    norms = [(m["monsterId"], float(m["norm"]["atk"])) for m in monsters]
    avg_norm = sum(a for _, a in norms) / len(norms)

    for slot in ("slot_3", "slot_2"):
        path = os.path.join(SAVE_DIR, slot + ".json")
        d = json.load(open(path, encoding="utf-8"))
        p = d["player"]
        slots = d.get("equipment", {})
        lv = int(p["level"])
        sc = scale(lv - SOFTCAP)
        print("=" * 78)
        print(f"{slot}  玩家 L{lv}  穿着 {sum(1 for v in slots.values() if isinstance(v, dict))} 件"
              f"  S({lv - SOFTCAP})={sc:.4f}")
        print(f"  player.attack={p['attack']} player.defense={p['defense']} "
              f"hpPercent={p.get('hpPercent', 0)} hpFlat={p.get('hpFlat', 0)}")
        states = {}
        for mode, label in (("full", "满耐久"), ("base", "新方案·仅砍词条"), ("none", "现状·全清")):
            st = derive(p, slots, mode)
            states[mode] = st
            b = st["bonus"]
            print(f"  {label:12s} atk={st['atk']:>7} def={st['def']:>7} hp={st['hp']:>8} "
                  f"mp={st['mp']:>6} 套装={st['setpct']*100:.0f}% ({st['quality']}/{st['star']}★)")
            print(f"  {'':12s} 装备合计 atk={b['atk']:.0f} def={b['def']:.0f} hp={b['hp']:.0f} "
                  f"hpPct={b['hpPercent']*100:.1f}%")
        print(f"  相对满耐久：新方案 atk {states['base']['atk']/states['full']['atk']*100:.0f}% "
              f"def {states['base']['def']/states['full']['def']*100:.0f}% "
              f"hp {states['base']['hp']/states['full']['hp']*100:.0f}%")
        print(f"              现状全清 atk {states['none']['atk']/states['full']['atk']*100:.0f}% "
              f"def {states['none']['def']/states['full']['def']*100:.0f}% "
              f"hp {states['none']['hp']/states['full']['hp']*100:.0f}%")

        atk_eff = avg_norm * sc
        print(f"  金脉普通怪 avg norm atk={avg_norm:.0f} ⇒ 实际 {atk_eff:.0f}"
              f"（单只范围 {min(a for _, a in norms)*sc:.0f}—{max(a for _, a in norms)*sc:.0f}）")
        for mode, label in (("full", "满耐久"), ("base", "新方案"), ("none", "现状全清")):
            st = states[mode]
            dmg, hits = hits_to_die(st["hp"], atk_eff, st["def"])
            print(f"    {label:8s} 单次挨打 {dmg:>6.0f}  可挨打 {hits:>6.2f} 击  "
                  f"（每 1.5s 一击 ⇒ 站桩 {hits*1.5:>6.1f}s）")
    print("=" * 78)
    tier_sweep("slot_3")
    return 0


if __name__ == "__main__":
    sys.exit(main())
