extends BaseWeapon
class_name WeaponDagger

@export var dagger_damage: float = 15.0
@export var dagger_range: float = 30.0
@export var dagger_speed: float = 0.1
@export var poison_damage: float = 5.0

@onready var dagger_sprite: Sprite2D = $DaggerSprite
@onready var hitbox: Area2D = $Hitbox

func _ready() -> void:
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)

func attack(attacker: Node2D, direction: Vector2) -> void:
	print("🗡️ Dagger attack!")
	
	rotation = direction.angle()
	
	if hitbox:
		hitbox.monitoring = true
		hitbox.monitorable = true
		
		await get_tree().create_timer(0.08).timeout
		hitbox.monitoring = false
		hitbox.monitorable = false
	
	if dagger_sprite:
		var tween = create_tween()
		tween.tween_property(dagger_sprite, "position", direction * 30, dagger_speed)
		tween.tween_property(dagger_sprite, "position", Vector2.ZERO, dagger_speed)

func _on_hitbox_body_entered(body: Node) -> void:
	if body is PlayerCharacter:
		var target = body
		if target.has_method("take_damage"):
			target.take_damage(dagger_damage)
			print("🗡️ Dagger hit for ", dagger_damage, " damage!")
			_apply_poison(target)

func _apply_poison(target: Node) -> void:
	if target.has_method("take_damage"):
		for i in range(3):
			await get_tree().create_timer(1.0).timeout
			target.take_damage(poison_damage)
			print("☠️ Poison damage: ", poison_damage)
