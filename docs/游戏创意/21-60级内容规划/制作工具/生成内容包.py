#!/usr/bin/env python3
"""从内容定义生成21—60级产品文档、坐标JSON和SVG参考；仅覆盖本内容包的衍生产物。
运行：python3 docs/游戏创意/21-60级内容规划/制作工具/生成内容包.py。
依赖Python标准库；不加载Godot、不写运行配置或玩家存档。手写总表/决策/交接不覆盖。
"""
import json, math, random, hashlib, html
from collections import deque, Counter
from pathlib import Path
from 内容定义 import ROOT, VERSION, SLOTS, SLOT_NAMES, CHAPTERS, MAIN, SIDE, rows
FOLDERS={3:'第三章',4:'第四章',5:'第五章',6:'第六章'}
BASE=[{'atk':17},{'def':4,'mp':10},{'def':9,'hp':25},{'def':5},{'def':4},{'def':4},{'def':10,'hp':15},{'atk':4},{'atk':3,'mp':8},{'hp':25}]
FACTORS={3:1.5,4:2.25,5:3.2,6:4.4}
AFFIX={3:3,4:4.5,5:6,6:8}
VALUE={3:3,4:4.5,5:6,6:8}
PRICE=[50,50,80,60,60,60,80,60,60,70]
MULT=[1,1,1,1,2,2,1,2,2,1]
LABEL={'kill':'击杀','collect':'收集','talk':'交谈','boss':'击败首领'}
BASELINE={}


def rnd(value):
    """采用正数四舍五入，与文档中金币和经验的整数口径保持一致。"""
    return int(math.floor(value+0.5))


def xp(level):
    """返回当前正式经验曲线中从level升至下一级所需经验，不修改曲线。"""
    return rnd(100*level**1.6)


def table(headers, data):
    """生成Markdown表格；单元格换行转为HTML换行，不产生额外列。"""
    clean=lambda x:str(x).replace('|','／').replace('\n','<br>')
    return '| '+' | '.join(headers)+' |\n|'+'|'.join(['---']*len(headers))+'|\n'+''.join('| '+' | '.join(map(clean,r))+' |\n' for r in data)+'\n'


def write(path, text):
    """写入本目录内的衍生文档，使用UTF-8并保留终止换行。"""
    p=ROOT/path; p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text.rstrip()+'\n')


def header(title):
    """标注衍生文档的版本、来源与产品候选性质，防止被误认为正式实现。"""
    return f'# {title}\n\n2026-10-15，{VERSION}。产品执行稿；数值为待实机校准候选，尚未接入游戏。本文由`制作工具/内容定义.py`与生成器导出，修改事实源后重建，勿只改衍生表。\n\n'


def stats(level, kind='normal', role='近战'):
    """依据等级和战斗职责生成首轮固定敌方数值；不是动态按玩家变强的公式。"""
    h=20*level+150; a=4*level+60; d=1.4*level+10
    if '远程' in role: h*=.8;a*=.9
    if '高防' in role or '盾卫' in role: h*=1.15;d*=1.35
    if '重型' in role: h*=1.4;a*=1.1
    if kind=='elite': h*=4;a*=1.15;d*=1.15
    if kind=='boss': h*=18;a*=1.4;d*=1.5
    return {'hp':rnd(h),'atk':rnd(a),'def':rnd(d),'interval':1.5 if kind=='normal' else 1.8,'xp':max(1,rnd(xp(level)*{'normal':.01,'elite':.03,'boss':.18}[kind]))}


def nearest_free(point, walk):
    """将设计点移动到最近可走格，只用于参考布局，不能替代真实碰撞验证。"""
    x,y=point
    return min(walk,key=lambda p:(p[0]-x)**2+(p[1]-y)**2)


def inside(x,y,poly):
    """用射线法判定格中心是否位于障碍多边形内，支持不规则岛状障碍。"""
    hit=False;j=len(poly)-1
    for i,(xi,yi) in enumerate(poly):
        xj,yj=poly[j]
        if (yi>y)!=(yj>y) and x < (xj-xi)*(y-yi)/(yj-yi)+xi:hit=not hit
        j=i
    return hit


def route(start, end, walk):
    """构建设计参考四邻接路线；失败即阻止交付，不进行真实角色物理测试。"""
    q=deque([start]);prev={start:None}
    while q:
        p=q.popleft()
        if p==end:break
        for dx,dy in [(1,0),(0,1),(-1,0),(0,-1)]:
            n=(p[0]+dx,p[1]+dy)
            if n in walk and n not in prev:prev[n]=p;q.append(n)
    if end not in prev: raise ValueError(f'布局点不连通 {start} {end}')
    result=[];p=end
    while p is not None:result.append(p);p=prev[p]
    return result[::-1]


def geometry(m, seed):
    """生成横向布局、格级障碍和可走集合；每图变化地形轮廓，保持宽回路和东侧首领场。"""
    w,h=m['w'],m['h'];polys=[]
    forms={
    '市集':[(.24,.23,.16,.17),(.47,.18,.17,.15),(.69,.27,.13,.19),(.29,.78,.16,.16),(.58,.79,.18,.16)],
    '河渠':[(.25,.18,.13,.34),(.34,.56,.21,.17),(.52,.78,.15,.32),(.64,.32,.20,.16)],
    '高架':[(.24,.46,.12,.26),(.42,.28,.10,.24),(.56,.65,.12,.26),(.71,.39,.10,.22)],
    '工坊':[(.24,.27,.17,.27),(.32,.70,.17,.25),(.49,.46,.14,.32),(.65,.25,.19,.23),(.67,.77,.16,.22)],
    '庭院':[(.32,.40,.23,.30),(.56,.68,.23,.26),(.69,.22,.13,.16)],
    '官署':[(.24,.18,.19,.22),(.25,.76,.19,.24),(.44,.44,.20,.35),(.65,.24,.15,.20),(.64,.75,.18,.20)],
    '驿站':[(.23,.22,.13,.20),(.48,.16,.16,.16),(.72,.24,.15,.18),(.34,.79,.18,.14),(.65,.80,.15,.14)],
    '根路':[(.23,.36,.12,.40),(.40,.64,.15,.39),(.57,.31,.12,.40),(.70,.69,.10,.30)],
    '哨林':[(.26,.40,.18,.23),(.48,.70,.18,.23),(.66,.28,.18,.23)],
    '观测':[(.25,.24,.20,.15),(.27,.69,.20,.16),(.43,.46,.12,.26),(.58,.26,.18,.17),(.66,.67,.20,.18)],
    '菌圃':[(.25,.30,.13,.18),(.25,.74,.13,.18),(.43,.49,.14,.20),(.60,.24,.14,.18),(.62,.72,.17,.19)],
    '观测台':[(.27,.49,.22,.40),(.51,.23,.16,.24),(.63,.68,.19,.28)],
    '关隘':[(.23,.21,.18,.19),(.53,.17,.16,.17),(.73,.25,.12,.17),(.27,.79,.18,.16),(.61,.78,.20,.15)],
    '长堤':[(.22,.19,.11,.34),(.36,.58,.23,.16),(.52,.82,.12,.32),(.66,.35,.23,.16)],
    '号台':[(.24,.28,.18,.22),(.44,.61,.19,.25),(.65,.34,.19,.23)],
    '营地':[(.23,.25,.14,.18),(.27,.74,.14,.18),(.43,.43,.14,.18),(.53,.77,.14,.17),(.63,.22,.14,.17),(.71,.56,.11,.20)],
    '舟坞':[(.24,.37,.07,.40),(.34,.32,.07,.43),(.46,.66,.08,.37),(.58,.70,.08,.34),(.68,.33,.09,.33)],
    '城门':[(.31,.15,.20,.36),(.31,.76,.20,.38),(.57,.29,.16,.32),(.61,.80,.16,.28)],
    '桥头':[(.29,.22,.22,.30),(.47,.73,.24,.29),(.66,.30,.13,.36)],
    '前哨':[(.23,.20,.16,.15),(.48,.17,.20,.16),(.73,.23,.13,.19),(.33,.78,.15,.16),(.59,.80,.16,.16)],
    '外廊':[(.23,.58,.12,.42),(.41,.25,.17,.26),(.55,.72,.17,.27),(.70,.37,.10,.33)],
    '兵库':[(.24,.27,.14,.34),(.42,.65,.14,.34),(.62,.32,.14,.34)],
    '环室':[(.24,.23,.17,.14),(.26,.69,.18,.15),(.41,.45,.11,.26),(.55,.22,.18,.14),(.64,.66,.19,.18),(.70,.37,.08,.15)],
    '纪念':[(.24,.27,.12,.22),(.34,.73,.12,.24),(.48,.42,.12,.26),(.66,.72,.12,.24)],
    '核心':[(.25,.33,.16,.25),(.30,.71,.16,.21),(.48,.20,.18,.16),(.54,.69,.16,.19),(.67,.40,.12,.27)]}
    centers=forms[m['style']]
    for i,(cx,cy,rx,ry) in enumerate(centers):
        tilt=((seed+i)%3-1)*.025
        norm=[(cx-rx/2,cy-ry/2),(cx+rx*.2,cy-ry*.6),(cx+rx*.55,cy-ry*.15+tilt),(cx+rx*.4,cy+ry*.45),(cx-rx*.2,cy+ry*.55),(cx-rx*.6,cy+ry*.1)]
        polys.append([[min(w-1,max(0,rnd(x*w))),min(h-1,max(0,rnd(y*h)))] for x,y in norm])
    walk={(x,y) for x in range(2,w-2) for y in range(2,h-2) if not any(inside(x+.5,y+.5,p) for p in polys)}
    # 留一格保守余量；结构化文件输出实际多边形和用于核查的间隙口径。
    safe={p for p in walk if all((p[0]+dx,p[1]+dy) in walk for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)])}
    m['obstacles']=polys;m['clearanceCells']=1
    return safe


