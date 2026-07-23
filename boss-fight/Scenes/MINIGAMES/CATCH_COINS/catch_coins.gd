extends BaseMiniGame

# ============================================================
# EXPORTS
# ============================================================
@export var coin_count: int = 20
@export var coin_scene: PackedScene
@export var spawn_area: Rect2 = Rect2(50, 50, 700, 500)

# ============================================================
# NODES
# ============================================================
@onready var coins_container: Node2D = $Coins
@onready var players_container: Node2D = $Players
@onready var scoreboard: Label = $UI/ScoreBoard


# ============================================================
# STATE
# ============================================================
var collected_coins: Dictionary = {}
var game_ended: bool = false

# ============================================================
# LIFECYCLE
# ============================================================
func _ready() -> void:
	_ensure_containers()
	
	if not coin_scene:
		coin_scene = load("res://Minigames/Coin.tscn")
		if not coin_scene:
			print("❌ Failed to load coin scene")
	
	super._ready()
	game_name = "Catch The Coins"
	
	if game_over_panel:
		game_over_panel.visible = false
	
	_update_timer_display()
	call_deferred("_spawn_coins")

func _ensure_containers() -> void:
	if not players_container:
		players_container = Node2D.new()
		players_container.name = "Players"
		add_child(players_container)
	
	if not coins_container:
		coins_container = Node2D.new()
		coins_container.name = "Coins"
		add_child(coins_container)

# ============================================================
# PROCESS
# ============================================================
func _process(delta: float) -> void:
	super._process(delta)
	
	if is_running:
		_update_timer_display()

func _update_timer_display() -> void:
	if timer_label:
		var time_left = max(0, int(timer))
		timer_label.text = "⏰ " + str(time_left) + "s"

# ============================================================
# ON GAME START
# ============================================================
func _on_game_start() -> void:
	print("🎮 Game started!")
	
	if status_label:
		status_label.text = "🪙 Collect as many coins as you can!"
		status_label.visible = true
		await get_tree().create_timer(2.0).timeout
		status_label.visible = false
	
	# ✅ تأكد من وجود لاعبين
	print("📊 Players before init: ", players_data.keys())
	
	for player_id in players_data.keys():
		collected_coins[player_id] = 0
		players_data[player_id]["score"] = 0
		print("📊 Initialized player ", player_id, " with score 0")
	
	print("📊 Players in game: ", players_data.keys())
	_update_scoreboard()
	_update_timer_display()

# ============================================================
# ADD PLAYER - ✅ المعدل
# ============================================================
func _on_player_added(player_id: int, player_name: String, skin_path: String) -> void:
	print("🎯 Adding player: ", player_name, " (", player_id, ")")
	
	if not players_container:
		players_container = Node2D.new()
		players_container.name = "Players"
		add_child(players_container)
	
	var player_scene = load(skin_path)
	if not player_scene:
		print("❌ Failed to load player scene")
		return
	
	var player = player_scene.instantiate()
	player.name = str(player_id)
	player.position = _get_spawn_position(player_id)
	
	# ✅ تعيين اللاعب المحلي
	if multiplayer and multiplayer.multiplayer_peer:
		var is_local = (player_id == multiplayer.get_unique_id())
		player.set_local_player(is_local)
		print("🎯 Player ", player_id, " is local: ", is_local)
	else:
		player.set_local_player(false)
	
	if player.has_method("set_game_mode"):
		player.set_game_mode(PlayerCharacter.GameMode.COLLECT)
	
	if player.has_method("set_movement_enabled"):
		player.set_movement_enabled(true)
	
	players_container.add_child(player)
	
	if not players_data.has(player_id):
		players_data[player_id] = {
			"name": player_name,
			"score": 0,
			"node": player
		}
	
	if player.has_signal("coin_collected"):
		player.coin_collected.connect(_on_coin_collected)
# ============================================================
# SPAWN COINS
# ============================================================
func _spawn_coins() -> void:
	if not multiplayer.is_server():
		return
	
	if not coins_container:
		coins_container = Node2D.new()
		coins_container.name = "Coins"
		add_child(coins_container)
	
	if not coin_scene:
		return
	
	print("🪙 Spawning ", coin_count, " coins...")
	
	var coin_positions = []
	for i in range(coin_count):
		var x = randf_range(spawn_area.position.x, spawn_area.position.x + spawn_area.size.x)
		var y = randf_range(spawn_area.position.y, spawn_area.position.y + spawn_area.size.y)
		coin_positions.append(Vector2(x, y))
	
	spawn_coins_rpc.rpc(coin_positions)

