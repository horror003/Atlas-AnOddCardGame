class_name DevMenu
extends Control

## 开发者菜单（仅在 OS.is_debug_build() 时由 main.gd 创建）。
## 右侧抽屉：直接修改玩家数值/区域卡牌/状态、控制回合与流程、操作牌堆、热重载数据、导出日志。
## 所有写操作都经 game.gd 的 dev_* 接口，保证日志与界面刷新一致。

var game: AtlasGame
var main_scene: Control
var on_refresh: Callable = Callable()

var _content: VBoxContainer = null

# 下拉框选择（rebuild 重建后保留）
var _sel_stats_player: int = 0
var _sel_zone_player: int = 0
var _sel_zone: String = "hand"
var _sel_grant_zone: String = "hand"
var _sel_status_player: int = 0
var _sel_status: String = ""
var _sel_duration: int = 0
var _sel_turn_player: int = 0
var _sel_phase: int = 2
var _sel_judge: int = 0
var _sel_card: int = 0

const DRAWER_WIDTH := 430
const BTN_H := 24
const FONT_SM := 12
const FONT_TITLE := 14

const ZONE_KEYS := ["hand", "equipment", "reserve", "traps"]
const ZONE_NAMES := ["手牌", "装备栏", "预备区", "陷阱区"]
const DURATION_VALUES := [-1, 1, 2, 3]
const DURATION_NAMES := ["永久", "1 回合", "2 回合", "3 回合"]

func _ready() -> void:
	# 必须同时设置锚点与偏移：只调用 set_anchors_preset 会保留加入场景时的 0×0 矩形，
	# 导致抽屉被算到父控件左侧之外。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -DRAWER_WIDTH
	panel.offset_right = 0
	panel.offset_top = 0
	panel.offset_bottom = 0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UITheme.flat(Color(0.07, 0.08, 0.10, 0.97), UITheme.ACCENT, 0, 1))
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)
	var title := Label.new()
	title.text = "DEV 开发者菜单"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title_row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "关闭 (F12)"
	close_btn.custom_minimum_size = Vector2(96, 26)
	UITheme.style_button(close_btn, UITheme.button_styles(UITheme.BG_CARD, UITheme.BORDER))
	close_btn.pressed.connect(_close)
	title_row.add_child(close_btn)

	var hint := Label.new()
	hint.text = "仅调试构建可用；所有操作会写入战斗日志。"
	hint.add_theme_font_size_override("font_size", FONT_SM)
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 4)
	scroll.add_child(_content)

	var refresh_btn := Button.new()
	refresh_btn.text = "刷新界面"
	refresh_btn.custom_minimum_size = Vector2(0, 26)
	UITheme.style_button(refresh_btn, UITheme.accent_button_styles())
	refresh_btn.pressed.connect(_on_refresh_clicked)
	vbox.add_child(refresh_btn)

func _close() -> void:
	visible = false

# ---------------- 构建 ----------------

func rebuild() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	if game == null:
		return
	if game.players.is_empty():
		_plain("尚未开始对局（选人阶段）。可重启本局或热重载数据。")
		_add_misc_section()
		return
	_add_stats_section()
	_add_zone_section()
	_add_status_section()
	_add_turn_section()
	_add_pile_section()
	_add_debug_section()
	_add_misc_section()

func _add_stats_section() -> void:
	_section("玩家数值")
	var p: PlayerData = game.players[clampi(_sel_stats_player, 0, game.players.size() - 1)]
	var row1 := _hbox()
	_option(row1, _player_items(), _sel_stats_player, _on_stats_player)

	var row2 := _hbox()
	_label(row2, "生命")
	var sp_hp := _spin(row2, p.hp, 0, 999)
	_label(row2, "上限")
	var sp_max := _spin(row2, p.max_hp, 1, 999)
	_label(row2, "痂")
	var sp_scab := _spin(row2, p.scab, 0, 999)

	var row3 := _hbox()
	_label(row3, "存牌值")
	var sp_hand := _spin(row3, p.hand_limit, 0, 99)
	_label(row3, "摸牌值")
	var sp_draw := _spin(row3, p.draw_limit, 1, 99)
	_btn(row3, "写入", _on_write_stats.bind(p, sp_hp, sp_max, sp_hand, sp_draw, sp_scab))

