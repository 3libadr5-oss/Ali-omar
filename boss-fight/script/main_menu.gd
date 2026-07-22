extends Control

# ============================================================
# 🎯 1. الثوابت والمتغيرات العامة
# ============================================================

const DEFAULT_PORT: int = 7070
const COUNTDOWN_DURATION: int = 5

enum GameMode { AUTO, MANUAL }

# ============================================================
# 🎯 2. المتغيرات المُصدَّرة (Export Variables)
# ============================================================

@export_group("🎮 Skins (الشخصيات)")
@export var skin1: SkinData
@export var skin2: SkinData
@export var skin3: SkinData
@export var skin4: SkinData
@export var skin5: SkinData

@export_group("🗺️ Maps (المراحل)")
@export var map1: MapData
@export var map2: MapData
@export var map3: MapData
@export var map4: MapData
@export var map5: MapData

@export_group("🎮 Mini Games (الألعاب المصغرة)")
@export var minigame1: MiniGameData
@export var minigame2: MiniGameData
@export var minigame3: MiniGameData
@export var minigame4: MiniGameData
@export var minigame5: MiniGameData
@export var minigame6: MiniGameData

@export_group("🎰 Slot Animation Settings")
@export var slot_animation_duration: float = 2.5
@export var slot_start_speed: float = 800.0
@export var slot_min_speed: float = 50.0

@export_group("📍 Lobby Positions")
@export var lobby_positions: Array[Vector2] = [
	Vector2(200, 300),
	Vector2(400, 300),
	Vector2(600, 300),
	Vector2(800, 300),
	Vector2(1000, 300)
]

@export_group("📏 Lobby Scale")
@export var lobby_scale: float = 1.0

@export_group("🎮 Game Mode Settings")
@export var auto_rounds: int = 5
@export var score_to_win: int = 3

# ============================================================
# 🎯 3. مراجع واجهة المستخدم (UI References)
# ============================================================

@onready var name_input: LineEdit = $UI/TopBar/NameInput
@onready var ip_input: LineEdit = $UI/IPInput
@onready var room_code_input: LineEdit = $UI/RoomCodeInput
@onready var host_button: Button = $UI/HostButton
@onready var join_button: Button = $UI/JoinButton
@onready var room_code_display: Label = $UI/RoomCodeDisplay
@onready var player_list: ItemList = $UI/PlayerList
@onready var status_label: Label = $UI/StatusLabel
@onready var start_button: Button = $UI/StartButton
@onready var countdown_label: Label = $UI/CountdownLabel
@onready var title_label: Label = $UI/Title
@onready var level_node: Node2D = $Level

@onready var skin_container: GridContainer = $UI/SkinSelection
@onready var map_container: HBoxContainer = $UI/MapSelection
@onready var minigame_container: HBoxContainer = $UI/MiniGameSelection
@onready var skins_button: Button = $UI/TopBar/SkinsButton
@onready var random_map_button: Button = $UI/TopBar/RandomMapButton
@onready var mode_container: HBoxContainer = $UI/ModeContainer

# ============================================================
# 🎯 4. مراجع شاشة التحميل (Loading Screen)
# ============================================================

@onready var loading_screen: Panel = $UI/LoadingScreen
@onready var loading_map_name: Label = $UI/LoadingScreen/MapName
@onready var loading_map_image: TextureRect = $UI/LoadingScreen/MapImage
@onready var loading_progress: ProgressBar = $UI/LoadingScreen/ProgressBar
@onready var loading_status: Label = $UI/LoadingScreen/StatusLabel

# ============================================================
# 🎯 5. متغيرات الحالة (State Variables)
# ============================================================

var skins: Array = []
var maps: Array = []
var minigames: Array = []
var skin_buttons: Array = []
var map_buttons: Array = []
var minigame_buttons: Array = []

var players: Dictionary = {}
var player_positions: Dictionary = {}
var peer_slot_map: Dictionary = {}
var my_name: String = ""
var my_skin_index: int = 0
var selected_map_index: int = 0
var selected_minigame_index: int = 0

var game_started: bool = false
var skin_menu_visible: bool = false
var is_spinning: bool = false
var countdown_active: bool = false
var countdown_timer: float = 0.0
var is_loading: bool = false
var load_progress: float = 0.0

var current_game_mode: GameMode = GameMode.AUTO
var auto_play_queue: Array = []
var played_minigames: Array = []
var current_round: int = 0
var player_scores: Dictionary = {}

var slot_is_animating: bool = false
var slot_tween: Tween = null
var spawned_players: Array = []
var _queued_minigame_path: String = ""

# ✅ NEW GUARD: prevents overlapping spawn-all operations
var is_respawning: bool = false

# ============================================================
# 🎯 6. دورة حياة اللعبة (Lifecycle)
# ============================================================

func _ready() -> void:
	_load_resources()
	_reset_ui()
	_create_skin_buttons()
	_create_map_buttons()
	_create_minigame_buttons()
	_setup_game_mode_buttons()
	
	if loading_screen:
		loading_screen.visible = false
	
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	skins_button.pressed.connect(_toggle_skin_menu)
	random_map_button.pressed.connect(_start_slot_animation)
	
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

# ============================================================
# 🎯 7. تحديث كل إطار (Process)
# ============================================================

func _process(delta: float) -> void:
	if countdown_active:
		countdown_timer -= delta
		if countdown_timer <= 0:
			countdown_timer = 0
			_finish_countdown()
		_update_countdown_label()
	
	if is_loading:
		load_progress += delta * 0.5
		load_progress = min(load_progress, 1.0)
		if loading_progress:
			loading_progress.value = load_progress * 100
		
		if load_progress < 0.3:
			loading_status.text = "🗺️ Loading Map..."
		elif load_progress < 0.6:
			loading_status.text = "🎮 Preparing Players..."
		elif load_progress < 0.9:
			loading_status.text = "⚡ Almost Ready..."
		else:
			loading_status.text = "✅ Ready to Start!"

	# ❌ REMOVED periodic lobby check: was the source of overlapping spawns

# ============================================================
# 🎯 8. تحميل الموارد (Resource Loading)
# ============================================================