def prepare():
    """建立稳定ID、任务引用、奖励、地图连接和坐标；仅生成设计层对象。"""
    repo=ROOT.parents[2]
    for path in ['data/equipmentRules.json','data/equipments.json','data/dropTables.json','data/quests.json','scripts/systems/hotbar_config.gd']:
        p=repo/path
        BASELINE[path]=hashlib.sha256(p.read_bytes()).hexdigest()
    for c in CHAPTERS:
        n=c['n'];s=(n-1)*10+1;c.update(start=s,end=s+9,folder=FOLDERS[n])
        c['maps']=[dict(id=f'c{n}_map{i:02}',name=r[0],w=int(r[1]),h=int(r[2]),level=int(r[3]),description=r[4],style=r[5],index=i,exits=[],npcs=[],normalSlots=0 if i==0 else [0,64,72,96,64,72,72][i],elites=[],bosses=[]) for i,r in enumerate(c['maps'])]
        c['npcs']=[dict(id=f'c{n}_npc{i+1:02}',name=r[0],role=r[1],motive=r[2],before=r[3],after=r[4],look=r[5],index=i,map=c['maps'][0 if i<8 else 1 if i==8 else 4 if i==9 else 5]['id']) for i,r in enumerate(c['npcs'])]
        c['normal']=[dict(id=f'c{n}_normal{i+1:02}',name=r[0],role=r[1],look=r[2],behavior=r[3],level=min(s+8,s+i),kind='normal',**stats(min(s+8,s+i),'normal',r[1])) for i,r in enumerate(c['normal'])]
        c['elites']=[dict(id=f'c{n}_elite{i+1:02}',name=r[0],look=r[1],behavior=r[2],atktype=r[3],level=s+3+i,kind='elite',**stats(s+3+i,'elite')) for i,r in enumerate(c['elites'])]
        c['bosses']=[dict(id=f'c{n}_boss{i+1:02}',name=r[0],level=int(r[1]),main=r[2]=='主线',look=r[3],behavior=r[4],meaning=r[5],kind='boss',**stats(int(r[1]),'boss')) for i,r in enumerate(c['bosses'])]
        for i,b in enumerate(c['bosses']):
            mi=2 if i==0 else 4 if i==1 else 5 if i==2 else 6
            b['map']=c['maps'][mi]['id'];c['maps'][mi]['bosses'].append(b['id'])
        c['gear']=[dict(id=f'c{n}_equip_{slot}',name=c['gear'][i],slot=slot,level=s+i,tier=s,raw={k:rnd(v*FACTORS[n]) for k,v in BASE[i].items()},price=PRICE[i],valueMultiplier=VALUE[n]) for i,slot in enumerate(SLOTS)]
        budget=sum(xp(l) for l in range(s-1,s+9));c['xpBudget']=budget
        c['tasks']=[]
        for side,text in [(False,MAIN[n]),(True,SIDE[n])]:
            parsed=rows(text);weights=[.6 if r[3]=='talk' else 1.4 if r[3]=='boss' else 1.1 if r[3]=='collect' else 1 for r in parsed]
            total=rnd(budget*(.10 if side else .35));alloc=[rnd(total*w/sum(weights)) for w in weights];alloc[-1]+=total-sum(alloc)
            gold_total=([0,0,0,3000,4000,5000,6000] if side else [0,0,0,8000,12000,16000,20000])[n]
            gold_alloc=[rnd(gold_total*w/sum(weights)) for w in weights];gold_alloc[-1]+=gold_total-sum(gold_alloc)
            for i,r in enumerate(parsed):
                name,l,ni,kind,ti,mi,count,brief,done=r; ni,ti,mi,count=int(ni),int(ti),int(mi),int(count)
                qid=f'C{n}{"S" if side else "Q"}{i+1:02}'
                prev=(f'C{n}S04' if i==4 else f'C{n}Q{(5 if i==1 else 3 if i==2 else 6 if i==3 else 9 if n==5 and i==5 else len(rows(MAIN[n])) if i>=5 else 1):02}') if side else (f'C{n}Q{i:02}' if i else 'C2Q12' if n==3 else f'C{n-1}Q{len(rows(MAIN[n-1])):02}')
                target=c['npcs'][ti]['id'] if kind=='talk' else c['bosses'][ti]['id'] if kind=='boss' else c['normal'][ti]['id']
                q=dict(id=qid,name=name,level=int(l),giver=c['npcs'][ni]['id'],turnIn=c['npcs'][ni]['id'],kind=kind,target=target,map=c['maps'][mi]['id'],count=count,prev=prev,side=side,accept=brief,complete=done,xp=alloc[i],gold=gold_alloc[i],unlock=[],gear=None)
                if kind=='collect':q.update(source=target,item=f'c{n}_item_{"s" if side else "q"}{i+1:02}',itemName=name+'·线索',target=f'c{n}_item_{"s" if side else "q"}{i+1:02}')
                if not side and i+1 in [3,6,8,len(parsed)]:
                    slot_idx={3:2,6:4,8:6,len(parsed):0}[i+1];q['gear']={'id':c['gear'][slot_idx]['id'],'quality':'epic' if i+1==len(parsed) else 'rare','star':0}
                if side and i==4:q['gear']={'id':c['gear'][8]['id'],'quality':'epic','star':0}
                c['tasks'].append(q)
        # 沿途证人承接清路交付，关键证据才返镇解析，减少同图反复往返。
        for q in c['tasks']:
            if q['side'] or q['kind']=='talk':continue
            qi=int(q['id'][-2:])
            if qi==2:q['turnIn']=c['npcs'][8]['id']
            if qi in [4,5]:q['giver']=c['npcs'][8]['id']
            if qi==4:q['turnIn']=c['npcs'][8]['id']
            if qi==8:q['turnIn']=c['npcs'][9]['id']
            if qi==10:q['giver']=c['npcs'][9]['id']
            if n==5 and qi==10:q['turnIn']=c['npcs'][10]['id']
            if n==5 and qi==12:q['giver']=c['npcs'][10]['id']
        edges=[(0,1,''),(1,2,f'C{n}Q03'),(2,3,f'C{n}Q05'),(3,4,f'C{n}Q06'),(3,5,f'C{n}Q09')]
        if n==5:edges.append((5,6,f'C{n}Q11'))
        for a,b,qid in edges:
            flag=f'c{n}_access_{b:02}' if qid else ''
            if qid:next(q for q in c['tasks'] if q['id']==qid)['unlock'].append(flag)
            c['maps'][a]['exits'].append(dict(to=c['maps'][b]['id'],flag=flag));c['maps'][b]['exits'].append(dict(to=c['maps'][a]['id'],flag=''))
        last=next(q for q in c['tasks'] if q['id']==f'C{n}Q{len(rows(MAIN[n])):02}')
        last['unlock'].append('campaign_complete' if n==6 else f'chapter{n+1}')
        prev_hub='c2_well_town' if n==3 else f'c{n-1}_map00'
        c['maps'][0]['exits'].insert(0,dict(to=prev_hub,flag=''))
        if n<6:c['maps'][0]['exits'].append(dict(to=f'c{n+1}_map00',flag=f'chapter{n+1}'))
        # 主线后期野外对话需先出现在可达位置；NPC发起自己的talk，不伪造跨人对话。
        for m in c['maps']:
            walk=geometry(m,n*20+m['index']);m['_walk']=walk
            positions=[(.04,.50),(.96,.50),(.53,.05),(.53,.95)]
            for j,e in enumerate(m['exits']):
                e['cell']=list(nearest_free((rnd(positions[j][0]*m['w']),rnd(positions[j][1]*m['h'])),walk));e['id']=f'{m["id"]}_exit{j+1:02}'
            for p in c['npcs']:
                if p['map']!=m['id']:continue
                i=p['index'];x=.34+(i%4)*.10 if i<8 else .12;y=.40 if i<4 else .64 if i<8 else .50
                p['cell']=list(nearest_free((rnd(m['w']*x),rnd(m['h']*y)),walk));m['npcs'].append(p['id'])
            for bid in m['bosses']:
                b=next(b for b in c['bosses'] if b['id']==bid);b['cell']=list(nearest_free((rnd(m['w']*.86),rnd(m['h']*.50)),walk));b['radius']=12
            m['eliteSlots']=0 if m['index']==0 else 2
            if m['index']>0:
                for j in range(2):
                    e=c['elites'][(m['index']-1+j)%len(c['elites'])]
                    pos=nearest_free((rnd(m['w']*(.34+.23*j)),rnd(m['h']*(.30 if j==0 else .73))),walk)
                    m['elites'].append(dict(template=e['id'],cell=list(pos),respawn=90))
            protect=[tuple(e['cell']) for e in m['exits']]+[tuple(p['cell']) for p in c['npcs'] if p['map']==m['id']]
            bosscells=[tuple(b['cell']) for b in c['bosses'] if b['map']==m['id']]
            elitecells=[tuple(e['cell']) for e in m['elites']]
            candidates=[p for p in walk if p[0]%4==0 and p[1]%4==0 and .16*m['w']<p[0]<.78*m['w'] and all((p[0]-x)**2+(p[1]-y)**2>=12**2 for x,y in protect) and all((p[0]-x)**2+(p[1]-y)**2>=18**2 for x,y in bosscells) and all((p[0]-x)**2+(p[1]-y)**2>=6**2 for x,y in elitecells)]
            random.Random(n*100+m['index']).shuffle(candidates)
            roster=[c['normal'][(2*(m['index']-1)+j)%len(c['normal'])]['id'] for j in range(4)] if m['index'] else []
            for q in c['tasks']:
                if q['map']==m['id'] and q['kind'] in ['kill','collect']:
                    v=q.get('source',q['target'])
                    if v not in roster:roster.append(v)
            m['normalRoster']=roster
            if len(candidates)<m['normalSlots']:raise ValueError('刷新候选不足 '+m['id'])
            m['spawns']=[dict(template=roster[j%len(roster)],cell=list(p),zone=min(4,int(p[0]/m['w']*4)+1),respawn=18) for j,p in enumerate(candidates[:m['normalSlots']])]
            anchor=tuple(m['exits'][0]['cell']);targets=[tuple(e['cell']) for e in m['exits'][1:]]+[tuple(p['cell']) for p in c['npcs'] if p['map']==m['id']]+[tuple(b['cell']) for b in c['bosses'] if b['map']==m['id']]
            names={
                '市集':['配水石槽','公开水亭','下街车站'],'河渠':['倒伏水车','陶汀水尺','断流分水口'],
                '高架':['检修支墩','配水印台','东闸台'],'工坊':['封存警报柜','旧工牌棚','断管接口'],
                '庭院':['证人亭','半埋库房','南院巢口'],'官署':['档案回廊','失效官印','空渠边栏'],
                '驿站':['老信树','回执台','驿车站'],'根路':['旧路桩','退信包棚','倒根缺口'],
                '哨林':['西哨塔','失声哨塔','护林牌'],'观测':['西测量环','破镜棚','外环退路'],
                '菌圃':['信匣台','药菌床','育巢隔栏'],'观测台':['峰值表室','分流图台','旧守门碑'],
                '关隘':['撤离集合点','到达册台','物资车站'],'长堤':['弃械架','旧路税牌','顾烽信棚'],
                '号台':['断号架','原军报匣','前哨信旗'],'营地':['担架棚','营道标牌','后卫帐'],
                '舟坞':['证人棚','舟骨泊位','遗民路标'],'城门':['交接门哨','旧值守牌','破城垛'],
                '桥头':['西石桥','相位测尺','东石桥'],'前哨':['停止条件牌','协作记录台','回程车站'],
                '外廊':['倒伏镇脉柱','检修路标','旁路出口'],'兵库':['原誓条碑','废止资格表','守誓试验台'],
                '环室':['西分流段','中心校核点','东旁路段'],'纪念':['前代姓名墙','证人台','训练场外栏'],
                '核心':['外环检修点','核心观测窗','东撤离路标']}[m['style']]
            m['landmarks']=[{'name':name,'cell':list(nearest_free((rnd(m['w']*x),rnd(m['h']*y)),walk))} for name,(x,y) in zip(names,[(.22,.59),(.49,.57),(.73,.71)])]
            targets += [tuple(p['cell']) for p in m['landmarks']]
            m['routes']=[route(anchor,t,walk) for t in targets]
            # 所有候选刷新位也须属于入口所在连通域，不能只校核主路。
            reachable=set(route(anchor,anchor,walk));todo=deque([anchor])
            while todo:
                x,y=todo.popleft()
                for p in [(x+1,y),(x-1,y),(x,y+1),(x,y-1)]:
                    if p in walk and p not in reachable:reachable.add(p);todo.append(p)
            for p in m['spawns']+m['elites']:
                if tuple(p['cell']) not in reachable:raise ValueError('刷新位不可达')
            m['reachableCount']=len(reachable)
    # 双向出口的到达点只在所有图确定后绑定。
    maps={m['id']:m for c in CHAPTERS for m in c['maps']}
    for m in maps.values():
        for e in m['exits']:
            if e['to'] in maps:
                reverse=next(x for x in maps[e['to']]['exits'] if x['to']==m['id']);e['arrival']=reverse['cell']
            else:e['arrival']=[80,27];e['externalPatch']='沉井镇新增至c3_map00的双向出口与hubLinks；返回落点80,27需对照最新布局验证'
    return maps