func _add_zone_section() -> void:
	_section("区域编辑")
	var row1 := _hbox()
	_option(row1, _player_items(), _sel_zone_player, _on_zone_player)
	_option(row1, ZONE_NAMES, maxi(0, ZONE_KEYS.find(_sel_zone)), _on_zone_type)

	var p: PlayerData = game.players[clampi(_sel_zone_player, 0, game.players.size() - 1)]
	var arr: Array[String] = game._dev_zone_array(p, _sel_zone)
	if arr.is_empty():
		_plain("（%s 为空）" % ZONE_NAMES[maxi(0, ZONE_KEYS.find(_sel_zone))])
	else:
		for i in arr.size():
			var row := _hbox()
			_label(row, "%d. %s" % [i + 1, String(game.db.get_card(arr[i]).get("name", arr[i]))])
			_btn(row, "移除", _on_remove_card.bind(p, _sel_zone, i), true)

	var row2 := _hbox()
	_label(row2, "添加卡牌")
	var ids := _card_ids()
	var items := _card_items(ids)
	_option(row2, items, _sel_card, _on_card_pick)
	_option(row2, ZONE_NAMES, maxi(0, ZONE_KEYS.find(_sel_grant_zone)), _on_grant_zone)
	_btn(row2, "加入", _on_grant_card.bind(p))

func _add_status_section() -> void:
	_section("状态效果")
	var row1 := _hbox()
	_option(row1, _player_items(), _sel_status_player, _on_status_player)
	var sid_list := _status_ids()
	_option(row1, _status_items(sid_list), _status_pick_index(sid_list), _on_status_pick)

	var row2 := _hbox()
	_label(row2, "层数")
	var sp_layers := _spin(row2, 1, 1, 99)
	_option(row2, DURATION_NAMES, _sel_duration, _on_duration)
	_btn(row2, "施加", _on_status_apply.bind(sp_layers))
	_btn(row2, "移除", _on_status_remove, true)

func _add_turn_section() -> void:
	_section("回合与流程")
	var row1 := _hbox()
	_option(row1, _player_items(), _sel_turn_player, _on_turn_player)
	_option(row1, AtlasGame.PHASE_NAMES, _sel_phase, _on_phase)
	_btn(row1, "设为该回合", _on_set_turn)

	var row2 := _hbox()
	_label(row2, "强制摸牌")
	var sp_n := _spin(row2, 1, 1, 20)
	_btn(row2, "摸牌", _on_force_draw.bind(sp_n))

	var row3 := _hbox()
	_label(row3, "下一次判定")
	_option(row3, _judge_items(), _sel_judge, _on_judge_pick)
	_btn(row3, "设置", _on_set_judge)
	if game.dev_forced_judge != "":
		_plain("当前已设置：%s（结算一次后自动清除）" % game.dev_forced_judge)

	var row4 := _hbox()
	for i in game.players.size():
		_btn(row4, "P%d 死亡" % (i + 1), _on_kill.bind(i), true)
	var row5 := _hbox()
	for i in game.players.size():
		_btn(row5, "P%d 胜利" % (i + 1), _on_win.bind(i))

func _add_pile_section() -> void:
	_section("牌堆")
	_plain("抽牌堆 %d 张 / 弃牌堆 %d 张 / 事件堆 %d 张" % [game.draw_pile.size(), game.discard_pile.size(), game.event_deck.size()])
	var top_names: Array[String] = []
	var n := mini(8, game.draw_pile.size())
	for i in n:
		var cid: String = game.draw_pile[game.draw_pile.size() - 1 - i]
		top_names.append(String(game.db.get_card(cid).get("name", cid)))
	var joined := ""
	for nm in top_names:
		if joined != "":
			joined += "、"
		joined += nm
	_plain("堆顶 %d 张：%s" % [n, joined if joined != "" else "无"])

	var row1 := _hbox()
	_btn(row1, "洗牌抽牌堆", _on_shuffle)

	var row2 := _hbox()
	_label(row2, "置入抽牌堆顶")
	var ids := _card_ids()
	_option(row2, _card_items(ids), _sel_card, _on_card_pick)
	_btn(row2, "置顶", _on_push_draw)

func _add_debug_section() -> void:
	_section("内部状态")
	var lines: Array[String] = []
	lines.append("mode：%s" % String(AtlasGame.Mode.keys()[game.mode]))
	lines.append("phase：%s" % AtlasGame.PHASE_NAMES[game.phase])
	lines.append("current：P%d" % (game.current + 1))
	lines.append("pending.kind：%s" % String(game.pending.get("kind", "（空）")))
	lines.append("damage_queue：%d 条" % game.damage_queue.size())
	for i in game.players.size():
		var p: PlayerData = game.players[i]
		lines.append("P%d %s：HP %d/%d 手牌 %d 装备 %d 预备 %d 状态 %d" % [
			i + 1, p.name, p.hp, p.max_hp, p.hand.size(), p.equipment.size(), p.reserve.size(), p.statuses.size()])
	var text := ""
	for line in lines:
		if text != "":
			text += "\n"
		text += line
	_plain(text)