func _load_resources() -> void:
	skins = []
	if skin1: skins.append(skin1)
	if skin2: skins.append(skin2)
	if skin3: skins.append(skin3)
	if skin4: skins.append(skin4)
	if skin5: skins.append(skin5)
	
	maps = []
	if map1: maps.append(map1)
	if map2: maps.append(map2)
	if map3: maps.append(map3)
	if map4: maps.append(map4)
	if map5: maps.append(map5)
	
	minigames = []
	if minigame1: minigames.append(minigame1)
	if minigame2: minigames.append(minigame2)
	if minigame3: minigames.append(minigame3)
	if minigame4: minigames.append(minigame4)
	if minigame5: minigames.append(minigame5)
	if minigame6: minigames.append(minigame6)

# ============================================================
# 🎯 9. إعدادات واجهة المستخدم (UI Setup)
# ============================================================

func _reset_ui() -> void:
	host_button.visible = true
	join_button.visible = true
	ip_input.visible = true
	room_code_input.visible = true
	name_input.visible = true
	status_label.visible = true
	status_label.text = "Ready"
	status_label.modulate = Color.WHITE
	
	room_code_display.visible = false
	start_button.visible = false
	countdown_label.visible = false
	map_container.visible = false
	minigame_container.visible = false
	skin_container.visible = false
	skins_button.visible = true
	random_map_button.visible = true
	mode_container.visible = true
	
	_clear_level()
	
	players.clear()
	player_positions.clear()
	peer_slot_map.clear()
	game_started = false
	countdown_active = false
	is_spinning = false
	is_loading = false
	load_progress = 0.0
	player_scores.clear()
	spawned_players.clear()
	is_respawning = false
	
	name_input.editable = true
	ip_input.editable = true
	room_code_input.editable = true
	host_button.disabled = false
	join_button.disabled = false

# ============================================================
# 🎯 10. إظهار واجهة اللوبي (Show Lobby UI) - مُصلح
# ============================================================

func _show_lobby_ui() -> void:
	host_button.visible = false
	join_button.visible = false
	ip_input.visible = false
	room_code_input.visible = false
	name_input.visible = false
	status_label.visible = false
	
	room_code_display.visible = true
	map_container.visible = true if multiplayer.is_server() else false
	skins_button.visible = true
	random_map_button.visible = true if multiplayer.is_server() else false
	mode_container.visible = true if multiplayer.is_server() else false
	
	start_button.visible = multiplayer.is_server()
	start_button.disabled = false
	
	skin_container.visible = false
	
	if multiplayer.is_server() and not game_started and not players.is_empty():
		call_deferred("_check_and_respawn_players")

# ============================================================
# 🎯 11. التحقق وإعادة spawn اللاعبين
# ============================================================

func _check_and_respawn_players() -> void:
	await get_tree().process_frame
	if spawned_players.is_empty() and not players.is_empty():
		_respawn_all_players_in_lobby()

# ============================================================
# 🎯 12. مسح المستوى (Clear Level)
# ============================================================

func _clear_level() -> void:
	for child in level_node.get_children():
		child.queue_free()
	
	spawned_players.clear()
	is_respawning = false
	
	if slot_tween and slot_tween.is_running():
		slot_tween.kill()

# ============================================================
# 🎯 13. إعدادات أوضاع اللعب (Game Mode Setup)
# ============================================================

func _setup_game_mode_buttons() -> void:
	if not mode_container:
		mode_container = HBoxContainer.new()
		mode_container.name = "ModeContainer"
		$UI.add_child(mode_container)
	
	for child in mode_container.get_children():
		child.queue_free()
	
	var auto_btn = Button.new()
	auto_btn.text = "🎯 Auto Mode"
	auto_btn.pressed.connect(_set_auto_mode)
	mode_container.add_child(auto_btn)
	
	var manual_btn = Button.new()
	manual_btn.text = "🎮 Manual Mode"
	manual_btn.pressed.connect(_set_manual_mode)
	mode_container.add_child(manual_btn)
	
	_set_auto_mode()

# ============================================================
# 🎯 14. أوضاع اللعب (Auto / Manual)
# ============================================================

func _set_auto_mode() -> void:
	current_game_mode = GameMode.AUTO
	status_label.text = "🎯 Auto Mode: Random Mini Games!"
	status_label.visible = true
	_prepare_auto_queue()
	minigame_container.visible = false

func _set_manual_mode() -> void:
	current_game_mode = GameMode.MANUAL
	status_label.text = "🎮 Manual Mode: Choose a game!"
	status_label.visible = true
	minigame_container.visible = true

# ============================================================
# 🎯 15. قائمة الألعاب التلقائية (Auto Queue)
# ============================================================

func _prepare_auto_queue() -> void:
	auto_play_queue.clear()
	played_minigames.clear()
	
	var shuffled = minigames.duplicate()
	shuffled.shuffle()
	
	var count = min(auto_rounds, shuffled.size())
	for i in range(count):
		if shuffled[i] != null:
			auto_play_queue.append(shuffled[i])

func _get_next_auto_game() -> MiniGameData:
	if auto_play_queue.is_empty():
		return null
	
	var next_game = auto_play_queue.pop_front()
	played_minigames.append(next_game)
	return next_game

# ============================================================
# 🎯 16. واجهة اختيار الجلود (Skin UI)
# ============================================================

func _create_skin_buttons() -> void:
	for child in skin_container.get_children():
		child.queue_free()
	skin_buttons.clear()
	
	for i in range(skins.size()):
		var data = skins[i]
		if data == null: continue
		
		var button = Button.new()
		button.text = data.name
		button.custom_minimum_size = Vector2(100, 60)
		if data.icon:
			button.icon = data.icon
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_skin_selected.bind(i))
		skin_container.add_child(button)
		skin_buttons.append(button)

# ============================================================
# 🎯 17. التحكم في قائمة الجلود (Skin Menu Toggle)
# ============================================================

func _toggle_skin_menu() -> void:
	skin_menu_visible = !skin_menu_visible
	skin_container.visible = skin_menu_visible
	skins_button.text = "❌ Hide Skins" if skin_menu_visible else "🎨 Skins"

# ============================================================
# 🎯 18. اختيار الجلد (Skin Selection)
# ============================================================