def svg(m,c,annotated):
    """输出正交16:9平面示意，纯布局仅保留绿地/黑障碍/红出口；标注版另画职责点与路线。"""
    w,h=m['w'],m['h'];scale=1440/w; ox,oy=80,90
    xy=lambda p:(ox+p[0]*scale,oy+p[1]*scale)
    out=['<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1020" viewBox="0 0 1600 1020">','<rect width="1600" height="1020" fill="white"/>',f'<g font-family="PingFang SC,Noto Sans CJK SC,sans-serif"><text x="80" y="38" font-size="24">{html.escape(m["name"])} · {w}×{h} · 正交布局</text>',f'<text x="80" y="66" font-size="15">{VERSION} / 黑色不可走 · 绿色可走 · 红色出口；不是最终贴图</text>',f'<rect x="{ox}" y="{oy}" width="1440" height="810" fill="#65ae76"/>']
    for p in m['obstacles']:
        out.append('<polygon points="'+' '.join(f'{x:.1f},{y:.1f}' for x,y in map(xy,p))+'" fill="#15191a"/>')
    if annotated:
        for r in m['routes']:
            # 折线抽稀只改变示意绘制，不改变JSON中的逐格导航参考。
            simple=[p for i,p in enumerate(r) if i==0 or i==len(r)-1 or (p[0]-r[i-1][0],p[1]-r[i-1][1]) != (r[i+1][0]-p[0],r[i+1][1]-p[1])]
            out.append('<polyline points="'+' '.join(f'{x:.1f},{y:.1f}' for x,y in map(xy,simple))+'" fill="none" stroke="#e7f0a2" stroke-width="3" opacity=".7"/>')
        for i,p in enumerate(m['landmarks']):
            x,y=xy(p['cell']);out.append(f'<text x="{x}" y="{y}" font-size="13" fill="#4b3417">L{i+1}</text>')
        for p in m['spawns']:
            x,y=xy(p['cell']);out.append(f'<circle cx="{x}" cy="{y}" r="3" fill="#20516e"/>')
        for i,p in enumerate(m['elites']):
            x,y=xy(p['cell']);out.append(f'<circle cx="{x}" cy="{y}" r="8" fill="#e8ba33"/><text x="{x+9}" y="{y-10}" font-size="14">E{i+1}</text>')
        for p in c['npcs']:
            if p['map']==m['id']:
                x,y=xy(p['cell']);out.append(f'<rect x="{x-5}" y="{y-5}" width="10" height="10" fill="#fff" stroke="#304255"/><text x="{x-8}" y="{y-14}" font-size="13">N{p["index"]+1}</text>')
        for b in c['bosses']:
            if b['map']==m['id']:
                x,y=xy(b['cell']);out.append(f'<circle cx="{x}" cy="{y}" r="{b["radius"]*scale}" fill="none" stroke="#a52570" stroke-width="3"/><text x="{x-40}" y="{y}" font-size="20" fill="#532340">B{b["id"][-2:]}</text>')
    for i,e in enumerate(m['exits']):
        x,y=xy(e['cell']);out.append(f'<circle cx="{x}" cy="{y}" r="9" fill="#df303b"/>')
        if annotated:out.append(f'<text x="{max(ox,x-14)}" y="{y-18}" font-size="15">P{i+1}</text>')
    out.append('<text x="80" y="936" font-size="16">P=出口　N=NPC序号　L=地标　E=精英点　B=首领场　蓝点=普通刷新位；详情见JSON/地图文档</text><text x="80" y="970" font-size="15">布局只校核静态四邻接与一格余量；工程须再验证真实碰撞、角色半径、门禁、巡游和渲染。</text></g></svg>')
    return '\n'.join(out)


