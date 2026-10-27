extends SceneTree

## 无头回归测试入口（不依赖 UI）：
## godot --headless --path d:\Atlas --script res://tests/run_tests.gd
## 退出码：0 = 全部通过，1 = 存在失败。

const SUITES := [
	"res://tests/suite_cards.gd",
	"res://tests/suite_damage.gd",
	"res://tests/suite_skills.gd",
	"res://tests/suite_events.gd",
	"res://tests/suite_multiplayer.gd",
	"res://tests/suite_retrace.gd",
]

var checks := 0
var failures := 0

func _initialize() -> void:
	for path in SUITES:
		var script: Script = load(path)
		if script == null:
			check(false, "无法加载测试套件：" + path)
			continue
		print("\n== %s ==" % path.get_file())
		var suite: Object = script.new()
		suite.call("run", self)
	print("\n—— 结果：%d 项检查，%d 项失败 ——" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  [PASS] ", msg)
	else:
		failures += 1
		print("  [FAIL] ", msg)

func check_eq(actual: Variant, expected: Variant, msg: String) -> void:
	check(actual == expected, "%s（期望 %s，实际 %s）" % [msg, str(expected), str(actual)])

## 构造一个最小对局：count 名玩家、出牌阶段、无手牌
func make_game(count: int = 2) -> AtlasGame:
	var g := AtlasGame.new()
	for i in count:
		var p := PlayerData.new()
		p.name = "P%d" % (i + 1)
		p.max_hp = 20
		p.hp = 20
		g.players.append(p)
	g.current = 0
	g.mode = AtlasGame.Mode.PLAY
	return g
