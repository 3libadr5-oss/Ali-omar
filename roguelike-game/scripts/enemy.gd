extends CharacterBody2D

# ثوابت
const SPEED = 60.0
const ATTACK_RANGE = 50.0
const ATTACK_COOLDOWN = 1.2

# متغيرات
var target: Node2D = null
var hp: int = 100
var can_attack: bool = true
var is_swinging: bool = false

# عقد
@onready var anim: AnimatedSprite2D = $anim
@onready var sight_area: Area2D = $sight
@onready var hand_marker: Marker2D = $hand_marker
@onready var attack_timer: Timer = $attack_cooldown

# السلاح
var weapon_instance: Area2D = null

func _ready() -> void:
	var weapon_scene = load("res://scenes/Weapon.tscn")
	if weapon_scene:
		weapon_instance = weapon_scene.instantiate()
		hand_marker.add_child(weapon_instance)
		weapon_instance.position = Vector2(25, 0)
		print("✅ تم تحميل السلاح بنجاح")
	else:
		print("⚠️ سلاح مش موجود")
	
	sight_area.body_entered.connect(_on_sight_body_entered)
	sight_area.body_exited.connect(_on_sight_body_exited)
	attack_timer.timeout.connect(_on_attack_cooldown_timeout)
	
	print("✅ العدو جاهز")

func _physics_process(delta: float) -> void:
	if hp <= 0:
		die()
		return
	
	if target:
		var direction = (target.global_position - global_position).normalized()
		var distance = global_position.distance_to(target.global_position)
		
		hand_marker.look_at(target.global_position)
		
		if distance > ATTACK_RANGE:
			velocity = direction * SPEED
			# تشغيل أنيميشن المشي بأمان
			play_anim_safe("walk", true)
			if weapon_instance:
				weapon_instance.deactivate()
		else:
			velocity = Vector2.ZERO
			play_anim_safe("idle", true)
			if can_attack and not is_swinging:
				_attack()
	else:
		velocity = Vector2.ZERO
		play_anim_safe("idle", true)
		if weapon_instance:
			weapon_instance.deactivate()
	
	move_and_slide()

# دالة آمنة لتشغيل الأنيميشن
func play_anim_safe(anim_name: String, use_default: bool = true) -> void:
	if anim.sprite_frames and anim.sprite_frames.get_animation_names().has(anim_name):
		anim.play(anim_name)
	elif use_default and anim.sprite_frames and anim.sprite_frames.get_animation_names().size() > 0:
		# لو مش موجود، اشغل أول أنيميشن موجود
		anim.play(anim.sprite_frames.get_animation_names()[0])

func _attack() -> void:
	if not weapon_instance:
		print("❌ مفيش سلاح")
		can_attack = false
		attack_timer.start(ATTACK_COOLDOWN)
		return
	
	can_attack = false
	is_swinging = true
	
	var base_angle = hand_marker.rotation
	var start_angle = base_angle - deg_to_rad(45)
	var end_angle = base_angle + deg_to_rad(45)
	
	weapon_instance.rotation = start_angle - base_angle
	
	var tween = create_tween()
	tween.tween_property(weapon_instance, "rotation", end_angle - base_angle, 0.15)
	tween.tween_callback(func(): 
		if weapon_instance:
			weapon_instance.activate()
			print("🗡️ السيف نشط!")
	)
	tween.tween_callback(func(): 
		if weapon_instance:
			weapon_instance.deactivate()
		is_swinging = false
		weapon_instance.rotation = 0.0
		print("🛑 انتهت الأرجحة")
	)
	
	attack_timer.start(ATTACK_COOLDOWN)

func _on_attack_cooldown_timeout() -> void:
	can_attack = true

func _on_sight_body_entered(body: Node2D) -> void:
	print("🟢 حاجة دخلت: ", body.name)
	if body.name == "player" or body.is_in_group("player"):
		target = body
		print("✅ تم تعيين الهدف")

func _on_sight_body_exited(body: Node2D) -> void:
	print("🔴 حاجة طلعت: ", body.name)
	if body == target:
		target = null
		if weapon_instance:
			weapon_instance.deactivate()
		is_swinging = false

func take_damage(damage: int) -> void:
	hp -= damage
	print("💥 العدو اتصاب! الحياة: ", hp)

func die() -> void:
	print("💀 العدو مات")
	if weapon_instance:
		weapon_instance.queue_free()
	queue_free()
