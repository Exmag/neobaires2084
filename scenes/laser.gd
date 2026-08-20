extends Area2D

var speed = 300
var owner_id : int
var damage = 5

func _ready():
	$sonido_laser.play()
	set_as_top_level(true)
	body_entered.connect(_on_body_entered)

func _process(delta):
	position += (Vector2.RIGHT*speed).rotated(rotation) * delta

func _on_visible_on_screen_enabler_2d_screen_exited():
	queue_free()

func _on_body_entered(body):
	if body is Player:
		# Que no se pegue a sí mismo
		if body.get_multiplayer_authority() == owner_id:
			return
		# El daño lo reporta SOLO el dueño del láser (evita aplicarlo duplicado)
		if multiplayer.get_unique_id() == owner_id:
			body.take_damage.rpc_id(body.get_multiplayer_authority(), damage, owner_id)
		# El láser desaparece visualmente en TODOS los clientes
		queue_free()
