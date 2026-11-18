"""从正式营地白盒道路编译模块地面掩码；不改变碰撞、NPC、出口或存档坐标。"""
import argparse
import json
import math
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]


def build():
    """将画布道路折线映射到世界，64×32格心采样；返回确定性道路和草地掩码。"""
    source = json.loads((ROOT/'data/map_art/camp_whitebox_v2.json').read_text())
    x0,y0,w,h = source['world_rect']
    cw,ch = source['reference_canvas']
    paths = [[(x0+x/cw*w,y0+y/ch*h) for x,y in path] for path in [source['main_road'],*source['branches']]]
    roads=[]
    grass=[]
    for y in range(source['grid_size'][1]):
        row=''
        for x in range(source['grid_size'][0]):
            px,py=(x-y)*32,-(x+y)*16
            distance=1e9
            for path in paths:
                for (ax,ay),(bx,by) in zip(path,path[1:]):
                    dx,dy=bx-ax,by-ay
                    t=max(0,min(1,((px-ax)*dx+(py-ay)*dy)/(dx*dx+dy*dy)))
                    distance=min(distance,math.hypot(px-ax-t*dx,py-ay-t*dy))
            row+='1' if distance<=36 else '0'
        roads.append(row)
        grass.append(''.join('0' if value=='1' else '1' for value in row))
    return {'layout_id':source['id'],'tile_size':[64,32],'roads':roads,'grass':grass}


def main():
    """默认重建；--check精确比较源布局编译结果，拒绝过期掩码。"""
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    target=ROOT/'data/map_art/camp_modular_v1.json'
    result=json.dumps(build(),ensure_ascii=False,indent=2)+'\n'
    if args.check:
        assert target.read_text()==result,'营地模块掩码需重新构建'
    else:
        target.write_text(result)
    print('CAMP_MODULAR_LAYOUT_OK')


if __name__=='__main__':
    main()
