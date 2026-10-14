#!/usr/bin/env python3
"""由设计JSON制作25图PNG总览和HTML索引；Pillow仅绘制坐标，不编辑游戏美术或运行素材。
运行前先执行生成内容包.py；使用带Pillow的Python。只覆盖本包地图总览.png与地图预览.html。
"""
import json, html
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]


def font(size):
    """优先系统中文字体，允许通过已知标准字体回退，确保总览标签可读。"""
    for path in ['/System/Library/Fonts/STHeiti Medium.ttc','/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc']:
        if Path(path).exists():return ImageFont.truetype(path,size)
    raise RuntimeError('需要可用中文字体以输出总览')


def main():
    """绘制地图缩略图并生成逐图可打开的产品参考页。"""
    data=json.loads((ROOT/'制作工具/内容总表.json').read_text());cs=data['chapters']
    image=Image.new('RGB',(2000,1590),'#f4f6f8');d=ImageDraw.Draw(image)
    d.text((30,18),'21—60级 · 25张地图布局总览',font=font(30),fill='#142c3d')
    d.text((30,59),'正交横向16:9 · 黑=障碍 红=出口 白=NPC 黄=精英 紫圈=Boss · 非最终贴图',font=font(19),fill='#405466')
    allmaps=[(c,m) for c in cs for m in c['maps']]
    for i,(c,m) in enumerate(allmaps):
        col,row=i%5,i//5;x=22+col*397;y=110+row*294
        d.text((x,y),f'{i+1:02} {m["name"]}  {m["w"]}×{m["h"]}',font=font(17),fill='#203743')
        top=y+30;ww,hh=374,210;scale=ww/m['w'];xy=lambda p:(round(x+p[0]*scale),round(top+p[1]*scale))
        d.rectangle((x,top,x+ww,top+hh),fill='#65ae76')
        for poly in m['obstacles']:d.polygon([xy(p) for p in poly],fill='#15191a')
        for p in m['spawns']:
            a,b=xy(p['cell']);d.ellipse((a-1,b-1,a+1,b+1),fill='#20516e')
        for e in m['elites']:
            a,b=xy(e['cell']);d.ellipse((a-3,b-3,a+3,b+3),fill='#f4c646')
        for p in c['npcs']:
            if p['map']==m['id']:
                a,b=xy(p['cell']);d.rectangle((a-2,b-2,a+2,b+2),fill='white')
        for b in c['bosses']:
            if b['map']==m['id']:
                a,z=xy(b['cell']);r=b['radius']*scale;d.ellipse((a-r,z-r,a+r,z+r),outline='#9d246a',width=2)
        for e in m['exits']:
            a,b=xy(e['cell']);d.ellipse((a-3,b-3,a+3,b+3),fill='#df303b')
        d.text((x,top+219),f'第{c["n"]}章  普通{m["normalSlots"]}位 / 精英{m["eliteSlots"]} / Boss{len(m["bosses"])}',font=font(15),fill='#405466')
    image.save(ROOT/'地图总览.png')
    page=['<!doctype html><html lang="zh"><meta charset="utf-8"><title>21—60级地图参考</title><style>body{font:16px system-ui;max-width:1440px;margin:32px auto;padding:0 20px;background:#f4f6f8;color:#182e3b}nav{position:sticky;top:0;background:#fff;padding:16px}a{color:#245b93;margin-right:16px}section{background:white;margin:24px 0;padding:24px;border-radius:12px}img{max-width:100%;height:auto}h3{scroll-margin-top:80px}code{color:#516272}</style><h1>21—60级地图参考</h1><p>25图规划参考，不是最终美术或游戏可运行导航。红出口/白NPC/黄精英/紫首领/蓝普通位；原尺寸SVG可供美术AI参考。</p><nav>']
    for c in cs:page.append(f'<a href="#c{c["n"]}">第{c["n"]}章 {c["title"]}</a>')
    page.append('</nav><img src="地图总览.png" alt="25图总览">')
    for c in cs:
        page.append(f'<section id="c{c["n"]}"><h2>第{c["n"]}章 {c["title"]}</h2>')
        for m in c['maps']:
            prefix=f'{c["folder"]}/地图参考/{m["id"]}'
            page.append(f'<h3>{html.escape(m["name"])}</h3><p>{html.escape(m["description"])}</p><p><a href="{prefix}-标注.svg">标注图</a><a href="{prefix}-纯布局.svg">纯布局图</a><a href="{prefix}.json">结构化坐标</a></p><img loading="lazy" src="{prefix}-标注.svg" alt="{m["name"]}">')
        page.append('</section>')
    page.append('</html>');(ROOT/'地图预览.html').write_text('\n'.join(page))
    print('已生成25图预览与PNG总览')


if __name__=='__main__':
    main()
