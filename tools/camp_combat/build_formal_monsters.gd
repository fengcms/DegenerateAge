extends SceneTree
## 把已验收的单方向四帧竖图无损重排为正式MonsterActorArt的横帧、纵方向图集。
## 输入仍来自隔离样板运行图，输出审核源包；不缩放、镜像或修改像素，正式复制由统一构建器负责。
const DIRECTIONS := ["s","sw","w","nw","n","ne","e","se"]
const STATES := ["idle","walk","attack","hit","death"]

## 参数为仓库绝对路径，附加--check只读核对每帧像素；失败不输出完成标记。
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size()>0)
	var root := args[0]
	var check_only := "--check" in args
	for kind: String in ["wolf","beetle"]:
		var monster := "wolf_corrupted" if kind=="wolf" else "shellback_bug"
		var id := monster+"_modular_v1"
		var folder := root+"/art_source/actors/"+monster+"_combat_pack_v1/"
		if not check_only:
			DirAccess.make_dir_recursive_absolute(folder)
		var metadata := {"id":id,"frame_size":[128,96],"pivot":[64,80],"directions":DIRECTIONS,"states":{}}
		for state: String in STATES:
			var packed := Image.create(512,768,false,Image.FORMAT_RGBA8)
			for direction in range(8):
				var suffix: String = DIRECTIONS[direction]
				var input := root+"/assets/art_pilot/"+kind+"_"+state+"_v1.png" if suffix=="sw" else root+"/assets/art_pilot/combat_monsters_v1/"+kind+"_"+state+"_"+suffix+".png"
				var source := Image.load_from_file(input)
				assert(source.get_size()==Vector2i(128,384))
				for frame in range(4):
					packed.blit_rect(source,Rect2i(0,frame*96,128,96),Vector2i(frame*128,direction*96))
			var output := folder+state+"_atlas.png"
			if check_only:
				assert(Image.load_from_file(output).get_data()==packed.get_data(),"正式图集重排改变帧像素："+output)
			else:
				assert(packed.save_png(output)==OK)
			metadata.states[state] = {"frames_per_direction":4,"fps":{"idle":3.0,"walk":6.0,"attack":8.0,"hit":25.0,"death":40.0/9.0}[state],"loop":state in ["idle","walk"],"visual_contact_frame":2 if state=="attack" else 0}
		if not check_only:
			FileAccess.open(folder+"animation.json",FileAccess.WRITE).store_string(JSON.stringify(metadata,"  ")+"\n")
			FileAccess.open(folder+"README.md",FileAccess.WRITE).store_string("# "+monster+"正式四帧动画包\n\n由tools/camp_combat/build_formal_monsters.gd将已验收的八向独立图集无损重排，不重新绘制、缩放或镜像。来源为assets/art_pilot/combat_monsters_v1与既有左前图集；原始生成记录见art_source/actors各方向combat_v1目录。\n\n横轴四帧、纵轴s/sw/w/nw/n/ne/e/se，单帧128×96、锚点(64,80)，每张512×768 RGBA8。攻击接触帧2、死亡0.90秒；正式MonsterActorArt推进表现，伤害/掉落由宿主结算。--check逐像素核对所有方向和状态；正式运行复制与索引由统一build_monster_animation_assets.mjs生成。\n")
	print("FORMAL_MONSTERS_PACKED_OK: 2 kinds / 8 directions / 5 states / 4 frames / lossless")
	quit()
