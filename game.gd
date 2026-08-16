extends Node

const PLAYER = preload("res://scenes/player.tscn")

@onready var tube = get_node_or_null("TubeClient")

var _last_seen: Dictionary = {}
var _heartbeat_acum := 0.0
var _spawn_counter := 0
var _spawn_idx: Dictionary = {}
var ws_server_peer: WebSocketMultiplayerPeer
var ws_client_peer: WebSocketMultiplayerPeer

# const WS_SERVER_URL := "ws://localhost:8080"   # solo para pruebas locales
const WS_SERVER_URL := "wss://neobaires2084.onrender.com"

var players: Array[Player] = []
var dash_time_left := 0.0
var shield_time_left := 0.0
var invisibility_time_left := 0.0
var game_finished := false

func _ready():
	print("=== BUILD 2026-08-11 F ===")
	
	var spawner = get_node_or_null("MultiplayerSpawner")

	if spawner:
		print("[SPAWNER] encontrado")
		print("[SPAWNER] authority = ", spawner.get_multiplayer_authority())
		print("[SPAWNER] spawn_path = ", spawner.spawn_path)
		print("[SPAWNER] spawnable_scenes = ", spawner.spawnable_scenes)
	else:
		print("[SPAWNER] NO ENCONTRADO")
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_remove_player)

	if _es_servidor_dedicado():
		_iniciar_servidor_websocket()
		return

	if _usar_cliente_websocket():
		_configurar_cliente_websocket()
		return

	if tube == null:
		push_error("No existe TubeClient y no estamos en modo WebSocket.")
		return

	tube.session_created.connect(_on_session_created)
	tube.session_joined.connect(_on_session_joined)
	tube.session_left.connect(_on_session_left)
	tube.error_raised.connect(_on_tube_error)
	%Host.disabled = true
	%Join.disabled = true
	%HostOnlineID.editable = false

func _process(delta):
	if multiplayer.is_server():
		_heartbeat_acum += delta
		if _heartbeat_acum >= 5.0:
			_heartbeat_acum = 0.0
			_servidor_heartbeat()

	if Input.is_action_just_pressed("ui_accept"):
		print(PlayerData.players)
		if tube:
			print("session_id =", tube.session_id)
		else:
			print("URL WebSocket =", WS_SERVER_URL)

	if dash_time_left > 0:
		dash_time_left -= delta
		%DashCooldown.text = str(int(ceil(dash_time_left)))
		if dash_time_left <= 0:
			dash_time_left = 0
			%DashCooldown.hide()
			%icono_dash.modulate = Color.WHITE
	if shield_time_left > 0:
		shield_time_left -= delta
		%EscudoCooldown.text = str(int(ceil(shield_time_left)))
		if shield_time_left <= 0:
			shield_time_left = 0
			%EscudoCooldown.hide()
			%icono_escudo.modulate = Color.WHITE
	if invisibility_time_left > 0:
		invisibility_time_left -= delta
		%InvisibilidadCooldown.text = str(int(ceil(invisibility_time_left)))
		if invisibility_time_left <= 0:
			invisibility_time_left = 0
			%InvisibilidadCooldown.hide()
			%icono_invisibilidad.modulate = Color.WHITE

# ============ SERVIDOR / CLIENTE ============

func _es_servidor_dedicado() -> bool:
	return OS.get_environment("SERVER_MODE") == "1"

func _usar_cliente_websocket() -> bool:
	return OS.get_name() == "Web" or OS.get_environment("WS_CLIENT") == "1"

func _iniciar_servidor_websocket() -> void:
	var port := 8080
	if OS.has_environment("PORT"):
		port = OS.get_environment("PORT").to_int()
	ws_server_peer = WebSocketMultiplayerPeer.new()
	if ws_server_peer.create_server(port, "*") != OK:
		push_error("No se pudo crear el servidor WebSocket")
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = ws_server_peer
	print("[SERVER] Servidor WebSocket escuchando en el puerto ", port)

func _configurar_cliente_websocket() -> void:
	multiplayer.connected_to_server.connect(_on_session_joined)
	multiplayer.connection_failed.connect(_on_websocket_connection_failed)
	multiplayer.server_disconnected.connect(_on_session_left)
	%HostOnlineID.hide()
	%Host.hide()
	%Join.show()
	%Join.text = "Unirse a partida"
	%Join.disabled = true

