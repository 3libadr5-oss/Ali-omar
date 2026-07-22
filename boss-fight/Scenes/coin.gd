extends Area2D
class_name Coin

# ============================================================
# SIGNALS
# ============================================================
signal collected(player_id: int, coin: Coin)

# ============================================================
# EXPORT VARIABLES
# ============================================================
@export var rotation_speed: float = 2.0
@export var bob_speed: float = 1.5
@export var bob_amount: float = 8.0
@export var collect_animation_duration: float = 0.3
@export var point_value: int = 1

# ============================================================
# STATE
# ============================================================
var start_y: float = 0.0
var time: float = 0.0
var is_collected: bool = false
var target_player: Node = null
var collect_tween: Tween = null

# ============================================================
# NODES
# ============================================================
@onready var sprite: Sprite2D = $Sprite2D
@onready var glow: Sprite2D = $Glow
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

# ============================================================
# LIFECYCLE
# ============================================================
func _ready() -> void:
	start_y = position.y
	
	add_to_group("coin")
	add_to_group("collectible")
	
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	_start_idle_animation()

func _process(delta: float) -> void:
	if is_collected:
		return
	
	if sprite:
		sprite.rotation += rotation_speed * delta
	
	time += delta
	position.y = start_y + sin(time * bob_speed) * bob_amount
	
	if glow:
		glow.modulate.a = 0.5 + sin(time * 2.0) * 0.3

# ============================================================
# ANIMATIONS
# ============================================================
func _start_idle_animation() -> void:
	if animation_player and animation_player.has_animation("idle"):
		animation_player.play("idle")

# ============================================================
# COLLISION
# ============================================================
func _on_body_entered(body: Node) -> void:
	if is_collected:
		return
	
	# ✅ استخدم PlayerCharacter بدل MiniGamePlayer
	if body is PlayerCharacter or body is CharacterBody2D:
		_collect(body)

func _on_area_entered(area: Area2D) -> void:
	if is_collected:
		return
	
	if area.is_in_group("collect_zone"):
		var player = area.get_parent()
		# ✅ استخدم PlayerCharacter بدل MiniGamePlayer
		if player is PlayerCharacter or player is CharacterBody2D:
			_collect(player)

# ============================================================
# COLLECT
# ============================================================
func _collect(player: Node) -> void:
	if is_collected:
		return
	
	is_collected = true
	
	if collision:
		collision.set_deferred("disabled", true)
	
	var player_id = int(player.name) if player.name.is_valid_int() else 0
	
	collected.emit(player_id, self)
	
	_play_collect_effect(player)
	
	if player.has_method("add_score"):
		player.add_score(point_value)
	
	await get_tree().create_timer(collect_animation_duration + 0.2).timeout
	queue_free()

# ============================================================
# COLLECT EFFECT
# ============================================================
func _play_collect_effect(player: Node) -> void:
	if collect_tween and collect_tween.is_running():
		collect_tween.kill()
	
	collect_tween = create_tween()
	collect_tween.set_parallel(true)
	
	collect_tween.tween_property(self, "scale", Vector2(1.5, 1.5), collect_animation_duration)
	collect_tween.tween_property(self, "modulate", Color.TRANSPARENT, collect_animation_duration)
	
	if player:
		var target_pos = player.global_position - global_position
		collect_tween.tween_property(self, "position", position + target_pos * 0.5, collect_animation_duration)
	
	if animation_player and animation_player.has_animation("collect"):
		animation_player.play("collect")
	
	_spawn_particles()

func _spawn_particles() -> void:
	var particles = get_node_or_null("Particles2D")
	if particles:
		particles.emitting = true
		var particle_copy = particles.duplicate()
		particle_copy.global_position = global_position
		get_parent().add_child(particle_copy)
		await get_tree().create_timer(1.0).timeout
		particle_copy.queue_free()

# ============================================================
# UTILITY
# ============================================================
func set_point_value(value: int) -> void:
	point_value = value

func get_point_value() -> int:
	return point_value

func set_coin_color(color: Color) -> void:
	if sprite:
		sprite.modulate = color

func set_coin_scale(scale_factor: float) -> void:
	scale = Vector2(scale_factor, scale_factor)