func _add_misc_section() -> void:
	_section("其他")
	var row1 := _hbox()
	_btn(row1, "重载 JSON 数据", _on_reload_data)
	_btn(row1, "重启本局", _on_restart, true)

	var row2 := _hbox()
	_btn(row2, "导出战斗日志", _on_export_log)

# ---------------- 动作 ----------------

func _on_refresh_clicked() -> void:
	_after()

func _on_stats_player(i: int) -> void:
	_sel_stats_player = i
	call_deferred("rebuild")

func _on_zone_player(i: int) -> void:
	_sel_zone_player = i
	call_deferred("rebuild")

func _on_zone_type(i: int) -> void:
	_sel_zone = String(ZONE_KEYS[clampi(i, 0, ZONE_KEYS.size() - 1)])
	call_deferred("rebuild")

func _on_grant_zone(i: int) -> void:
	_sel_grant_zone = String(ZONE_KEYS[clampi(i, 0, ZONE_KEYS.size() - 1)])

func _on_status_player(i: int) -> void:
	_sel_status_player = i
	call_deferred("rebuild")

func _on_status_pick(i: int) -> void:
	var ids := _status_ids()
	if i >= 0 and i < ids.size():
		_sel_status = String(ids[i])

func _on_duration(i: int) -> void:
	_sel_duration = i

func _on_turn_player(i: int) -> void:
	_sel_turn_player = i

func _on_phase(i: int) -> void:
	_sel_phase = i

func _on_judge_pick(i: int) -> void:
	_sel_judge = i

func _on_card_pick(i: int) -> void:
	_sel_card = i

func _on_write_stats(p: PlayerData, sp_hp: SpinBox, sp_max: SpinBox, sp_hand: SpinBox, sp_draw: SpinBox, sp_scab: SpinBox) -> void:
	game.dev_apply_stats(p, int(sp_hp.value), int(sp_max.value), int(sp_hand.value), int(sp_draw.value), int(sp_scab.value))
	_after()

func _on_remove_card(p: PlayerData, zone: String, idx: int) -> void:
	game.dev_remove_card(p, zone, idx)
	_after()

func _on_grant_card(p: PlayerData) -> void:
	var ids := _card_ids()
	if ids.is_empty():
		return
	game.dev_grant_card(p, String(ids[clampi(_sel_card, 0, ids.size() - 1)]), _sel_grant_zone)
	_after()

func _on_status_apply(sp_layers: SpinBox) -> void:
	var ids := _status_ids()
	var sid := _effective_status_id(ids)
	if sid == "":
		return
	var p: PlayerData = game.players[clampi(_sel_status_player, 0, game.players.size() - 1)]
	game._add_status_capped(p, sid, int(sp_layers.value), int(DURATION_VALUES[clampi(_sel_duration, 0, DURATION_VALUES.size() - 1)]))
	_after()

func _on_status_remove() -> void:
	var sid := _effective_status_id(_status_ids())
	if sid == "":
		return
	var p: PlayerData = game.players[clampi(_sel_status_player, 0, game.players.size() - 1)]
	p.remove_status(sid)
	game.message.emit("【开发者】移除了 %s 的「%s」。" % [p.name, String(game.db.get_status(sid).get("name", sid))])
	_after()

func _on_set_turn() -> void:
	game.dev_set_turn(_sel_turn_player, _sel_phase)
	_after()

func _on_force_draw(sp_n: SpinBox) -> void:
	var p: PlayerData = game.players[clampi(_sel_turn_player, 0, game.players.size() - 1)]
	game.dev_draw(p, int(sp_n.value))
	_after()

func _on_set_judge() -> void:
	game.dev_forced_judge = _judge_value(_sel_judge)
	game.message.emit("【开发者】下一次判定：%s。" % String(_judge_items()[clampi(_sel_judge, 0, _judge_items().size() - 1)]))
	_after()

func _on_kill(idx: int) -> void:
	game.dev_kill(idx)
	_after()

func _on_win(idx: int) -> void:
	game.dev_win(idx)
	_after()