def write_story(c):
    """导出每章完整分幕叙事、剧情持久状态及发布边界。"""
    n=c['n'];p=Path(c['folder']);s=header(f'第{n}章《{c["title"]}》故事与流程')
    s+=f'**章节承诺：{c["promise"]}** 推荐等级{c["start"]}—{c["end"]}；可从前章末整十级进入，无新增等级硬锁。\n\n'
    for title,text in c['story']:s+=f'## {title}\n\n{text}\n\n'
    s+='## 场景与状态链\n\n'
    main=[q for q in c['tasks'] if not q['side']]
    s+=table(['节点','行动与情节','生效时机'],[(q['id'],q['name'],('领奖写入 '+','.join(q['unlock'])) if q['unlock'] else '领奖推进后继；不自动领奖') for q in main])
    s+='## 叙事执行边界\n\n主线线性、一次性；所有关键目标有确定路径。击杀首领只完成目标，领奖才开放下一路。支线不发主线必需钥匙。物理地形以地图JSON为准，文本状态用已领奖标记驱动；不模拟真实水流、根系生长、群众护送或能源管网。\n\n'
    s+='结局/章末前后功能NPC原地保留，野外人物不强制迁移，确保补做支线。已清场的首领按残留构型复刷，既有墓碑倒计时保留；首通对白与任务奖励不再次执行。未发布下一章时隐藏其出口，尾声仅留下新线索，不把玩家送进空地图。\n'
    write(p/'00-章节故事与流程.md',s)


def write_npcs(c):
    """导出功能、动机、场景坐标和剧情前后对白，并登记任务职责。"""
    s=header('NPC与对白');s+='全员使用线性对白；角色不因主线结束死亡或永久离场。NPC编号对应地图N标记。交易、升星、仓库沿统一服务入口；对话状态以章末领奖为分界，任务原话见任务卡。\n\n'
    for p in c['npcs']:
        related=[q['id'] for q in c['tasks'] if p['id'] in [q['giver'],q['turnIn']] or (q['kind']=='talk' and q['target']==p['id'])]
        s+=f'## N{p["index"]+1} {p["name"]}／{p["id"]}\n\n- 地点：{p["map"]}，格坐标{p["cell"]}；功能：{p["role"]}。\n- 动机：{p["motive"]}。\n- 外观：{p["look"]}。\n- 首次招呼：“{p["before"]}”\n- 任务职责：{",".join(related) or "常驻功能服务；不另造主线前置"}。\n- 章末对白：“{p["after"]}”\n- 关闭对话：服务NPC回功能菜单，其余回场景；不在对白里偷偷发奖。地图/任务状态改变只由统一结算写入。\n\n'
    s+='## 信息权限与关系\n\n主线负责人(N1)协调行动，记录解析者(N8)仅从已交付证据中解释真相；N9和N10是各自现场的证人，不提前知道终章答案。铁匠(N2)、药师(N5)从工具和伤员的角度检验计划，不替玩家把所有人都说服。货郎(N3)、仓管(N4)、车夫(N6)持续服务；生活角色(N7)让章末改变落到具体人。第五章N11只知道门哨交接，不掌握全部回流真相。\n\n'
    if c['n']==6:s+='本章十人均为独立前哨人员。陆衡、白芷、许铸、祁言、岑素等旧人通过署名文件与结局回信出现，不复制活人NPC、不移动旧服务点；终章文本中出现的“陆衡来信”是记录条目而非新NPC。\n'
    write(Path(c['folder'])/'01-NPC与对白.md',s)


