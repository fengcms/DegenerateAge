"""在Blender中构建四个受约束的步行关键姿态，作为图像生成的姿势参考。

只制作双色关节人偶，不替代主角美术；固定骨段长度，显式交替前脚和支撑脚。
执行blender -b -t 4 --python tools/motion_review/build_pose_guide.py -- /tmp/hero-pose-guide。
输出透明参考图与骨段/接触点校验JSON，不修改游戏资产。
"""
import argparse
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view


def material(name, color):
    """建立左右肢体共用的颜色材质，仅用来辨认关节归属。"""
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*color, 1)
    return mat


def ellipsoid(name, point, scale, mat):
    """建立关节、躯干或足部的简易体积，非正式美术模型。"""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, location=point)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(mat)
    return obj


def segment(name, start, end, radius, mat):
    """以两端点约束圆柱骨段方向及长度，保证姿态不是自由变形。"""
    delta = end - start
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=radius, depth=delta.length, location=(start+end)/2)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = delta.to_track_quat('Z', 'Y').to_euler()
    obj.data.materials.append(mat)


def knee(hip, ankle):
    """解析求解等长双骨腿；膝向身体前方弯，单位米，不改变骨段长度。"""
    length = 0.46
    delta = ankle - hip
    assert delta.length < 2*length
    along = delta.normalized()
    forward = Vector((0, -1, 0))
    bend = (forward - along*forward.dot(along)).normalized()
    return (hip+ankle)/2 + bend*math.sqrt(length**2-delta.length_squared/4)


def main():
    """按八个方位相机渲染固定正交四姿态；左右肢体和前方不变，切换视角不镜像骨架。"""
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    parser.add_argument('--direction', choices=['se', 'ne', 'sw', 'nw', 's', 'n', 'e', 'w'], default='se')
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    output = args.output.resolve()
    camera_position = {'se':(-6,-8,7), 'ne':(-6,8,7), 'sw':(6,-8,7), 'nw':(6,8,7), 's':(0,-10,7), 'n':(0,10,7), 'e':(-10,0,7), 'w':(10,0,7)}[args.direction]
    screen_right = Vector((-camera_position[1],camera_position[0],0)).normalized()
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    neutral = material('躯干', (0.55,0.55,0.51))
    left = material('左肢蓝', (0.12,0.38,0.7))
    right = material('右肢红', (0.7,0.19,0.12))
    poses = [((-0.28,0.08),(0.28,0.08)), ((0.0,0.08),(0.0,0.22)), ((0.28,0.08),(-0.28,0.08)), ((0.0,0.22),(0.0,0.08))]
    reports = []
    for index, feet in enumerate(poses):
        origin = screen_right * ((index-1.5)*1.8)
        ellipsoid('胸', origin+Vector((0,0,1.29)), (0.23,0.14,0.30), neutral)
        ellipsoid('骨盆', origin+Vector((0,0,0.94)), (0.18,0.13,0.13), neutral)
        ellipsoid('头', origin+Vector((0,0,1.72)), (0.13,0.12,0.17), neutral)
        ellipsoid('鼻·指向前方', origin+Vector((0,-0.125,1.71)), (0.035,0.06,0.035), neutral)
        report = {'frame':index,'legs':{}}
        for name, x, foot, mat in [('left',0.13,feet[0],left),('right',-0.13,feet[1],right)]:
            hip = Vector((x,0,0.93))
            ankle = Vector((x,foot[0],foot[1]))
            joint = knee(hip,ankle)
            for label, point in [('hip',hip),('knee',joint),('ankle',ankle)]:
                ellipsoid(name+label,origin+point,(0.075,0.075,0.075),mat)
            segment(name+'thigh',origin+hip,origin+joint,0.08,mat)
            segment(name+'shin',origin+joint,origin+ankle,0.06,mat)
            ellipsoid(name+'foot',origin+ankle+Vector((0,-0.065,-0.02)),(0.075,0.15,0.06),mat)
            shoulder = origin+Vector((x*1.9,0,1.43))
            hand = origin+Vector((x*2.1,-foot[0]*0.3,1.0))
            elbow = (shoulder+hand)/2+Vector((0,-0.06,0))
            segment(name+'upper_arm',shoulder,elbow,0.055,mat)
            segment(name+'forearm',elbow,hand,0.045,mat)
            ellipsoid(name+'hand',hand,(0.06,0.045,0.07),mat)
            lengths = [(hip-joint).length,(ankle-joint).length]
            assert all(abs(value-0.46)<1e-6 for value in lengths)
            report['legs'][name] = {'hip':list(hip),'knee':list(joint),'ankle':list(ankle),'lengths':lengths,'sole_z':ankle.z-0.08}
        reports.append(report)
    assert poses[0][0][0] < poses[0][1][0] and poses[2][0][0] > poses[2][1][0]
    assert abs(reports[1]['legs']['left']['sole_z'])<1e-6 and abs(reports[3]['legs']['right']['sole_z'])<1e-6
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 2048
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.world.color = (0.3,0.3,0.3)
    bpy.ops.object.camera_add(location=camera_position)
    camera = bpy.context.object
    camera.rotation_euler = (Vector((0,0,0.95))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 7.6
    scene.camera = camera
    bpy.context.view_layer.update()
    projected_origin = world_to_camera_view(scene, camera, Vector((0,0,0)))
    projected_forward = world_to_camera_view(scene, camera, Vector((0,-1,0)))
    projected_delta = projected_forward - projected_origin
    expected_x = 1 if args.direction.endswith('e') else (-1 if args.direction.endswith('w') else 0)
    expected_y = 1 if args.direction.startswith('n') else (-1 if args.direction.startswith('s') else 0)
    assert projected_delta.x * expected_x > 0 if expected_x else abs(projected_delta.x) < 1e-6
    assert projected_delta.y * expected_y > 0 if expected_y else abs(projected_delta.y) < 1e-6
    bpy.ops.object.light_add(type='AREA',location=(-3,-4,8))
    bpy.context.object.data.energy = 1600
    bpy.context.object.data.shape = 'DISK'
    bpy.context.object.data.size = 6
    scene.render.filepath = str(output/'pose_guide.png')
    bpy.ops.render.render(write_still=True)
    (output/'pose_checks.json').write_text(json.dumps({'direction':args.direction,'camera':camera_position,'projected_forward_delta':list(projected_delta),'screen_right':list(screen_right),'units':'meters','forward':[0,-1,0],'left_color':'blue','right_color':'red','frames':reports},indent=2)+'\n')
    print('POSE_GUIDE_OK: alternating contacts / equal bone lengths / planted sole heights')


if __name__ == '__main__':
    main()
