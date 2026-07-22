extends CharacterBody2D


# ============================================================
# 📦 SIGNALS
# ============================================================
signal coin_collected(coin_node: Node)
signal item_picked(item_node: Node)
signal player_died()
signal score_updated(new_score: int)

# ============================================================
# 🎮 EXPORT VARIABLES
# ============================================================
@export var MAX_SPEED: float = 350.0
@export var ACCELERATION: float = 2000.0
@export var FRICTION: float = 1800.0
@export var DASH_SPEED: float = 1000.0
@export var DASH_DURATION: float = 0.15
@export var DASH_COOLDOWN: float = 0.6
@export var LUNGE_SPEED: float = 500.0
@export var MAX_HEALTH: float = 100.0

# ✅ سلاح قابل للتحديد من الـ Inspector
@export var weapon_scene: PackedScene = null  # اسحب أي سلاح هنا

# ============================================================
# 🎮 GAME MODE VARIABLES
# ============================================================
enum GameMode { DEFAULT, COLLECT, MEMORY, RACE, SHOOT }
var current_game_mode: GameMode = GameMode.DEFAULT

# ============================================================
# 🧬 STATE VARIABLES
# ============================================================
var health: float = MAX_HEALTH
var input_vector: Vector2 = Vector2.ZERO
var dash_direction: Vector2 = Vector2.RIGHT
var last_move_direction: Vector2 = Vector2.RIGHT
var is_dashing: bool = false
var is_invincible: bool = false
var is_attacking: bool = false
var combo_step: int = 0
var combo_window: bool = false
var movement_enabled: bool = true
var is_local_player: bool = false
var score: int = 0
var player_name: String = ""

# ✅ متغيرات للـ Skin والسلاح
var skin_type: String = "default"
var attack_damage: float = 20.0
var attack_range: float = 50.0
var current_weapon: Node = null  # السلاح الحالي

# ============================================================
# 🎯 NODE REFERENCES
# ============================================================
@onready var camera: Camera2D = $Camera2D
@onready var dash_timer: Timer = $DashTimer
@onready var dash_cooldown_timer: Timer = $DashCooldownTimer
@onready var sword_area: Area2D = $SwordArea
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var name_label: Label = $NameLabel
@onready var collision_shape: CollisionPolygon2D = $CollisionShape2D
@onready var weapon_holder: Node2D = $WeaponHolder  # ✅ Node لحمل السلاح

# ============================================================
# 🚀 LIFECYCLE
# ============================================================
func _ready() -> void:
	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_animation_finished)
	
	if multiplayer and multiplayer.multiplayer_peer:
		set_multiplayer_authority(name.to_int())
		print("✅ Multiplayer authority set for: ", name)
	else:
		print("⚠️ Multiplayer not available, skipping authority")
	
	_setup_camera()
	_setup_sword_area()
	
	attack_damage = 20.0
	attack_range = 50.0
	
	# ✅ تجهيز السلاح
	_equip_weapon()

func _setup_camera() -> void:
	if camera:
		camera.enabled = false
		
		if not has_node("RemoteTransform2D"):
			var remote_transform = RemoteTransform2D.new()
			remote_transform.name = "RemoteTransform2D"
			remote_transform.remote_path = camera.get_path()
			add_child(remote_transform)
			print("✅ RemoteTransform2D added")

func _setup_sword_area() -> void:
	if sword_area:
		sword_area.area_entered.connect(_on_sword_area_area_entered)
		sword_area.body_entered.connect(_on_sword_area_body_entered)

# ============================================================
# 🔫 WEAPON SYSTEM
# ============================================================
func _equip_weapon() -> void:
	# ✅ لو في سلاح محدد في الـ Inspector
	if weapon_scene:
		# حذف السلاح القديم
		if current_weapon:
			current_weapon.queue_free()
			current_weapon = null
		
		# إنشاء السلاح الجديد
		current_weapon = weapon_scene.instantiate()
		
		# إضافة السلاح للـ WeaponHolder
		if weapon_holder:
			weapon_holder.add_child(current_weapon)
		else:
			add_child(current_weapon)
		
		print("🔫 Weapon equipped: ", current_weapon.name)
		
		# تحديث خصائص الهجوم من السلاح
		if current_weapon.has_method("get_damage"):
			attack_damage = current_weapon.get_damage()
		if current_weapon.has_method("get_range"):
			attack_range = current_weapon.get_range()
		
		print("⚔️ Damage: ", attack_damage, " | Range: ", attack_range)
	else:
		print("⚠️ No weapon assigned in Inspector")