def write_maps(c):
    """导出25图的用途、数值预算、出入口、物种分布和可重建参考图。"""
    s=header('地图与布局');s+=f'视觉基调：{c["theme"]}。全图采用正交横向16:9逻辑格，投影按现有等距入口，不能为屏幕轮廓再拉伸瓦片。\n\n'
    s+='常态普通同时存活10、精英2、Boss1为单图候选上限；邻近可激活普通6，接敌建议3—4，精英/Boss场避免牵入普通。新章节前缀必须由工程显式接入活动预算。刷新位总数不是同时怪物数。\n\n'
    s+=table(['地图','尺寸','推荐级','普通位','精英位','Boss位'],[(m['name']+'／'+m['id'],f'{m["w"]}×{m["h"]}',m['level'],m['normalSlots'],m['eliteSlots'],len(m['bosses'])) for m in c['maps']])
    for m in c['maps']:
        mid=m['id'];s+=f'## {m["name"]}／{mid}\n\n{m["description"]}。\n\n'
        s+=f'[标注布局](地图参考/{mid}-标注.svg) · [纯布局](地图参考/{mid}-纯布局.svg) · [坐标JSON](地图参考/{mid}.json)\n\n'
        s+='- 黑色多边形为不可走区域，所有顶点、入口、NPC、精英、普通位和首领圆心均有格坐标。主路和旁路由同一JSON导出；不需要用户提供草图。\n'
        s+='- 出口/服务点12格内不布普通刷新；精英点6格内不布普通，首领中心18格内不布普通，场地半径12格。主路保留至少一格静态余量；真实角色净宽另由工程验证。\n'
        if m['index']:
            s+='- 普通18秒、精英90秒、Boss600秒刷新，倒计时跨图保存。普通点四区分布，沿障碍南北侧巡回。常态上限10，附近最多6；预计一圈90—150秒，短于刷新的路段应接下一怪区而非等点。工程需测连续两轮无超过8秒的无目标站立，不能靠加数量通过。\n'
        else:s+='- 安全枢纽，普通/精英/Boss均为0。八个服务/故事点集中在中街；不让药品、仓库和铁匠分处地图四角。\n'
        s+='\n'+table(['出口','坐标','去向','向外条件','目标到达点'],[(f'P{i+1}',e['cell'],e['to'],e['flag'] or '已解锁来路/本地开放',e['arrival']) for i,e in enumerate(m['exits'])])
        if m['index']:
            counts=Counter(p['template'] for p in m['spawns']);s+=table(['普通模板','刷新位数'],counts.items())
            s+=table(['精英模板','格坐标','刷新秒'],[(e['template'],e['cell'],e['respawn']) for e in m['elites']])
        s+=table(['地标','格坐标'],[(p['name'],p['cell']) for p in m['landmarks']])
        s+=table(['人物/首领','格坐标'],[(p['id'],p['cell']) for p in c['npcs'] if p['map']==mid]+[(b['id'],b['cell']) for b in c['bosses'] if b['map']==mid])
        public={k:v for k,v in m.items() if not k.startswith('_')}
        public.update(layoutVersion=VERSION,coordinates='正交格，左上原点，x向右y向下，边界外不可走；obstacles不可走',runtime=False)
        write(Path(c['folder'])/'地图参考'/f'{mid}.json',json.dumps(public,ensure_ascii=False,indent=2))
        for name,marked in [('标注',True),('纯布局',False)]:write(Path(c['folder'])/'地图参考'/f'{mid}-{name}.svg',svg(m,c,marked))
    s+='## 出行与首通后\n\n步行道路免费，车夫只到本集群已访问附属图与相邻枢纽。每个野外入口保留车夫休整点（用服务角色，不增加具名人物）；目标落点取该图首个返回出口附近，必须通过战斗外保护区复核。首访与任务门禁均校验，通过后可直达，不要求按地图逐段交费。\n\n候选费用：枢纽间300/400/500/600金币（第三至六章进入价），本集群普通野外150、首领图250，往同一目的地报价与路深无关；第一、二章旧线路报价不变。车费不足可免费步行，无主线强制花费。通关后所有已开路与可选场保留。枢纽hubLinks只能相邻连，不能把第三章车夫连到第六章井底。\n'
    write(Path(c['folder'])/'02-地图与布局.md',s)


def write_monsters(c):
    """导出全敌方模板、固定候选数值和每只首领可交接的时间与场地规格。"""
    s=header('怪物、精英与Boss');s+='基础值只在内容制作时由等级公式推导，进游戏后是固定配置，不随玩家配装动态缩放。HP=20L+150，攻=4L+60，防=1.4L+10；职责/精英/首领倍率与取整见制作工具。攻击/防御和技能伤害均沿现有Combat公式。\n\n'
    s+=table(['ID／普通怪','等级','职责/外观','行为与弱点','HP／攻／防','间隔秒／经验'],[(b['id']+'／'+b['name'],b['level'],b['role']+'；'+b['look'],b['behavior'],f'{b["hp"]}／{b["atk"]}／{b["def"]}',f'{b["interval"]}／{b["xp"]}') for b in c['normal']])
    s+=table(['ID／精英','等级','职责/攻击类型','外观与招式','HP／攻／防','间隔秒／经验'],[(b['id']+'／'+b['name'],b['level'],b['atktype'],b['look']+'；'+b['behavior'],f'{b["hp"]}／{b["atk"]}／{b["def"]}',f'{b["interval"]}／{b["xp"]}') for b in c['elites']])
    s+='所有距离按逻辑格×现有Iso单位换算。**普通怪「职责 → 移速／`attackRange.kind`／射程」映射**跨章同值；职责措辞不同不等于数值不同：\n\n'
    s+=table(['职责','移速（格／秒）','attackRange.kind','射程（格）'],[('近战／近战高防','2.4','melee','1'),('快速近战／伏击／近战伏击','3.1','melee','1'),('重型／重型近战／盾卫／高防','1.8','melee','1'),('远程','2.4','ranged','6'),('定点远程','0','ranged','6')])
    s+='「近战高防」为近战本体加高防数值后缀，取近战 2.4，与「高防」「盾卫」的重装 1.8 属有意区分而非数据回退；同一职责跨章取同值。精英统一移速 2.2，攻击类型按同一口径由招式形态登记（线技／定点投射类为 `ranged` 6 格，近身挥击／冲撞／拍地／盾压类为 `melee` 1 格），逐条见精英表「职责/攻击类型」列；同一风格招式在不同章若登记值不同，以本章 `monsters.json` 为准，并登记为待实机校准项，统一时只改对应章数据、不动本文结构。Boss 统一移速 1.8，攻击类型见各首领条目。\n'
    s+='无硬元素免疫、致盲或未实现控制。普通近战体量100%；精英130%并有独立金色徽记、加粗名字与双层血条；Boss180—220%、专属轮廓和独立首领血条。区分不只靠颜色。精英招式共享其首领动作组件的低频单招：每8秒一次、0.9秒预警、基础伤害系数1.1；其余时间普通攻击。\n\n'
    for i,b in enumerate(c['bosses']):
        s+=f'## {b["name"]}／{b["id"]}\n\n- 等级{b["level"]}，{"主线必打" if b["main"] else "完全可选"}；{b["map"]}，圆心{b["cell"]}、参考半径12格。外观：{b["look"]}。故事职责：{b["meaning"]}。\n- HP{b["hp"]}，攻{b["atk"]}，防{b["def"]}；普通攻击间隔1.8秒，奖励经验{b["xp"]}。无闪避堆叠或元素硬免疫。\n- 专属表现：{b["behavior"]}。\n'
        shape=['宽线','两处错位圆圈','左右扇形','轮转扇区'][i%4]
        s+=f'- 招式A：{b["attackA"]}。进入战斗后4秒首次，之后每8秒；伤害每段系数1.15、同段只命中一次，结束0.8秒硬直。所有段均执行预警，前一段伤害结束后下一段才可开始，不重复用多碰撞格计伤。\n'
        s+='- 招式B：生命降至50%时进入二阶段，只触发一次；先1.3秒抬臂/亮核，再以半径5格的局部环击（中心2格或圈外可避，系数1.3），随后2秒输出窗口。每12秒重复一次，A与B互斥，公共动作锁至少1秒，不同预警不得占满全场。\n- 第三阶段：仅终章空天之眼在25%血时将A间隔缩至6秒；预警和安全通路不缩短，不加召唤数量。其他首领无第三阶段。\n'
        if c['n']==6 and i==2:s+='- 空天之眼的“核心暴露”是B后2秒停手窗口，不额外乘易伤倍率；最终回注通过领奖对白表现，不让玩家在Boss战中操作新能量条。\n'
        s+='- 不召唤新增实体；沙圈、船骨、根臂、灯照等均为相同预警组件的主题表现，不增加真实可变障碍。首次上线动作不足时可保留慢速A与B，不用删除躲避窗口维持难度。\n- 玩家可自由手动接管；不强制关闭F/G。自动战斗不能承诺躲过新预警，工程需提示接管，且避免自动巡游误入首领场。\n- 脱战：首领距圆心18格或玩家离场/死亡，脱战5秒后归位回满；保留已结算战利品，未死亡不发掉落。出入无永久锁门，死亡可从本图入口安全重试。\n- 首通：击杀完成目标、领奖推动剧情；复刷600秒，掉落使用本章Boss池，首通任务奖励不再发。\n\n'
    s+='## 刷新和产出归属\n\n普通、精英和Boss分别使用本章normal/elite/boss掉落规则，装备均来自本章十个型号；首领追加槽也覆盖所有部位。精英点与首领点不在同一圆场中心重叠，地图JSON列出所有实例点。普通预算10、精英2、首领1是首轮工程目标，地图里刷新位更多用于巡回，不是无上限同时生成。新视觉与行为须工程实施，本文不是已完成技能支持清单。\n'
    write(Path(c['folder'])/'03-怪物精英与Boss.md',s)


