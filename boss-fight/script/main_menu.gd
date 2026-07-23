extends Control

# ==============================================================================
# Constants & Enums
# ==============================================================================
const DEFAULT_PORT: int = 7070
const COUNTDOWN_DURATION: int = 5

enum GameMode { AUTO, MANUAL }

# ==============================================================================
# Signals – decouple gameplay state from UI manipulation
# ==============================================================================
signal countdown_updated(seconds_left: int)
signal countdown_finished()
signal loading_screen_updated(progress: float, status: String)
signal status_message_changed(message: String, color: Color)
signal player_list_changed()
signal map_highlight_changed(selected_index: int)
signal minigame_highlight_changed(selected_index: int)
signal skin_highlight_changed(selected_index: int)
signal game_winner_declared(winner_id: int, winner_name: String)
signal score_display_updated()

# ==============================================================================
# Exported Resources & Settings (IMPROVED: Using Arrays instead of individual vars)
# ==============================================================================
@export_group("🎮 Skins")
@export var skins: Array[SkinData] = []

@export_group("🗺️ Maps")
@export var maps: Array[MapData] = []

@export_group("🎮 Mini Games")
@export var minigames: Array[MiniGameData] = []

@export_group("🎰 Slot Animation")
@export var slot_animation_duration: float = 2.5
@export var slot_start_speed: float = 800.0
@export var slot_min_speed: float = 50.0

@export_group("📍 Lobby Positions")
@export var lobby_positions: Array[Vector2] = [
	Vector2(200, 300), Vector2(400, 300), Vector2(600, 300),
	Vector2(800, 300), Vector2(1000, 300)
]

@export_group("📏 Lobby Scale")
@export var lobby_scale: float = 1.0

@export_group("🎮 Game Mode Settings")
@export var auto_rounds: int = 5
@export var score_to_win: int = 3

# ==============================================================================
# UI Node References (onready)
# ==============================================================================
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

@onready var loading_screen: Panel = $UI/LoadingScreen
@onready var loading_map_name: Label = $UI/LoadingScreen/MapName
@onready var loading_map_image: TextureRect = $UI/LoadingScreen/MapImage
@onready var loading_progress: ProgressBar = $UI/LoadingScreen/ProgressBar
@onready var loading_status: Label = $UI/LoadingScreen/StatusLabel

# ==============================================================================
# Internal State
# ==============================================================================
# Resource arrays (redundant with exports, but kept for runtime changes)
var skin_buttons: Array[Button] = []
var map_buttons: Array[Button] = []
var minigame_buttons: Array[Button] = []

# Player & network data
var players: Dictionary = {}  # { id: { "name": String, "skin_index": int } }
var player_positions: Dictionary = {}  # { id: Vector2 }
var peer_slot_map: Dictionary = {}  # { id: slot_index }
var my_name: String = ""
var my_skin_index: int = 0
var selected_map_index: int = 0
var selected_minigame_index: int = 0

# Game flow state
var game_started: bool = false
var skin_menu_visible: bool = false
var is_spinning: bool = false
var countdown_active: bool = false
var countdown_timer: float = 0.0
var is_loading: bool = false
var load_progress: float = 0.0
var is_respawning: bool = false

# Game mode specifics
var current_game_mode: GameMode = GameMode.AUTO
var auto_play_queue: Array[MiniGameData] = []
var played_minigames: Array[MiniGameData] = []
var current_round: int = 0
var player_scores: Dictionary = {}  # { id: score }

# Slot animation
var slot_is_animating: bool = false
var slot_tween: Tween = null
var spawned_players: Array[String] = []
var _queued_minigame_path: String = ""

# FIX: Store flash tweens to prevent memory leaks
var _active_flash_tweens: Array[Tween] = []

# ==============================================================================
# Lifecycle
# ==============================================================================
func _ready() -> void:
	# FIX: No need to manually load, export arrays are already filled.
	_reset_ui()
	_create_skin_buttons()
	_create_map_buttons()
	_create_minigame_buttons()
	_setup_game_mode_buttons()

	if loading_screen:
		loading_screen.visible = false

	# UI button connections
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	skins_button.pressed.connect(_toggle_skin_menu)
	random_map_button.pressed.connect(_start_slot_animation)

	# Multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

	# Internal signals -> UI bridges
	countdown_updated.connect(_on_countdown_tick)
	countdown_finished.connect(_on_countdown_end)
	loading_screen_updated.connect(_on_loading_progress_update)
	status_message_changed.connect(_on_status_message_change)
	player_list_changed.connect(_rebuild_player_list)
	map_highlight_changed.connect(_update_button_highlight.bind(map_buttons, Color.YELLOW))
	minigame_highlight_changed.connect(_update_button_highlight.bind(minigame_buttons, Color.GREEN))
	skin_highlight_changed.connect(_update_button_highlight.bind(skin_buttons, Color.YELLOW))
	game_winner_declared.connect(_on_game_winner_display)
	score_display_updated.connect(_on_score_display_refresh)

