extends Node2D
class_name BaseMiniGame

# ============================================================
# SIGNALS
# ============================================================
signal game_finished(results: Dictionary)

# ============================================================
# EXPORT VARIABLES
# ============================================================
@export var game_duration: float = 30.0
@export var game_name: String = "Mini Game"

# ============================================================
# STATE VARIABLES
# ============================================================
var timer: float = 0.0
var is_running: bool = false
var players_data: Dictionary = {}  # { player_id: { name, score, node } }
var local_player_id: int = 0

# ============================================================
# UI REFERENCES
# ============================================================
@onready var timer_label: Label = get_node_or_null("UI/TimerLabel")
@onready var status_label: Label = get_node_or_null("UI/StatusLabel")
@onready var score_display: Control = get_node_or_null("UI/ScoreDisplay")
@onready var game_over_panel: Panel = get_node_or_null("UI/GameOverPanel")

# ============================================================
# LIFECYCLE
# ============================================================

func _ready() -> void:
	# ❗ NO lobby cleanup – we reuse existing players
	_setup_game()
	_start_game()

func _process(delta: float) -> void:
	if not is_running:
		return
	
	timer -= delta
	
	if timer_label:
		timer_label.text = str(int(timer)) + "s"
	
	if timer <= 0:
		_end_game()

# ============================================================
# SETUP
# ============================================================
func _setup_game() -> void:
	pass

func _start_game() -> void:
	is_running = true
	timer = game_duration
	_on_game_start()

# ============================================================
# VIRTUAL FUNCTIONS
# ============================================================
func _on_game_start() -> void:
	pass

func _on_game_end() -> void:
	pass

# ============================================================
# PLAYER PLACEMENT – يستخدم شخصيات اللوبي الموجودة مسبقاً
# ============================================================
func _on_player_added(player_id: int, player_name: String, skin_path: String) -> void:
	# حساب موقع الإسباون (وسط الشاشة + إزاحة بسيطة)
	var spawn_index = players_data.size() - 1
	var spawn_pos = Vector2(640 + (spawn_index * 40), 360 + (spawn_index * 40))

	# إرسال للجميع (السيرفر + العملاء) مع استدعاء محلي
	reposition_player.rpc(player_id, spawn_pos)

@rpc("authority", "call_local", "reliable")
func reposition_player(pid: int, pos: Vector2) -> void:
	# البحث عن اللاعب الموجود في مستوى Level (الوالد)
	var level_node = get_parent()
	if not level_node:
		level_node = get_tree().current_scene

	var player_node = level_node.get_node_or_null(str(pid))
	if not player_node:
		# fallback inside a "Players" container if any
		var container = get_node_or_null("Players")
		if container:
			player_node = container.get_node_or_null(str(pid))

	if not player_node:
		push_warning("Could not find player node for ID ", pid)
		return

	# 1. إظهار وتفعيل اللاعب
	player_node.visible = true
	player_node.z_index = 10
	player_node.global_position = pos

	player_node.set_process(true)
	player_node.set_physics_process(true)
	player_node.set_process_unhandled_input(true)

	if player_node.has_method("set_movement_enabled"):
		player_node.set_movement_enabled(true)

	# 2. تفعيل التصادمات
	for child in player_node.get_children():
		if child is CollisionObject2D:
			child.set_deferred("disabled", false)

	# 3. تخزين المرجع
	if players_data.has(pid):
		players_data[pid]["node"] = player_node

	print("✅ Player ", pid, " positioned at ", pos, " on peer ", multiplayer.get_unique_id())

func _on_player_score_updated(player_id: int, new_score: int) -> void:
	update_score_ui.rpc(player_id, new_score)

# ============================================================
# ADD PLAYER (called from lobby) – server triggers placement
# ============================================================
func add_player(player_id: int, player_name: String, skin_path: String) -> void:
	print("📥 BaseMiniGame.add_player: ", player_name, " (", player_id, ")")
	
	if not players_data.has(player_id):
		players_data[player_id] = {
			"name": player_name,
			"score": 0,
			"node": null
		}
	
	if multiplayer and multiplayer.multiplayer_peer:
		if player_id == multiplayer.get_unique_id():
			local_player_id = player_id
		
		# Only the server triggers repositioning
		if multiplayer.is_server():
			_on_player_added(player_id, player_name, skin_path)

# ============================================================
# UPDATE SCORE
# ============================================================
@rpc("authority", "call_local", "reliable")
func update_score_ui(player_id: int, new_score: int) -> void:
	if players_data.has(player_id):
		players_data[player_id]["score"] = new_score
	
	if player_id == local_player_id:
		var local_score_label = get_node_or_null("UI/LocalScore")
		if local_score_label:
			local_score_label.text = "Your Score: " + str(new_score)

# ============================================================
# END GAME
# ============================================================
func _end_game() -> void:
	if not multiplayer.is_server():
		return
	
	if not is_running:
		return
	
	print("🏆 Game ending...")
	is_running = false
	_on_game_end()
	
	var results = {}
	for player_id in players_data.keys():
		results[player_id] = players_data[player_id].get("score", 0)
	
	show_game_over.rpc(results)
	
	await get_tree().create_timer(3.0).timeout
	game_finished.emit(results)
	queue_free()

@rpc("authority", "call_local", "reliable")
func show_game_over(results: Dictionary) -> void:
	if game_over_panel:
		game_over_panel.visible = true
		
		var sorted = results.keys()
		sorted.sort_custom(func(a, b): return results[a] > results[b])
		
		var text = "🏆 GAME OVER! 🏆\n\n"
		for i in range(sorted.size()):
			var id = sorted[i]
			var name = players_data[id].get("name", "Player")
			var score = results[id]
			var medal = ["🥇", "🥈", "🥉"][i] if i < 3 else str(i + 1)
			text += medal + " " + name + ": " + str(score) + " pts\n"
		
		var label = game_over_panel.get_node_or_null("ResultLabel")
		if label:
			label.text = text
