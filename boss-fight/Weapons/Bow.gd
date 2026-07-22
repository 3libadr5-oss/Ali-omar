extends BaseWeapon
class_name Bow

# ============================================================
# خصائص القوس
# ============================================================
@export var arrow_damage: float = 25.0
@export var arrow_speed: float = 800.0
@export var arrow_range: float = 400.0
@export var arrow_count: int = 1  # عدد الأسهم في الرمية

# ============================================================
# NODES
# ============================================================
@onready var bow_sprite: Sprite2D = $BowSprite
@onready var arrow_spawn: Node2D = $ArrowSpawn

# ============================================================
# الهجوم - إطلاق سهام
# ============================================================
func attack(attacker: Node2D, direction: Vector2) -> void:
	print("🏹 Bow attack!")
	
	# اتجاه القوس
	rotation = direction.angle()
	
	# إطلاق سهام
	for i in range(arrow_count):
		await get_tree().create_timer(0.1 * i).timeout
		_spawn_arrow(attacker, direction)

func _spawn_arrow(attacker: Node2D, direction: Vector2) -> void:
	var arrow_scene = load("res://Weapons/Arrow.tscn")
	if not arrow_scene:
		return
	
	var arrow = arrow_scene.instantiate()
	arrow.position = arrow_spawn.global_position if arrow_spawn else attacker.global_position
	arrow.direction = direction
	arrow.speed = arrow_speed
	arrow.damage = arrow_damage
	arrow.range = arrow_range
	
	# أضف السهم للعالم
	get_tree().current_scene.add_child(arrow)
	
	print("🏹 Arrow fired!")