# ==============================================================================
# Process (frame update)
# ==============================================================================
func _process(delta: float) -> void:
	if countdown_active:
		countdown_timer -= delta
		if countdown_timer <= 0:
			countdown_timer = 0
			_finish_countdown()
		else:
			countdown_updated.emit(int(ceil(countdown_timer)))

	if is_loading:
		load_progress += delta * 0.5
		load_progress = min(load_progress, 1.0)
		var status_text: String
		if load_progress < 0.3:
			status_text = "🗺️ Loading Map..."
		elif load_progress < 0.6:
			status_text = "🎮 Preparing Players..."
		elif load_progress < 0.9:
			status_text = "⚡ Almost Ready..."
		else:
			status_text = "✅ Ready to Start!"
		loading_screen_updated.emit(load_progress, status_text)

# ==============================================================================
# UI Signal Handlers – update actual nodes
# ==============================================================================
func _on_countdown_tick(seconds: int) -> void:
	if countdown_label:
		countdown_label.text = str(seconds)

func _on_countdown_end() -> void:
	if countdown_label:
		countdown_label.text = "GO!"

func _on_loading_progress_update(progress: float, status: String) -> void:
	if loading_progress:
		loading_progress.value = progress * 100
	if loading_status:
		loading_status.text = status

func _on_status_message_change(message: String, color: Color) -> void:
	status_label.text = message
	status_label.modulate = color
	status_label.visible = true

func _rebuild_player_list() -> void:
	player_list.clear()
	for id in players.keys():
		var data: Dictionary = players[id]
		var skin_index: int = data.get("skin_index", 0)
		var name: String = data.get("name", "Player")
		var skin_name: String = "?"
		var icon: Texture2D = null
		if skin_index < skins.size() and skins[skin_index] != null:
			skin_name = skins[skin_index].name
			if skins[skin_index].icon:
				icon = skins[skin_index].icon
		player_list.add_item("🎮 " + skin_name + " - " + name)
		if icon:
			player_list.set_item_icon(player_list.item_count - 1, icon)

# FIX: Unified highlight function
func _update_button_highlight(index: int, buttons: Array[Button], highlight_color: Color) -> void:
	for i in range(buttons.size()):
		if i == index:
			buttons[i].modulate = highlight_color
			buttons[i].scale = Vector2(1.1, 1.1)
		else:
			buttons[i].modulate = Color.WHITE
			buttons[i].scale = Vector2(1.0, 1.0)

func _on_game_winner_display(winner_id: int, winner_name: String) -> void:
	status_message_changed.emit("🏆 " + winner_name + " WINS THE GAME! 🎉", Color.YELLOW)

func _on_score_display_refresh() -> void:
	var text_parts: PackedStringArray = []
	for pid in player_scores.keys():
		var name: String = players[pid]["name"] if players.has(pid) else "P" + str(pid)
		text_parts.append(name + ": " + str(player_scores[pid]))
	var full_text: String = "📊 " + "  ".join(text_parts)
	if not full_text.is_empty():
		status_message_changed.emit(full_text, Color.WHITE)

# ==============================================================================
# UI Setup & Reset
# ==============================================================================
func _reset_ui() -> void:
	host_button.visible = true
	join_button.visible = true
	ip_input.visible = true
	room_code_input.visible = true
	name_input.visible = true
	status_label.visible = true
	status_message_changed.emit("Ready", Color.WHITE)

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
	
	# FIX: Stop any ongoing slot animation
	if slot_tween:
		slot_tween.kill()
		slot_tween = null
	is_spinning = false

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

func _check_and_respawn_players() -> void:
	await get_tree().process_frame
	# FIX: Safety check
	if not is_instance_valid(self): return
	if spawned_players.is_empty() and not players.is_empty():
		_respawn_all_players_in_lobby()

func _clear_level() -> void:
	# FIX: Kill all flash tweens
	for t in _active_flash_tweens:
		if is_instance_valid(t):
			t.kill()
	_active_flash_tweens.clear()
	
	for child in level_node.get_children():
		child.queue_free()
	spawned_players.clear()
	is_respawning = false
	if slot_tween and slot_tween.is_running():
		slot_tween.kill()
		slot_tween = null

func _setup_game_mode_buttons() -> void:
	if not mode_container:
		mode_container = HBoxContainer.new()
		mode_container.name = "ModeContainer"
		$UI.add_child(mode_container)

	for child in mode_container.get_children():
		child.queue_free()

	var auto_btn := Button.new()
	auto_btn.text = "🎯 Auto Mode"
	auto_btn.pressed.connect(_set_auto_mode)
	mode_container.add_child(auto_btn)

	var manual_btn := Button.new()
	manual_btn.text = "🎮 Manual Mode"
	manual_btn.pressed.connect(_set_manual_mode)
	mode_container.add_child(manual_btn)

	_set_auto_mode()

# ==============================================================================
# Game Mode Selection
# ==============================================================================
func _set_auto_mode() -> void:
	current_game_mode = GameMode.AUTO
	status_message_changed.emit("🎯 Auto Mode: Random Mini Games!", Color.WHITE)
	_prepare_auto_queue()
	minigame_container.visible = false

