extends Node2D

@onready var anim = $AnimatedSprite2D
@onready var timer = $Timer
@onready var sonido = $sonido_escudo

func _ready():
	
	timer.timeout.connect(_on_Timer_timeout)
	anim.animation_finished.connect(_on_animation_finished)
	sonido.play()
	anim.play("shield_in")

func _on_animation_finished():

	if anim.animation == "shield_in":
		timer.start(2.0)
	else:
		queue_free()

func _on_Timer_timeout():
	anim.play("shield_out")
