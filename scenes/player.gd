class_name Player
extends CharacterBody2D

signal dash_cooldown_started(time: float)
signal shield_cooldown_started(time: float)
signal invisibility_cooldown_started(time: float)
signal health_depleted

@onready var sonido_dash = $sonido_dash
@onready var sonido_invi = $sonido_invi
@export var invisibility_time := 10.0
@export var invisibility_cooldown := 25.0


var game_over := false
var invisible := false
var can_use_invisibility := true
var escudo_scene = preload("res://scenes/escudo.tscn")
var invulnerable = false
var health = 100.0
var spawn_points = []
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite
@onready var nombre_label: Label = $NombreLabel
var player_name := ""
var is_dashing = false
var dash_direction = Vector2.ZERO
var dash_speed = 0.0
@export var dash_time = 0.30
@export var dash_cooldown = 15.0
var dash_available = true
@export var shield_cooldown = 20.0
var shield_available = true
var ghost_timer = 0.0
@export var dash_distance = 100.0
var blaster_equiped = true
var blaster_cooldown = true
var shooting = false
var laser = preload("res://scenes/laser.tscn")
var mouse_loc_from_player = null
var target_position: Vector2
var my_spawn_position: Vector2
var speed = 100.0
var last_direction = "down"
var _last_anim_sent := ""


func _ready():
	spawn_points = [
		get_tree().current_scene.get_node("Level/Piso/SpawnPoint1"),
		get_tree().current_scene.get_node("Level/Piso/SpawnPoint2"),
		get_tree().current_scene.get_node("Level/Piso/SpawnPoint3"),
		get_tree().current_scene.get_node("Level/Piso/SpawnPoint4")
	]
	%ProgressBar.max_value = 100
	%ProgressBar.value = health
	if !is_multiplayer_authority():
		animated_sprite.modulate = Color.RED
	$Camera2D.enabled = is_multiplayer_authority()
	target_position = global_position
	dash_speed = dash_distance / dash_time
	# Limitar la sincronización de posición a 20 Hz para no saturar el WebSocket:
	for child in get_children():
		if child is MultiplayerSynchronizer:
			child.replication_interval = 0.05

func _enter_tree():
	set_multiplayer_authority(int(name))

func _set_anim(anim:String):
	if anim != _last_anim_sent:
		_last_anim_sent = anim
		sync_animation.rpc(anim)

func _input(event):
	if game_over:
		return
	if !is_multiplayer_authority():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			target_position = get_global_mouse_position()
	if Input.is_action_just_pressed("w") and shield_available:
		shield_available = false
		shield_cooldown_started.emit(shield_cooldown)
		crear_escudo()
		await get_tree().create_timer(shield_cooldown).timeout
		shield_available = true
	if Input.is_action_just_pressed("dash") and !is_dashing and dash_available:
		is_dashing = true
		reproducir_sonido_dash.rpc()
		dash_available = false
		dash_cooldown_started.emit(dash_cooldown)
		dash_direction = (get_global_mouse_position() - global_position).normalized()
		ghost_timer = 0.0
		await get_tree().create_timer(dash_time).timeout
		is_dashing = false
		target_position = global_position
		await get_tree().create_timer(dash_cooldown).timeout
		dash_available = true

func _physics_process(delta):
	if game_over:
		return
	mouse_loc_from_player = get_global_mouse_position() - global_position
	if !is_multiplayer_authority():
		return
	if Input.is_action_just_pressed("invisibility"):
		use_invisibility()
	if is_dashing:
		ghost_timer -= delta
		if ghost_timer <= 0:
			spawn_afterimage_rpc.rpc(
				animated_sprite.global_position,
				animated_sprite.global_rotation,
				animated_sprite.global_scale,
				animated_sprite.flip_h,
				animated_sprite.flip_v,
				animated_sprite.animation,
				animated_sprite.frame,
				animated_sprite.centered,
				animated_sprite.offset
			)
			ghost_timer = 0.03
	get_input()
	move_and_slide()
	var mouse_pos = get_global_mouse_position()
	$Marker2D.look_at(mouse_pos)
	if Input.is_action_just_pressed("q") and blaster_equiped and blaster_cooldown and !shooting:
		cancel_invisibility()
		shooting = true
		blaster_cooldown = false
		if abs(mouse_loc_from_player.x) > abs(mouse_loc_from_player.y):
			if mouse_loc_from_player.x > 0:
				last_direction = "right"
				_set_anim("shoot_right")
			else:
				last_direction = "left"
				_set_anim("shoot_left")
		else:
			if mouse_loc_from_player.y > 0:
				last_direction = "down"
				_set_anim("shoot_down")
			else:
				last_direction = "up"
				_set_anim("shoot_top")
		var spawn_pos = $SalidaLaser.global_position + Vector2.RIGHT.rotated($Marker2D.rotation) * 30
		spawn_laser.rpc(
			spawn_pos,
			$Marker2D.rotation,
			multiplayer.get_unique_id()
		)
		await get_tree().create_timer(0.15).timeout
		shooting = false
		if velocity == Vector2.ZERO:
			_set_anim("idle_" + last_direction)
		await get_tree().create_timer(0.25).timeout
		blaster_cooldown = true
		


@rpc("any_peer", "call_local", "reliable")
func reproducir_sonido_dash():
	sonido_dash.play()

@rpc("any_peer", "call_local", "reliable")
func reproducir_sonido_invi():
	sonido_invi.stop()
	sonido_invi.play()

