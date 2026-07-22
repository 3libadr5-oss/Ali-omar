extends BaseWeapon
class_name Staff

# ============================================================
# خصائص العصا
# ============================================================
@export var magic_damage: float = 15.0
@export var magic_range: float = 200.0
@export var mana_cost: float = 10.0

# ============================================================
# NODES
# ============================================================
@onready var staff_sprite: Sprite2D = $StaffSprite
@onready var magic_particles: GPUParticles2D = $MagicParticles

# ============================================================
# الهجوم - إطلاق سحر
# ============================================================
func attack(attacker: Node2D, direction: Vector2) -> void:
	print("🧙 Staff magic attack!")
	
	# اتجاه العصا
	rotation = direction.angle()
	
	# تأثير سحري
	if magic_particles:
		magic_particles.emitting = true
		await get_tree().create_timer(0.3).timeout
		magic_particles.emitting = false
	
	# إطلاق السحر (يبحث عن الأعداء في النطاق)
	_apply_magic(attacker, direction)

func _apply_magic(attacker: Node2D, direction: Vector2) -> void:
	# البحث عن اللاعبين في النطاق
	var targets = get_tree().get_nodes_in_group("players")
	for target in targets:
		if target == attacker:
			continue
		
		var distance = attacker.global_position.distance_to(target.global_position)
		if distance < magic_range:
			if target.has_method("take_damage"):
				target.take_damage(magic_damage)
				print("🧙 Magic hit for ", magic_damage, " damage!")

# ============================================================
# تأثير إضافي - السحر يضرب الكل في النطاق
# ============================================================
func _on_magic_area_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemy"):
		area.get_parent().take_damage(magic_damage * 1.5)