ITEMS={'C3Q03':'配水封片','C3Q06':'警报索引','C3S02':'原字拓片','C3S03':'净水布封','C4Q02':'邮袋封签','C4Q06':'观测标片','C4S02':'退信木签','C4S03':'药菌封签','C5Q03':'号台残签','C5Q06':'营道标片','C5S02':'原始军报','C5S03':'担架带扣','C5S06':'值守门牌','C6Q03':'守护誓条','C6Q06':'旁路校验片','C6S01':'药架扣','C6S03':'旧名签'}
PATTERNS={
'c3_boss01':'两条平行线长10格宽2格，间距5格；先左后右，相隔0.7秒；两次锁定均在伤害前1.0秒完成',
'c3_boss02':'三个半径2.5格沙圈，中心相距至少6格，按0/0.7/1.4秒顺序爆开；每圈预警1.0秒',
'c3_boss03':'半径6格、70度印阵，按0/120/240度顺序落下，相隔0.8秒，每次独立预警1.0秒',
'c4_boss01':'半径6格、80度扫根，1.2秒后沿首次锁定方向冲击长8宽2格；扇形预警1.0秒、直线预警1.1秒',
'c4_boss02':'三枚半径2.5格孢灯圈按0/0.8/1.6秒炸开，圈间至少6格；每次预警1.1秒',
'c4_boss03':'左右两条长9宽2格根臂线，相隔0.8秒；预警各1.0秒，中间至少3格通道',
'c5_boss01':'号角前两拍各0.6秒只发声亮纹，第三拍沿长10宽3格前方线冲击；第三拍前预警1.1秒',
'c5_boss02':'四块半径2格舟骨落点沿横向依次坠落，间隔0.6秒，各预警1.1秒，不能同时封两座通路',
'c5_boss03':'长8宽3格盾压后，左右70度扇扫各一次，相隔0.9秒，各预警1.1秒；盾压前1.2秒',
'c5_boss04':'三次半径7格、60度灯照扇区轮换，角度间隔120度，每次间隔1.0秒、预警1.2秒；第三次后停手1.5秒',
'c6_boss01':'两条长10宽2格审判线相隔0.8秒，随后停顿1秒；每线预警1.2秒，重击放在B而不重叠',
'c6_boss02':'长8宽2格慢斩线后一次半径5格70度扇扫，间隔1秒，各预警1.2秒；环击仅放在B',
'c6_boss03':'三次半径7格60度局部凝视，按玩家首次锁定方向、加120度、再加120度，间隔1秒，各预警1.2秒；结束暴露2秒，不增加易伤倍率'}


def reward_text(q,c):
    """从同一奖励记录生成可读摘要，任务表与奖励表不手工维护重复值。"""
    text=f'{q["xp"]}经验、{q["gold"]}金币'
    if q['gear']:
        g=next(g for g in c['gear'] if g['id']==q['gear']['id']);quality='史诗' if q['gear']['quality']=='epic' else '稀有'
        text+=f'；{quality}{g["name"]}×1（Lv{g["level"]}，0星）'
    return text


def write_tasks(c):
    """导出75个完整任务卡及统一异常恢复，不引入游戏不支持的目标类型。"""
    s=header('任务链与任务卡');s+='每项均一次性；主线不可放弃，支线可放弃后重接，计数清零。前置只在领奖后达成；至多5个进行中任务，支线最多留4个，不隐藏下一主线导航。所有地图范围显式列出。\n\n'
    s+=table(['ID','任务','推荐级','前置','目标类型/数量'],[(q['id'],q['name'],q['level'],q['prev'],LABEL[q['kind']]+'×'+str(q['count'])) for q in c['tasks']])
    s+='## 通用执行规则\n\n击杀只统计接取后且发生在指定图的有效击杀；先杀首领后接取可等600秒复刷，前置不消费首领唯一道具。收集每次指定来源击杀100%提供一件任务计数，达到所需数量后停止生成；该计数不占装备格，不可出售。放弃清本任务计数，重接重新累计；一个任务的同名物品不能替别的任务计数。交谈均由目标本人发布（talkOnAccept），接取后完成，仍须点击领奖。\n\n装备奖励使用统一生成器，一次抽定后按持久化发奖计划保存；满包/失败时保留同一待发实例与随机结果，下次领取不得重抽。所有金币/经验/解锁/装备先校验再原子结算，成功才标记rewarded。该待发结果若当前工程尚无持久入口，须先补齐，不允许失败重试成为洗词条入口。\n\n'
    lookup={p['id']:p['name'] for p in c['npcs']};lookup.update({b['id']:b['name'] for b in c['normal']+c['bosses']})
    for q in c['tasks']:
        target=lookup.get(q['target'],q.get('itemName',q['target']))
        s+=f'## {q["id"]} {q["name"]}\n\n- 类型：{"支线，可放弃" if q["side"] else "主线，不可放弃"}；推荐Lv{q["level"]}；前置：{q["prev"]}已领奖。\n- 发布：{lookup[q["giver"]]}／{q["giver"]}；交付：{lookup[q["turnIn"]]}／{q["turnIn"]}；人物坐标见NPC表。\n- 显式范围：{q["map"]}。目标：{LABEL[q["kind"]]} {target}／{q["target"]}，数量{q["count"]}。\n'
        if q['kind']=='collect':s+=f'- 确定来源：{lookup[q["source"]]}／{q["source"]}，指定图接取后每次击杀100%给1件，计满停止。\n'
        s+=f'- 接取：“{q["accept"]}”\n- 进行追踪：到 {{map:{q["map"]}}} {LABEL[q["kind"]]} {target}（{{current}}/{{count}}）。\n- 交付追踪：到 {{npc:{q["turnIn"]}}} 交付“{q["name"]}”；不自动交付。\n- 完成：“{q["complete"]}”\n- 奖励：{reward_text(q,c)}。\n- 领奖解锁：{",".join(q["unlock"]) or "仅后继前置满足，不写额外世界状态"}。\n- 异常：目标死亡不在图中则按同点刷新；NPC不迁走；等级不足可领奖留用但不可越级穿；满包按通用规则保留结果。能力：现有kill/collect/talk及新内容配置。\n\n'
    s+='## 支线组织\n\nS01生活清路；S02补充真实记录；S03药品/修护帮助；S04→S05为一条可选首领短链；末项为章末生活回声。第五章另有S06门牌收集，属于独立军务委托。可选链只奖励装备/经验/金币，不决定任何主线门禁。\n'
    write(Path(c['folder'])/'04-任务链与任务卡.md',s)


def model(c,level=None,star=2):
    """计算可复核的中性稀有配装：每件固定HP+8、MP+5乘套词条档，无百分比词条。"""
    level=level or c['end'];fac=1+.1*star;tot=Counter()
    for i,g in enumerate(c['gear']):
        for k,v in g['raw'].items():tot[k]+=v*1.5*fac*MULT[i]
        tot['hp']+=rnd(8*AFFIX[c['n']])*fac*MULT[i];tot['mp']+=rnd(5*AFFIX[c['n']])*fac*MULT[i]
    a=12+2*(level-1)+rnd(tot['atk']);d=5+(level-1)+rnd(tot['def'])
    return dict(level=level,atk=a,defense=d,hp=rnd(50+8*level+2*a+4*d)+rnd(tot['hp']),mp=30+5*level+rnd(tot['mp']))


