extends CharacterBody2D

var speed: float = 200
var last_dir : Vector2 = Vector2.RIGHT 
var is_attacking : bool = false
var hitbox_offset : Vector2
@onready var anim : AnimatedSprite2D = $anim
@onready var hitbox : Area2D = $hitbox

func _ready() -> void:
	#hitbox_offset
	hitbox_offset = hitbox.position
	$hitbox/CollisionShape2D.disabled = true

func _physics_process(_delta: float) -> void:
	
	if Input.is_action_just_pressed("attack") && !is_attacking:
		attack()
	if is_attacking:
		velocity = Vector2.ZERO
		return
	
	movement()
	process_animation()
	move_and_slide()


# move & animation
func movement() -> void:
	var direction := Input.get_vector("left","right","up","down")
	if direction != Vector2.ZERO:
		velocity = direction * speed
		last_dir = direction
		update_hitbox_offset()
	else: 
		velocity = Vector2.ZERO
	
	

func process_animation() -> void:
	if is_attacking:
		return
	if velocity != Vector2.ZERO:
		play_animation("walk", last_dir)
	else: 
		play_animation("idle", last_dir)
	
	
	
	
func play_animation(prefix: String,dir: Vector2):
	if dir.x != 0:
		anim.flip_h = dir.x < 0
		anim.play(prefix +"_right")
	elif dir.y < 0:
		anim.play(prefix +"_up")
	elif dir.y > 0:
		anim.play(prefix +"_down")

# attacking
func attack():
	is_attacking = true
	$hitbox/CollisionShape2D.disabled = false
	play_animation("attack", last_dir)
	


func _on_anim_animation_finished() -> void:
	if is_attacking:
		is_attacking = false
		$hitbox/CollisionShape2D.disabled = true
	pass # Replace with function body.


#hitbox 
func update_hitbox_offset() -> void:
	var x = hitbox_offset.x
	var y = hitbox_offset.y
	match last_dir:
		Vector2.LEFT:
			hitbox.position = Vector2(-x, y)
		Vector2.RIGHT:
			hitbox.position = Vector2(x, y)
		Vector2.UP:
			hitbox.position = Vector2(y, -x)
		Vector2.DOWN:
			hitbox.position = Vector2(y, x)
	


func _on_hitbox_body_entered(body: Node2D) -> void:
	if is_attacking && body.name.begins_with("enemy"):
		$hitbox/CollisionShape2D.disabled = false
		body.take_damage(30)
		print("hp")
	pass # Replace with function body.
