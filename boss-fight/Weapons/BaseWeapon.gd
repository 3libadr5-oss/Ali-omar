extends Node2D
class_name BaseWeapon

# ============================================================
# خصائص السلاح
# ============================================================
@export var weapon_name: String = "Weapon"
@export var damage: float = 20.0
@export var range: float = 50.0
@export var attack_speed: float = 1.0  # هجمات في الثانية
@export var knockback: float = 100.0

# ============================================================
# دوال الهجوم (كل سلاح ينفذها بطريقته)
# ============================================================
func attack(attacker: Node2D, direction: Vector2) -> void:
	print("🔶 Base attack from ", weapon_name)
	# كل سلاح ينفذ ده بطريقته

func get_damage() -> float:
	return damage

func get_range() -> float:
	return range