func _on_skin_selected(index: int) -> void:
	my_skin_index = index
	
	for i in range(skin_buttons.size()):
		if i == index:
			skin_buttons[i].modulate = Color.YELLOW
			skin_buttons[i].scale = Vector2(1.1, 1.1)
		else:
			skin_buttons[i].modulate = Color.WHITE
			skin_buttons[i].scale = Vector2(1.0, 1.0)
	
	skin_container.visible = false
	skin_menu_visible = false
	skins_button.text = "🎨 Skins"
	
	var my_id = multiplayer.get_unique_id()
	if players.has(my_id):
		players[my_id]["skin_index"] = index
		
		if multiplayer.is_server():
			_update_all_players()
		else:
			send_skin_choice.rpc_id(1, index)

# ============================================================
# 🎯 19. RPC إرسال اختيار الجلد (مُصلح)
# ============================================================

@rpc("any_peer", "call_local", "reliable")
func send_skin_choice(skin_index: int) -> void:
	if not multiplayer.is_server():
		return
	
	var id = multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	
	players[id]["skin_index"] = skin_index
	_update_all_players()
	_update_player_list.rpc()

# ============================================================
# 🎯 20. واجهة اختيار الخريطة (Map UI)
# ============================================================

func _create_map_buttons() -> void:
	for child in map_container.get_children():
		child.queue_free()
	map_buttons.clear()
	
	for i in range(maps.size()):
		var data = maps[i]
		if data == null: continue
		
		var button = Button.new()
		button.text = data.name
		button.custom_minimum_size = Vector2(100, 50)
		if data.icon:
			button.icon = data.icon
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_map_selected.bind(i))
		map_container.add_child(button)
		map_buttons.append(button)

# ============================================================
# 🎯 21. اختيار الخريطة (Map Selection)
# ============================================================

func _on_map_selected(index: int) -> void:
	if not multiplayer.is_server():
		return
	
	selected_map_index = index
	
	for i in range(map_buttons.size()):
		if i == index:
			map_buttons[i].modulate = Color.YELLOW
			map_buttons[i].scale = Vector2(1.1, 1.1)
		else:
			map_buttons[i].modulate = Color.WHITE
			map_buttons[i].scale = Vector2(1.0, 1.0)
	
	_update_status_label()
	update_map_selection.rpc(index)

# ============================================================
# 🎯 22. RPC تحديث اختيار الخريطة
# ============================================================

@rpc("authority", "call_local", "reliable")
func update_map_selection(map_index: int) -> void:
	selected_map_index = map_index
	
	for i in range(map_buttons.size()):
		if i == map_index:
			map_buttons[i].modulate = Color.YELLOW
			map_buttons[i].scale = Vector2(1.1, 1.1)
		else:
			map_buttons[i].modulate = Color.WHITE
			map_buttons[i].scale = Vector2(1.0, 1.0)

# ============================================================
# 🎯 23. واجهة اختيار اللعبة المصغرة (Mini Game UI)
# ============================================================

func _create_minigame_buttons() -> void:
	for child in minigame_container.get_children():
		child.queue_free()
	minigame_buttons.clear()
	
	for i in range(minigames.size()):
		var data = minigames[i]
		if data == null: continue
		
		var button = Button.new()
		button.text = data.name
		button.custom_minimum_size = Vector2(120, 60)
		if data.icon:
			button.icon = data.icon
			button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_minigame_selected.bind(i))
		minigame_container.add_child(button)
		minigame_buttons.append(button)

# ============================================================
# 🎯 24. اختيار اللعبة المصغرة (Mini Game Selection)
# ============================================================

func _on_minigame_selected(index: int) -> void:
	if not multiplayer.is_server():
		return
	
	selected_minigame_index = index
	
	for i in range(minigame_buttons.size()):
		if i == index:
			minigame_buttons[i].modulate = Color.GREEN
			minigame_buttons[i].scale = Vector2(1.2, 1.2)
		else:
			minigame_buttons[i].modulate = Color.WHITE
			minigame_buttons[i].scale = Vector2(1.0, 1.0)
	
	_update_status_label()
	update_minigame_selection.rpc(index)

# ============================================================
# 🎯 25. RPC تحديث اختيار اللعبة المصغرة
# ============================================================

@rpc("authority", "call_local", "reliable")
func update_minigame_selection(minigame_index: int) -> void:
	selected_minigame_index = minigame_index
	
	for i in range(minigame_buttons.size()):
		if i == minigame_index:
			minigame_buttons[i].modulate = Color.GREEN
			minigame_buttons[i].scale = Vector2(1.2, 1.2)
		else:
			minigame_buttons[i].modulate = Color.WHITE
			minigame_buttons[i].scale = Vector2(1.0, 1.0)

# ============================================================
# 🎯 26. تحديث حالة الواجهة (Update Status Label)
# ============================================================

func _update_status_label() -> void:
	var map_name = maps[selected_map_index].name if maps.size() > 0 and selected_map_index < maps.size() else "No Map"
	var minigame_name = minigames[selected_minigame_index].name if minigames.size() > 0 and selected_minigame_index < minigames.size() else "No Game"
	status_label.text = "🎮 " + minigame_name + " | 🗺️ " + map_name
	status_label.visible = true

# ============================================================
# 🎯 27. أنيميشن الاختيار العشوائي (Slot Animation)
# ============================================================

func _start_slot_animation() -> void:
	if not multiplayer.is_server() or maps.is_empty() or is_spinning or game_started:
		return
	
	is_spinning = true
	var target_index = randi() % maps.size()
	_animate_slot_selection(target_index)

# ============================================================
# 🎯 28. تشغيل أنيميشن الاختيار
# ============================================================

func _animate_slot_selection(target_index: int) -> void:
	if slot_tween and slot_tween.is_running():
		slot_tween.kill()
	
	slot_tween = create_tween()
	slot_tween.set_parallel(false)
	
	var total_steps = 20 + randi() % 10
	var current_index = 0
	
	for step in range(total_steps):
		var progress = float(step) / float(total_steps)
		var eased_progress = 1.0 - pow(1.0 - progress, 3.0)
		var highlight_index
		
		if step < total_steps - 1:
			highlight_index = randi() % maps.size()
			while highlight_index == current_index and maps.size() > 1:
				highlight_index = randi() % maps.size()
		else:
			highlight_index = target_index
		
		current_index = highlight_index
		var step_duration = 0.05 + (eased_progress * 0.15)
		
		slot_tween.tween_callback(_update_slot_highlight.bind(highlight_index))
		slot_tween.tween_callback(_play_slot_flash.bind(highlight_index))
		slot_tween.tween_interval(step_duration)
	
	slot_tween.tween_callback(_on_slot_animation_finished.bind(target_index))

