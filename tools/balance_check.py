#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""末法纪元 M1 数值校准分析（依据 03/04/06/07 文档公式 + data/*.json 实配）。"""
import json, math, os

ROOT = "/Users/fungleo/Sites/GameProjects/DegenerateAge"
def j(p):
    with open(os.path.join(ROOT, p), encoding="utf-8") as f:
        return json.load(f)

monsters = {m["id"]: m for m in j("data/monsters.json")}
equips   = {e["id"]: e for e in j("data/equipments.json")}
maps     = {m["id"]: m for m in j("data/maps.json")}
drops    = {d["id"]: d for d in j("data/dropTables.json")}
potions  = {p["id"]: p for p in j("data/potions.json")}
upgrade  = j("data/upgrade.json")

# ---- 玩家模型（4.3 / 4.4 / 3.2）----
BASE_HP, HP_LV, HP_ATK, HP_DEF = 50, 8, 2, 4
BASE_MP, MP_LV = 30, 5
ATK0, DEF0 = 12, 5
LV_ATK, LV_DEF = 2, 1
ATK_INTERVAL = 0.8
CRIT, CRIT_MULT = 0.05, 1.5

def player(L, atk=0, df=0, hp=0):
    atk_t = ATK0 + LV_ATK*(L-1) + atk
    df_t  = DEF0 + LV_DEF*(L-1) + df
    hp_t  = round(BASE_HP + HP_LV*L + HP_ATK*atk_t + HP_DEF*df_t + hp)
    mp    = round(BASE_MP + MP_LV*L)
    return dict(level=L, atk=atk_t, df=df_t, hp=hp_t, mp=mp)

def p_dmg(p, mon):
    return max(1, math.floor(p["atk"]*1.0 - mon["defense"]*0.5))
def m_dmg(mon, p):
    return max(1, math.floor(mon["attack"]*1.0 - p["df"]*0.5))
def ttk(p, mon, hp=None):
    hp = hp if hp is not None else mon["hpBase"]
    d = p_dmg(p, mon)
    return math.ceil(hp/d)*ATK_INTERVAL, math.ceil(hp/d), d

def monster_hp(mon, spawn_lv):
    return max(1, round(mon["hpBase"]*(1+0.12*(spawn_lv-mon["level"]))))

def xp_next(L): return round(100*(L**1.6))
def xp_cum(L):  return sum(xp_next(i) for i in range(1, L))

# ---- 装备场景 ----
BONUS = {"无装备": {"atk":0,"df":0,"hp":0},
         "Q001短刃": {"atk":5,"df":0,"hp":0},
         "Q003护甲套": {"atk":5,"df":4,"hp":15},
         "Q004狼王套": {"atk":23,"df":4,"hp":15}}

print("="*104)
print("【1】玩家属性成长（含装备）")
print("="*104)
print(f"{'Lv':>3} {'无装备 攻/防/HP':>22} {'Q003护甲套 攻/防/HP':>24} {'Q004狼王套 攻/防/HP':>24}")
for L in [1,2,3,4,5,6,8,10,15,20]:
    a = player(L, **BONUS["无装备"]); b = player(L, **BONUS["Q003护甲套"]); c = player(L, **BONUS["Q004狼王套"])
    f = lambda p: f"{p['atk']:>4}/{p['df']:>3}/{p['hp']:>5}"
    print(f"{L:>3} {f(a):>22} {f(b):>24} {f(c):>24}")

print()
print("="*104)
print("【2】怪物击杀耗时 TTK（玩家 = 推荐等级 / 各装备场景，纯普攻，含暴击期望；实战TTK 叠加怪物闪避）")
print("="*104)
MAP_LV = {"wild_trial": {2:["wolf_corrupted"], 3:["shellback_bug"], 4:["elite_wolf_king"]},
          "ash_land": {6:["ash_wraith"], 7:["shellback_bug"]},
          "corruption_source": {9:["shellback_bug"], 10:["boss_corrupted_beast"]}}
