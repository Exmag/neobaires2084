extends CharacterBody2D

@onready var sprite = $AnimatedSprite2D
@onready var timer = $Timer

var destino := Vector2.ZERO
var velocidad := 20.0
var moviendose := false


func _physics_process(delta):
	if !is_multiplayer_authority():
		return

	if moviendose:
		var dir = (destino - global_position).normalized()
		velocity = dir * velocidad
		move_and_slide()

		if global_position.distance_to(destino) < 2:
			global_position = destino
			velocity = Vector2.ZERO
			moviendose = false
			timer.start(randf_range(0.5, 2.0))
			return

		if get_slide_collision_count() > 0:
			velocity = Vector2.ZERO
			move_and_slide()
			moviendose = false
			timer.start(randf_range(0.5, 2.0))
			return


func _on_timer_timeout():
	if !is_multiplayer_authority():
		return

	var direcciones = [
		Vector2.UP,
		Vector2.DOWN,
		Vector2.LEFT,
		Vector2.RIGHT
	]

	var dir = direcciones.pick_random()
	var distancia = randi_range(32, 48)

	destino = global_position + dir * distancia
	actualizar_animacion.rpc(dir)

	moviendose = true


@rpc("call_local", "reliable")
func actualizar_animacion(dir: Vector2):
	if dir == Vector2.UP:
		sprite.play("dron_idle_top")
	elif dir == Vector2.DOWN:
		sprite.play("dron_idle_down")
	elif dir == Vector2.LEFT:
		sprite.play("dron_idle_left")
	elif dir == Vector2.RIGHT:
		sprite.play("dron_idle_right")