# ✅ دالة لتغيير السلاح يدوياً
func set_weapon(weapon: PackedScene) -> void:
	weapon_scene = weapon
	_equip_weapon()

# ✅ دالة لتحديد السلاح حسب نوع الـ Skin
func set_weapon_by_type(type: String) -> void:
	var weapon_path = ""
	match type:
		"warrior":
			weapon_path = "res://Weapons/Sword.tscn"
		"mage":
			weapon_path = "res://Weapons/Staff.tscn"
		"archer":
			weapon_path = "res://Weapons/Bow.tscn"
		"rogue":
			weapon_path = "res://Weapons/Dagger.tscn"
		_:
			weapon_path = "res://Weapons/Sword.tscn"
	
	if weapon_path != "" and ResourceLoader.exists(weapon_path):
		var weapon = load(weapon_path)
		set_weapon(weapon)
		print("🔫 Weapon set by type: ", type)

# ============================================================
# 🎥 CAMERA SETUP
# ============================================================
func set_local_player(is_local: bool) -> void:
	is_local_player = is_local
	print("🎯 Player ", name, " is_local: ", is_local)
	
	if is_local:
		if camera:
			camera.enabled = true
			camera.position = Vector2.ZERO
			print("✅ Camera enabled for local player: ", name)
	else:
		if camera:
			camera.enabled = false
			print("❌ Camera disabled for remote player: ", name)

# ============================================================
# 🎮 PLAYER SETUP
# ============================================================
func set_movement_enabled(enabled: bool) -> void:
	movement_enabled = enabled

func set_game_mode(mode: GameMode) -> void:
	current_game_mode = mode
	print("🎮 Game mode set to: ", mode)

func set_name_label(new_name: String) -> void:
	player_name = new_name
	if name_label:
		name_label.text = new_name
		name_label.text_direction = Control.TEXT_DIRECTION_RTL

func get_name_label() -> String:
	return player_name

# ✅ دوال للـ Skin
func set_skin_type(type: String) -> void:
	skin_type = type
	print("🎨 Skin type set to: ", type)
	
	match type:
		"warrior":
			MAX_SPEED = 300.0
			attack_damage = 30.0
			attack_range = 60.0
			MAX_HEALTH = 150.0
			health = MAX_HEALTH
			set_weapon_by_type("warrior")
			
		"mage":
			MAX_SPEED = 350.0
			attack_damage = 15.0
			attack_range = 200.0
			MAX_HEALTH = 80.0
			health = MAX_HEALTH
			set_weapon_by_type("mage")
			
		"archer":
			MAX_SPEED = 400.0
			attack_damage = 25.0
			attack_range = 400.0
			MAX_HEALTH = 100.0
			health = MAX_HEALTH
			set_weapon_by_type("archer")
			
		"rogue":
			MAX_SPEED = 450.0
			attack_damage = 20.0
			attack_range = 40.0
			MAX_HEALTH = 90.0
			health = MAX_HEALTH
			set_weapon_by_type("rogue")
			
		_:
			MAX_SPEED = 350.0
			attack_damage = 20.0
			attack_range = 50.0
			MAX_HEALTH = 100.0
			health = MAX_HEALTH

func set_attack_stats(damage: float, range: float) -> void:
	attack_damage = damage
	attack_range = range

# ============================================================
# 🎯 SCORING SYSTEM
# ============================================================
func add_score(points: int) -> void:
	score += points
	score_updated.emit(score)
	
	if is_local_player:
		_update_score_ui()

func _update_score_ui() -> void:
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