func _on_shuffle() -> void:
	game.dev_shuffle_draw()
	_after()

func _on_push_draw() -> void:
	var ids := _card_ids()
	if ids.is_empty():
		return
	game.dev_push_draw(String(ids[clampi(_sel_card, 0, ids.size() - 1)]))
	_after()

func _on_reload_data() -> void:
	game.db = CardDB.new()
	game.message.emit("【开发者】已重新加载 data/*.json。")
	_after()

func _on_restart() -> void:
	get_tree().reload_current_scene()

func _on_export_log() -> void:
	var rl := main_scene.get("log_label") as RichTextLabel
	if rl == null:
		return
	var text := rl.get_parsed_text()
	DirAccess.make_dir_recursive_absolute("user://dev_logs")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://dev_logs/dev_log_%s.txt" % stamp
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		game.message.emit("【开发者】日志导出失败：无法写入 %s。" % path)
		return
	f.store_string(text)
	f.close()
	game.message.emit("【开发者】日志已导出到 %s。" % ProjectSettings.globalize_path(path))
	_after()

func _after() -> void:
	if on_refresh.is_valid():
		on_refresh.call()
	call_deferred("rebuild")

# ---------------- 小工具 ----------------

func _section(title: String) -> void:
	var l := Label.new()
	l.text = "── %s ──" % title
	l.add_theme_font_size_override("font_size", FONT_TITLE)
	l.add_theme_color_override("font_color", UITheme.ACCENT)
	_content.add_child(l)

func _plain(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SM)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(l)

func _hbox() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	_content.add_child(h)
	return h

func _label(parent: HBoxContainer, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SM)
	l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	parent.add_child(l)
	return l

func _btn(parent: HBoxContainer, text: String, cb: Callable, danger: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BTN_H)
	b.add_theme_font_size_override("font_size", FONT_SM)
	if danger:
		UITheme.style_button(b, UITheme.danger_button_styles())
	else:
		UITheme.style_button(b, UITheme.button_styles(UITheme.BG_CARD, UITheme.BORDER))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _option(parent: HBoxContainer, items: Array, sel: int, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for item in items:
		o.add_item(String(item))
	o.selected = clampi(sel, 0, maxi(0, items.size() - 1))
	o.add_theme_font_size_override("font_size", FONT_SM)
	# 卡牌/状态名较长，必须裁剪文本并允许横向扩展，否则下拉框的最小宽度会
	# 把整个抽屉撑到超过 430px，右侧溢出屏幕。
	o.clip_text = true
	o.fit_to_longest_item = false
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.custom_minimum_size = Vector2(90, BTN_H)
	o.item_selected.connect(cb)
	parent.add_child(o)
	return o

func _spin(parent: HBoxContainer, value: int, min_v: int, max_v: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.value = clampi(value, min_v, max_v)
	s.custom_minimum_size = Vector2(72, BTN_H)
	parent.add_child(s)
	return s

func _player_items() -> Array:
	var out: Array = []
	for i in game.players.size():
		out.append("P%d · %s" % [i + 1, game.players[i].name])
	return out

func _card_ids() -> Array:
	var ids: Array = []
	for k in game.db.cards.keys():
		ids.append(String(k))
	ids.sort()
	return ids

func _card_items(ids: Array) -> Array:
	var out: Array = []
	for cid in ids:
		out.append("%s（%s）" % [String(game.db.get_card(cid).get("name", cid)), cid])
	return out

func _status_ids() -> Array:
	var ids: Array = []
	for k in game.db.statuses.keys():
		ids.append(String(k))
	ids.sort()
	return ids

func _status_items(ids: Array) -> Array:
	var out: Array = []
	for sid in ids:
		out.append("%s（%s）" % [String(game.db.get_status(sid).get("name", sid)), sid])
	return out

func _status_pick_index(ids: Array) -> int:
	var idx := ids.find(_sel_status)
	return maxi(0, idx)

func _effective_status_id(ids: Array) -> String:
	if ids.is_empty():
		return ""
	if _sel_status == "" or not ids.has(_sel_status):
		return String(ids[0])
	return _sel_status

func _judge_items() -> Array:
	return ["不干预", "强制成功", "强制失败", "骰子 1", "骰子 2", "骰子 3", "骰子 4", "骰子 5", "骰子 6"]

func _judge_value(idx: int) -> String:
	if idx == 1:
		return "success"
	if idx == 2:
		return "fail"
	if idx >= 3:
		return "roll:%d" % (idx - 2)
	return ""
