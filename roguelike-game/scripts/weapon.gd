extends Area2D

var damage: int = 10
var is_active: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	monitoring = false  # نطفيه في البداية

func _on_body_entered(body: Node2D) -> void:
	if not is_active:
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(damage)
		print("السيف ضرب اللاعب!")

func activate() -> void:
	is_active = true
	monitoring = true

func deactivate() -> void:
	is_active = false
	monitoring = false
