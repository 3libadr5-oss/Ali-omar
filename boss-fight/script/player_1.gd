extends CharacterBody2D

# ============================================================
# 📦 SIGNALS (always present, regardless of toggles)
# ============================================================
signal coin_collected(coin_node: Node)
signal item_picked(item_node: Node)
signal player_died()
signal score_updated(new_score: int)

# ============================================================
# 🎮 EXPORT GROUPS – FEATURE TOGGLES & PARAMETERS
# ============================================================

# ---------- Movement ----------
@export_group("Movement")
@export var enable_movement: bool = true
@export var MAX_SPEED: float = 350.0
@export var ACCELERATION: float = 2000.0
@export var FRICTION: float = 1800.0

# ---------- Jump ----------
@export_group("Jump")
@export var enable_jump: bool = true
@export var gravity: float = 980.0
@export var jump_velocity: float = -400.0

# ---------- Dash ----------
@export_group("Dash")
@export var enable_dash: bool = true
@export var DASH_SPEED: float = 1000.0
@export var DASH_DURATION: float = 0.15
@export var DASH_COOLDOWN: float = 0.6

# ---------- Combat & Weapons ----------
@export_group("Combat")
@export var enable_combat: bool = true
@export var LUNGE_SPEED: float = 500.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 50.0
@export var weapon_scene: PackedScene = null   # assign in Inspector

# ---------- Health ----------
@export_group("Health")
@export var enable_health: bool = true
@export var MAX_HEALTH: float = 100.0

# ---------- Collectibles & Scoring ----------
@export_group("Collectibles")
@export var enable_collectibles: bool = true

# ---------- Animations ----------
@export_group("Visuals / Animations")
@export var enable_animations: bool = true

# ============================================================
# 🧬 STATE VARIABLES (used regardless of toggles)
# ============================================================
enum GameMode { DEFAULT, COLLECT, MEMORY, RACE, SHOOT }
var current_game_mode: GameMode = GameMode.DEFAULT

var input_vector: Vector2 = Vector2.ZERO
var last_move_direction: Vector2 = Vector2.RIGHT
var movement_enabled: bool = true
var is_local_player: bool = false
var player_name: String = ""

# Health (only used if enable_health)
var health: float = MAX_HEALTH
var is_invincible: bool = false

# Dash (only used if enable_dash)
var is_dashing: bool = false
var dash_direction: Vector2 = Vector2.RIGHT

# Combat (only used if enable_combat)
var is_attacking: bool = false
var combo_step: int = 0
var combo_window: bool = false
var current_weapon: Node = null

# Scoring (only used if enable_collectibles)
var score: int = 0

# ============================================================
# 🎯 NODE REFERENCES
# ============================================================
@onready var camera: Camera2D = $Camera2D
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var name_label: Label = $NameLabel
@onready var collision_shape: CollisionPolygon2D = $CollisionShape2D


# Optional nodes – they may be missing if the feature is off
@onready var dash_timer: Timer = $DashTimer if has_node("DashTimer") else null
@onready var dash_cooldown_timer: Timer = $DashCooldownTimer if has_node("DashCooldownTimer") else null
@onready var sword_area: Area2D = $SwordArea if has_node("SwordArea") else null
@onready var weapon_holder: Node2D = $WeaponHolder if has_node("WeaponHolder") else null

# ============================================================
# 🚀 LIFECYCLE
# ============================================================
func _ready() -> void:
	# Multiplayer authority
	if multiplayer and multiplayer.multiplayer_peer:
		set_multiplayer_authority(name.to_int())
		print("✅ Multiplayer authority set for: ", name)
	else:
		print("⚠️ Multiplayer not available, skipping authority")

	# Setup camera
	_setup_camera()

	# Conditionally setup features
	if enable_combat:
		_setup_sword_area()
		_equip_weapon()

	if enable_animations and animated_sprite:
		animated_sprite.animation_finished.connect(_on_animation_finished)

	# Disable unused nodes to avoid errors
	if not enable_dash and dash_timer:
		dash_timer.stop()
	if not enable_combat and sword_area:
		sword_area.monitoring = false
		sword_area.monitorable = false