func _set_manual_mode() -> void:
	current_game_mode = GameMode.MANUAL
	status_message_changed.emit("🎮 Manual Mode: Choose a game!", Color.WHITE)
	minigame_container.visible = true

# ==============================================================================
# Auto Mode Queue Management
# ==============================================================================
func _prepare_auto_queue() -> void:
	auto_play_queue.clear()
	played_minigames.clear()
	var shuffled := minigames.duplicate()
	shuffled.shuffle()
	var count := mini(auto_rounds, shuffled.size())
	for i in range(count):
		if shuffled[i] != null:
			auto_play_queue.append(shuffled[i])

func _get_next_auto_game() -> MiniGameData:
	if auto_play_queue.is_empty():
		return null
	var next_game: MiniGameData = auto_play_queue.pop_front()
	played_minigames.append(next_game)
	return next_game

# ==============================================================================
# Skin UI
# ==============================================================================
func _create_skin_buttons() -> void:
	for child in skin_container.get_children():
		child.queue_free()
	skin_buttons.clear()
	for i in range(skins.size()):
		var data := skins[i]
		if data == null: continue
		var btn := Button.new()
		btn.text = data.name
		btn.custom_minimum_size = Vector2(100, 60)
		if data.icon:
			btn.icon = data.icon
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_skin_selected.bind(i))
		skin_container.add_child(btn)
		skin_buttons.append(btn)

func _toggle_skin_menu() -> void:
	skin_menu_visible = not skin_menu_visible
	skin_container.visible = skin_menu_visible
	skins_button.text = "❌ Hide Skins" if skin_menu_visible else "🎨 Skins"

func _on_skin_selected(index: int) -> void:
	my_skin_index = index
	skin_highlight_changed.emit(index)
	skin_container.visible = false
	skin_menu_visible = false
	skins_button.text = "🎨 Skins"

	var my_id := multiplayer.get_unique_id()
	if players.has(my_id):
		players[my_id]["skin_index"] = index
		if multiplayer.is_server():
			_update_all_players()
		else:
			send_skin_choice.rpc_id(1, index)

@rpc("any_peer", "call_local", "reliable")
func send_skin_choice(skin_index: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	players[id]["skin_index"] = skin_index
	_update_all_players()
	_update_player_list.rpc()

# ==============================================================================
# Map UI & Slot Animation
# ==============================================================================
func _create_map_buttons() -> void:
	for child in map_container.get_children():
		child.queue_free()
	map_buttons.clear()
	for i in range(maps.size()):
		var data := maps[i]
		if data == null: continue
		var btn := Button.new()
		btn.text = data.name
		btn.custom_minimum_size = Vector2(100, 50)
		if data.icon:
			btn.icon = data.icon
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_map_selected.bind(i))
		map_container.add_child(btn)
		map_buttons.append(btn)

func _on_map_selected(index: int) -> void:
	if not multiplayer.is_server():
		return
	# FIX: Safety check for index
	if index < 0 or index >= maps.size():
		return
	selected_map_index = index
	map_highlight_changed.emit(index)
	_update_status_label()
	update_map_selection.rpc(index)

@rpc("authority", "call_local", "reliable")
func update_map_selection(map_index: int) -> void:
	if map_index < 0 or map_index >= maps.size():
		return
	selected_map_index = map_index
	map_highlight_changed.emit(map_index)

func _start_slot_animation() -> void:
	if not multiplayer.is_server() or maps.is_empty() or is_spinning or game_started:
		return
	# FIX: Kill previous tween
	if slot_tween:
		slot_tween.kill()
		slot_tween = null
		
	is_spinning = true
	var target_index := randi() % maps.size()
	_animate_slot_selection(target_index)

func _animate_slot_selection(target_index: int) -> void:
	slot_tween = create_tween()
	slot_tween.set_parallel(false)

	var total_steps := 20 + randi() % 10
	var current_index := 0
	for step in range(total_steps):
		var progress := float(step) / float(total_steps)
		var eased_progress := 1.0 - pow(1.0 - progress, 3.0)
		var highlight_index: int
		if step < total_steps - 1:
			highlight_index = randi() % maps.size()
			while highlight_index == current_index and maps.size() > 1:
				highlight_index = randi() % maps.size()
		else:
			highlight_index = target_index
		current_index = highlight_index
		var step_duration := 0.05 + (eased_progress * 0.15)
		slot_tween.tween_callback(_update_slot_highlight.bind(highlight_index))
		slot_tween.tween_callback(_play_slot_flash.bind(highlight_index))
		slot_tween.tween_interval(step_duration)
	slot_tween.tween_callback(_on_slot_animation_finished.bind(target_index))

func _update_slot_highlight(index: int) -> void:
	map_highlight_changed.emit(index)

func _play_slot_flash(index: int) -> void:
	if index < 0 or index >= map_buttons.size():
		return
	var btn := map_buttons[index]
	if not is_instance_valid(btn):
		return
	# FIX: Proper tween management
	var ft := create_tween()
	_active_flash_tweens.append(ft)
	ft.tween_property(btn, "modulate", Color.YELLOW, 0.05)
	ft.tween_property(btn, "modulate", Color.WHITE, 0.05)
	ft.finished.connect(_remove_flash_tween.bind(ft))