func conectar_websocket() -> void:
	ws_client_peer = WebSocketMultiplayerPeer.new()
	var resultado = OK
	if ws_client_peer.has_method("connect_to_url"):
		resultado = ws_client_peer.call("connect_to_url", WS_SERVER_URL)
	elif ws_client_peer.has_method("create_client"):
		resultado = ws_client_peer.call("create_client", WS_SERVER_URL)
	else:
		push_error("Esta versión de Godot no tiene método de cliente WebSocket")
		return
	if resultado != OK:
		push_error("No se pudo iniciar la conexión WebSocket, error: " + str(resultado))
		return
	multiplayer.multiplayer_peer = ws_client_peer
	print("Conectando a WebSocket: ", WS_SERVER_URL)

func _on_websocket_connection_failed() -> void:
	push_error("Falló la conexión WebSocket")

# ============ HEARTBEAT ============

func _servidor_heartbeat():
	var now := Time.get_unix_time_from_system()
	for pid in _last_seen.keys():
		if now - _last_seen.get(pid, now) > 30.0:
			print("[SERVER] Expulsando peer inactivo: ", pid)
			_remove_player(pid)
		else:
			ping_jugador.rpc_id(pid)

@rpc("reliable")
func ping_jugador():
	pong_jugador.rpc_id(1)

@rpc("any_peer", "reliable")
func pong_jugador():
	_last_seen[multiplayer.get_remote_sender_id()] = Time.get_unix_time_from_system()

# ============ JUGADORES (única vía, spawn asignado por el servidor) ============

func _asignar_idx(pid:int) -> int:
	if _spawn_idx.has(pid):
		return _spawn_idx[pid]
	var idx := _spawn_counter % 4
	_spawn_counter += 1
	_spawn_idx[pid] = idx
	return idx

func _crear_jugador_local(pid:int, idx:int):
	
	if !multiplayer.is_server():
		return
	if get_node_or_null(str(pid)):
		print("[SERVER] Player ", pid, " ya existe")
		return
	var player = PLAYER.instantiate()
	player.name = str(pid)
	
	player.set_multiplayer_authority(pid)
	var piso = $Level/Piso
	var spawn_point = piso.get_child(idx % piso.get_child_count())
	var spawn_pos = spawn_point.global_position
	player.global_position = spawn_pos
	
	print("[SERVER] Creando Player ", pid)
	print("[SERVER] idx = ", idx)
	print("[SERVER] spawn_point = ", spawn_point.name)
	print("[SERVER] spawn_pos = ", spawn_pos)
	player.my_spawn_position = spawn_pos
	add_child(player)
	
	print("[SERVER] Player agregado: ", player.name)
	print("[SERVER] Player authority: ", player.get_multiplayer_authority())
	
	players.append(player)
	player.dash_cooldown_started.connect(_on_dash_cooldown_started)
	player.shield_cooldown_started.connect(_on_shield_cooldown_started)
	player.invisibility_cooldown_started.connect(_on_invisibility_cooldown_started)
	if pid == multiplayer.get_unique_id():
		call_deferred("_enviar_mi_nombre")



@rpc("call_local", "reliable")
func eliminar_jugador(pid:int):
	var player = get_node_or_null(str(pid))
	if player:
		players.erase(player)
		player.queue_free()



func _on_peer_connected(pid):
	if multiplayer.is_server():
		_last_seen[pid] = Time.get_unix_time_from_system()
		var idx := _asignar_idx(pid)
		sincronizar_diccionario.rpc_id(pid, PlayerData.players)
		_crear_jugador_local(pid, idx)

func _remove_player(pid):
	if !multiplayer.is_server():
		return
	_last_seen.erase(pid)
	PlayerData.players.erase(pid)
	actualizar_marcador()
	eliminar_jugador.rpc(pid)

# ============ DATOS / UI ============

@rpc("any_peer","call_local","reliable")
func registrar_nombre(peer_id:int, nombre:String):
	if multiplayer.is_server():
		_last_seen[peer_id] = Time.get_unix_time_from_system()
	PlayerData.players[peer_id] = {
		"nombre": nombre,
		"kills": 0,
		"deaths": 0
	}
	actualizar_labels()
	actualizar_marcador()

@rpc("any_peer", "call_local", "reliable")
func registrar_kill(attacker_id: int, victim_id: int):
	if PlayerData.players.has(attacker_id):
		PlayerData.players[attacker_id]["kills"] += 1
		if !game_finished and PlayerData.players[attacker_id]["kills"] >= 10:
			game_finished = true
			var nombre = PlayerData.players[attacker_id]["nombre"]
			var kills = PlayerData.players[attacker_id]["kills"]
			var deaths = PlayerData.players[attacker_id]["deaths"]
			finalizar_partida.rpc(nombre, kills, deaths)
	if PlayerData.players.has(victim_id):
		PlayerData.players[victim_id]["deaths"] += 1
	actualizar_marcador()