# ============================================================
# 🎯 29. تحديث إضاءة الخريطة في الأنيميشن
# ============================================================

func _update_slot_highlight(index: int) -> void:
	for i in range(map_buttons.size()):
		if i == index:
			map_buttons[i].modulate = Color.YELLOW
			map_buttons[i].scale = Vector2(1.3, 1.3)
		else:
			map_buttons[i].modulate = Color.WHITE
			map_buttons[i].scale = Vector2(1.0, 1.0)

# ============================================================
# 🎯 30. تأثير الفلاش في الأنيميشن
# ============================================================

func _play_slot_flash(index: int) -> void:
	if index < map_buttons.size():
		var button = map_buttons[index]
		var flash_tween = create_tween()
		flash_tween.tween_property(button, "modulate", Color.YELLOW, 0.05)
		flash_tween.tween_property(button, "modulate", Color.WHITE, 0.05)

# ============================================================
# 🎯 31. نهاية أنيميشن الاختيار
# ============================================================

func _on_slot_animation_finished(target_index: int) -> void:
	slot_is_animating = false
	is_spinning = false
	selected_map_index = target_index
	_on_map_selected(target_index)
	_play_win_effect()
	sync_slot_result.rpc(target_index)

# ============================================================
# 🎯 32. تأثير الفوز في الأنيميشن
# ============================================================

func _play_win_effect() -> void:
	if selected_map_index >= map_buttons.size():
		return
	var button = map_buttons[selected_map_index]
	if not button:
		return
	
	for i in range(3):
		var tween = create_tween()
		tween.tween_property(button, "scale", Vector2(1.5, 1.5), 0.1)
		tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.1)
		await get_tree().create_timer(0.15).timeout

# ============================================================
# 🎯 33. RPC مزامنة نتيجة الأنيميشن
# ============================================================

@rpc("authority", "call_local", "reliable")
func sync_slot_result(map_index: int) -> void:
	selected_map_index = map_index
	_update_slot_highlight(map_index)
	_on_map_selected(map_index)

# ============================================================
# 🎯 34. ظهور اللاعب (Spawn Player) - FIXED
# ============================================================

@rpc("authority", "call_local", "reliable")
func spawn_player(id: int, name: String, skin_path: String, started: bool) -> void:
	# ✅ All peers (server + clients) execute this when called by the server.
	# Authority annotation ensures only the server can call it.
	
	var node_name = str(id)
	
	# Clean up any previous instance of this player
	_remove_existing_player(node_name)
	await get_tree().process_frame
	
	# FINAL GUARD: if a duplicate managed to slip in, abort
	if level_node.get_node_or_null(node_name) != null:
		print("Warning: Player %d already exists, skipping duplicate spawn." % id)
		return
	
	# Fallback to default player scene if skin not found
	if not ResourceLoader.exists(skin_path):
		skin_path = "res://Player.tscn"
	
	var player_scene = load(skin_path)
	if not player_scene:
		push_error("❌ Failed to load player scene: " + skin_path)
		return
	
	var player_instance = player_scene.instantiate()
	player_instance.name = node_name
	
	var spawn_position = player_positions.get(id, Vector2(200, 300))
	player_instance.position = spawn_position
	
	var is_local = (id == multiplayer.get_unique_id())
	if player_instance.has_method("set_local_player"):
		player_instance.set_local_player(is_local)
	
	# Configure lobby / game state
	if not started:
		player_instance.set_process(false)
		player_instance.set_physics_process(false)
		player_instance.set_process_unhandled_input(false)
		player_instance.scale = Vector2(lobby_scale, lobby_scale)
		if player_instance.has_method("set_movement_enabled"):
			player_instance.set_movement_enabled(false)
		for child in player_instance.get_children():
			if child is CollisionObject2D:
				child.set_deferred("disabled", true)
	else:
		player_instance.set_process(true)
		player_instance.set_physics_process(true)
		player_instance.set_process_unhandled_input(true)
		player_instance.scale = Vector2(1.0, 1.0)
		if player_instance.has_method("set_movement_enabled"):
			player_instance.set_movement_enabled(true)
		for child in player_instance.get_children():
			if child is CollisionObject2D:
				child.set_deferred("disabled", false)
	
	level_node.add_child(player_instance)
	_setup_player_name_label(player_instance, name, id)
	
	if node_name not in spawned_players:
		spawned_players.append(node_name)
	
	print("✅ Player spawned: ", name, " (ID: ", id, ") - Started: ", started)

# ============================================================
# 🎯 35. إضافة اسم اللاعب فوق الشخصية
# ============================================================

func _setup_player_name_label(player_node: Node, name: String, id: int) -> void:
	var label = player_node.get_node_or_null("NameLabel")
	if not label:
		label = Label.new()
		label.name = "NameLabel"
		label.position = Vector2(0, -40)
		label.z_index = 1
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_font_size_override("font_size", 16)
		label.text_direction = Control.TEXT_DIRECTION_RTL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		player_node.add_child(label)
	
	label.text = name

# ============================================================
# 🎯 36. دالة مساعدة لحذف اللاعب الموجود
# ============================================================

func _remove_existing_player(node_name: String) -> void:
	var existing = level_node.get_node_or_null(node_name)
	if existing:
		level_node.remove_child(existing)
		existing.queue_free()
	
	if node_name in spawned_players:
		spawned_players.erase(node_name)

# ============================================================
# 🎯 37. إعادة spawn جميع اللاعبين في اللوبي - مُصلح (مع Guard)
# ============================================================

# ============================================================
# 🎯 37. إعادة spawn جميع اللاعبين في اللوبي - FIXED
# ============================================================

func _respawn_all_players_in_lobby() -> void:
	if is_respawning:
		return
	is_respawning = true
	
	if not multiplayer.is_server():
		is_respawning = false
		return
	
	# Clear all current player nodes
	spawned_players.clear()
	for child in level_node.get_children():
		if child is CharacterBody2D and child.name.is_valid_int():
			child.queue_free()
	
	await get_tree().process_frame
	
	for pid in players.keys():
		var skin_index = players[pid]["skin_index"]
		var skin_path = "res://Player.tscn"   # fallback default
		if skins.size() > 0 and skin_index < skins.size() and skins[skin_index] != null and skins[skin_index].scene:
			skin_path = skins[skin_index].scene.resource_path
		spawn_player.rpc(pid, players[pid]["name"], skin_path, false)
	
	await get_tree().process_frame
	is_respawning = false

