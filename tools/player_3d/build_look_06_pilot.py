"""构建 60 级角色的三维动作试验源文件与审稿帧。

该脚本仅产出 art_source 下的可编辑 Blender 工程和预览，不覆盖游戏图集。
使用 Blender 5.2.3 验证；在仓库根目录执行：blender -b -t 4 --python tools/player_3d/build_look_06_pilot.py
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path.cwd()
OUTPUT = ROOT / "art_source/player/look_06/3d_pilot"
OUTPUT.mkdir(parents=True, exist_ok=True)


def material(name: str, color: tuple[float, float, float], metallic: float = 0.0) -> bpy.types.Material:
    """为所有共享零件建立可审查的固定材质；颜色使用线性 RGB。"""
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*color, 1.0)
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = 0.72 if metallic < 0.3 else 0.47
    return result


DARK = material("布料·炭黑", (0.095, 0.083, 0.078))
STONE = material("旧石甲·灰白", (0.57, 0.54, 0.48), 0.22)
EDGE = material("石甲暗边", (0.29, 0.275, 0.25), 0.22)
GOLD = material("分流纹·旧金", (0.55, 0.39, 0.17), 0.65)
SCARF = material("旧沙色围巾", (0.54, 0.45, 0.34))
HAIR = material("乱黑发", (0.065, 0.064, 0.062))
SKIN = material("面部", (0.65, 0.43, 0.32))
CYAN = material("青白灵能石", (0.025, 0.50, 0.63), 0.18)
PURPLE = material("甲面紫色旧伤", (0.30, 0.11, 0.39))


def empty(name: str, location=(0.0, 0.0, 0.0), parent=None) -> bpy.types.Object:
    """建立关节枢轴；下级零件坐标相对枢轴，便于重复烘焙动作。"""
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.empty_display_size = 0.08
    obj.location = location
    obj.parent = parent
    return obj


def cube(name: str, location, scale, mat, parent=None, bevel=0.035) -> bpy.types.Object:
    """制作有轻微倒角的低面数甲片、布层与装具，避免大量独立高模。"""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    obj.parent = parent
    obj.location = location
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new("软化棱线", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        obj.modifiers.new("加权法线", "WEIGHTED_NORMAL")
    obj.data.materials.append(mat)
    return obj


def sphere(name: str, location, scale, mat, parent=None) -> bpy.types.Object:
    """建立头部、靴尖或嵌石；限制细分量，使源文件可快速调整。"""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    obj.parent = parent
    obj.location = location
    obj.scale = scale
    obj.data.materials.append(mat)
    return obj


def cone(name: str, location, radius1, radius2, depth, mat, parent=None, vertices=5) -> bpy.types.Object:
    """制作头发簇和剑尖，保持八向轮廓可辨。"""
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1, radius2=radius2, depth=depth)
    obj = bpy.context.object
    obj.name = name
    obj.parent = parent
    obj.location = location
    obj.data.materials.append(mat)
    return obj


def line_mesh(name: str, points, mat, parent=None, thickness=0.035) -> bpy.types.Object:
    """用低成本曲线刻出金线或开放旁路环，不添加高面数网格。"""
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.resolution_u = 1
    data.bevel_depth = thickness
    data.bevel_resolution = 1
    spline = data.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, xyz in zip(spline.points, points):
        point.co = (*xyz, 1.0)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.data.materials.append(mat)
    return obj


def armor(parent, side: int) -> None:
    """制作肩部旧石甲、暖金边与青白嵌石；左右结构基本一致。"""
    x = side * 0.47
    plate = cube("肩甲·旧石", (x, -0.015, 0.08), (0.42, 0.36, 0.32), STONE, parent, 0.065)
    plate.rotation_euler[1] = side * 0.18
    cube("肩甲外缘", (x, -0.19, 0.12), (0.33, 0.035, 0.055), GOLD, parent, 0.012)
    sphere("肩甲石座", (x, -0.198, 0.11), (0.07, 0.02, 0.07), GOLD, parent)
    sphere("肩甲青石", (x, -0.225, 0.11), (0.045, 0.018, 0.045), CYAN, parent)


def build_character() -> dict[str, bpy.types.Object]:
    """按定稿三大特征建立可编辑三维试验模型；不宣称是最终高保真重建。"""
    root = empty("ROOT·八方向旋转与脚底锚点")
    body = empty("腰部枢轴", (0, 0, 1.04), root)
    torso = empty("胸腔枢轴", (0, 0, 0.60), body)
    head = empty("颈部枢轴", (0, 0, 0.56), torso)
    left_leg = empty("左腿枢轴", (-0.20, 0, 0.01), body)
    right_leg = empty("右腿枢轴", (0.20, 0, 0.01), body)
    sword_arm = empty("持剑臂枢轴", (-0.48, 0, 0.28), torso)
    ring_arm = empty("持环臂枢轴", (0.48, 0, 0.28), torso)
    cape = empty("披风枢轴", (0, 0.19, 0.33), torso)

    cube("腰甲和深色衣摆", (0, 0, -0.01), (0.58, 0.40, 0.36), DARK, body)
    cube("胸甲底层", (0, 0, 0.11), (0.81, 0.42, 0.72), DARK, torso)
    cube("胸甲左石片", (-0.22, -0.238, 0.11), (0.37, 0.09, 0.50), STONE, torso)
    cube("胸甲右石片", (0.22, -0.238, 0.11), (0.37, 0.09, 0.50), STONE, torso)
    line_mesh("胸前闭合分流纹", [(-0.28,-0.30,0.28),(-0.05,-0.30,0.05),(0.18,-0.30,-0.10),(0.30,-0.30,0.24)], GOLD, torso, 0.018)
    cube("斜跨带", (-0.03,-0.29,0.06), (0.07,0.05,0.72), EDGE, torso, 0.008).rotation_euler[1] = -0.64
    sphere("胸口旧金盘", (0.06,-0.34,-0.11), (0.115,0.025,0.115), GOLD, torso)
    sphere("胸口圆盘内核", (0.06,-0.367,-0.11), (0.075,0.013,0.075), DARK, torso)

    cube("围巾厚领", (0,-0.04,0.03), (0.82,0.57,0.23), SCARF, head, 0.10)
    sphere("面部", (0,-0.068,0.27), (0.235,0.204,0.28), SKIN, head)
    sphere("左眼", (-0.09,-0.254,0.30), (0.035,0.013,0.022), HAIR, head)
    sphere("右眼", (0.09,-0.254,0.30), (0.035,0.013,0.022), HAIR, head)
    sphere("发顶", (0,-0.01,0.46), (0.285,0.247,0.21), HAIR, head)
    for index in range(19):
        angle = 2 * math.pi * index / 19
        tuft = cone("乱发簇%02d" % index, (0.24*math.cos(angle), 0.20*math.sin(angle), 0.48), 0.09, 0.0, 0.24, HAIR, head)
        tuft.rotation_euler[1] = 0.36*math.cos(angle)
        tuft.rotation_euler[0] = -0.36*math.sin(angle)
    for index in range(5):
        x = (index-2)*0.10
        tuft = cone("额前乱发%02d" % index, (x,-0.20,0.37), 0.08, 0, 0.24, HAIR, head)
        tuft.rotation_euler[0] = -0.24

    for side, pivot in [(-1, sword_arm), (1, ring_arm)]:
        armor(torso, side)
        cube("深色袖", (0, 0, -0.24), (0.25, 0.25, 0.49), DARK, pivot)
        cube("护臂旧石", (0,-0.025,-0.45), (0.27,0.27,0.33), STONE, pivot)
        cube("手套", (0,-0.01,-0.63), (0.19,0.21,0.18), DARK, pivot)
        cube("护腕金边", (0,-0.01,-0.40), (0.28,0.28,0.045), GOLD, pivot, 0.01)

    for side, pivot in [(-1,left_leg),(1,right_leg)]:
        cube("深色裤腿", (0,0,-0.37), (0.31,0.32,0.67), DARK, pivot)
        cube("膝甲", (0,-0.14,-0.37), (0.30,0.12,0.28), STONE, pivot)
        cube("胫甲", (0,-0.095,-0.65), (0.30,0.17,0.36), STONE, pivot)
        cube("胫甲金边", (0,-0.19,-0.65), (0.24,0.025,0.035), GOLD, pivot, 0.006)
        cube("靴", (0,-0.12,-0.88), (0.34,0.54,0.21), DARK, pivot)
        cube("靴头旧石扣", (0,-0.32,-0.85), (0.22,0.10,0.06), EDGE, pivot)

    cube("腰带", (0,-0.22,-0.13), (0.75,0.11,0.09), EDGE, body)
    cube("腰带铜扣", (0,-0.30,-0.13), (0.15,0.05,0.12), GOLD, body)
    for index, x in enumerate((-0.28,0,0.28)):
        length = 0.59 if index == 1 else 0.48
        cube("前垂甲布%d" % index, (x,-0.21,-0.40), (0.23,0.08,length), SCARF if index == 1 else DARK, body)
        cube("前垂甲石沿%d" % index, (x,-0.267,-0.58), (0.20,0.035,0.08), STONE, body)
    cube("腰侧皮袋", (0.41,-0.02,-0.19), (0.20,0.26,0.26), EDGE, body)

    for side in (-1,1):
        for index in range(3):
            x = side*(0.13+index*0.10)
            cloth = cube("破边披风 %s-%s" % (side,index), (x,0.12+index*0.03,-0.44-index*0.05), (0.18,0.045,0.96-index*0.13), SCARF, cape, 0.012)
            cloth.rotation_euler[1] = side*0.09
    cube("披风背部旧金扣", (0,0.17,0.19), (0.19,0.065,0.07), GOLD, cape)

    cube("镇脉长剑柄", (0,-0.02,-0.83), (0.085,0.09,0.42), EDGE, sword_arm)
    cube("剑护手", (0,-0.02,-0.94), (0.43,0.11,0.08), GOLD, sword_arm)
    cube("长剑石钢刃", (0,-0.02,-1.41), (0.18,0.09,0.91), STONE, sword_arm, 0.018)
    cone("镇脉剑尖", (0,-0.02,-1.92), 0.11,0,0.27,STONE,sword_arm,vertices=4).rotation_euler[0] = math.pi
    sphere("剑柄青石", (0,-0.09,-0.92), (0.055,0.017,0.055), CYAN, sword_arm)
    line_mesh("剑身暖金槽", [(0,-0.083,-1.02),(0,-0.083,-1.70)], GOLD, sword_arm, 0.014)

    ring_points = []
    for index in range(28):
        angle = math.radians(-72+index*270/27)
        ring_points.append((0.255*math.cos(angle),-0.02, -0.81+0.255*math.sin(angle)))
    line_mesh("开放旁路环·旧石", ring_points, STONE, ring_arm, 0.075)
    line_mesh("开放旁路环·金线", ring_points, GOLD, ring_arm, 0.017)
    sphere("旁路环青白核心", (0,-0.12,-0.81), (0.075,0.035,0.075), CYAN, ring_arm)

    return dict(root=root,body=body,torso=torso,head=head,left_leg=left_leg,right_leg=right_leg,sword_arm=sword_arm,ring_arm=ring_arm,cape=cape)


def key(obj: bpy.types.Object, frame: int, rotation=None, location=None) -> None:
    """给动作枢轴写入关键帧；输入角度统一为弧度、位移为 Blender 单位。"""
    if rotation is not None:
        obj.rotation_euler = rotation
        obj.keyframe_insert(data_path="rotation_euler", frame=frame)
    if location is not None:
        obj.location = location
        obj.keyframe_insert(data_path="location", frame=frame)


def animate(joints: dict) -> None:
    """建立四段可播放动作：站立 1–16、行走 21–45、攻击 49–72、打坐 77–108 帧。"""
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = 108
    scene.render.fps = 24
    markers = ((1,"站立"),(21,"行走"),(49,"攻击"),(77,"打坐"))
    for frame,name in markers:
        scene.timeline_markers.new(name,frame=frame)
    neutral = {
        "body":(0,0,0),"left_leg":(0,0,0),"right_leg":(0,0,0),
        "sword_arm":(0,0,0),"ring_arm":(0,0,0),"torso":(0,0,0),"cape":(0,0,0),
    }
    poses = [
        (1,neutral),(8,{**neutral,"body":(0.02,0,0),"cape":(0.02,0,0.03)}),(16,neutral),
        (21,neutral),
        (27,{**neutral,"body":(0.06,0.04,0),"left_leg":(-0.34,0,0),"right_leg":(0.34,0,0),"sword_arm":(0.29,0,0),"ring_arm":(-0.29,0,0),"cape":(0.05,0,0.06)}),
        (33,neutral),
        (39,{**neutral,"body":(0.06,0.04,0),"left_leg":(0.34,0,0),"right_leg":(-0.34,0,0),"sword_arm":(-0.29,0,0),"ring_arm":(0.29,0,0),"cape":(0.05,0,-0.04)}),
        (45,neutral),
        (49,neutral),
        (54,{**neutral,"body":(-0.02,-0.16,0.18),"sword_arm":(0.50,0,0.72),"ring_arm":(0.13,0,-0.12),"cape":(-0.10,0,-0.07)}),
        (58,{**neutral,"body":(0.03,0.20,-0.16),"left_leg":(-0.14,0,0),"right_leg":(0.16,0,0),"sword_arm":(-1.10,0,-0.50),"ring_arm":(0.14,0,0.25),"torso":(-0.13,0,-0.18),"cape":(0.22,0,0.10)}),
        (62,{**neutral,"body":(0.02,0.13,-0.10),"sword_arm":(-0.78,0,-0.37),"cape":(0.16,0,0.08)}),
        (72,neutral),
        (77,neutral),
        (85,{**neutral,"body":(-0.25,-0.07,0),"left_leg":(-0.51,0,-0.08),"right_leg":(-0.51,0,0.08),"sword_arm":(-0.17,0,-0.04),"ring_arm":(-0.17,0,0.04)}),
        (93,{**neutral,"body":(-0.42,-0.12,0),"left_leg":(-0.95,0,-0.20),"right_leg":(-0.95,0,0.20),"sword_arm":(-0.32,0,-0.10),"ring_arm":(-0.32,0,0.10),"torso":(0.12,0,0),"cape":(0.22,0,0)}),
        (100,{**neutral,"body":(-0.43,-0.12,0),"left_leg":(-0.95,0,-0.20),"right_leg":(-0.95,0,0.20),"sword_arm":(-0.32,0,-0.10),"ring_arm":(-0.32,0,0.10),"torso":(0.12,0,0),"cape":(0.22,0,0)}),
        (108,{**neutral,"body":(-0.42,-0.12,0),"left_leg":(-0.95,0,-0.20),"right_leg":(-0.95,0,0.20),"sword_arm":(-0.32,0,-0.10),"ring_arm":(-0.32,0,0.10),"torso":(0.12,0,0),"cape":(0.22,0,0)}),
    ]
    for frame,values in poses:
        for joint_name, rotation in values.items():
            obj = joints[joint_name]
            if joint_name == "body":
                key(obj,frame,rotation=(rotation[1],0,rotation[2]),location=(0,0,1.04+rotation[0]))
            else:
                key(obj,frame,rotation=rotation)
    for obj in joints.values():
        if obj.animation_data and obj.animation_data.action:
            obj.animation_data.action.name = "四段动作 · %s" % obj.name


def setup_scene(joints: dict) -> None:
    """统一审稿光线和正交机位；角色透明背景便于与游戏现图比较。"""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 320
    scene.render.resolution_y = 400
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.world.color = (0.09,0.09,0.09)
    scene.view_settings.view_transform = "Standard"
    scene.render.engine = "BLENDER_EEVEE"
    bpy.ops.object.camera_add(location=(4,-6,4.3))
    camera = bpy.context.object
    camera.name = "审稿正交相机"
    direction = Vector((0,0,1.32))-camera.location
    camera.rotation_euler = direction.to_track_quat("-Z","Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 3.75
    scene.camera = camera
    bpy.ops.object.light_add(type="AREA", location=(-3,-4,7))
    bpy.context.object.name = "柔和主光"
    bpy.context.object.data.energy = 850
    bpy.context.object.data.shape = "DISK"
    bpy.context.object.data.size = 5
    bpy.ops.object.light_add(type="AREA", location=(4,2,5))
    bpy.context.object.name = "背侧轮廓光"
    bpy.context.object.data.energy = 550
    bpy.context.object.data.size = 4


def render_review(joints: dict) -> None:
    """输出审稿静帧、八方向和三组低分辨率连续帧，供模型及动作双重检查。"""
    scene = bpy.context.scene
    review = (("idle",1),("walk",27),("attack",58),("sit",93))
    for name, frame in review:
        scene.frame_set(frame)
        scene.render.filepath = str(OUTPUT / ("look_06_%s_review.png" % name))
        bpy.ops.render.render(write_still=True)
    scene.frame_set(1)
    for direction in range(8):
        joints["root"].rotation_euler[2] = direction*math.pi/4
        scene.render.filepath = str(OUTPUT / ("look_06_dir_%d.png" % direction))
        bpy.ops.render.render(write_still=True)
    joints["root"].rotation_euler[2] = 0
    scene.render.resolution_x = 128
    scene.render.resolution_y = 160
    sequences = {
        "walk": (21,24,27,30,33,36,39,42),
        "attack": (49,52,54,56,58,60,64,70),
        "sit": (77,81,85,89,93,98,103,108),
    }
    for name,frames in sequences.items():
        for index,frame in enumerate(frames):
            scene.frame_set(frame)
            scene.render.filepath = str(OUTPUT / ("%s_%02d.png" % (name,index)))
            bpy.ops.render.render(write_still=True)
    scene.render.resolution_x = 320
    scene.render.resolution_y = 400


def main() -> None:
    """清理临时场景、建立三维角色和动作审稿资产；仅输出源稿目录。"""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    joints = build_character()
    setup_scene(joints)
    animate(joints)
    render_review(joints)
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT / "look_06_3d_pilot.blend"))


if __name__ == "__main__":
    main()
