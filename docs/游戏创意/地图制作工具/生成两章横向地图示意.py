"""Product layout illustrations; does not write game configuration.
Run with Pillow installed. Outputs labelled/plain/navigation PNG and reference JSON.
"""
from pathlib import Path
import json, math, heapq
from PIL import Image, ImageDraw, ImageFont
BASE=Path(__file__).resolve().parents[1]
FONT_PATH='/System/Library/Fonts/STHeiti Medium.ttc'
FONT=ImageFont.truetype(FONT_PATH,23)
SMALL=ImageFont.truetype(FONT_PATH,19)
TITLE=ImageFont.truetype(FONT_PATH,34)
GREEN='#4eaa70'; BLACK='#18241f'
def rect(x,y,w,h): return [(x,y),(x+w,y),(x+w,y+h),(x,y+h)]
def zone(code,x,y,n,composition):return dict(id=code,center=[x,y],normalCount=n,composition=composition)
def point(id,label,x,y,kind='landmark'):return dict(id=id,label=label,cell=[x,y],kind=kind)
def exit(id,label,x,y,target,entrance):return dict(id=id,label=label,cell=[x,y],toMap=target,toEntrance=entrance)
plans=[
 dict(name='幸存者营地',id='camp',chapter=1,size=[64,36],concept='围绕镇灵灯的横向服务街，东出野外，北接第二章',blocks=[rect(48,13,17,13),rect(96,13,18,13),rect(48,62,17,14),rect(96,62,18,14),rect(75,39,10,12),rect(10,0,20,10),rect(128,80,18,10)],exits=[exit('to_wild','往试炼野外',156,45,'wild_trial','from_camp'),exit('to_c2','往沉井镇',80,4,'c2_well_town','from_camp')],zones=[],points=[point('lamp','镇灵灯',80,45),point('elder','长老',94,44,'npc'),point('shop','货郎',66,44,'npc'),point('blacksmith','铁匠',67,28,'npc'),point('warehouse','仓库',93,28,'npc'),point('carter','车夫',91,59,'npc'),point('training','3个教学木桩',80,73)],routes=[[(80,8),(80,30),(69,30),(69,56),(93,56),(93,45),(152,45)],[(69,56),(69,77),(92,77),(93,56)]],normal=0,elite=0,boss=0),
 dict(name='试炼野外',id='wild_trial',chapter=1,size=[176,99],concept='沿旧商路横向推进，北侧岩坡与南侧草地形成不同回路',blocks=[[(48,18),(61,16),(66,31),(62,47),(48,47),(43,32)],rect(98,38,12,31),rect(20,81,18,9),rect(73,0,12,11),rect(126,73,6,17)],exits=[exit('to_camp','回幸存者营地',4,45,'camp','from_wild'),exit('to_ash','往灰烬之地',156,45,'ash_land','from_wild')],zones=[zone('A',27,42,18,'狼12 / 虫6'),zone('B',76,18,18,'狼12 / 虫6'),zone('C',128,25,18,'狼12 / 虫6'),zone('D',78,73,18,'狼12 / 虫6')],points=[point('carter','驿站',14,47,'npc'),point('elite_bug_1','精英虫①',31,68,'elite'),point('elite_bug_2','精英虫②',117,13,'elite'),point('wolf_king','裂爪狼王',142,73,'elite'),point('relic','虫蚀石碑',119,31)],routes=[[(8,45),(30,45),(39,57),(78,57),(88,28),(123,28),(142,45),(152,45)],[(30,45),(30,13),(69,13),(69,28),(88,28)],[(39,57),(48,76),(87,76),(88,28)]],normal=72,elite=3,boss=0),
 dict(name='灰烬之地',id='ash_land',chapter=1,size=[192,108],concept='长街贯通三段废墟，北街与南庭院连成可循环的支路',blocks=[rect(35,23,29,14),rect(90,44,29,18),rect(67,55,16,17),rect(125,14,14,12),rect(15,0,18,8),rect(78,82,18,8)],exits=[exit('to_wild','回试炼野外',4,45,'wild_trial','from_ash'),exit('to_source','往腐化源头',156,45,'corruption_source','from_ash')],zones=[zone('A',25,43,16,'魂10 / 虫6'),zone('B',74,14,16,'魂10 / 虫6'),zone('C',145,33,16,'魂10 / 虫6'),zone('D',76,44,16,'魂10 / 虫6'),zone('E',42,73,16,'魂10 / 虫6'),zone('F',132,75,16,'魂10 / 虫6')],points=[point('carter','驿站 / 货郎',14,48,'npc'),point('elite_wraith_1','精英魂①',28,15,'elite'),point('elite_wraith_2','精英魂②',145,74,'elite'),point('elite_bug_1','精英虫①',58,77,'elite'),point('elite_bug_2','精英虫②',113,15,'elite'),point('memorial','旧镇脉告示',83,26)],routes=[[(8,45),(29,45),(77,44),(85,33),(121,33),(146,45),(152,45)],[(29,45),(29,14),(77,14),(85,33)],[(29,45),(34,76),(59,77),(86,77),(123,74),(146,45)]],normal=96,elite=4,boss=0),
 dict(name='腐化源头',id='corruption_source',chapter=1,size=[160,90],concept='横向串联前庭、两侧洞室、封印外环和独立巨兽场地',blocks=[rect(33,0,13,31),rect(64,61,14,29),rect(86,14,14,16),rect(101,67,13,17),rect(0,0,14,11),rect(147,0,13,10)],exits=[exit('to_ash','回灰烬之地',4,45,'ash_land','from_source')],zones=[zone('A',24,45,12,'虫8 / 魂4'),zone('B',65,20,12,'虫8 / 魂4'),zone('C',51,74,12,'虫8 / 魂4'),zone('D',93,45,12,'虫8 / 魂4')],points=[point('carter','安全前室 / 驿站',14,49,'npc'),point('elite_bug_1','精英虫①',45,65,'elite'),point('elite_bug_2','精英虫②',105,34,'elite'),point('elite_wraith_1','精英魂①',77,20,'elite'),point('elite_wraith_2','精英魂②',85,74,'elite'),point('gate','封印观察点',113,45),point('beast','腐化巨兽',136,45,'boss')],arenas=[dict(center=[136,45],radius=14)],routes=[[(8,45),(25,45),(51,45),(81,45),(109,45),(119,45),(136,45)],[(25,45),(24,65),(52,76),(54,48)],[(51,45),(55,19),(77,20),(81,45)]],normal=48,elite=4,boss=1),
 dict(name='沉井镇',id='c2_well_town',chapter=2,size=[96,54],concept='西进东出的炉塔长街，八名人物围绕集中服务区而非分散四角',blocks=[rect(40,11,22,15),rect(91,11,23,15),rect(41,64,23,14),rect(96,64,22,14),rect(73,38,10,13),rect(10,0,22,10),rect(132,80,22,10)],exits=[exit('to_camp','回幸存者营地',4,45,'camp','from_c2'),exit('to_slope','往断管坡',156,45,'c2_pipe_slope','from_town')],zones=[],points=[point('tower','中央炉塔',78,44),point('lu_heng','陆衡 / 工程师',94,44,'npc'),point('bai_zhi','白芷 / 药师',65,31,'npc'),point('xu_zhu','许铸 / 铁匠',92,31,'npc'),point('mi_cang','米仓 / 仓库',115,32,'npc'),point('a_xu','阿絮 / 杂货',63,56,'npc'),point('qi_yan','祁言 / 记录员',93,58,'npc'),point('miao_miao','苗苗 / 汤棚',45,37,'npc'),point('carter','老辙 / 车夫',115,55,'npc'),point('backup','备用炉预留',79,72)],routes=[[(8,45),(66,45),(66,31),(87,31),(87,45),(152,45)],[(66,45),(66,59),(115,59),(115,45)],[(66,59),(71,77),(91,77),(93,58)]],normal=0,elite=0,boss=0),
 dict(name='旧汲灵井',id='c2_old_well',chapter=2,size=[224,126],concept='两座干井横向并列，平台上下贯通，最右端是监工调压台',blocks=[rect(46,29,19,31),rect(92,27,18,30),rect(13,0,19,12),rect(73,78,18,12)],exits=[exit('to_slope','回断管坡',4,45,'c2_pipe_slope','from_well'),exit('to_works','往工坊下层',156,45,'c2_lower_works','from_well')],zones=[zone('A',29,24,30,'幼虫10 / 铜壳8 / 守卫8 / 喷渣4'),zone('B',79,68,30,'幼虫10 / 铜壳8 / 守卫8 / 喷渣4'),zone('C',121,19,30,'幼虫10 / 铜壳8 / 守卫8 / 喷渣4')],points=[point('carter','入口平台 / 驿站',15,48,'npc'),point('pit_1','干井口①',55,44),point('pit_2','干井口②',101,42),point('elite_bug','铜壳母虫',39,73,'elite'),point('elite_guard','断链巡检长',81,16,'elite'),point('elite_fast','汲灵护卫',119,70,'elite'),point('foreman','镇井监工铁臂',137,46,'boss')],arenas=[dict(center=[137,46],radius=13)],routes=[[(8,45),(29,45),(30,17),(77,17),(78,68),(119,68),(137,46),(152,45)],[(29,45),(31,69),(78,68)],[(77,17),(119,17),(119,68)]],normal=90,elite=3,boss=1),
 dict(name='工坊下层',id='c2_lower_works',chapter=2,size=[240,135],concept='沿长轴依次布置车间与废料场，三路循环，南侧接炉房',blocks=[rect(40,20,20,15),rect(92,18,20,22),rect(68,56,16,20),rect(120,61,18,15),rect(10,0,18,8),rect(18,82,21,8)],exits=[exit('to_well','回旧汲灵井',4,45,'c2_old_well','from_works'),exit('to_core','往井心机室',156,45,'c2_well_core','from_works'),exit('to_furnace','往余烬炉房',91,86,'c2_ember_furnace','from_works')],zones=[zone('A',27,29,20,'守卫8 / 游魂4 / 喷渣4 / 侍虫4'),zone('B',74,15,20,'守卫8 / 游魂4 / 喷渣4 / 煤灰4'),zone('C',135,31,24,'守卫8 / 游魂8 / 喷渣4 / 侍虫4'),zone('D',77,44,20,'守卫4 / 游魂8 / 喷渣4 / 煤灰4'),zone('E',36,70,20,'守卫8 / 游魂4 / 侍虫4 / 煤灰4'),zone('F',104,75,24,'守卫4 / 游魂4 / 喷渣8 / 侍虫4 / 煤灰4')],points=[point('carter','驿站 / 补给摊',15,48,'npc'),point('elite_guard','断链巡检长',30,58,'elite'),point('elite_scribe','灰印书记',124,13,'elite'),point('elite_beast','煤灰头领',143,77,'elite'),point('gate','井心封锁阀',147,45)],routes=[[(8,45),(29,45),(76,45),(118,45),(152,45)],[(29,45),(29,12),(76,12),(83,45)],[(29,45),(32,76),(60,79),(89,79),(106,79),(114,58),(118,45)],[(89,79),(91,82)]],normal=128,elite=3,boss=0),
 dict(name='余烬炉房',id='c2_ember_furnace',chapter=2,size=[160,90],concept='纵长熔坑把主线外炉与右端可选内炉分开，上下热管桥连通',blocks=[rect(61,29,26,36),rect(22,28,16,12),rect(28,65,15,11),rect(110,14,15,11),rect(10,0,23,8),rect(110,81,18,9)],exits=[exit('to_works','回工坊下层',91,4,'c2_lower_works','from_furnace')],zones=[zone('A',45,15,18,'煤灰8 / 铜壳6 / 喷渣4'),zone('B',48,77,18,'煤灰8 / 铜壳6 / 喷渣4'),zone('C',103,42,18,'煤灰8 / 铜壳6 / 喷渣4')],points=[point('carter','驿站 / 安全入口',82,11,'npc'),point('pit','中央熔坑',74,47),point('component','主线组件工作台',47,52),point('elite_bug','铜壳母虫',49,61,'elite'),point('slag','可选炉渣吞噬者',137,46,'boss'),point('observe','内炉观察点',116,47)],arenas=[dict(center=[137,46],radius=13)],routes=[[(91,8),(91,15),(46,15),(46,50),(48,77),(100,77),(102,43),(91,15)],[(46,15),(15,17),(14,51),(48,50)],[(102,43),(116,47),(137,46)]],normal=54,elite=1,boss=1),
 dict(name='井心机室',id='c2_well_core',chapter=2,size=[208,117],concept='左侧外围与两翼维护回路，右侧主机场，与长轴一致推进',blocks=[rect(41,0,13,34),rect(43,62,15,28),rect(88,23,14,13),rect(86,60,13,15),rect(147,0,13,10)],exits=[exit('to_works','回工坊下层',4,45,'c2_lower_works','from_core')],zones=[zone('A',28,45,12,'寄生6 / 守卫4 / 侍虫2'),zone('B',69,18,12,'寄生6 / 守卫4 / 侍虫2'),zone('C',68,76,12,'寄生6 / 守卫4 / 侍虫2')],points=[point('carter','前室 / 驿站',14,50,'npc'),point('elite_fast','汲灵护卫',110,18,'elite'),point('elite_beast','煤灰头领',110,75,'elite'),point('gate','主机安全锁',115,45),point('extractor','百臂汲灵机',136,45,'boss')],arenas=[dict(center=[136,45],radius=14)],routes=[[(8,45),(28,45),(62,45),(107,45),(119,45),(136,45)],[(28,45),(28,17),(34,17),(34,42),(62,42),(65,17),(109,17),(108,45)],[(28,45),(28,75),(36,75),(36,50),(62,50),(63,79),(108,79),(108,45)]],normal=36,elite=2,boss=1),
]
# Keep chapter order explicit for previews and documents.
order=['camp','wild_trial','ash_land','corruption_source','c2_well_town','c2_pipe_slope','c2_old_well','c2_lower_works','c2_ember_furnace','c2_well_core']
# The slope is defined separately to make its ravine layout distinct from chapter-one rocks.
plans.append(dict(name='断管坡',id='c2_pipe_slope',chapter=2,size=[192,108],concept='横向山坡由两段错位断崖分隔，主管路与废料回路并行',blocks=[[(41,20),(70,15),(76,32),(64,48),(40,43)],[(94,44),(117,36),(126,49),(119,69),(94,70)],rect(18,80,20,10),rect(84,0,13,12)],exits=[exit('to_town','回沉井镇',4,45,'c2_well_town','from_slope'),exit('to_well','往旧汲灵井',156,45,'c2_old_well','from_slope')],zones=[zone('A',25,34,21,'幼虫11 / 铜壳5 / 守卫5'),zone('B',77,18,21,'幼虫11 / 铜壳5 / 守卫5'),zone('C',132,27,21,'幼虫10 / 铜壳6 / 守卫5'),zone('D',75,76,21,'幼虫10 / 铜壳5 / 守卫6')],points=[point('carter','驿站 / 石岑',14,49,'npc'),point('elite_guard','断链巡检长',34,67,'elite'),point('elite_bug','铜壳母虫',137,73,'elite'),point('pipe','主管裂口',83,47)],routes=[[(8,45),(26,45),(37,56),(82,56),(84,27),(130,27),(146,45),(152,45)],[(26,45),(26,13),(78,13),(84,27)],[(37,56),(48,77),(86,77),(86,56)]],normal=84,elite=2,boss=0))
plans.sort(key=lambda p:order.index(p['id']))