def write_gear(c):
    """导出40型号的确定基底、真实穿戴等级、掉落分组和章级奖励预算。"""
    n=c['n'];s=header('装备、奖励与成长');s+=f'本章十型号，套起点{c["start"]}，实际穿戴要求分布{c["start"]}—{c["end"]}。双槽用相同型号，不增加左右名字。基础值取第二套对应部位基底×{FACTORS[n]}后四舍五入；品质和星级另算，套倍率不在运行时再乘一次。\n\n'
    s+=table(['ID／名称','部位','穿戴Lv','0星无品质基底','模板price／套售价系数'],[(g['id']+'／'+g['name'],SLOT_NAMES[i],g['level'],g['raw'],f'{g["price"]}／{g["valueMultiplier"]}') for i,g in enumerate(c['gear'])])
    s+=f'五品质基础倍率1/1.2/1.5/1.9/2.4，词条总数0/1/2/3/4；百分比也占条数，稀有以上50%机会用一条百分比替换固定条。固定词条档位倍率{AFFIX[n]}，攻击/防御原值2—5、生命8—20、法力5—12分别乘此档倍率取整；生命/法力百分比2%—8%，不再乘档位。全属性按(1+0.1×星级)放大，最高12，不改品质、不重抽。\n\n'
    s+='## 本章掉落定义\n\n'+table(['来源','装备数量与概率','品质权重（各槽独立）'],[
      ('普通','20%掉1件','普通65／优秀25／稀有9／史诗1'),
      ('精英低档组','必掉2—3件（等概率数量）','普通55／优秀45'),
      ('精英好装组','必掉1件','稀有90／史诗10'),
      ('Boss低档组','必掉5—8件（等概率数量）','普通70／优秀30'),
      ('Boss好装组','必掉2件','稀有75／史诗25'),
      ('Boss传说追加','每次击杀独立5%追加1件','传说100；从全部十部位等概率选型号')])
    s+='所有装备槽从本章十型号等概率选一件，可重复；先抽是否掉/数量，再抽型号与品质，不按玩家等级抬升门槛。提前获得高于玩家等级的本套装备可留用。Boss每次7—10件基础装备，5%追加后8—11件；不是每次保底传说。精英3—4件装备。掉落真实奖励与装备雨动画分离，满包保留未领取物，不吞奖励。\n\n'
    lo=20+8*(n-3);s+=f'普通金币必掉{lo}—{lo+12}；精英必掉{lo*8}—{(lo+12)*8}；Boss必掉{1200+600*(n-3)}—{1600+600*(n-3)}。敌人goldReward固定0，金币只从掉落表发，避免重复入账。普通另有15%大红药、10%大蓝药；精英各1瓶；Boss各2瓶。沿用已有大药500恢复/150售价，不新造强制消耗品；如意沿当前已实施Boss规则接入，不改变概率或额外添加装备件数。\n\n'
    s+='## 任务固定奖励\n\n'+table(['任务','经验／金币／装备'],[(q['id'],reward_text(q,c)) for q in c['tasks']])
    main=sum(q['xp'] for q in c['tasks'] if not q['side']);side=sum(q['xp'] for q in c['tasks'] if q['side'])
    s+=f'## 经验预算\n\n以Lv{c["start"]-1}、0经验进入，目标达到Lv{c["end"]}、0经验，按现有round(100×L^1.6)累计需{c["xpBudget"]}经验。主线提供{main}（约35%）、支线提供{side}（约10%）；剩余来自击杀，首领/精英经验已包括在击杀预算中，不能再当免费加成重复计算。不做支线的10%可从已开放普通区补足。\n\n'
    m=model(c);b=c['bosses'][-1];damage=max(1,math.floor(m['atk']-.5*b['def']));hit=max(1,math.floor(b['atk']-.5*m['defense']))
    s+=f'## 代表配装与校准目标\n\n章末Lv{m["level"]}，本套十四件全稀有+2，每件两条中性固定词条（生命与法力，取上述最小档值），无百分比、无暴击收益：攻击{m["atk"]}、防御{m["defense"]}、HP{m["hp"]}、MP{m["mp"]}。逐件四舍五入差异由工程统一汇总口径复核，本文按全身汇总取整。\n\n对章末Boss：普攻单次约{damage}，间隔0.8秒，忽略技能/走位/暴击的静态击杀时间约{b["hp"]/(damage/.8):.1f}秒；Boss普通命中约{hit}，约占HP的{hit/m["hp"]*100:.1f}%。该值仅推导，不代表可以站桩通关。目标普通怪4—7次普攻、精英15—30秒、主线首领90—180秒；实际使用AOE、走位与药水后的结果要另测，不能把算例当实机通过。\n\n'
    s+='章初采用上一套稀有+2加新套武器的混穿，支线/低风险区保持开放以补强。不得用本套尚未到级的十四件全穿作为入口难度基准。章末算例只用于横向校准；主线不要求史诗/传说或高于+4的装备。\n\n升星继续500×1.5^当前星级的单次费用和当前成功率，不随章节重置；+12为长线追求，不是结局门槛。收入/药品/车费及升星期望成本的统一账见总表02。\n'
    write(Path(c['folder'])/'05-装备奖励与成长.md',s)


def write_growth():
    """汇总四十级节点、章级经验/金币账与代表配装，不把候选时间标成实测。"""
    s=header('逐级成长与经济总表');s+='当前经验曲线round(100×L^1.6)，角色每级攻击+2、防御+1；药品、战斗和升星沿现有公式。章节从Lv20/30/40/50、0经验入场预算，推荐下一等级进入但不硬锁。所有费用/用时为设计推导。\n\n'
    s+='## 四十个等级的行动与装备目标\n\n';lines=[]
    for c in CHAPTERS:
        main=[q for q in c['tasks'] if not q['side']]
        for i,g in enumerate(c['gear']):
            l=g['level'];focus=min(main,key=lambda q:(abs(q['level']-l),q['id']))
            skill='25破甲重击仅配置，非通关前提' if l==25 else '40灵刃风暴仅配置，非通关前提' if l==40 else '使用已开放四技能；不新增技能' if l in [50,60] else '四技能配合/词条与升星'
            lines.append([l,SLOT_NAMES[i]+'／'+g['name'],focus['map'],focus['id']+' '+focus['name'],xp(l-1),'刷本章同部位五品质；任务保证奖见章表',skill])
    s+=table(['到达等级','新可穿装备','主要活动图','主线阶段','从上一级所需XP','成长追求','技能边界'],lines)
    s+='## 章级预算与可持续金币\n\n普通XP约等于对应等级升级经验的1%，精英3%，Boss18%；任务总XP为章需求45%（主35%＋支10%）。下表按全支线、各Boss首杀一次、每战斗图2次精英击杀估算，再补普通击杀到目标等级。反复刷Boss会替代部分普通击杀，不叠加为额外免费级数。\n\n'
    econ=[]
    for c in CHAPTERS:
        n=c['n'];questxp=sum(q['xp'] for q in c['tasks']);bossxp=sum(b['xp'] for b in c['bosses']);ecount=2*(len(c['maps'])-1);ex= sum(e['xp'] for e in c['elites'])/len(c['elites']);nx=sum(e['xp'] for e in c['normal'])/len(c['normal'])
        kills=math.ceil(max(0,c['xpBudget']-questxp-bossxp-ecount*ex)/nx)
        price=sum(g['price'] for g in c['gear'])/10*VALUE[n];coin=26+8*(n-3)
        income=rnd(kills*(coin+.2*1.355*price)+ecount*(coin*8+6.3625*price)+len(c['bosses'])*(1400+600*(n-3)+15.575*price)+sum(q['gold'] for q in c['tasks']))
        # 购买药物按20大红+10大蓝额外补充；保留全部掉药而非把它们虚构成金币。
        spend=30*150+10*250+rnd(14*(500+750/.9))+rnd((1125/.8+1688/.7)*2)
        c['economy']={'normalKills':kills,'eliteKills':ecount,'income':income,'baselineSpend':spend,'net':income-spend}
        econ.append([c['n'],c['xpBudget'],questxp,bossxp,kills,income,spend,income-spend])
    s+=table(['章','20→30等十级需求','全部任务XP','全部首领首杀XP','估计普通击杀','金币总入账估计','基线支出','余量'],econ)
    s+='金币账口径：普通装备20%×平均品质卖价系数1.355；精英平均3.5件、卖价系数加权总和6.3625；Boss平均8.5件基础与5%追加的卖价系数加权总和15.575。各部位模板price均值×套售价倍率，计入金币掉落及任务金币；所有可售件按售出估算，保留自用装备会少收入。不得把留地未领取物当已入账。\n\n基线支出=额外购买20大红＋10大蓝4500，10次250金币野外车费2500，十四件从0到+2的无如意期望成本约18667，再两件从+2到+4约7635。此非保证消耗/收益；升星方差可显著高于均值，玩家可先用低星、步行并继续刷取，主线不能锁在一次升星成功上。\n\n14件装备更换成本高，章初不要求整套重升。保留上一套高星，自选优先武器/护甲。已到+12的旧装备仍可穿，新套不自动继承星级。通关后高星追求继续使用现有系统。\n\n'
    s+='## 升星成本算例\n\n'+table(['跨度','单次金币','成功率','无如意期望金币'],[(f'{i}→{i+1}',rnd(500*1.5**i),r,rnd(rnd(500*1.5**i)/(r/100))) for i,r in enumerate([100,90,80,70,60,50,40,30,20,10,10,5])])
    s+='## 时间与数值边界\n\n候选首通每章120—200分钟，含约25—40分钟对话/调查、25—40分钟探索交通、其余击杀与配装；第五章可放宽至150—220分钟。不把这些目标说成已测时长。普通目标4—7次普攻、精英15—30秒、Boss90—180秒，自动AOE会改变效率。若超过预算，先校准怪物经验和必要击杀，不加无意义跑图或强制稀有装备门槛。\n\n500恢复大药在高等级可能低于一次重击，但免费未受击恢复和打坐仍有效；第一版不新加大药。实机若基本配装明显无法维持生存，先调整敌方伤害/节奏，不能用要求玩家无限买药掩盖问题。\n\n最小可通关模型是上一套稀有+2混穿新武器、逐级换装，不要求全史诗、传说、+12或新技能。各章末算例详见05；静态模型不涵盖走位、暴击、目标拥挤、技能蓝耗与回城，必须后续试玩。\n'
    write('02-逐级成长与经济总表.md',s)