func _remove_flash_tween(t: Tween) -> void:
	if _active_flash_tweens.has(t):
		_active_flash_tweens.erase(t)

func _on_slot_animation_finished(target_index: int) -> void:
	slot_is_animating = false
	is_spinning = false
	selected_map_index = target_index
	_on_map_selected(target_index)
	_play_win_effect()
	sync_slot_result.rpc(target_index)

func _play_win_effect() -> void:
	if selected_map_index < 0 or selected_map_index >= map_buttons.size():
		return
	var btn := map_buttons[selected_map_index]
	if not is_instance_valid(btn):
		return
	for _i in range(3):
		var tw := create_tween()
		tw.tween_property(btn, "scale", Vector2(1.5, 1.5), 0.1)
		tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1)
		await get_tree().create_timer(0.15).timeout
		# FIX: Safety check
		if not is_instance_valid(self): return

@rpc("authority", "call_local", "reliable")
func sync_slot_result(map_index: int) -> void:
	if map_index < 0 or map_index >= maps.size():
		return
	selected_map_index = map_index
	map_highlight_changed.emit(map_index)
	_on_map_selected(map_index)

# ==============================================================================
# Mini Game UI
# ==============================================================================
func _create_minigame_buttons() -> void:
	for child in minigame_container.get_children():
		child.queue_free()
	minigame_buttons.clear()
	for i in range(minigames.size()):
		var data := minigames[i]
		if data == null: continue
		var btn := Button.new()
		btn.text = data.name
		btn.custom_minimum_size = Vector2(120, 60)
		if data.icon:
			btn.icon = data.icon
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_minigame_selected.bind(i))
		minigame_container.add_child(btn)
		minigame_buttons.append(btn)

func _on_minigame_selected(index: int) -> void:
	if not multiplayer.is_server():
		return
	if index < 0 or index >= minigames.size():
		return
	selected_minigame_index = index
	minigame_highlight_changed.emit(index)
	_update_status_label()
	update_minigame_selection.rpc(index)

@rpc("authority", "call_local", "reliable")
func update_minigame_selection(minigame_index: int) -> void:
	if minigame_index < 0 or minigame_index >= minigames.size():
		return
	selected_minigame_index = minigame_index
	minigame_highlight_changed.emit(minigame_index)

func _update_status_label() -> void:
	var map_name := maps[selected_map_index].name if maps.size() > 0 and selected_map_index < maps.size() else "No Map"
	var minigame_name := minigames[selected_minigame_index].name if minigames.size() > 0 and selected_minigame_index < minigames.size() else "No Game"
	status_message_changed.emit("🎮 " + minigame_name + " | 🗺️ " + map_name, Color.WHITE)

# ==============================================================================
# Player Spawning & Management
# ==============================================================================
@rpc("authority", "call_local", "reliable")
func spawn_player(id: int, name: String, skin_path: String, started: bool) -> void:
	var node_name := str(id)
	_remove_existing_player(node_name)
	await get_tree().process_frame
	if not is_instance_valid(self): return

	if level_node.get_node_or_null(node_name) != null:
		print("Warning: Player %d already exists, skipping duplicate spawn." % id)
		return

	if not ResourceLoader.exists(skin_path):
		skin_path = "res://Player.tscn"

	var player_scene: PackedScene = load(skin_path)
	if not player_scene:
		push_error("❌ Failed to load player scene: " + skin_path)
		return

	var player_instance: Node = player_scene.instantiate()
	player_instance.name = node_name
	var spawn_pos: Vector2 = player_positions.get(id, Vector2(200, 300))
	player_instance.position = spawn_pos

	var is_local := (id == multiplayer.get_unique_id())
	if player_instance.has_method("set_local_player"):
		player_instance.set_local_player(is_local)

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

func _setup_player_name_label(player_node: Node, p_name: String, id: int) -> void:
	var label: Label = player_node.get_node_or_null("NameLabel")
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
	label.text = p_name

func _remove_existing_player(node_name: String) -> void:
	var existing := level_node.get_node_or_null(node_name)
	if existing:
		level_node.remove_child(existing)
		existing.queue_free()
	if node_name in spawned_players:
		spawned_players.erase(node_name)

func _respawn_all_players_in_lobby() -> void:
	if is_respawning or not multiplayer.is_server():
		return
	is_respawning = true

	spawned_players.clear()
	for child in level_node.get_children():
		if child is CharacterBody2D and child.name.is_valid_int():
			child.queue_free()
	await get_tree().process_frame
	if not is_instance_valid(self): 
		is_respawning = false
		return

	for pid in players.keys():
		var skin_index: int = players[pid]["skin_index"]
		var skin_path: String = "res://Player.tscn"
		if skins.size() > 0 and skin_index < skins.size() and skins[skin_index] != null and skins[skin_index].scene:
			skin_path = skins[skin_index].scene.resource_path
		spawn_player.rpc(pid, players[pid]["name"], skin_path, false)

	await get_tree().process_frame
	if is_instance_valid(self):
		is_respawning = false

