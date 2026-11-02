"""用当前营地v2布局重建独立A/B样板，不覆盖正式游戏仍引用的旧B样板素材。

复用既有源图与分层构建函数；新输出assets/maps/camp_style_sample_v2/，四段训练场
栅栏直接引用正式v2清单，禁止重画已经取消碰撞的外围岩带和栅栏。
"""
import json
import shutil
import tempfile
from pathlib import Path
from build_camp_style_sample import write_ground, write_split_object

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/maps/camp_style_sample_v2"


def main():
    """统一使用正式足迹、艺术矩形和脚底坐标生成样板，透明层切分不改地图事实源。"""
    if shutil.which("magick") is None:
        raise RuntimeError("需要ImageMagick")
    layout = json.loads((ROOT / "data/map_art/camp_whitebox_v2.json").read_text())
    formal = json.loads((ROOT / "assets/maps/camp_style_full_b_v2/manifest.json").read_text())
    entities = {e["id"]: e for e in layout["entities"]}
    objects = {e["id"]: e for e in formal["objects"]}
    cuts = {"blacksmith":153,"merchant":120,"elder_tree":130}
    for style, scale in [("a",1),("b",2)]:
        output = OUTPUT / style
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="camp-sample-v2-") as scratch:
            write_ground(style,scale,output,Path(scratch),layout)
            generated = []
            for name, cut in cuts.items():
                entry = entities[name]
                result = write_split_object(style,scale,name,{"rect":entry["art_rect"],"cut":cut,"foot_y":entry["art_foot_y"]},output,Path(scratch))
                for layer in ["back","front"]:
                    result[layer] = result[layer].replace("camp_style_sample/","camp_style_sample_v2/")
                generated.append(result)
        generated.extend(objects[f["id"]] for f in layout["fences"])
        manifest = {"style":style.upper(),"layout_id":layout["id"],"canvas":layout["reference_canvas"],
                    "patch":[0,60,1250,790],"ground":f"res://assets/maps/camp_style_sample_v2/{style}/ground.png","objects":generated}
        (output / "manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
        print(f"v2样板{style}: 三个整体实体与四段正式训练栅栏")


if __name__ == "__main__":
    main()