def scale_plan(p):
 w,h=p['size'];f=w/160
 def cv(v):return [round(v[0]*f),round(v[1]*f)]
 q={k:v for k,v in p.items() if k not in ('blocks','routes','zones','points','exits','arenas')}
 q.update(layoutVersion='2026-10-14-landscape-v2',coordinateSpace='orthographic_grid',aspectRatio='16:9')
 q['blocks']=[[cv(v) for v in b] for b in p['blocks']]
 q['zones']=[dict(z,center=cv(z['center'])) for z in p['zones']]
 q['points']=[dict(t,cell=cv(t['cell'])) for t in p['points']]
 q['exits']=[dict(e,cell=cv(e['cell'])) for e in p['exits']]
 q['arenas']=[dict(center=cv(a['center']),radius=round(a['radius']*f,2)) for a in p.get('arenas',[])]
 q['routeWaypoints']=[[cv(v) for v in r] for r in p['routes']]
 return q

def occupancy(q):
 w,h=q['size'];im=Image.new('1',(w,h),1);d=ImageDraw.Draw(im)
 for b in q['blocks']:d.polygon(b,fill=0)
 return im

def path(im,start,end):
 w,h=im.size;start=tuple(start);end=tuple(end)
 if not im.getpixel(start) or not im.getpixel(end):raise ValueError(('Point in obstacle',start,end))
 pq=[(0,0,start)];cost={start:0};prev={}
 while pq:
  _,g,u=heapq.heappop(pq)
  if g!=cost[u]:continue
  if u==end:
   r=[u]
   while r[-1]!=start:r.append(prev[r[-1]])
   return list(reversed(r))
  for dx,dy in [(1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)]:
   v=(u[0]+dx,u[1]+dy)
   if not(0<=v[0]<w and 0<=v[1]<h) or not im.getpixel(v):continue
   if dx and dy and (not im.getpixel((u[0]+dx,u[1])) or not im.getpixel((u[0],u[1]+dy))):continue
   step=math.hypot((dx-dy)*32,(dx+dy)*16);ng=g+step
   if ng<cost.get(v,1e30):
    cost[v]=ng;prev[v]=u
    ex,ey=end[0]-v[0],end[1]-v[1]
    heapq.heappush(pq,(ng+math.hypot((ex-ey)*32,(ex+ey)*16),ng,v))
 raise ValueError(('Unreachable',start,end))