# ============================================================
# 🎯 38. ❌ _check_players_in_lobby() removed entirely
# ============================================================

# ============================================================
# 🎯 39. تحديث كل اللاعبين - مُصلح (مع Guard)
# ============================================================
func _update_all_players() -> void:
	if is_respawning:
		return
	is_respawning = true
	
	if not multiplayer.is_server():
		is_respawning = false
		return
	
	_update_player_list.rpc()
	
	spawned_players.clear()
	for child in level_node.get_children():
		if child is CharacterBody2D and child.name.is_valid_int():
			child.queue_free()
	
	await get_tree().process_frame
	
	for pid in players.keys():
		var skin_index = players[pid]["skin_index"]
		var skin_path = "res://Player.tscn"
		if skins.size() > 0 and skin_index < skins.size() and skins[skin_index] != null and skins[skin_index].scene:
			skin_path = skins[skin_index].scene.resource_path
		spawn_player.rpc(pid, players[pid]["name"], skin_path, game_started)
	
	await get_tree().process_frame
	is_respawning = false

# ============================================================
# 🎯 40. استضافة اللعبة (Host)
# ============================================================

func _on_host_pressed() -> void:
	my_name = name_input.text.strip_edges()
	if my_name.is_empty():
		my_name = "Host"
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, 4)
	if error != OK:
		status_label.text = "❌ Failed to create server: " + str(error)
		status_label.modulate = Color.RED
		return
	
	multiplayer.multiplayer_peer = peer
	
	var room_code = str(randi() % 9000 + 1000)
	var local_ip = _get_local_ip()
	room_code_display.text = "🔑 Code: " + room_code + " | 🌐 IP: " + local_ip
	
	my_skin_index = 0
	var host_id = multiplayer.get_unique_id()
	players[host_id] = {"name": my_name, "skin_index": my_skin_index}
	_assign_slot_position(host_id)
	
	_show_lobby_ui()
	status_label.text = "✅ Waiting for players..."
	status_label.visible = true
	
	await get_tree().process_frame
	_respawn_all_players_in_lobby()
	_update_player_list.rpc()
	
	var skin_data = []
	for s in skins:
		if s:
			skin_data.append({
				"name": s.name,
				"scene_path": s.scene.resource_path if s.scene else "",
				"icon_path": s.icon.resource_path if s.icon else ""
			})
	rpc("receive_skin_data", skin_data)
	
	var map_data = []
	for m in maps:
		if m:
			map_data.append({
				"name": m.name,
				"scene_path": m.scene.resource_path if m.scene else "",
				"icon_path": m.icon.resource_path if m.icon else ""
			})
	rpc("receive_map_data", map_data)
	
	var minigame_data = []
	for mg in minigames:
		if mg:
			var data = {
				"name": mg.name,
				"scene_path": mg.scene.resource_path if mg.scene else "",
				"icon_path": mg.icon.resource_path if mg.icon else "",
				"description": mg.description if "description" in mg else "",
				"max_players": mg.max_players if "max_players" in mg else 4,
				"min_players": mg.min_players if "min_players" in mg else 2
			}
			minigame_data.append(data)
	rpc("receive_minigame_data", minigame_data)

# ============================================================
# 🎯 41. الانضمام للعبة (Join)
# ============================================================

func _on_join_pressed() -> void:
	my_name = name_input.text.strip_edges()
	if my_name.is_empty():
		my_name = "Player"
	
	var room_code = room_code_input.text.strip_edges()
	if room_code.is_empty() or not room_code.is_valid_int():
		status_label.text = "⚠️ Please enter a valid room code"
		status_label.modulate = Color.RED
		return
	
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, DEFAULT_PORT)
	if error != OK:
		status_label.text = "❌ Failed to connect: " + str(error)
		status_label.modulate = Color.RED
		return
	
	multiplayer.multiplayer_peer = peer
	status_label.text = "🔄 Connecting to " + ip + "..."
	status_label.modulate = Color.YELLOW

# ============================================================
# 🎯 42. أحداث الاتصال (Connection Events)
# ============================================================

func _on_connected_to_server() -> void:
	status_label.text = "✅ Connected! Registering..."
	status_label.modulate = Color.GREEN
	
	_show_lobby_ui()
	
	my_skin_index = 0
	send_my_name.rpc_id(1, my_name, my_skin_index)

func _on_connection_failed() -> void:
	status_label.text = "❌ Connection failed"
	status_label.modulate = Color.RED
	_reset_ui()

# ============================================================
# 🎯 43. تحديد موقع اللاعب (Slot Position)
# ============================================================

func _assign_slot_position(peer_id: int) -> void:
	var slot_index = peer_slot_map.size()
	if slot_index < lobby_positions.size():
		player_positions[peer_id] = lobby_positions[slot_index]
		peer_slot_map[peer_id] = slot_index
	else:
		player_positions[peer_id] = Vector2(200 + (slot_index * 200), 300)
		peer_slot_map[peer_id] = slot_index

# ============================================================
# 🎯 44. RPC إرسال اسم اللاعب - مُصلح
# ============================================================

@rpc("any_peer", "call_local", "reliable")
func send_my_name(name: String, skin_index: int) -> void:
	if not multiplayer.is_server():
		return
	
	var id = multiplayer.get_remote_sender_id()
	if players.has(id):
		return
	
	_assign_slot_position(id)
	players[id] = {"name": name, "skin_index": skin_index}
	
	_send_full_state_to_client(id)
	_update_all_players()
	
	var skin_data = []
	for s in skins:
		if s:
			skin_data.append({
				"name": s.name,
				"scene_path": s.scene.resource_path if s.scene else "",
				"icon_path": s.icon.resource_path if s.icon else ""
			})
	rpc_id(id, "receive_skin_data", skin_data)
	
	var map_data = []
	for m in maps:
		if m:
			map_data.append({
				"name": m.name,
				"scene_path": m.scene.resource_path if m.scene else "",
				"icon_path": m.icon.resource_path if m.icon else ""
			})
	rpc_id(id, "receive_map_data", map_data)
	
	var minigame_data = []
	for mg in minigames:
		if mg:
			var data = {
				"name": mg.name,
				"scene_path": mg.scene.resource_path if mg.scene else "",
				"icon_path": mg.icon.resource_path if mg.icon else "",
				"description": mg.description if "description" in mg else "",
				"max_players": mg.max_players if "max_players" in mg else 4,
				"min_players": mg.min_players if "min_players" in mg else 2
			}
			minigame_data.append(data)
	rpc_id(id, "receive_minigame_data", minigame_data)

