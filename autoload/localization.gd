extends Node
## Localization — 文案外置（M5-4，产品文档 11.1 / 10.1）。
##
## 首版仅中文：`data/localization.json` 是**唯一文案源**（key → 文案）。
## 代码中的一切**玩家可见文本**都经 `tr_key("ui.xxx")` 取用，不再硬编码。
## 缺失 key：回退为 key 本身并 `push_warning`，便于测试期发现遗漏；
## 冒烟测试在收尾断言 `missing_keys()` 为空，使「文案漏 key」成为可失败的闸门。
##
## 边界（D2-A 拍板）：
##   - P0 界面骨架 / P1 交互文案 → 本文件的表；
##   - **P2 数据文案（物品名 / 描述 / 任务文本）留在 `data/*.json`**，不并入本表；
##   - **开发者诊断**（`push_warning` / `push_error` / 校验报告）保持中文原文，不属玩家可见文案。

const FILE_PATH := "res://data/localization.json"

## key → 文案。JSON 解析后键序会变，只做查表不做顺序依赖。
var _table: Dictionary = {}
## 本次运行中出现过的缺失 key（去重），供测试断言。
var _missing: Dictionary = {}

func _ready() -> void:
	reload()

## 重新读取文案表（数据热重载 / 测试用）。
func reload() -> void:
	_missing.clear()
	_table = {}
	if not FileAccess.file_exists(FILE_PATH):
		push_error("[Localization] 缺失文案文件：%s" % FILE_PATH)
		return
	var f := FileAccess.open(FILE_PATH, FileAccess.READ)
	if f == null:
		push_error("[Localization] 无法打开文案文件：%s" % FILE_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_table = parsed
	else:
		push_error("[Localization] 文案文件应为 JSON 对象：%s" % FILE_PATH)

## 取文案。命中返回文案；未命中 push_warning 并返回 key 本身。
## args 非空时按 `%` 占位填充（文案需含对应占位符）。
func tr_key(key: String, args: Array = []) -> String:
	var text := String(_table.get(key, ""))
	if text.is_empty():
		_missing[key] = true
		push_warning("[Localization] 缺失文案 key：%s" % key)
		# 回退值是 key 本身、未必含 `%` 占位符，此时做填充会触发格式化错误。
		return key
	if args.is_empty():
		return text
	return text % args

func has_key(key: String) -> bool:
	return _table.has(key)

## 本次运行中缺失过的 key（测试用）。
func missing_keys() -> Array:
	return _missing.keys()

func count() -> int:
	return _table.size()

## 全部 key（测试用）。
func all_keys() -> Array:
	return _table.keys()