def render(q):
 folder=BASE/('第一章地图重设计示意图' if q['chapter']==1 else '地图示意图');folder.mkdir(exist_ok=True)
 w,h=q['size'];sx=1920/w;sy=1080/h
 def xy(v,off=(160,175)):return (round(off[0]+v[0]*sx),round(off[1]+v[1]*sy))
 mask=Image.new('RGB',(1920,1080),GREEN);md=ImageDraw.Draw(mask)
 for b in q['blocks']:md.polygon([xy(v,(0,0)) for v in b],fill=BLACK)
 mask.save(folder/(q['name']+'-导航参考.png'))
 pure=mask.copy();d=ImageDraw.Draw(pure)
 for e in q['exits']:
  x,y=xy(e['cell'],(0,0));d.ellipse((x-13,y-13,x+13,y+13),fill='#ef4438')
 pure.save(folder/(q['name']+'-纯色布局.png'))
 im=Image.new('RGB',(2240,1470),'#f6f4ef');im.paste(mask,(160,175));d=ImageDraw.Draw(im)
 d.text((160,35),f"第{q['chapter']}章 · {q['name']}   {w}×{h}逻辑格  |  横向16:9",font=TITLE,fill='#172b28')
 d.text((160,96),q['concept'],font=FONT,fill='#36544b')
 for route in q['routes']:
  d.line([xy(v) for v in route],fill='#f5e8ab',width=6)
 for a in q['arenas']:
  x,y=xy(a['center']);rx=a['radius']*sx;ry=a['radius']*sy
  d.ellipse((x-rx,y-ry,x+rx,y+ry),outline='#d6a3a3',width=4)
 labels=[]
 for z in q['zones']:
  x,y=xy(z['center']);d.ellipse((x-30,y-30,x+30,y+30),outline='#235a43',width=3)
  labels.append((z['id']+'区 '+str(z['normalCount'])+'只 | '+z['composition'],x,y,'zone'))
 colors={'npc':'#216f9a','elite':'#bd8224','boss':'#b34046','landmark':'#42674f','exit':'#df3d30'}
 for p in q['points']+ [dict(e,kind='exit') for e in q['exits']]:
  x,y=xy(p['cell']);c=colors[p['kind']];r=11 if p['kind']!='boss' else 17
  if p['kind']=='elite':d.polygon([(x,y-r-3),(x+r+3,y),(x,y+r+3),(x-r-3,y)],fill=c)
  else:d.ellipse((x-r,y-r,x+r,y+r),fill=c)
  labels.append((p['label'],x,y,p['kind']))
 used=[]
 for text,x,y,kind in labels:
  tw=d.textbbox((0,0),text,font=FONT)[2]+18;th=37
  chosen=None
  for dx,dy in [(0,-56),(0,20),(30,-17),(-tw-30,-17),(0,-105),(0,65),(0,-150),(0,110),(70,-65),(-70,65)]:
   lx=max(165,min(2075-tw,x-tw/2+dx));ly=max(180,min(1215,y+dy));box=(lx,ly,lx+tw,ly+th)
   if all(box[2]<b[0]-6 or box[0]>b[2]+6 or box[3]<b[1]-5 or box[1]>b[3]+5 for b in used):chosen=box;break
  if chosen is None:chosen=(max(165,min(2075-tw,x-tw/2)),min(1215,y+140),max(165,min(2075-tw,x-tw/2))+tw,min(1215,y+140)+th)
  used.append(chosen);lx,ly,rx,by=chosen
  d.line([(x,y),((lx+rx)/2,(ly+by)/2)],fill='#edf1df',width=2)
  d.rounded_rectangle(chosen,radius=5,fill='#fffdf0',outline='#637b68',width=1)
  d.text((lx+9,ly+4),text,font=FONT,fill='#23372f')
 # Keep exit anchors visible independent of labels.
 for e in q['exits']:
  x,y=xy(e['cell']);d.ellipse((x-12,y-12,x+12,y+12),fill='#ef4438')
 d.text((160,1300),'绿色：可走区域   深色：障碍   红：出口   蓝：NPC   金：精英   红褐：Boss',font=FONT,fill='#23372f')
 d.text((160,1350),f"普通刷新位 {q['normal']}   精英 {q['elite']}   Boss {q['boss']}   |   浅线为参考路线，圆环为Boss场；标注不写入导航",font=FONT,fill='#23372f')
 d.text((160,1400),'正交规划图；游戏内转换等距坐标。路径为静态点导航参考，未代替角色净宽和实机体验验收。',font=SMALL,fill='#53665b')
 im.save(folder/(q['name']+'-标注示意.png'))
 (folder/(q['name']+'-布局参考.json')).write_text(json.dumps(q,ensure_ascii=False,indent=2)+'\n')
 return folder