# ============================================================
# 🎯 45. إرسال الحالة الكاملة للعميل
# ============================================================

func _send_full_state_to_client(client_id: int) -> void:
	var player_data = []
	for pid in players.keys():
		player_data.append({
			"id": pid,
			"name": players[pid]["name"],
			"skin_index": players[pid]["skin_index"],
			"position": player_positions[pid]
		})
	rpc_id(client_id, "receive_full_state", player_data, selected_map_index, selected_minigame_index)

# ============================================================
# 🎯 46. RPC استقبال الحالة الكاملة - مُصلح (بدون spawn)
# ============================================================

@rpc("authority", "call_local", "reliable")
func receive_full_state(player_data: Array, map_index: int, minigame_index: int) -> void:
	players.clear()
	player_positions.clear()
	peer_slot_map.clear()
	
	for data in player_data:
		var pid = data.get("id", 0)
		var name = data.get("name", "Player")
		var skin_index = data.get("skin_index", 0)
		var position = data.get("position", Vector2(200, 300))
		
		players[pid] = {"name": name, "skin_index": skin_index}
		player_positions[pid] = position
		peer_slot_map[pid] = peer_slot_map.size()
	
	selected_map_index = map_index
	selected_minigame_index = minigame_index
	
	_update_slot_highlight(map_index)
	update_minigame_selection(minigame_index)
	_update_player_list()

# ============================================================
# 🎯 47. استقبال بيانات الجلود
# ============================================================

@rpc("authority", "call_local", "reliable")
func receive_skin_data(data: Array) -> void:
	skins.clear()
	for item in data:
		var skin = SkinData.new()
		skin.name = item.get("name", "Unknown")
		
		var scene_path = item.get("scene_path", "")
		if ResourceLoader.exists(scene_path):
			skin.scene = load(scene_path)
		
		var icon_path = item.get("icon_path", "")
		if ResourceLoader.exists(icon_path):
			skin.icon = load(icon_path)
		
		skins.append(skin)
	
	_create_skin_buttons()
	if not skins.is_empty():
		_on_skin_selected(0)

# ============================================================
# 🎯 48. استقبال بيانات الخرائط
# ============================================================

@rpc("authority", "call_local", "reliable")
func receive_map_data(data: Array) -> void:
	maps.clear()
	for item in data:
		var map = MapData.new()
		map.name = item.get("name", "Unknown")
		
		var scene_path = item.get("scene_path", "")
		if ResourceLoader.exists(scene_path):
			map.scene = load(scene_path)
		
		var icon_path = item.get("icon_path", "")
		if ResourceLoader.exists(icon_path):
			map.icon = load(icon_path)
		
		maps.append(map)
	
	_create_map_buttons()

# ============================================================
# 🎯 49. استقبال بيانات الألعاب المصغرة
# ============================================================

@rpc("authority", "call_local", "reliable")
func receive_minigame_data(data: Array) -> void:
	minigames.clear()
	for item in data:
		var mg = MiniGameData.new()
		mg.name = item.get("name", "Unknown")
		mg.description = item.get("description", "")
		mg.max_players = item.get("max_players", 4)
		mg.min_players = item.get("min_players", 2)
		
		var scene_path = item.get("scene_path", "")
		if ResourceLoader.exists(scene_path):
			mg.scene = load(scene_path)
		
		var icon_path = item.get("icon_path", "")
		if ResourceLoader.exists(icon_path):
			mg.icon = load(icon_path)
		
		minigames.append(mg)
	
	_create_minigame_buttons()
	if not minigames.is_empty():
		_on_minigame_selected(0)

# ============================================================
# 🎯 50. تحديث قائمة اللاعبين
# ============================================================

@rpc("authority", "call_local", "reliable")
func _update_player_list() -> void:
	player_list.clear()
	for id in players.keys():
		var name = players[id].get("name", "Player")
		var skin_index = players[id].get("skin_index", 0)
		var skin_name = skins[skin_index].name if skin_index < skins.size() and skins[skin_index] != null else "?"
		
		var icon = null
		if skin_index < skins.size() and skins[skin_index] != null and skins[skin_index].icon:
			icon = skins[skin_index].icon
		
		player_list.add_item("🎮 " + skin_name + " - " + name)
		if icon:
			player_list.set_item_icon(player_list.item_count - 1, icon)

# ============================================================
# 🎯 51. أحداث انضمام وانفصال اللاعبين - مُصلح
# ============================================================

func _on_player_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("🔗 Player connected: ", id)

func _on_player_disconnected(id: int) -> void:
	if multiplayer.is_server():
		print("🔌 Player disconnected: ", id)
		players.erase(id)
		player_positions.erase(id)
		peer_slot_map.erase(id)
		
		var node_name = str(id)
		_remove_existing_player(node_name)
		
		_update_player_list.rpc()

# ============================================================
# 🎯 52. RPC إزالة لاعب
# ============================================================

@rpc("authority", "call_local", "reliable")
func remove_player(id: int) -> void:
	var node_name = str(id)
	_remove_existing_player(node_name)

# ============================================================
# 🎯 53. بدء اللعبة (Start Game)
# ============================================================

func _on_start_pressed() -> void:
	if not multiplayer.is_server() or game_started or is_spinning:
		return
	
	if players.size() < 2:
		status_label.text = "⚠️ Need at least 2 players to start!"
		status_label.visible = true
		status_label.modulate = Color.YELLOW
		return
	
	_initialize_scores()
	
	match current_game_mode:
		GameMode.AUTO:
			_start_auto_mode()
		GameMode.MANUAL:
			_start_manual_mode()

# ============================================================
# 🎯 54. تهيئة النقاط
# ============================================================

