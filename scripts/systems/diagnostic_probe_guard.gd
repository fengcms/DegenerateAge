class_name DiagnosticProbeGuard
extends RefCounted
## 诊断探针边界：只允许默认user目录下的随机隔离项目，拒绝正式项目身份和自定义共享目录。
const SCENES := ["ReforgeCrashProbe.tscn","ReloadCrashProbe.tscn","FullPathProbe.tscn","SplitProbe.tscn","NoopProbe.tscn"]

## 纯判据供隔离回归使用；项目名必须与实际user目录末级一致，不能只伪造环境变量。
static func isolated_identity(name: String, custom: bool, directory: String) -> bool:
	return name.begins_with("DegenerateAge-Test-") and name.length() > "DegenerateAge-Test-".length() and not custom and directory.replace("\\","/").trim_suffix("/").get_file() == name

## 在autoload之前可查询的身份信息，不读取槽位或调用任何存档入口。
static func is_isolated() -> bool:
	return isolated_identity(String(ProjectSettings.get_setting("application/config/name","")),bool(ProjectSettings.get_setting("application/config/use_custom_user_dir",false)),OS.get_user_data_dir())

## 识别命令行或配置启动的危险探针，用于SaveManager在任何目录写入前提前退出初始化。
static func unsafe_startup() -> bool:
	if is_isolated():
		return false
	for argument in OS.get_cmdline_args():
		if argument.get_file() in SCENES:
			return true
	var main := String(ProjectSettings.get_setting("application/run/main_scene",""))
	if main.begins_with("uid://"):
		var id := ResourceUID.text_to_id(main)
		if ResourceUID.has_id(id):
			main = ResourceUID.get_id_path(id)
	return main.get_file() in SCENES

## 探针正文再次检查；拒绝时清除活动槽并退出，正常游戏不会调用此入口。
static func require_isolated(node: Node) -> bool:
	if is_isolated():
		return true
	SaveManager.autosave_enabled = false
	SaveManager.active_slot = -1
	push_error("诊断探针拒绝正式项目，请使用tools/run_isolated_probe.py与存档副本")
	node.get_tree().quit(2)
	return false