def write_registry():
    """输出全部稳定草案ID的登记与权威文件位置；不重复维护属性数值。"""
    s=header('内容登记与关联索引');s+='本表为设计草案登记；未接入data目录。名称变更不换ID。详细数值/对白/奖励/坐标分别读章内03/01/05/02，任务前置读04。\n\n'
    for c in CHAPTERS:
        f=c['folder'];s+=f'## 第{c["n"]}章\n\n';data=[]
        for typ,key,file in [('地图','maps','02-地图与布局.md'),('NPC','npcs','01-NPC与对白.md'),('普通','normal','03-怪物精英与Boss.md'),('精英','elites','03-怪物精英与Boss.md'),('Boss','bosses','03-怪物精英与Boss.md'),('装备','gear','05-装备奖励与成长.md'),('任务','tasks','04-任务链与任务卡.md')]:
            for x in c[key]:data.append([x['id'],x['name'],typ,f'[{file}]({f}/{file})'])
        for q in c['tasks']:
            if q['kind']=='collect':data.append([q['item'],q['itemName'],'任务计数道具',f'[{q["id"]}]({f}/04-任务链与任务卡.md)'])
        s+=table(['ID','名称','类型','权威正文'],data)
        s+=table(['解锁标记','来源任务'],[(flag,q['id']) for q in c['tasks'] for flag in q['unlock']])
    s+='## 全局引用\n\n外部前置C2Q12与chapter3沿现有数据，不重命名；四章尾声依次写chapter4、chapter5、chapter6、campaign_complete。沉井镇新增至c3_map00的双向步行边和相邻hubLinks是唯一旧图交通改动需求，详细落点需工程对照当前布局。没有把未发布目标提前写入正式配置。\n'
    write('03-内容登记与关联索引.md',s)


def audit(maps):
    """执行内容静态审阅：数量、前置、目标来源、出口配对、连通与等级；不是游戏测试。"""
    tasks={q['id']:q for c in CHAPTERS for q in c['tasks']};npcs={p['id']:p for c in CHAPTERS for p in c['npcs']};monsters={b['id']:b for c in CHAPTERS for b in c['normal']+c['elites']+c['bosses']};gear={g['id']:g for c in CHAPTERS for g in c['gear']}
    assert len(maps)==25 and len(tasks)==75 and len(monsters)==63 and len(npcs)==41 and len(gear)==40
    ids=list(maps)+list(tasks)+list(monsters)+list(npcs)+list(gear)+[q['item'] for q in tasks.values() if q['kind']=='collect']
    assert len(ids)==len(set(ids))
    for q in tasks.values():
        assert q['prev'] in tasks or q['prev']=='C2Q12'
        assert q['giver'] in npcs and q['turnIn'] in npcs and q['map'] in maps
        if not q['side']:assert 'S' not in q['prev']
        if q['kind']=='talk':assert q['target']==q['giver'] and npcs[q['target']]['map']==q['map']
        elif q['kind']=='boss':assert monsters[q['target']]['map']==q['map']
        else:assert q.get('source',q['target']) in maps[q['map']]['normalRoster']
        if q['gear']:assert q['gear']['id'] in gear
    for c in CHAPTERS:
        assert [g['level'] for g in c['gear']]==list(range(c['start'],c['end']+1))
        assert len(c['npcs'])==(11 if c['n']==5 else 10)
        assert len(c['bosses'])==(4 if c['n']==5 else 3)
    # 模拟所有主线推进，不依赖任何可选任务或首领，检查任务与门禁形成的联合图。
    reached={'c3_map00'};flags={'chapter3'};rewarded={'C2Q12'};changed=True
    while changed:
        changed=False
        for mid in list(reached):
            for e in maps[mid]['exits']:
                if e['to'] in maps and (not e['flag'] or e['flag'] in flags) and e['to'] not in reached:reached.add(e['to']);changed=True
        for q in tasks.values():
            if q['side'] or q['id'] in rewarded:continue
            if q['prev'] in rewarded and q['map'] in reached and npcs[q['giver']]['map'] in reached and npcs[q['turnIn']]['map'] in reached:
                rewarded.add(q['id']);flags.update(q['unlock']);changed=True
    assert all(q['id'] in rewarded for q in tasks.values() if not q['side'])
    assert len(reached)==25 and 'campaign_complete' in flags
    # 再检查可选链也可完成，不形成不可达交付点。
    while True:
        more=[q for q in tasks.values() if q['id'] not in rewarded and q['prev'] in rewarded and q['map'] in reached and npcs[q['giver']]['map'] in reached and npcs[q['turnIn']]['map'] in reached]
        if not more:break
        rewarded.update(q['id'] for q in more)
    assert len(rewarded)==76
    totalnormal=sum(m['normalSlots'] for m in maps.values());elitepoints=sum(m['eliteSlots'] for m in maps.values())
    result=dict(version=VERSION,maps=25,npcs=41,normalTemplates=33,eliteTemplates=17,bosses=13,mainTasks=50,sideTasks=25,equipmentModels=40,questItems=len(ITEMS),normalSpawnSites=totalnormal,eliteSpawnSites=elitepoints,mainOnlyProgression='50/50任务和25/25地图可达，不依赖支线',staticNavigation='25图关键点及全部刷新位通过四邻接一格余量检查',runtimeValidation='未执行；图形与数值不是游戏实测',baselineSHA256=BASELINE)
    write('制作工具/内容校核记录.json',json.dumps(result,ensure_ascii=False,indent=2))
    return result


def main():
    """按依赖顺序生成全部章包、总表与地图，失败时不产生通过声明。"""
    maps=prepare()
    for c in CHAPTERS:
        for q in c['tasks']:
            if q['kind']=='collect':q['itemName']=ITEMS[q['id']]
        for b in c['bosses']:b['attackA']=PATTERNS[b['id']]
        write_story(c);write_npcs(c);write_maps(c);write_monsters(c);write_tasks(c);write_gear(c)
    write_growth();write_registry()
    # 清除仅供构建时用的集合，结构化交付保持标准JSON。
    public=[{k:v for k,v in c.items()} for c in CHAPTERS]
    for c in public:c['maps']=[{k:v for k,v in m.items() if not k.startswith('_')} for m in c['maps']]
    write('制作工具/内容总表.json',json.dumps({'version':VERSION,'runtime':False,'chapters':public},ensure_ascii=False,indent=2))
    report=audit(maps)
    print(json.dumps(report,ensure_ascii=False,indent=2))


if __name__=='__main__':
    main()
