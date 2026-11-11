"""为博客生成确定性中文解释图；读取 diagram_specs.json，不修改游戏资源。
依赖 Pillow 与 macOS 黑体。输出每篇两张 1500×1000 PNG，自动检查文字边界。
运行：uv run --with pillow python docs/blogs/assets/game/editorial/render_diagrams.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json,math,hashlib
A=Path(__file__).resolve().parent
FONT='/System/Library/Fonts/STHeiti Medium.ttc'
NAVY='#1c3345';AMBER='#bd782b';PALE='#edf2f5';BLUE='#557489';INK='#233d50'

# 按像素宽度换行，保留显式换行，不用字符数猜测英文宽度。
def wrap(draw,text,font,width):
 lines=[]
 for para in text.split('\n'):
  line=''
  for c in para:
   if draw.textlength(line+c,font=font)>width and line:lines.append(line);line=c
   else:line+=c
  lines.append(line)
 return lines

# 在给定盒内绘制文本；高度不足直接报错，禁止悄悄截断。
def textbox(d,box,text,size=36,color=INK,center=False):
 x,y,w,h=box;f=ImageFont.truetype(FONT,size);lines=wrap(d,text,f,w);lh=int(size*1.5)
 assert len(lines)*lh<=h,(text,box,len(lines)*lh)
 for line in lines:
  px=x+(w-d.textlength(line,font=f))/2 if center else x
  d.text((px,y),line,font=f,fill=color);y+=lh

# 画有向连接，箭头仅用于规格明确的顺序或变换关系。
def arrow(d,a,b,color=AMBER,width=5):
 d.line([a,b],fill=color,width=width);ang=math.atan2(b[1]-a[1],b[0]-a[0]);r=15
 d.polygon([b,(b[0]-r*math.cos(ang-.5),b[1]-r*math.sin(ang-.5)),(b[0]-r*math.cos(ang+.5),b[1]-r*math.sin(ang+.5))],fill=color)

# 创建固定版式基础，正文图采用浅底以保证段落内阅读。
def canvas(spec):
 im=Image.new('RGB',(1500,1000),'#f3f5f5');d=ImageDraw.Draw(im)
 for x in range(-1000,2000,80):d.line((x,940,x+1100,390),fill='#e5ebed',width=1)
 d.rectangle((0,0,1500,104),fill=NAVY)
 textbox(d,(60,25,1100,70),'末法纪元 · 游戏开发  /  '+spec['article'],32,'#f6e8cf')
 textbox(d,(60,145,1380,150),spec['title'],49,NAVY)
 d.rounded_rectangle((60,790,1440,928),18,fill='#e8edf0')
 d.rectangle((60,790,68,928),fill=AMBER)
 textbox(d,(95,810,1310,110),spec['note'],30)
 textbox(d,(60,954,1380,40),'FungLeo  ·  机制示意，非游戏截图或实测数据',22,BLUE)
 return im,d

# 根据布局语义生成图，不将并列要点误画成必然的时间顺序。
def render(s):
 im,d=canvas(s);kind=s['layout'];nodes=s['nodes']
 if kind=='compare':
  for i,text in enumerate(nodes):
   x=60+i*710
   d.rounded_rectangle((x,320,x+670,725),22,fill='white',outline='#b9c8d0',width=2)
   d.rounded_rectangle((x+26,344,x+102,402),10,fill=NAVY if i==0 else AMBER)
   textbox(d,(x+26,350,76,50),chr(65+i),30,'white',True)
   title,sep,body=text.partition('：')
   if sep:
    textbox(d,(x+30,432,610,110),title,40,NAVY)
    textbox(d,(x+30,551,610,164),body,33)
   else:textbox(d,(x+30,432,610,270),text,36)
 elif kind in ('flow','columns'):
  n=len(nodes);gap=38;w=(1380-gap*(n-1))/n
  for i,text in enumerate(nodes):
   x=60+i*(w+gap)
   d.rounded_rectangle((x,350,x+w,680),18,fill='white',outline='#b9c8d0',width=2)
   textbox(d,(x+20,375,w-40,70),f'{i+1:02}',38,AMBER)
   textbox(d,(x+22,473,w-44,195),text,34,NAVY,True)
   if kind=='flow' and i<n-1:arrow(d,(x+w+5,515),(x+w+gap-5,515))
  if kind=='columns':
   d.line((85,723,1415,723),fill=BLUE,width=3)
   for i in range(n):
    x=60+i*(w+gap)+w/2;d.line((x,688,x,723),fill=BLUE,width=3)
 elif kind in ('geometry','area'):
  cx1,cx2,cy=385,1105,520;r=160
  rx,ry=(r,r/2) if kind=='geometry' else (r*math.sqrt(2),r/math.sqrt(2))
  for cx in [cx1,cx2]:
   d.line((cx-260,cy,cx+260,cy),fill='#a8bbc6',width=2);d.line((cx,cy-215,cx,cy+215),fill='#a8bbc6',width=2)
  d.ellipse((cx1-r,cy-r,cx1+r,cy+r),outline=BLUE,width=6)
  d.ellipse((cx2-rx,cy-ry,cx2+rx,cy+ry),outline=AMBER,width=6)
  arrow(d,(630,520),(810,520))
  textbox(d,(150,285,470,65),nodes[0],34,NAVY,True);textbox(d,(855,285,500,65),nodes[1],34,NAVY,True)
  textbox(d,(160,720,460,60),'半径 r',30,BLUE,True)
  textbox(d,(850,720,510,60),'横纵直径比 2:1' if kind=='geometry' else '面积均为 πr²',30,AMBER,True)
 elif kind=='corner':
  for k,cx in enumerate([200,910]):
   cy=365;cell=105
   for y in range(3):
    for x in range(3):
     blocked=k==0 and (x,y) in [(1,0),(0,1)]
     d.rectangle((cx+x*cell,cy+y*cell,cx+(x+1)*cell-4,cy+(y+1)*cell-4),fill=NAVY if blocked else '#dde7eb',outline='white',width=2)
   a=(cx+50,cy+50);b=(cx+155,cy+155)
   arrow(d,a,b,AMBER)
   if k==0:
    d.line((cx+75,cy+75,cx+130,cy+130),fill='#b64837',width=10);d.line((cx+130,cy+75,cx+75,cy+130),fill='#b64837',width=10)
   textbox(d,(cx-90,700,500,70),nodes[k],30,NAVY,True)
 elif kind=='camera':
  # 无单位递推算例，不冒充引擎测量；初值0，固定目标1。
  for k,cx in enumerate([100,820]):
   d.line((cx,665,cx+540,665),fill=BLUE,width=2)
   ty=435;d.line((cx,ty,cx+540,ty),fill='#b8c7cc',width=2)
   vals=[0.0];alpha=1.5 if k==0 else .35
   for _ in range(9):vals.append(vals[-1]+alpha*(1-vals[-1]))
   pts=[(cx+j*58,665-v*230) for j,v in enumerate(vals)]
   d.line(pts,fill=AMBER if k==0 else BLUE,width=5)
   for x,y in pts:d.ellipse((x-6,y-6,x+6,y+6),fill=AMBER if k==0 else BLUE)
   textbox(d,(cx,295,550,70),nodes[k],36,NAVY,True)
   textbox(d,(cx,700,550,70),'示例系数 1.5' if k==0 else '示例系数 0.35',29,BLUE,True)
 else:raise ValueError(kind)
 dest=A.parent/s['article']/(s['name']+'.png');dest.parent.mkdir(parents=True,exist_ok=True);im.save(dest)
 return {'id':s['id'],'path':str(dest.relative_to(A.parent.parent.parent)),'size':[1500,1000],'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'textBounds':'passed','method':'Pillow deterministic diagram'}

if __name__=='__main__':
 specs=json.loads((A/'diagram_specs.json').read_text());results=[render(s) for s in specs]
 (A/'diagram_render_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
 print('Rendered',len(results),'diagrams; all text bounds passed.')