func _setup_camera() -> void:
	if camera:
		camera.enabled = false
		if not has_node("RemoteTransform2D"):
			var remote_transform = RemoteTransform2D.new()
			remote_transform.name = "RemoteTransform2D"
			remote_transform.remote_path = camera.get_path()
			add_child(remote_transform)

func _setup_sword_area() -> void:
	if sword_area:
		sword_area.area_entered.connect(_on_sword_area_area_entered)
		sword_area.body_entered.connect(_on_sword_area_body_entered)

# ============================================================
# 🔫 WEAPON SYSTEM (only if enable_combat)
# ============================================================
func _equip_weapon() -> void:
	if not enable_combat:
		return
	if weapon_scene:
		if current_weapon:
			current_weapon.queue_free()
			current_weapon = null
		current_weapon = weapon_scene.instantiate()
		if weapon_holder:
			weapon_holder.add_child(current_weapon)
		else:
			add_child(current_weapon)
		print("🔫 Weapon equipped: ", current_weapon.name)
		if current_weapon.has_method("get_damage"):
			attack_damage = current_weapon.get_damage()
		if current_weapon.has_method("get_range"):
			attack_range = current_weapon.get_range()

func set_weapon(weapon: PackedScene) -> void:
	if not enable_combat:
		return
	weapon_scene = weapon
	_equip_weapon()

# ============================================================
# 🎥 CAMERA SETUP (always works)
# ============================================================
func set_local_player(is_local: bool) -> void:
	is_local_player = is_local
	if is_local:
		if camera:
			camera.enabled = true
			camera.position = Vector2.ZERO
	else:
		if camera:
			camera.enabled = false

# ============================================================
# 🎮 PUBLIC METHODS (used by BaseMiniGame)
# ============================================================
func set_movement_enabled(enabled: bool) -> void:
	movement_enabled = enabled

func set_game_mode(mode: GameMode) -> void:
	current_game_mode = mode

func set_name_label(new_name: String) -> void:
	player_name = new_name
	if name_label:
		name_label.text = new_name
		name_label.text_direction = Control.TEXT_DIRECTION_RTL

func get_name_label() -> String:
	return player_name

func add_score(points: int) -> void:
	if not enable_collectibles:
		return
	score += points
	score_updated.emit(score)
	if is_local_player:
		_update_score_ui()

func _update_score_ui() -> void:
	if not enable_collectibles:
		return
	var parent = get_parent()
	while parent and not parent is BaseMiniGame:
		parent = parent.get_parent()
	
	if parent and parent is BaseMiniGame:
		var score_label = parent.get_node_or_null("UI/LocalScore")
		if score_label:
			score_label.text = "Your Score: " + str(score)

func get_score() -> int:
	return score

func reset_score() -> void:
	score = 0
	score_updated.emit(0)

func take_damage(amount: float) -> void:
	if not enable_health:
		return
	if is_invincible:
		return
	health -= amount
	modulate = Color.RED
	await get_tree().create_timer(0.15).timeout
	modulate = Color.WHITE
	if health <= 0:
		player_died.emit()
		_respawn()

# ============================================================
# 🧬 PHYSICS PROCESS – CONDITIONAL EXECUTION
# ============================================================
func _physics_process(delta: float) -> void:
	if not multiplayer or not multiplayer.multiplayer_peer:
		return
	if not is_multiplayer_authority():
		return
	if not movement_enabled:
		return

	# ---- Handle Input ----
	_handle_input()

	# ---- Movement ----
	if enable_movement:
		_handle_movement(delta)

	# ---- Jump ----
	if enable_jump:
		_handle_jump(delta)

	# ---- Dash ----
	if enable_dash and is_dashing:
		velocity = dash_direction * DASH_SPEED

	# ---- Apply velocity ----
	move_and_slide()

	# ---- Animations ----
	if enable_animations:
		update_visuals()

	# ---- Camera follow ----
	if is_local_player and camera and camera.enabled:
		camera.position = Vector2.ZERO