func get_input():
	if shooting:
		velocity = Vector2.ZERO
		return
	if is_dashing:
		velocity = dash_direction * dash_speed
		return
	var direction = global_position.direction_to(target_position)
	if global_position.distance_to(target_position) < 5:
		velocity = Vector2.ZERO
		_set_anim("idle_" + last_direction)
		return
	velocity = direction * speed
	if abs(direction.x) > abs(direction.y):
		if direction.x > 0:
			last_direction = "right"
		else:
			last_direction = "left"
	else:
		if direction.y > 0:
			last_direction = "down"
		else:
			last_direction = "up"
	_set_anim("run_" + last_direction)

func update_animation(state):
	animated_sprite.play(state + "_" + last_direction)
	
@rpc("any_peer", "call_local", "reliable")
func set_spawn_position(pos: Vector2):
	my_spawn_position = pos
	if is_multiplayer_authority():
		global_position = pos
		target_position = pos

@rpc("any_peer", "call_local", "unreliable")
func sync_animation(anim_name):
	animated_sprite.play(anim_name)

@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: float, attacker_id: int):
	if invulnerable:
		return
	if is_multiplayer_authority():
		health -= amount
		if health <= 0:
			get_tree().current_scene.registrar_kill.rpc(
				attacker_id,
				multiplayer.get_unique_id()
			)
			respawn()
			return
		update_health_bar.rpc(health)

@rpc("any_peer", "call_local", "reliable")
func update_health_bar(new_health: float):
	health = new_health
	%ProgressBar.value = health
	%ProgressBar.queue_redraw()

func respawn():
	global_position = my_spawn_position
	target_position = global_position
	velocity = Vector2.ZERO
	last_direction = "down"
	_last_anim_sent = ""
	_set_anim("idle_down")
	health = 100
	update_health_bar.rpc(health)

@rpc("any_peer", "call_local", "reliable")
func spawn_laser(pos: Vector2, rot: float, shooter_id: int):
	var laser_instance = laser.instantiate()
	laser_instance.owner_id = shooter_id
	laser_instance.global_position = pos
	laser_instance.rotation = rot
	get_tree().current_scene.add_child(laser_instance)

@rpc("any_peer", "call_local", "unreliable")
func spawn_afterimage_rpc(
	pos: Vector2,
	rot: float,
	scale: Vector2,
	flip_h: bool,
	flip_v: bool,
	anim: String,
	frame: int,
	centered: bool,
	offset: Vector2
):
	var ghost := Sprite2D.new()
	ghost.texture = animated_sprite.sprite_frames.get_frame_texture(
		anim,
		frame
	)
	ghost.global_position = pos
	ghost.global_rotation = rot
	ghost.global_scale = scale
	ghost.centered = centered
	ghost.offset = offset
	if flip_h:
		ghost.scale.x *= -1
	if flip_v:
		ghost.scale.y *= -1
	ghost.modulate = Color(1, 1, 1, 0.6)
	get_tree().current_scene.add_child(ghost)
	var tween = create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.20)
	await tween.finished
	ghost.queue_free()

func crear_escudo():
	mostrar_escudo.rpc()

@rpc("any_peer", "call_local", "reliable")
func mostrar_escudo():
	if is_multiplayer_authority():
		invulnerable = true
	var escudo = escudo_scene.instantiate()
	add_child(escudo)
	escudo.position = Vector2.ZERO
	if is_multiplayer_authority():
		await escudo.tree_exited
		invulnerable = false

@rpc("any_peer", "call_local", "reliable")
func set_player_name(nombre:String):
	player_name = nombre
	nombre_label.text = nombre

func use_invisibility():
	if !is_multiplayer_authority():
		return
	if !can_use_invisibility:
		return
	can_use_invisibility = false
	reproducir_sonido_invi.rpc()
	invisibility_cooldown_started.emit(invisibility_cooldown)
	var cooldown_timer = get_tree().create_timer(invisibility_cooldown)
	invisible = true
	update_invisibility.rpc(true)
	await get_tree().create_timer(invisibility_time).timeout
	if invisible:
		invisible = false
		update_invisibility.rpc(false)
	await cooldown_timer.timeout
	can_use_invisibility = true

func cancel_invisibility():
	if !invisible:
		return
	invisible = false
	update_invisibility.rpc(false)


@rpc("any_peer", "call_local", "reliable")
func update_invisibility(state: bool):
	var tween = create_tween()
	if state:
		var alpha_objetivo := 0.0
		if is_multiplayer_authority():
			alpha_objetivo = 0.3
		tween.parallel().tween_property($AnimatedSprite, "modulate:a", alpha_objetivo, 0.5)
		tween.parallel().tween_property($NombreLabel, "modulate:a", alpha_objetivo, 0.5)
		tween.parallel().tween_property($ProgressBar, "modulate:a", alpha_objetivo, 0.5)
		await tween.finished
		if !is_multiplayer_authority():
			$AnimatedSprite.visible = false
			$NombreLabel.visible = false
			$ProgressBar.visible = false
	else:
		$AnimatedSprite.visible = true
		$NombreLabel.visible = true
		$ProgressBar.visible = true
		if is_multiplayer_authority():
			$AnimatedSprite.modulate.a = 0.3
			$NombreLabel.modulate.a = 0.3
			$ProgressBar.modulate.a = 0.3
		else:
			$AnimatedSprite.modulate.a = 0.0
			$NombreLabel.modulate.a = 0.0
			$ProgressBar.modulate.a = 0.0
		tween.parallel().tween_property($AnimatedSprite, "modulate:a", 1.0, 0.5)
		tween.parallel().tween_property($NombreLabel, "modulate:a", 1.0, 0.5)
		tween.parallel().tween_property($ProgressBar, "modulate:a", 1.0, 0.5)
		