func _initialize_scores() -> void:
	player_scores.clear()
	for player_id in players.keys():
		player_scores[player_id] = 0

# ============================================================
# 🎯 55. بدء الوضع التلقائي (Auto Mode)
# ============================================================

func _start_auto_mode() -> void:
	if auto_play_queue.is_empty():
		_prepare_auto_queue()
	
	var next_game = _get_next_auto_game()
	if next_game == null:
		_finish_auto_mode()
		return
	
	var game_index = minigames.find(next_game)
	if game_index != -1:
		selected_minigame_index = game_index
		update_minigame_selection.rpc(game_index)
		_start_game_with_minigame(next_game)

# ============================================================
# 🎯 56. بدء الوضع اليدوي (Manual Mode)
# ============================================================

func _start_manual_mode() -> void:
	if selected_minigame_index < minigames.size() and minigames[selected_minigame_index] != null:
		var selected_game = minigames[selected_minigame_index]
		_start_game_with_minigame(selected_game)
	else:
		status_label.text = "⚠️ Please select a mini game!"
		status_label.visible = true
		status_label.modulate = Color.RED

# ============================================================
# 🎯 57. بدء اللعبة بلعبة مصغرة محددة
# ============================================================

func _start_game_with_minigame(minigame_data: MiniGameData) -> void:
	if not minigame_data or not minigame_data.scene:
		status_label.text = "❌ Invalid mini game!"
		status_label.visible = true
		return
	
	game_started = true
	countdown_active = true
	countdown_timer = COUNTDOWN_DURATION
	start_button.disabled = true
	
	countdown_label.visible = true
	start_countdown.rpc(minigame_data.scene.resource_path)

# ============================================================
# 🎯 58. RPC بدء العد التنازلي
# ============================================================

@rpc("authority", "call_local", "reliable")
func start_countdown(minigame_path: String) -> void:
	countdown_active = true
	countdown_timer = COUNTDOWN_DURATION
	countdown_label.visible = true
	start_button.disabled = true
	_update_countdown_label()
	
	if multiplayer.is_server():
		_queued_minigame_path = minigame_path

# ============================================================
# 🎯 59. تحديث العد التنازلي
# ============================================================

func _update_countdown_label() -> void:
	if countdown_timer > 0:
		countdown_label.text = str(ceil(countdown_timer))
	else:
		countdown_label.text = "GO!"

# ============================================================
# 🎯 60. إنهاء العد التنازلي
# ============================================================

func _finish_countdown() -> void:
	countdown_active = false
	countdown_label.text = "🚀 START!"
	
	hide_ui_elements.rpc()
	countdown_label.visible = false
	
	if multiplayer.is_server():
		spawned_players.clear()
		
		var map_scene_path = ""
		var map_image: Texture2D = null
		var map_name_str = "Unknown Map"
		
		if selected_map_index < maps.size() and maps[selected_map_index] != null:
			var map_data = maps[selected_map_index]
			map_name_str = map_data.name
			if map_data.scene:
				map_scene_path = map_data.scene.resource_path
			if map_data.preview_image != null:
				map_image = map_data.preview_image
		
		var minigame_scene_path = _queued_minigame_path
		var minigame_name_str = "Unknown Game"
		
		if selected_minigame_index < minigames.size() and minigames[selected_minigame_index] != null:
			minigame_name_str = minigames[selected_minigame_index].name
		
		show_loading_screen.rpc(map_name_str, minigame_name_str, map_image)
		
		load_selected_map.rpc(map_scene_path)
		load_selected_minigame.rpc(minigame_scene_path)
		
		await get_tree().create_timer(1.0).timeout
		enable_player_movement.rpc()
		
		await get_tree().create_timer(2.0).timeout
		hide_loading_screen.rpc()

# ============================================================
# 🎯 61. RPC إظهار شاشة التحميل
# ============================================================

@rpc("authority", "call_local", "reliable")
func show_loading_screen(map_name: String, minigame_name: String, map_image: Texture2D = null) -> void:
	if loading_screen:
		loading_screen.visible = true
		loading_map_name.text = "🗺️ " + map_name + " | 🎮 " + minigame_name
		loading_status.text = "🔄 Loading..."
		loading_progress.value = 0
		is_loading = true
		load_progress = 0.0
		
		if map_image:
			loading_map_image.texture = map_image
			loading_map_image.visible = true
		else:
			loading_map_image.visible = false

# ============================================================
# 🎯 62. RPC إخفاء شاشة التحميل
# ============================================================

@rpc("authority", "call_local", "reliable")
func hide_loading_screen() -> void:
	if loading_screen:
		loading_screen.visible = false
		is_loading = false
		load_progress = 0.0

# ============================================================
# 🎯 63. تحميل الخريطة المختارة
# ============================================================

@rpc("authority", "call_local", "reliable")
func load_selected_map(map_path: String) -> void:
	for child in level_node.get_children():
		if not (child is CharacterBody2D and child.name.is_valid_int()):
			child.queue_free()
	
	if map_path != "" and ResourceLoader.exists(map_path):
		var map_scene = load(map_path)
		if map_scene:
			var map_instance = map_scene.instantiate()
			level_node.add_child(map_instance)
			level_node.move_child(map_instance, 0)

# ============================================================
# 🎯 64. تحميل اللعبة المصغرة المختارة
# ============================================================

@rpc("authority", "call_local", "reliable")
func load_selected_minigame(minigame_path: String) -> void:
	if minigame_path != "" and ResourceLoader.exists(minigame_path):
		var minigame_scene = load(minigame_path)
		if minigame_scene:
			var minigame_instance = minigame_scene.instantiate()
			
			if minigame_instance.has_method("add_player"):
				for player_id in players.keys():
					var skin_index = players[player_id]["skin_index"]
					var skin_path = skins[skin_index].scene.resource_path if skin_index < skins.size() and skins[skin_index] != null else "res://Player.tscn"
					minigame_instance.add_player(player_id, players[player_id]["name"], skin_path)
			
			if minigame_instance.has_signal("game_finished"):
				minigame_instance.game_finished.connect(_on_minigame_finished)
			
			level_node.add_child(minigame_instance)

# ============================================================
# 🎯 65. نهاية اللعبة المصغرة
# ============================================================