# ============================================================
# 🧬 STATE MANAGEMENT
# ============================================================
func set_player_state(state: Dictionary) -> void:
	if state.has("health"):
		health = state["health"]
	if state.has("is_dashing"):
		is_dashing = state["is_dashing"]
	if state.has("is_invincible"):
		is_invincible = state["is_invincible"]
	if state.has("is_attacking"):
		is_attacking = state["is_attacking"]
	if state.has("combo_step"):
		combo_step = state["combo_step"]
	if state.has("combo_window"):
		combo_window = state["combo_window"]
	if state.has("modulate_color"):
		modulate = state["modulate_color"]
	if state.has("last_move_direction"):
		last_move_direction = state["last_move_direction"]
	if state.has("movement_enabled"):
		movement_enabled = state["movement_enabled"]
	if state.has("score"):
		score = state["score"]
		score_updated.emit(score)

func get_player_state() -> Dictionary:
	return {
		"health": health,
		"is_dashing": is_dashing,
		"is_invincible": is_invincible,
		"is_attacking": is_attacking,
		"combo_step": combo_step,
		"combo_window": combo_window,
		"modulate_color": modulate,
		"last_move_direction": last_move_direction,
		"movement_enabled": movement_enabled,
		"score": score
	}

# ============================================================
# 🔄 VISUAL SYNC
# ============================================================
func sync_visual_direction(flip_h: bool, rotation_angle: float) -> void:
	if not multiplayer.multiplayer_peer:
		return
	
	if animated_sprite:
		animated_sprite.flip_h = flip_h
	if sword_area:
		sword_area.rotation = rotation_angle
	
	update_visual_direction.rpc(flip_h, rotation_angle)

@rpc("authority", "call_local")
func update_visual_direction(flip_h: bool, rotation_angle: float) -> void:
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

# ============================================================
# 🎮 PHYSICS
# ============================================================
func _physics_process(delta: float) -> void:
	# ✅ تأكد من وجود multiplayer
	if not multiplayer or not multiplayer.multiplayer_peer:
		return
	
	# ✅ فقط اللاعب صاحب الصلاحية يتحكم في الفيزياء
	if not is_multiplayer_authority():
		return
	
	if not movement_enabled:
		return
	
	_handle_input()
	_handle_movement(delta)
	update_visuals()
	move_and_slide()
	
	# ✅ فقط الكاميرا المحلية تتبع
	if is_local_player and camera and camera.enabled:
		camera.position = Vector2.ZERO

func _handle_input() -> void:
	# ✅ بس اللاعب المحلي يتحكم
	if not is_local_player:
		return
	
	match current_game_mode:
		GameMode.COLLECT, GameMode.DEFAULT:
			_get_movement_input()
			_get_action_input()
		GameMode.MEMORY:
			_get_movement_input()
			if Input.is_action_just_pressed("click"):
				_handle_memory_click()
		GameMode.RACE:
			_get_movement_input()
		GameMode.SHOOT:
			_get_movement_input()
			if Input.is_action_just_pressed("click"):
				_handle_shoot()

func _get_movement_input() -> void:
	# ✅ بس اللاعب المحلي ياخد المدخلات
	if not is_local_player:
		input_vector = Vector2.ZERO
		return
	
	input_vector.x = Input.get_axis("ui_left", "ui_right")
	input_vector.y = Input.get_axis("ui_up", "ui_down")
	input_vector = input_vector.normalized()
	
	if input_vector != Vector2.ZERO:
		dash_direction = input_vector
		last_move_direction = input_vector

func _get_action_input() -> void:
	# ✅ بس اللاعب المحلي ياخد المدخلات
	if not is_local_player:
		return
	
	if Input.is_action_just_pressed("ui_select") and dash_cooldown_timer and dash_cooldown_timer.is_stopped():
		start_dash()
	
	if Input.is_action_just_pressed("click") and not is_dashing:
		handle_attack_input()