func _update_all_players() -> void:
	if is_respawning or not multiplayer.is_server():
		return
	is_respawning = true

	_update_player_list.rpc()

	spawned_players.clear()
	for child in level_node.get_children():
		if child is CharacterBody2D and child.name.is_valid_int():
			child.queue_free()
	await get_tree().process_frame
	if not is_instance_valid(self):
		is_respawning = false
		return

	for pid in players.keys():
		var skin_index: int = players[pid]["skin_index"]
		var skin_path: String = "res://Player.tscn"
		if skins.size() > 0 and skin_index < skins.size() and skins[skin_index] != null and skins[skin_index].scene:
			skin_path = skins[skin_index].scene.resource_path
		spawn_player.rpc(pid, players[pid]["name"], skin_path, game_started)

	await get_tree().process_frame
	if is_instance_valid(self):
		is_respawning = false

# ==============================================================================
# Host & Join Logic
# ==============================================================================
func _on_host_pressed() -> void:
	my_name = name_input.text.strip_edges()
	if my_name.is_empty():
		my_name = "Host"

	var peer := ENetMultiplayerPeer.new()
	var error: int = peer.create_server(DEFAULT_PORT, 4)
	if error != OK:
		status_message_changed.emit("❌ Failed to create server: " + str(error), Color.RED)
		return
	multiplayer.multiplayer_peer = peer

	var room_code: String = str(randi() % 9000 + 1000)
	var local_ip: String = _get_local_ip()
	room_code_display.text = "🔑 Code: " + room_code + " | 🌐 IP: " + local_ip

	my_skin_index = 0
	var host_id: int = multiplayer.get_unique_id()
	players[host_id] = {"name": my_name, "skin_index": my_skin_index}
	_assign_slot_position(host_id)

	_show_lobby_ui()
	status_message_changed.emit("✅ Waiting for players...", Color.WHITE)

	await get_tree().process_frame
	if not is_instance_valid(self): return
	_respawn_all_players_in_lobby()
	_update_player_list.rpc()

	_broadcast_resource_data()

func _on_join_pressed() -> void:
	my_name = name_input.text.strip_edges()
	if my_name.is_empty():
		my_name = "Player"

	var room_code: String = room_code_input.text.strip_edges()
	if room_code.is_empty() or not room_code.is_valid_int():
		status_message_changed.emit("⚠️ Please enter a valid room code", Color.RED)
		return

	var ip: String = ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"

	var peer := ENetMultiplayerPeer.new()
	var error: int = peer.create_client(ip, DEFAULT_PORT)
	if error != OK:
		status_message_changed.emit("❌ Failed to connect: " + str(error), Color.RED)
		return

	multiplayer.multiplayer_peer = peer
	status_message_changed.emit("🔄 Connecting to " + ip + "...", Color.YELLOW)

func _broadcast_resource_data() -> void:
	var skin_data := _serialize_resources(skins, false)
	rpc("receive_skin_data", skin_data)

	var map_data := _serialize_resources(maps, false)
	rpc("receive_map_data", map_data)

	var minigame_data := _serialize_resources(minigames, true)
	rpc("receive_minigame_data", minigame_data)

# FIX: Unified serialization
func _serialize_resources(res_list: Array, is_minigame: bool = false) -> Array:
	var out: Array = []
	for res in res_list:
		if res:
			var entry: Dictionary = {
				"name": res.name,
				"scene_path": res.scene.resource_path if res.scene else "",
				"icon_path": res.icon.resource_path if res.icon else ""
			}
			if is_minigame:
				# استخدم get() للوصول الآمن للخصائص
				var desc = res.get("description")
				var max_pl = res.get("max_players")
				var min_pl = res.get("min_players")
				entry["description"] = desc if desc != null else ""
				entry["max_players"] = max_pl if max_pl != null else 4
				entry["min_players"] = min_pl if min_pl != null else 2
			out.append(entry)
	return out

# ==============================================================================
# Connection Events
# ==============================================================================
func _on_connected_to_server() -> void:
	status_message_changed.emit("✅ Connected! Registering...", Color.GREEN)
	_show_lobby_ui()
	my_skin_index = 0
	send_my_name.rpc_id(1, my_name, my_skin_index)

func _on_connection_failed() -> void:
	status_message_changed.emit("❌ Connection failed", Color.RED)
	_reset_ui()

# ==============================================================================
# Slot Position Management
# ==============================================================================
func _assign_slot_position(peer_id: int) -> void:
	var slot_index: int = peer_slot_map.size()
	if slot_index < lobby_positions.size():
		player_positions[peer_id] = lobby_positions[slot_index]
	else:
		player_positions[peer_id] = Vector2(200 + (slot_index * 200), 300)
	peer_slot_map[peer_id] = slot_index

