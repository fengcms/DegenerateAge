class_name SkillDetailTooltip
extends PanelContainer
## 技能详情浮层：按当前阶解析静态效果，只在浮层存活期间刷新剩余冷却。
## 一次最多展示一张；关闭或更换悬停目标后释放，不在技能列表里常驻复杂节点。

var skill_id := ""
var _title: Label
var _description: Label
var _effect: Label
var _meta: Label
var _cooldown: Label
var _remaining: Label
var _next: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _live_accumulator := 0.0

## 创建一张与技能 ID 绑定的卡片；未解锁技能也能查看基础资料。
static func for_skill(id: String) -> SkillDetailTooltip:
	var tooltip := SkillDetailTooltip.new()
	tooltip.skill_id = id
	return tooltip

func _ready() -> void:
	_build()
	EventBus.equipment_changed.connect(_refresh_static)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.player_leveled.connect(_on_player_leveled)
	EventBus.skill_rank_changed.connect(_on_skill_rank_changed)
	EventBus.settings_changed.connect(_on_settings_changed)
	EventBus.data_loaded.connect(_refresh_static)
	_refresh_static()
	_refresh_live()

## 临时浮层主动断开全局事件，避免它被关闭后仍收到角色变化。
func _exit_tree() -> void:
	if EventBus.equipment_changed.is_connected(_refresh_static):
		EventBus.equipment_changed.disconnect(_refresh_static)
	if EventBus.gold_changed.is_connected(_on_gold_changed):
		EventBus.gold_changed.disconnect(_on_gold_changed)
	if EventBus.player_leveled.is_connected(_on_player_leveled):
		EventBus.player_leveled.disconnect(_on_player_leveled)
	if EventBus.skill_rank_changed.is_connected(_on_skill_rank_changed):
		EventBus.skill_rank_changed.disconnect(_on_skill_rank_changed)
	if EventBus.settings_changed.is_connected(_on_settings_changed):
		EventBus.settings_changed.disconnect(_on_settings_changed)
	if EventBus.data_loaded.is_connected(_refresh_static):
		EventBus.data_loaded.disconnect(_refresh_static)

## 只更新当前浮层的时间行；基础资料、价格和名称均走事件刷新。
func _process(delta: float) -> void:
	_live_accumulator += delta
	if _live_accumulator < 0.1:
		return
	_live_accumulator = 0.0
	_refresh_live()

## 设置浮层深底与有限滚动区域，文字字号只乘文字倍率一次。
func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111820")
	style.border_color = PanelChrome.GOLD
	style.set_border_width_all(1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 7)
	_scroll.add_child(_body)
	_title = _line(18, PanelChrome.TEXT)
	_description = _line(15, Color("d8e2e5"))
	_effect = _line(16, Color("80d6e7"))
	_meta = _line(15, Color("cbd3d6"))
	_cooldown = _line(15, Color("e3c17c"))
	_remaining = _line(15, Color("ffc779"))
	_next = _line(15, Color("b5d6bd"))
	_apply_text_scale()

## 七行信息分别成控件，便于冷却倒计时只改变一行文本。
func _line(base_size: int, color: Color) -> Label:
	var label := Label.new()
	label.set_meta("base_font_size", base_size)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	label.add_theme_color_override("font_color", color)
	_body.add_child(label)
	return label

## 文字倍率变化时重设字号，再用真实字宽预折行，避免原生浮层首帧高度失真。
func _apply_text_scale() -> void:
	var scale := SettingsRuntime.text_scale_value()
	for label in [_title, _description, _effect, _meta, _cooldown, _remaining, _next]:
		label.add_theme_font_size_override("font_size", maxi(10, roundi(int(label.get_meta("base_font_size")) * scale)))
	_fit_text()

## 装备、升级和等级事件重新解析当前技能，但不会重建整张技能面板。
func _refresh_static() -> void:
	if _title == null:
		return
	var base: Variant = DataLoader.get_entry("skills", skill_id)
	if not base is Dictionary:
		hide()
		return
	var rank := GameState.skill_rank(skill_id)
	var maximum := SkillProgression.max_rank(skill_id)
	var skill := SkillProgression.resolve(skill_id, maxi(rank, 1))
	_set_line(_title, Localization.tr_key("ui.skill_panel.detail_title") % [str(base.get("name", skill_id)), rank, maximum])
	_set_line(_description, str(base.get("desc", "")))
	_set_line(_effect, Localization.tr_key("ui.skill_panel.detail_current" if rank > 0 else "ui.skill_panel.detail_after_unlock") % _effect_summary(skill))
	var mana := int(skill.get("manaCost", 0))
	var range := Localization.tr_key("ui.skill_panel.detail_tiles") % str(skill.get("range", 0.0)) if str(skill.get("shape", "")) != "self" else Localization.tr_key("ui.skill_panel.detail_self")
	_set_line(_meta, Localization.tr_key("ui.skill_panel.detail_meta") % [mana, range])
	if skill_id == "basic_slash":
		var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
		var interval := player.effective_attack_interval() if player != null else GameState.total_attack_interval()
		_set_line(_cooldown, Localization.tr_key("ui.skill_panel.detail_basic_interval") % interval)
	else:
		var base_cd := float(skill.get("cooldown", 0.0))
		_set_line(_cooldown, Localization.tr_key("ui.skill_panel.detail_cooldown") % [
			base_cd, GameState.cooldown_after_cdr(base_cd), GameState.total_cdr() * 100.0])
	_set_line(_next, _next_step_text(rank, maximum))
	_fit_text()
	_refresh_live()