if __name__=='__main__':
 summary=[]
 for p in plans:
  q=scale_plan(p);im=occupancy(q)
  q['entrances']={}
  for source in plans:
   for outgoing in source['exits']:
    if outgoing['toMap']!=q['id']:continue
    reverse=next(e for e in q['exits'] if e['toMap']==source['id'])
    x,y=reverse['cell'];w,h=q['size']
    edge=min([(x,'left'),(w-1-x,'right'),(y,'top'),(h-1-y,'bottom')])[1]
    dx,dy={'left':(4,0),'right':(-4,0),'top':(0,4),'bottom':(0,-4)}[edge]
    q['entrances'][outgoing['toEntrance']]=[x+dx,y+dy]
  carter=next(t for t in q['points'] if t['id']=='carter')
  q['carterArrival']=[carter['cell'][0],carter['cell'][1]+3]
  # Structural checks for generated product diagrams, not game tests.
  points=q['exits']+[p for p in q['points'] if p['kind']!='landmark']+q['zones']
  root=q['exits'][0]['cell']
  for t in points:path(im,root,t.get('cell',t.get('center')))
  for arrival in list(q['entrances'].values())+[q['carterArrival']]:path(im,root,arrival)
  routes=[];lengths=[]
  for r in q['routeWaypoints']:
   full=[]
   for a,b in zip(r,r[1:]):
    seg=path(im,a,b);full.extend(seg if not full else seg[1:])
   compact=[full[0]]
   for i in range(1,len(full)-1):
    previous=(full[i][0]-full[i-1][0],full[i][1]-full[i-1][1])
    following=(full[i+1][0]-full[i][0],full[i+1][1]-full[i][1])
    if previous!=following:compact.append(full[i])
   compact.append(full[-1])
   routes.append([list(v) for v in compact]);lengths.append(round(sum(math.hypot((b[0]-a[0]-b[1]+a[1])*32,(b[0]-a[0]+b[1]-a[1])*16) for a,b in zip(full,full[1:]))/256,1))
  q['routes']=routes;q['referenceRouteSecondsAt256']=lengths
  q['walkableRatio']=round(im.convert('L').histogram()[255]/(q['size'][0]*q['size'][1]),3)
  folder=render(q)
  summary.append({k:q[k] for k in ['id','name','chapter','size','normal','elite','boss','walkableRatio','referenceRouteSecondsAt256']})
  print(q['name'],q['size'],'可走比例',q['walkableRatio'],'参考路线秒',lengths)
 (BASE/'地图制作工具'/'两章地图规格汇总.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