# ============================================================
# 🎮 INPUT HANDLING (conditional)
# ============================================================
func _handle_input() -> void:
	if not is_local_player:
		return

	# Movement input
	if enable_movement:
		input_vector.x = Input.get_axis("ui_left", "ui_right")
		input_vector.y = Input.get_axis("ui_up", "ui_down")
		input_vector = input_vector.normalized()
		if input_vector != Vector2.ZERO:
			last_move_direction = input_vector

	# Dash input
	if enable_dash and Input.is_action_just_pressed("ui_select") and dash_cooldown_timer and dash_cooldown_timer.is_stopped():
		start_dash()

	# Combat input
	if enable_combat and Input.is_action_just_pressed("click") and not is_dashing:
		handle_attack_input()

	# Jump input
	if enable_jump and Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Special game modes (these may override some inputs)
	match current_game_mode:
		GameMode.MEMORY:
			if Input.is_action_just_pressed("click"):
				_handle_memory_click()
		GameMode.SHOOT:
			if Input.is_action_just_pressed("click"):
				_handle_shoot()

# ============================================================
# 🏃 MOVEMENT
# ============================================================
func _handle_movement(delta: float) -> void:
	if is_dashing:
		return   # dash overrides movement
	if is_attacking and enable_combat:
		# during attack, decelerate (but lunge handles initial impulse)
		velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
	else:
		if input_vector != Vector2.ZERO:
			velocity = velocity.move_toward(input_vector * MAX_SPEED, ACCELERATION * delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)