## 显示下一阶生效值与门槛；满阶只显示状态，不制造不可购买的空按钮。
func _next_step_text(rank: int, maximum: int) -> String:
	if rank < 1:
		var base: Dictionary = DataLoader.get_entry("skills", skill_id)
		return Localization.tr_key("ui.skill_panel.detail_locked") % int(base.get("unlockLevel", 1))
	if rank >= maximum:
		return Localization.tr_key("ui.skill_panel.max_rank") if maximum > 1 else Localization.tr_key("ui.skill_panel.detail_basic_max")
	var step := SkillProgression.step(skill_id, rank + 1)
	var next := SkillProgression.resolve(skill_id, rank + 1)
	var reason := Localization.tr_key("ui.skill_panel.detail_ready")
	if int(GameState.player.level) < int(step.get("unlockLevel", 0)):
		reason = Localization.tr_key("ui.skill_panel.detail_level_short")
	elif GameState.gold < int(step.get("goldCost", 0)):
		reason = Localization.tr_key("ui.skill_panel.detail_gold_short")
	return Localization.tr_key("ui.skill_panel.detail_next") % [
		_effect_summary(next), rank + 1, int(step.get("unlockLevel", 0)), int(step.get("goldCost", 0)), reason]

## 攻击系数使用解析后的实际值；多段技能明确为单段系数，不混作总伤害。
func _effect_summary(skill: Dictionary) -> String:
	if str(skill.get("kind", "")) == "buff":
		var effects: Dictionary = skill.get("effects", {})
		return Localization.tr_key("ui.skill_panel.detail_buff") % [
			float(effects.get("attackPct", 0.0)) * 100.0,
			float(effects.get("attackSpeedPct", 0.0)) * 100.0,
			float(skill.get("duration", 0.0))]
	var hits := maxi(1, int(skill.get("hits", 1)))
	return Localization.tr_key("ui.skill_panel.detail_multi") % [float(skill.get("coefficient", 0.0)), hits] if hits > 1 else \
		Localization.tr_key("ui.skill_panel.detail_attack") % float(skill.get("coefficient", 0.0))

## 运行中计时从真实玩家读取；没有玩家时不显示看似已就绪的假数据。
func _refresh_live() -> void:
	if _remaining == null:
		return
	var was_visible := _remaining.visible
	var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
	if player == null:
		_remaining.hide()
		if was_visible:
			_fit_height()
		return
	if skill_id == "battle_focus":
		var buff_left := GameState.buff_remaining(skill_id)
		var cd_left := player.skill_cooldown(skill_id)
		_set_line(_remaining, Localization.tr_key("ui.skill_panel.detail_remaining_buff") % [cd_left, buff_left] if buff_left > 0.0 else \
			Localization.tr_key("ui.skill_panel.detail_remaining") % cd_left)
		_remaining.visible = cd_left > 0.0 or buff_left > 0.0
	elif skill_id == "basic_slash":
		_remaining.hide()
	else:
		var left := player.skill_cooldown(skill_id)
		_set_line(_remaining, Localization.tr_key("ui.skill_panel.detail_remaining") % left)
		_remaining.visible = left > 0.0
	if _remaining.visible:
		_wrap_line(_remaining)
	if was_visible != _remaining.visible:
		_fit_height()

## 保留未折行文本，缩放或金币变化时重新计算，不在已有换行上重复插入换行。
func _set_line(label: Label, value: String) -> void:
	label.set_meta("raw_text", value)
	label.text = value

## 给每行按宽度插入换行，限定整卡尺寸；窄窗口或 200% 文字倍率靠内部纵向滚动。
func _fit_text() -> void:
	if _scroll == null:
		return
	for label in [_title, _description, _effect, _meta, _cooldown, _remaining, _next]:
		_wrap_line(label)
	_scroll.custom_minimum_size.x = _text_width()
	_fit_height()

## 仅重排发生变化的一行，10Hz 倒计时不重复测量七行文本。
func _wrap_line(label: Label) -> void:
	var raw := str(label.get_meta("raw_text", label.text))
	label.text = PanelHelpButton.wrap_to_width(raw, label.get_theme_font("font"),
		label.get_theme_font_size("font_size"), _text_width())

## 将物理视口换算为面板逻辑像素，浮层宽度不超过当前可用窗口。
func _text_width() -> float:
	var logical_width := get_viewport().get_visible_rect().size.x / SettingsRuntime.ui_scale_value()
	return minf(340.0, maxf(48.0, logical_width - 64.0))

## 内容区至多占逻辑视口 65% 高；超出的详情由内部滚动查看。
func _fit_height() -> void:
	var logical := get_viewport().get_visible_rect().size / SettingsRuntime.ui_scale_value()
	var max_height := minf(maxf(100.0, logical.y * 0.65), maxf(40.0, logical.y - 24.0))
	_scroll.custom_minimum_size.y = minf(_body.get_combined_minimum_size().y, max_height)

## 价格和门槛变化通过事件更新；剩余秒数仍由 0.1 秒心跳负责。
func _on_gold_changed(_amount: int) -> void:
	_refresh_static()

func _on_player_leveled(_level: int) -> void:
	_refresh_static()

func _on_skill_rank_changed(_id: String, _rank: int) -> void:
	_refresh_static()

func _on_settings_changed() -> void:
	_apply_text_scale()
	_refresh_static()