@rpc("authority", "call_local", "reliable")
func spawn_coins_rpc(positions: Array) -> void:
	if not coins_container:
		coins_container = Node2D.new()
		coins_container.name = "Coins"
		add_child(coins_container)
	
	if not coin_scene:
		return
	
	for child in coins_container.get_children():
		child.queue_free()
	await get_tree().process_frame
	
	for pos in positions:
		var coin = coin_scene.instantiate()
		coin.position = pos
		coin.collected.connect(_on_coin_collected)
		coins_container.add_child(coin)
	
	print("✅ Spawned ", positions.size(), " coins")

func _spawn_single_coin() -> void:
	if not multiplayer.is_server():
		return
	
	if not coin_scene:
		return
	
	if not coins_container:
		coins_container = Node2D.new()
		coins_container.name = "Coins"
		add_child(coins_container)
	
	var x = randf_range(spawn_area.position.x, spawn_area.position.x + spawn_area.size.x)
	var y = randf_range(spawn_area.position.y, spawn_area.position.y + spawn_area.size.y)
	
	spawn_single_coin_rpc.rpc(Vector2(x, y))

@rpc("authority", "call_local", "reliable")
func spawn_single_coin_rpc(position: Vector2) -> void:
	if not coin_scene:
		return
	
	var coin = coin_scene.instantiate()
	coin.position = position
	coin.collected.connect(_on_coin_collected)
	
	if coins_container:
		coins_container.add_child(coin)

# ============================================================
# COIN COLLECTED - ✅ المعدل
# ============================================================
func _on_coin_collected(player_id: int, coin: Coin) -> void:
	if not is_running:
		print("⚠️ Game not running")
		return
	
	if not multiplayer.is_server():
		return
	
	# ✅ تحقق من وجود اللاعب في players_data
	if not players_data.has(player_id):
		print("❌ ERROR: Player ", player_id, " not found in players_data!")
		print("📊 Available players: ", players_data.keys())
		return
	
	var points = coin.get_point_value()
	print("🪙 Player ", player_id, " collected coin! +", points, " points")
	
	if not collected_coins.has(player_id):
		collected_coins[player_id] = 0
	
	collected_coins[player_id] += points
	var new_score = collected_coins[player_id]
	
	players_data[player_id]["score"] = new_score
	print("📊 Player ", player_id, " score: ", new_score)
	
	_on_player_score_updated(player_id, new_score)
	_update_scoreboard.rpc()
	_spawn_single_coin()

# ============================================================
# UPDATE SCORE
# ============================================================
@rpc("authority", "call_local", "reliable")
func update_score_ui(player_id: int, new_score: int) -> void:
	print("🔄 Updating score for player ", player_id, ": ", new_score)
	
	if players_data.has(player_id):
		players_data[player_id]["score"] = new_score
	
	if player_id == local_player_id:
		_update_local_score(new_score)
	
	var player_node = get_node_or_null("Players/" + str(player_id))
	if player_node and player_node.has_method("update_score"):
		player_node.update_score(new_score)

func _update_local_score(score: int) -> void:
	var local_score_label = get_node_or_null("UI/LocalScore")
	if local_score_label:
		local_score_label.text = "Your Score: " + str(score)

@rpc("authority", "call_local", "reliable")
func _update_scoreboard() -> void:
	var score_text = "📊 Scores:\n"
	for player_id in players_data.keys():
		var name = players_data[player_id].get("name", "Player")
		var score = players_data[player_id].get("score", 0)
		score_text += name + ": " + str(score) + "\n"
	
	if scoreboard:
		scoreboard.text = score_text

# ============================================================
# END GAME
# ============================================================
func _end_game() -> void:
	if not multiplayer.is_server():
		return
	
	if not is_running or game_ended:
		return
	
	print("🏆 Game ending...")
	game_ended = true
	is_running = false
	_on_game_end()
	
	var results = {}
	for player_id in players_data.keys():
		results[player_id] = players_data[player_id].get("score", 0)
		print("📊 ", players_data[player_id]["name"], ": ", results[player_id], " points")
	
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
		
		if status_label:
			status_label.text = "🏆 Game Over! Check scores above!"
			status_label.visible = true

# ============================================================
# TEST
# ============================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F3:
			print("\n📊 CURRENT SCORES:")
			print("  players_data: ", players_data.keys())
			for player_id in players_data.keys():
				var name = players_data[player_id].get("name", "Player")
				var score = players_data[player_id].get("score", 0)
				print("  ", name, " (", player_id, "): ", score, " points")
			print("  collected_coins: ", collected_coins)
			print("  Is running: ", is_running)
			print("  Game ended: ", game_ended)
			print("  Time left: ", timer, "\n")

# ============================================================
# UTILITY
# ============================================================
func _get_spawn_position(player_id: int) -> Vector2:
	var positions = [
		Vector2(100, 100),
		Vector2(700, 100),
		Vector2(100, 500),
		Vector2(700, 500)
	]
	var index = player_id % positions.size()
	return positions[index]