ORDER = ["wolf_corrupted","shellback_bug","ash_wraith","elite_wolf_king","boss_corrupted_beast"]
SPAWN = {"wolf_corrupted":2,"shellback_bug":3,"ash_wraith":6,"elite_wolf_king":4,"boss_corrupted_beast":10}
PLV   = {"wolf_corrupted":3,"shellback_bug":4,"ash_wraith":6,"elite_wolf_king":5,"boss_corrupted_beast":10}
for mid in ORDER:
    mon = monsters[mid]
    slv = SPAWN[mid]; hp = monster_hp(mon, slv); plv = PLV[mid]
    miss = mon["dodge"]/(mon["dodge"]+50.0)
    print(f"\n● {mon['name']}（{mid}）模板L{mon['level']}·刷L{slv}·HP{hp}·攻{mon['attack']}·防{mon['defense']}·闪{mon['dodge']}（Miss {100*miss:.1f}%）   ［按玩家 L{plv} 打］")
    print(f"  {'场景':<12}{'玩家攻':>6}{'单次伤害':>9}{'需击数':>7}{'纯TTK':>8}{'实战TTK':>9}{'被击伤害':>9}{'被击杀数':>9}")
    for name, b in BONUS.items():
        p = player(plv, **b)
        t, hits, d = ttk(p, mon, hp)
        eff = t / (1.0 - miss) if miss < 1.0 else t
        md = m_dmg(mon, p)
        ph = p["hp"]
        print(f"  {name:<12}{p['atk']:>6}{d:>9}{hits:>7}{t:>8.1f}{eff:>9.1f}{md:>9}{math.ceil(ph/md):>9}")

print()
print("闪避口径检查：missChance = dodge/(dodge+50)")
for mid in ORDER:
    d = monsters[mid]["dodge"]
    print(f"  {monsters[mid]['name']:<8} 配置 dodge={d:<5} → 实际 Miss = {100*d/(d+50):.2f}%   （按 3.5 示例「50→50%」，若想 10% 应配 5.56）")

print()
print("="*104)
print("【3】升级经验曲线（4.4：xp = round(100×L^1.6)）")
print("="*104)
print(f"{'Lv':>4}{'本级所需':>10}{'累计':>10}   试炼野外(6狼+2虫=210XP/轮)")
for L in [1,2,3,4,5,6,7,8,9,10,15,20]:
    n = xp_next(L); c = xp_cum(L)
    print(f"{L:>4}{n:>10}{c:>10}   {c/210:>6.1f} 轮 = {c/210*30/60:>5.1f} 分钟(respawn30s)")

print()
print("="*104)
print("【4】经济：单只怪期望收益 & 升星成本")
print("="*104)
def coin_of(table_id):
    for e in drops[table_id]["entries"]:
        if e["kind"] == "coin":
            lo, hi = e["goldRange"]; return (lo+hi)/2
    return 0
for mid in ORDER:
    mon = monsters[mid]
    tid = mon["dropTableId"]
    if tid:
        c = coin_of(tid); eq = next((e for e in drops[tid]["entries"] if e["kind"]=="equip"), None)
        eqc = eq["chance"] if eq else 0
        print(f"  {mon['name']:<8} 金币期望 ~{c:>6.0f}   装备掉率 {eqc*100:>4.0f}%   模板 goldReward(被表覆盖)={mon['goldReward']}")
    else:
        print(f"  {mon['name']:<8} 无掉落表 → 直接结算 goldReward={mon['goldReward']}")

print("\n  升星成本 upgradeCost(star)= 500×1.5^star，successRate：", upgrade["successRate"][:12])
tot = 0
for s in range(0, 12):
    c = round(500*(1.5**s)); tot += c
    print(f"    {s}→{s+1}: {c:>9,} 金（累计 {tot:>10,}）")

print("\n  装备售价举例（6.2：base×品质倍率×(1+星×0.08)）：")
QM = {"common":1.0,"uncommon":1.5,"rare":3.0,"epic":6.0,"legendary":12.0}
for eid in ["weapon_starter","armor_starter","weapon_wolfking","helmet_cloth"]:
    e = equips[eid]
    print(f"    {e['name']:<10} price={e['price']:<4} {e['quality']:<9} → 卖价 {round(e['price']*QM[e['quality']])}")

print()
print("="*104)
print("【5】药水效率")
print("="*104)
for L in [1,3,5,10]:
    hp0 = player(L, **BONUS["无装备"])["hp"]; hp4 = player(L, **BONUS["Q004狼王套"])["hp"]
    print(f"  L{L:<3} 无装HP={hp0:<5} 狼王套HP={hp4:<5}  小药80={80/hp0*100:>5.1f}%/{80/hp4*100:>5.1f}%  中药220={220/hp0*100:>5.1f}%/{220/hp4*100:>5.1f}%  大药500={500/hp0*100:>5.1f}%/{500/hp4*100:>5.1f}%")