func _on_minigame_finished(results: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	
	for player_id in results.keys():
		var points = results[player_id]
		if player_scores.has(player_id):
			player_scores[player_id] += points
		else:
			player_scores[player_id] = points
		
		update_score_display.rpc(player_id, player_scores[player_id])
	
	var winner_id = _check_winner()
	if winner_id != -1:
		_declare_winner(winner_id)
		return
	
	if current_game_mode == GameMode.AUTO:
		await get_tree().create_timer(2.0).timeout
		
		if not auto_play_queue.is_empty():
			_start_auto_mode()
		else:
			var final_winner = _get_winner()
			if final_winner != -1:
				_declare_winner(final_winner)
			else:
				status_label.text = "🤝 It's a Tie!"
				status_label.visible = true
				await get_tree().create_timer(2.0).timeout
				_return_to_lobby()
	else:
		await get_tree().create_timer(3.0).timeout
		_return_to_lobby()

# ============================================================
# 🎯 66. نظام النقاط
# ============================================================

@rpc("authority", "call_local", "reliable")
func update_score_display(player_id: int, score: int) -> void:
	var score_text = ""
	for pid in player_scores.keys():
		var name = players[pid]["name"] if players.has(pid) else "P" + str(pid)
		score_text += name + ": " + str(player_scores[pid]) + "  "
	
	if score_text != "":
		status_label.text = "📊 " + score_text
		status_label.visible = true

# ============================================================
# 🎯 67. التحقق من الفائز
# ============================================================

func _check_winner() -> int:
	for player_id in player_scores.keys():
		if player_scores[player_id] >= score_to_win:
			return player_id
	return -1

func _get_winner() -> int:
	var max_score = -1
	var winner = -1
	var tie = false
	
	for player_id in player_scores.keys():
		if player_scores[player_id] > max_score:
			max_score = player_scores[player_id]
			winner = player_id
			tie = false
		elif player_scores[player_id] == max_score:
			tie = true
	
	return winner if not tie else -1

# ============================================================
# 🎯 68. إعلان الفائز
# ============================================================

func _declare_winner(winner_id: int) -> void:
	if not multiplayer.is_server():
		return
	
	var winner_name = players[winner_id]["name"] if players.has(winner_id) else "Unknown"
	status_label.text = "🏆 " + winner_name + " WINS THE GAME! 🎉"
	status_label.modulate = Color.YELLOW
	status_label.visible = true
	
	declare_winner.rpc(winner_id, winner_name)
	
	game_started = false
	start_button.disabled = true
	
	await get_tree().create_timer(4.0).timeout
	_return_to_lobby()

# ============================================================
# 🎯 69. RPC إعلان الفائز
# ============================================================

@rpc("authority", "call_local", "reliable")
func declare_winner(winner_id: int, winner_name: String) -> void:
	status_label.text = "🏆 " + winner_name + " WINS THE GAME! 🎉"
	status_label.modulate = Color.YELLOW
	status_label.visible = true
	game_started = false

# ============================================================
# 🎯 70. إنهاء الوضع التلقائي
# ============================================================

func _finish_auto_mode() -> void:
	var winner_id = _get_winner()
	if winner_id != -1:
		_declare_winner(winner_id)
	else:
		status_label.text = "🤝 It's a Tie!"
		status_label.visible = true
		await get_tree().create_timer(2.0).timeout
		_return_to_lobby()

# ============================================================
# 🎯 71. العودة إلى اللوبي - مُصلح
# ============================================================

func _return_to_lobby() -> void:
	player_scores.clear()
	game_started = false
	countdown_active = false
	start_button.disabled = false
	
	_clear_level()
	_show_lobby_ui()
	
	if current_game_mode == GameMode.AUTO:
		_prepare_auto_queue()
	
	status_label.text = "🔄 Back to Lobby!"
	status_label.visible = true
	status_label.modulate = Color.GREEN
	
	return_to_lobby.rpc()
	
	await get_tree().create_timer(2.0).timeout
	status_label.text = "Ready"
	status_label.modulate = Color.WHITE
	
	await get_tree().process_frame
	if multiplayer.is_server():
		_respawn_all_players_in_lobby()

# ============================================================
# 🎯 72. RPC العودة إلى اللوبي
# ============================================================

@rpc("authority", "call_local", "reliable")
func return_to_lobby() -> void:
	if not multiplayer.is_server():
		player_scores.clear()
		game_started = false
		countdown_active = false
		start_button.disabled = false
		
		_clear_level()
		_show_lobby_ui()
		
		status_label.text = "🔄 Back to Lobby!"
		status_label.visible = true
		status_label.modulate = Color.GREEN
		
		await get_tree().create_timer(2.0).timeout
		status_label.text = "Ready"
		status_label.modulate = Color.WHITE
	
	await get_tree().process_frame
	if multiplayer.is_server():
		_respawn_all_players_in_lobby()

# ============================================================
# 🎯 73. تفعيل حركة اللاعبين
# ============================================================

@rpc("authority", "call_local", "reliable")
func enable_player_movement() -> void:
	for child in level_node.get_children():
		if child is CharacterBody2D and child.name.is_valid_int():
			child.set_process(true)
			child.set_physics_process(true)
			child.set_process_unhandled_input(true)
			child.scale = Vector2(1.0, 1.0)
			
			if child.has_method("set_movement_enabled"):
				child.set_movement_enabled(true)
			
			for sub_child in child.get_children():
				if sub_child is CollisionObject2D:
					sub_child.set_deferred("disabled", false)

# ============================================================
# 🎯 74. إخفاء عناصر الواجهة
# ============================================================

@rpc("authority", "call_local", "reliable")
func hide_ui_elements() -> void:
	title_label.visible = false
	status_label.visible = false
	map_container.visible = false
	minigame_container.visible = false
	skin_container.visible = false
	start_button.visible = false
	skins_button.visible = false
	random_map_button.visible = false
	room_code_display.visible = false
	player_list.visible = false
	mode_container.visible = false

# ============================================================
# 🎯 75. دوال مساعدة (Utility)
# ============================================================

func _get_local_ip() -> String:
	var addresses = IP.get_local_addresses()
	for addr in addresses:
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return addresses[0] if addresses.size() > 0 else "127.0.0.1"

# ============================================================
# 🎯 76. التنظيف عند الخروج
# ============================================================

func _exit_tree() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