# ==============================================================================
# RPC: Player Name Registration & Full State
# ==============================================================================
@rpc("any_peer", "call_local", "reliable")
func send_my_name(player_name: String, skin_index: int) -> void:
	if not multiplayer.is_server():
		return
	var id: int = multiplayer.get_remote_sender_id()
	if players.has(id):
		return
	_assign_slot_position(id)
	players[id] = {"name": player_name, "skin_index": skin_index}

	_send_full_state_to_client(id)
	_update_all_players()

	var skin_data := _serialize_resources(skins, false)
	rpc_id(id, "receive_skin_data", skin_data)
	var map_data := _serialize_resources(maps, false)
	rpc_id(id, "receive_map_data", map_data)
	var minigame_data := _serialize_resources(minigames, true)
	rpc_id(id, "receive_minigame_data", minigame_data)

func _send_full_state_to_client(client_id: int) -> void:
	var player_data: Array = []
	for pid in players.keys():
		player_data.append({
			"id": pid,
			"name": players[pid]["name"],
			"skin_index": players[pid]["skin_index"],
			"position": player_positions[pid]
		})
	# FIX: Send scores too
	rpc_id(client_id, "receive_full_state", player_data, selected_map_index, selected_minigame_index, player_scores)

@rpc("authority", "call_local", "reliable")
func receive_full_state(player_data: Array, map_index: int, minigame_index: int, scores: Dictionary) -> void:
	players.clear()
	player_positions.clear()
	peer_slot_map.clear()
	for entry in player_data:
		var pid: int = entry.get("id", 0)
		var pname: String = entry.get("name", "Player")
		var skin: int = entry.get("skin_index", 0)
		var pos: Vector2 = entry.get("position", Vector2(200, 300))
		players[pid] = {"name": pname, "skin_index": skin}
		player_positions[pid] = pos
		peer_slot_map[pid] = peer_slot_map.size()

	selected_map_index = map_index
	selected_minigame_index = minigame_index
	map_highlight_changed.emit(map_index)
	minigame_highlight_changed.emit(minigame_index)
	
	# FIX: Sync scores
	player_scores = scores.duplicate()
	score_display_updated.emit()
	player_list_changed.emit()

# ==============================================================================
# RPC: Resource Data Reception
# ==============================================================================
@rpc("authority", "call_local", "reliable")
func receive_skin_data(data: Array) -> void:
	skins.clear()
	for item in data:
		var skin := SkinData.new()
		skin.name = item.get("name", "Unknown")
		var scene_path: String = item.get("scene_path", "")
		if ResourceLoader.exists(scene_path):
			skin.scene = load(scene_path)
		var icon_path: String = item.get("icon_path", "")
		if ResourceLoader.exists(icon_path):
			skin.icon = load(icon_path)
		skins.append(skin)
	_create_skin_buttons()
	if not skins.is_empty():
		_on_skin_selected(0)

@rpc("authority", "call_local", "reliable")
func receive_map_data(data: Array) -> void:
	maps.clear()
	for item in data:
		var map := MapData.new()
		map.name = item.get("name", "Unknown")
		var scene_path: String = item.get("scene_path", "")
		if ResourceLoader.exists(scene_path):
			map.scene = load(scene_path)
		var icon_path: String = item.get("icon_path", "")
		if ResourceLoader.exists(icon_path):
			map.icon = load(icon_path)
		maps.append(map)
	_create_map_buttons()

@rpc("authority", "call_local", "reliable")
func receive_minigame_data(data: Array) -> void:
	minigames.clear()
	for item in data:
		var mg := MiniGameData.new()
		mg.name = item.get("name", "Unknown")
		mg.description = item.get("description", "")
		mg.max_players = item.get("max_players", 4)
		mg.min_players = item.get("min_players", 2)
		var scene_path: String = item.get("scene_path", "")
		if ResourceLoader.exists(scene_path):
			mg.scene = load(scene_path)
		var icon_path: String = item.get("icon_path", "")
		if ResourceLoader.exists(icon_path):
			mg.icon = load(icon_path)
		minigames.append(mg)
	_create_minigame_buttons()
	if not minigames.is_empty():
		_on_minigame_selected(0)

# ==============================================================================
# Player Connect/Disconnect
# ==============================================================================
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
		player_scores.erase(id) # FIX: Clean scores
		_remove_existing_player(str(id))
		_update_player_list.rpc()

@rpc("authority", "call_local", "reliable")
func _update_player_list() -> void:
	player_list_changed.emit()

@rpc("authority", "call_local", "reliable")
func remove_player(id: int) -> void:
	_remove_existing_player(str(id))

# ==============================================================================
# Game Start Sequence
# ==============================================================================
func _on_start_pressed() -> void:
	if not multiplayer.is_server() or game_started or is_spinning:
		return
	if players.size() < 2:
		status_message_changed.emit("⚠️ Need at least 2 players to start!", Color.YELLOW)
		return

	_initialize_scores()
	match current_game_mode:
		GameMode.AUTO:
			_start_auto_mode()
		GameMode.MANUAL:
			_start_manual_mode()

func _initialize_scores() -> void:
	player_scores.clear()
	for pid in players.keys():
		player_scores[pid] = 0
	# FIX: Update clients immediately
	update_all_scores.rpc(player_scores)