func _handle_movement(delta: float) -> void:
	if is_dashing:
		velocity = dash_direction * DASH_SPEED
	else:
		if is_attacking:
			velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)
		else:
			if input_vector != Vector2.ZERO:
				velocity = velocity.move_toward(input_vector * MAX_SPEED, ACCELERATION * delta)
			else:
				velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)

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
# 🎨 VISUALS
# ============================================================
func update_visuals() -> void:
	if not animated_sprite or is_dashing or is_attacking:
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
# 💨 DASH
# ============================================================
func start_dash() -> void:
	is_dashing = true
	is_invincible = true
	is_attacking = false
	combo_step = 0
	combo_window = false
	
	if animated_sprite:
		animated_sprite.play("dash")
		if dash_direction.x > 0:
			animated_sprite.flip_h = false
		elif dash_direction.x < 0:
			animated_sprite.flip_h = true
	
	if dash_timer:
		dash_timer.start(DASH_DURATION)
	if dash_cooldown_timer:
		dash_cooldown_timer.start(DASH_COOLDOWN)
	
	modulate = Color(0, 2, 5)
	
	var rotation_angle = dash_direction.angle()
	var flip_h = false if dash_direction.x > 0 else true if dash_direction.x < 0 else animated_sprite.flip_h
	sync_visual_direction(flip_h, rotation_angle)

func _on_dash_timer_timeout() -> void:
	is_dashing = false
	is_invincible = false
	modulate = Color.WHITE

# ============================================================
# ⚔️ ATTACK SYSTEM
# ============================================================
func handle_attack_input() -> void:
	if not is_attacking:
		combo_step = 1
		start_attack("attack_1")
	elif combo_window and combo_step == 1:
		combo_step = 2
		combo_window = false
		start_attack("attack_2")

func start_attack(anim_name: String) -> void:
	is_attacking = true
	var attack_dir = input_vector if input_vector != Vector2.ZERO else last_move_direction
	
	if sword_area:
		sword_area.rotation = attack_dir.angle()
	if animated_sprite:
		if attack_dir.x > 0:
			animated_sprite.flip_h = false
		elif attack_dir.x < 0:
			animated_sprite.flip_h = true
		animated_sprite.play(anim_name)
	
	# ✅ استخدم السلاح الحالي
	if current_weapon and current_weapon.has_method("attack"):
		current_weapon.attack(self, attack_dir)
	
	velocity = attack_dir * LUNGE_SPEED
	
	sync_visual_direction(animated_sprite.flip_h, sword_area.rotation if sword_area else 0.0)

func _on_animation_finished() -> void:
	if not animated_sprite:
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
# 🎯 COLLISION & INTERACTION
# ============================================================
func _on_sword_area_area_entered(area: Area2D) -> void:
	if area.is_in_group("boss_hurtbox"):
		area.get_parent().take_damage(attack_damage)

func _on_sword_area_body_entered(body: Node) -> void:
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
# 💔 HEALTH SYSTEM
# ============================================================
func take_damage(amount: float) -> void:
	if is_invincible:
		return
	
	health -= amount
	modulate = Color.RED
	await get_tree().create_timer(0.15).timeout
	modulate = Color.WHITE
	
	if health <= 0:
		player_died.emit()
		_respawn()

func _respawn() -> void:
	health = MAX_HEALTH
	position = Vector2.ZERO
	modulate = Color.WHITE
	movement_enabled = true

# ============================================================
# 🎮 COLLECTIBLE INTERACTION
# ============================================================
func _on_coin_collected(coin: Node) -> void:
	if current_game_mode == GameMode.COLLECT:
		add_score(1)
		coin.queue_free()
		
		var parent = get_parent()
		while parent and not parent is BaseMiniGame:
			parent = parent.get_parent()
		
		if parent and parent is BaseMiniGame and parent.has_method("_on_coin_collected"):
			parent._on_coin_collected(name.to_int(), coin)

# ============================================================
# 🧹 CLEANUP
# ============================================================
func _exit_tree() -> void:
	if animated_sprite:
		animated_sprite.animation_finished.disconnect(_on_animation_finished)
	
	if sword_area:
		sword_area.area_entered.disconnect(_on_sword_area_area_entered)
		sword_area.body_entered.disconnect(_on_sword_area_body_entered)
