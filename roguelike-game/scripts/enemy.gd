extends CharacterBody2D

const speed = 60
var target = null
var hp : int = 100
@onready var anim : AnimatedSprite2D = $anim

func _physics_process(delta: float) -> void:
	if target:
		_attack(delta)

	if hp <= 0:
		die()
	
func _attack(delta: float) -> void:
	var direction = (target.position - position).normalized()
	position += direction * speed * delta


func take_damage(damage: int) -> void:
	hp -= damage
	print(hp)

func die() -> void:
	queue_free()
func _on_sight_body_entered(body: Node2D) -> void:
	if body.name == "player":
		target = body
		print(target)
		anim.play("walk_right")
	pass # Replace with function body.


func _on_sight_body_exited(body: Node2D) -> void:
	if body.name == "player":
		target = null
		anim.play("idle")
	pass # Replace with function body.