@rpc("authority", "call_local", "reliable")
func update_all_scores(scores: Dictionary) -> void:
	player_scores = scores.duplicate()
	score_display_updated.emit()

func _start_auto_mode() -> void:
	if auto_play_queue.is_empty():
		_prepare_auto_queue()
	var next_game: MiniGameData = _get_next_auto_game()
	if next_game == null:
		_finish_auto_mode()
		return
	var game_index: int = minigames.find(next_game)
	if game_index != -1:
		selected_minigame_index = game_index
		update_minigame_selection.rpc(game_index)
		_start_game_with_minigame(next_game)

func _start_manual_mode() -> void:
	if selected_minigame_index < minigames.size() and minigames[selected_minigame_index] != null:
		var selected_game: MiniGameData = minigames[selected_minigame_index]
		_start_game_with_minigame(selected_game)
	else:
		status_message_changed.emit("⚠️ Please select a mini game!", Color.RED)

func _start_game_with_minigame(minigame_data: MiniGameData) -> void:
	if not minigame_data or not minigame_data.scene:
		status_message_changed.emit("❌ Invalid mini game!", Color.WHITE)
		return
	game_started = true
	countdown_active = true
	countdown_timer = COUNTDOWN_DURATION
	start_button.disabled = true
	countdown_label.visible = true
	start_countdown.rpc(minigame_data.scene.resource_path)

# ==============================================================================
# Countdown & Loading Sequence
# ==============================================================================
@rpc("authority", "call_local", "reliable")
func start_countdown(minigame_path: String) -> void:
	countdown_active = true
	countdown_timer = COUNTDOWN_DURATION
	countdown_label.visible = true
	start_button.disabled = true
	countdown_updated.emit(int(ceil(countdown_timer)))
	if multiplayer.is_server():
		_queued_minigame_path = minigame_path

func _finish_countdown() -> void:
	countdown_active = false
	countdown_finished.emit()
	hide_ui_elements.rpc()
	countdown_label.visible = false

	if multiplayer.is_server():
		spawned_players.clear()
		var map_scene_path: String = ""
		var map_preview: Texture2D = null
		var map_name_str: String = "Unknown Map"
		if selected_map_index < maps.size() and maps[selected_map_index] != null:
			var map_data: MapData = maps[selected_map_index]
			map_name_str = map_data.name
			if map_data.scene:
				map_scene_path = map_data.scene.resource_path
			if map_data.preview_image != null:
				map_preview = map_data.preview_image

		var minigame_scene_path: String = _queued_minigame_path
		var minigame_name_str: String = "Unknown Game"
		if selected_minigame_index < minigames.size() and minigames[selected_minigame_index] != null:
			minigame_name_str = minigames[selected_minigame_index].name

		show_loading_screen.rpc(map_name_str, minigame_name_str, map_preview)
		load_selected_map.rpc(map_scene_path)
		load_selected_minigame.rpc(minigame_scene_path)

		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(self): return
		enable_player_movement.rpc()
		await get_tree().create_timer(2.0).timeout
		if not is_instance_valid(self): return
		hide_loading_screen.rpc()

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

@rpc("authority", "call_local", "reliable")
func hide_loading_screen() -> void:
	if loading_screen:
		loading_screen.visible = false
		is_loading = false
		load_progress = 0.0

@rpc("authority", "call_local", "reliable")
func load_selected_map(map_path: String) -> void:
	for child in level_node.get_children():
		if not (child is CharacterBody2D and child.name.is_valid_int()):
			child.queue_free()
	if map_path != "" and ResourceLoader.exists(map_path):
		var map_scene: PackedScene = load(map_path)
		if map_scene:
			var map_instance: Node = map_scene.instantiate()
			level_node.add_child(map_instance)
			level_node.move_child(map_instance, 0)

@rpc("authority", "call_local", "reliable")
func load_selected_minigame(minigame_path: String) -> void:
	if minigame_path != "" and ResourceLoader.exists(minigame_path):
		var minigame_scene: PackedScene = load(minigame_path)
		if minigame_scene:
			var minigame_instance: Node = minigame_scene.instantiate()
			if minigame_instance.has_method("add_player"):
				for pid in players.keys():
					var skin_index: int = players[pid]["skin_index"]
					var skin_path: String = skins[skin_index].scene.resource_path if skin_index < skins.size() and skins[skin_index] != null else "res://Player.tscn"
					minigame_instance.add_player(pid, players[pid]["name"], skin_path)
			if minigame_instance.has_signal("game_finished"):
				minigame_instance.game_finished.connect(_on_minigame_finished)
			level_node.add_child(minigame_instance)

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