# ============================================================
# 🦘 JUMP
# ============================================================
func _handle_jump(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y += gravity * delta

# ============================================================
# 💨 DASH (only if enable_dash)
# ============================================================
func start_dash() -> void:
	if not enable_dash:
		return
	is_dashing = true
	is_invincible = true   # if health is enabled, this works
	is_attacking = false
	combo_step = 0
	combo_window = false

	if enable_animations and animated_sprite:
		animated_sprite.play("dash")
		if last_move_direction.x > 0:
			animated_sprite.flip_h = false
		elif last_move_direction.x < 0:
			animated_sprite.flip_h = true

	if dash_timer:
		dash_timer.start(DASH_DURATION)
	if dash_cooldown_timer:
		dash_cooldown_timer.start(DASH_COOLDOWN)

	modulate = Color(0, 2, 5)   # visual feedback
	# Sync direction visually
	var flip_h = false if last_move_direction.x > 0 else true if last_move_direction.x < 0 else animated_sprite.flip_h
	sync_visual_direction(flip_h, last_move_direction.angle())

func _on_dash_timer_timeout() -> void:
	is_dashing = false
	is_invincible = false
	modulate = Color.WHITE

# ============================================================
# ⚔️ COMBAT (only if enable_combat)
# ============================================================
func handle_attack_input() -> void:
	if not enable_combat:
		return
	if not is_attacking:
		combo_step = 1
		start_attack("attack_1")
	elif combo_window and combo_step == 1:
		combo_step = 2
		combo_window = false
		start_attack("attack_2")

func start_attack(anim_name: String) -> void:
	if not enable_combat:
		return
	is_attacking = true
	var attack_dir = input_vector if input_vector != Vector2.ZERO else last_move_direction

	if sword_area:
		sword_area.rotation = attack_dir.angle()

	if enable_animations and animated_sprite:
		if attack_dir.x > 0:
			animated_sprite.flip_h = false
		elif attack_dir.x < 0:
			animated_sprite.flip_h = true
		animated_sprite.play(anim_name)

	# Use weapon if available
	if current_weapon and current_weapon.has_method("attack"):
		current_weapon.attack(self, attack_dir)

	# Lunge
	velocity = attack_dir * LUNGE_SPEED

	sync_visual_direction(animated_sprite.flip_h, sword_area.rotation if sword_area else 0.0)

func _on_animation_finished() -> void:
	if not enable_combat or not animated_sprite:
		return
	var anim_name = animated_sprite.animation
	if anim_name == "attack_1":
		combo_window = true
		is_attacking = false
		get_tree().create_timer(0.2).timeout.connect(_on_combo_timeout)
	elif anim_name == "attack_2":
		is_attacking = false
		combo_step = 0
		combo_window = false

func _on_combo_timeout() -> void:
	if combo_step == 1:
		combo_step = 0
		combo_window = false

# ============================================================
# 🎯 COLLISION & INTERACTION (conditional)
# ============================================================
func _on_sword_area_area_entered(area: Area2D) -> void:
	if not enable_combat:
		return
	if area.is_in_group("boss_hurtbox"):
		area.get_parent().take_damage(attack_damage)

func _on_sword_area_body_entered(body: Node) -> void:
	if not enable_collectibles:
		return
	if body.is_in_group("coin"):
		if body.has_method("collect"):
			body.collect(self)
		else:
			coin_collected.emit(body)
			add_score(1)
	elif body.is_in_group("collectible"):
		if body.has_method("collect"):
			body.collect(self)

# ============================================================
# 🎮 SPECIAL GAME MODE INPUTS
# ============================================================
func _handle_memory_click() -> void:
	var mouse_pos = get_global_mouse_position()
	var cards = get_tree().get_nodes_in_group("memory_card")
	for card in cards:
		if card.global_position.distance_to(mouse_pos) < 50:
			if card.has_method("flip"):
				card.flip()
			break

func _handle_shoot() -> void:
	var bullet_scene = load("res://Minigames/Shooting/Bullet.tscn")
	if bullet_scene:
		var bullet = bullet_scene.instantiate()
		bullet.position = global_position + last_move_direction * 30
		bullet.direction = last_move_direction
		get_parent().add_child(bullet)

# ============================================================
# 🎨 VISUAL SYNC (only if enable_animations)
# ============================================================
func sync_visual_direction(flip_h: bool, rotation_angle: float) -> void:
	if not enable_animations:
		return
	if not multiplayer.multiplayer_peer:
		return
	if animated_sprite:
		animated_sprite.flip_h = flip_h
	if sword_area:
		sword_area.rotation = rotation_angle
	update_visual_direction.rpc(flip_h, rotation_angle)

@rpc("authority", "call_local")
func update_visual_direction(flip_h: bool, rotation_angle: float) -> void:
	if not enable_animations:
		return
	if not multiplayer.multiplayer_peer:
		return
	var caller_id = multiplayer.get_remote_sender_id()
	if caller_id == 0:
		caller_id = multiplayer.get_unique_id()
	if name.to_int() == multiplayer.get_unique_id():
		return
	if animated_sprite:
		animated_sprite.flip_h = flip_h
	if sword_area:
		sword_area.rotation = rotation_angle

func update_visuals() -> void:
	if not enable_animations or not animated_sprite or is_dashing or is_attacking:
		return
	if input_vector != Vector2.ZERO:
		last_move_direction = input_vector

	var new_flip_h = animated_sprite.flip_h
	var new_rotation = sword_area.rotation if sword_area else 0.0
	var dir = last_move_direction

	if dir == Vector2(0, 1):
		new_flip_h = false
		new_rotation = PI / 2
	elif dir == Vector2(0, -1):
		new_flip_h = false
		new_rotation = -PI / 2
	elif dir == Vector2(1, 0):
		new_flip_h = false
		new_rotation = 0.0
	elif dir == Vector2(-1, 0):
		new_flip_h = true
		new_rotation = PI
	elif dir == Vector2(1, 1):
		new_flip_h = false
		new_rotation = PI / 4
	elif dir == Vector2(-1, 1):
		new_flip_h = true
		new_rotation = 3 * PI / 4
	elif dir == Vector2(1, -1):
		new_flip_h = false
		new_rotation = -PI / 4
	elif dir == Vector2(-1, -1):
		new_flip_h = true
		new_rotation = -3 * PI / 4
	else:
		return

	if animated_sprite.flip_h != new_flip_h or (sword_area and sword_area.rotation != new_rotation):
		sync_visual_direction(new_flip_h, new_rotation)

	if input_vector != Vector2.ZERO:
		animated_sprite.play("walk")
	else:
		animated_sprite.play("idle")

# ============================================================
# 💔 HEALTH (only if enable_health)
# ============================================================
func _respawn() -> void:
	if not enable_health:
		return
	health = MAX_HEALTH
	position = Vector2.ZERO
	modulate = Color.WHITE
	movement_enabled = true

# ============================================================
# 🧹 CLEANUP
# ============================================================
func _exit_tree() -> void:
	if enable_animations and animated_sprite:
		animated_sprite.animation_finished.disconnect(_on_animation_finished)
	if enable_combat and sword_area:
		sword_area.area_entered.disconnect(_on_sword_area_area_entered)
		sword_area.body_entered.disconnect(_on_sword_area_body_entered)