@rpc("any_peer","call_local","reliable")
func sincronizar_diccionario(diccionario:Dictionary):
	PlayerData.players = diccionario
	actualizar_labels()

@rpc("call_local", "reliable")
func finalizar_partida(nombre:String, kills:int, deaths:int):
	%TituloGanador.text = "Ganador:"
	%NombreGanador.text = nombre
	%Score.text = str(kills) + " kills / " + str(deaths) + " deaths"
	%Ganador.show()
	_inmovilizar_jugadores()

func _inmovilizar_jugadores():
	for p in players:
		p.game_over = true

func actualizar_labels():
	for id in PlayerData.players.keys():
		var jugador = get_node_or_null(str(id))
		if jugador:
			jugador.nombre_label.text = PlayerData.players[id]["nombre"]

func actualizar_marcador():
	var vbox = %VBoxScore
	var plantilla = %Fila
	for hijo in vbox.get_children():
		if hijo != plantilla:
			hijo.queue_free()
	plantilla.hide()
	for id in PlayerData.players.keys():
		var datos = PlayerData.players[id]
		if str(datos.get("nombre", "")) == "":
			continue
		var fila = plantilla.duplicate()
		fila.show()
		fila.get_node("NombreScore").text = datos["nombre"]
		fila.get_node("Kills").text = str(datos["kills"])
		fila.get_node("Deaths").text = str(datos["deaths"])
		vbox.add_child(fila)

func get_player_name() -> String:
	var nombre = %Nombre.text.strip_edges()
	if nombre.is_empty():
		nombre = "Jugador"
	return nombre

func _enviar_mi_nombre():
	registrar_nombre.rpc(
		multiplayer.get_unique_id(),
		get_player_name()
	)

func _on_nombre_text_changed(new_text: String) -> void:
	var habilitar: bool = !new_text.strip_edges().is_empty()
	%Host.disabled = !habilitar
	%Join.disabled = !habilitar
	%HostOnlineID.editable = habilitar

# ============ COOLDOWNS ============

func _on_dash_cooldown_started(time):
	dash_time_left = time
	%DashCooldown.show()
	%icono_dash.modulate = Color(0.4, 0.4, 0.4, 1.0)

func _on_shield_cooldown_started(time):
	shield_time_left = time
	%EscudoCooldown.show()
	%icono_escudo.modulate = Color(0.4, 0.4, 0.4, 1.0)

func _on_invisibility_cooldown_started(time):
	invisibility_time_left = time
	%InvisibilidadCooldown.show()
	%icono_invisibilidad.modulate = Color(0.4, 0.4, 0.4, 1.0)

# ============ BOTONES / SALAS ============

func _on_host_pressed():
	if _usar_cliente_websocket():
		conectar_websocket()
		return
	print("Creando sala...")
	if tube:
		tube.create_session()

func _on_join_pressed():
	if _usar_cliente_websocket():
		conectar_websocket()
		return
	if tube:
		tube.join_session(%HostOnlineID.text)

func _on_texture_button_pressed():
	if _usar_cliente_websocket():
		DisplayServer.clipboard_set(WS_SERVER_URL)
		return
	if tube:
		DisplayServer.clipboard_set(tube.session_id)

func _on_leave_room_pressed():
	if _usar_cliente_websocket():
		if ws_client_peer:
			ws_client_peer.close()
		multiplayer.multiplayer_peer = null
		ws_client_peer = null
		get_tree().reload_current_scene()
		return
	if tube:
		tube.leave_session()
	get_tree().reload_current_scene()

func _cleanup_room():
	%LeaveRoom.hide()
	%Invitar.hide()
	%menu_principal.show()
	%Controles.hide()
	%IconosCooldowns.hide()
	%Scoreboard.hide()

func _on_session_created():
	print("Sesión creada:", tube.session_id)
	%OnlineID.text = "Para invitar a otros jugadores enviales esta ID: " + tube.session_id
	%menu_principal.hide()
	%Invitar.show()
	%LeaveRoom.show()
	%Controles.show()
	%IconosCooldowns.show()
	%Scoreboard.show()
	_crear_jugador_local(multiplayer.get_unique_id(), _asignar_idx(multiplayer.get_unique_id()))
	registrar_nombre.rpc(
		multiplayer.get_unique_id(),
		get_player_name()
	)

func _on_session_joined():
	print("Conectado correctamente")
	%menu_principal.hide()
	%LeaveRoom.show()
	%Controles.show()
	%IconosCooldowns.show()
	%Scoreboard.show()

func _on_session_left():
	print("Sesión finalizada")
	_cleanup_room()

func _on_tube_error(code, message):
	push_error(message)