# ==============================================================================
# Mini Game End & Score System
# ==============================================================================
func _on_minigame_finished(results: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	for player_id in results.keys():
		# FIX: Ensure player still exists
		if not players.has(player_id):
			continue
		var points: int = results[player_id]
		if player_scores.has(player_id):
			player_scores[player_id] += points
		else:
			player_scores[player_id] = points
		update_score_display.rpc(player_id, player_scores[player_id])

	var winner_id: int = _check_winner()
	if winner_id != -1:
		_declare_winner(winner_id)
		return

	if current_game_mode == GameMode.AUTO:
		await get_tree().create_timer(2.0).timeout
		if not is_instance_valid(self): return
		if not auto_play_queue.is_empty():
			_start_auto_mode()
		else:
			var final_winner: int = _get_winner()
			if final_winner != -1:
				_declare_winner(final_winner)
			else:
				status_message_changed.emit("🤝 It's a Tie!", Color.WHITE)
				await get_tree().create_timer(2.0).timeout
				if not is_instance_valid(self): return
				_return_to_lobby()
	else:
		await get_tree().create_timer(3.0).timeout
		if not is_instance_valid(self): return
		_return_to_lobby()

@rpc("authority", "call_local", "reliable")
func update_score_display(player_id: int, score: int) -> void:
	if not player_scores.has(player_id):
		player_scores[player_id] = 0
	player_scores[player_id] = score
	score_display_updated.emit()

func _check_winner() -> int:
	for pid in player_scores.keys():
		if player_scores[pid] >= score_to_win:
			return pid
	return -1

func _get_winner() -> int:
	var max_score: int = -1
	var winner: int = -1
	var tie: bool = false
	for pid in player_scores.keys():
		var s: int = player_scores[pid]
		if s > max_score:
			max_score = s
			winner = pid
			tie = false
		elif s == max_score:
			tie = true
	return winner if not tie else -1

func _declare_winner(winner_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not players.has(winner_id):
		return
	var winner_name: String = players[winner_id]["name"]
	game_winner_declared.emit(winner_id, winner_name)
	declare_winner.rpc(winner_id, winner_name)
	game_started = false
	start_button.disabled = true
	await get_tree().create_timer(4.0).timeout
	if not is_instance_valid(self): return
	_return_to_lobby()

@rpc("authority", "call_local", "reliable")
func declare_winner(winner_id: int, winner_name: String) -> void:
	game_winner_declared.emit(winner_id, winner_name)
	game_started = false

func _finish_auto_mode() -> void:
	var winner_id: int = _get_winner()
	if winner_id != -1:
		_declare_winner(winner_id)
	else:
		status_message_changed.emit("🤝 It's a Tie!", Color.WHITE)
		await get_tree().create_timer(2.0).timeout
		if not is_instance_valid(self): return
		_return_to_lobby()

# ==============================================================================
# Return to Lobby
# ==============================================================================
func _return_to_lobby() -> void:
	player_scores.clear()
	game_started = false
	countdown_active = false
	start_button.disabled = false

	_clear_level()
	_show_lobby_ui()

	if current_game_mode == GameMode.AUTO:
		_prepare_auto_queue()

	status_message_changed.emit("🔄 Back to Lobby!", Color.GREEN)
	
	# FIX: Sync cleared scores back to clients
	return_to_lobby.rpc(player_scores)

	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(self): return
	status_message_changed.emit("Ready", Color.WHITE)

	await get_tree().process_frame
	if not is_instance_valid(self): return
	if multiplayer.is_server():
		_respawn_all_players_in_lobby()

@rpc("authority", "call_local", "reliable")
func return_to_lobby(scores: Dictionary) -> void:
	if not multiplayer.is_server():
		player_scores = scores.duplicate()
		game_started = false
		countdown_active = false
		start_button.disabled = false
		_clear_level()
		_show_lobby_ui()
		status_message_changed.emit("🔄 Back to Lobby!", Color.GREEN)
		await get_tree().create_timer(2.0).timeout
		if not is_instance_valid(self): return
		status_message_changed.emit("Ready", Color.WHITE)
		score_display_updated.emit()

	await get_tree().process_frame
	if not is_instance_valid(self): return
	if multiplayer.is_server():
		_respawn_all_players_in_lobby()

# ==============================================================================
# Utility
# ==============================================================================
func _get_local_ip() -> String:
	var addresses: PackedStringArray = IP.get_local_addresses()
	# FIX: Improved IP detection
	for addr in addresses:
		# Prefer IPv4 local addresses
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172.16.") or addr.begins_with("172.17.") or addr.begins_with("172.18.") or addr.begins_with("172.19.") or addr.begins_with("172.20.") or addr.begins_with("172.21.") or addr.begins_with("172.22.") or addr.begins_with("172.23.") or addr.begins_with("172.24.") or addr.begins_with("172.25.") or addr.begins_with("172.26.") or addr.begins_with("172.27.") or addr.begins_with("172.28.") or addr.begins_with("172.29.") or addr.begins_with("172.30.") or addr.begins_with("172.31."):
			return addr
	# Fallback to first non-localhost
	for addr in addresses:
		if addr != "127.0.0.1" and addr != "::1":
			return addr
	return addresses[0] if addresses.size() > 0 else "127.0.0.1"

func _exit_tree() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	# FIX: Clean up tweens on exit
	if slot_tween:
		slot_tween.kill()
	for t in _active_flash_tweens:
		if is_instance_valid(t):
			t.kill()
