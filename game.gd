extends Node

const PLAYER = preload("res://scenes/player.tscn")
@onready var tube = get_node_or_null("TubeClient")

var ws_server_peer: WebSocketMultiplayerPeer
var ws_client_peer: WebSocketMultiplayerPeer

# Para pruebas locales:
const WS_SERVER_URL := "ws://localhost:8080"
# Cuando tengas el servidor en Render, usa algo como:
# const WS_SERVER_URL := "wss://tu-servicio.onrender.com"

var players: Array[Player] = []

var dash_time_left := 0.0
var shield_time_left := 0.0
var invisibility_time_left := 0.0

var game_finished := false


@rpc("call_local", "reliable")
func finalizar_partida(nombre:String, kills:int, deaths:int):

	%TituloGanador.text = "Ganador:"
	%NombreGanador.text = nombre
	%Score.text = str(kills) + " kills / " + str(deaths) + " deaths"

	%Ganador.show()

	_inmovilizar_jugadores()

@rpc("any_peer","call_local","reliable")
func registrar_nombre(peer_id:int, nombre:String):

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

	print(PlayerData.players)

	
func _ready():

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_remove_player)
	$MultiplayerSpawner.spawn_function = _add_player

	# Si este proceso es el servidor dedicado, iniciamos WebSocket server.
	if _es_servidor_dedicado():
		_iniciar_servidor_websocket()
		return

	# Si estamos en navegador o forzamos cliente WebSocket, usamos WebSocket client.
	if _usar_cliente_websocket():
		_configurar_cliente_websocket()
		return

	# Si no, seguimos usando Tube normalmente.
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
	
	

func _on_host_pressed():
	if _usar_cliente_websocket():
		conectar_websocket()
		return

	print("Creando sala...")

	if tube:
		tube.create_session()
	
	
func _on_peer_connected(pid):
	if multiplayer.is_server():
		$MultiplayerSpawner.spawn(pid)
		sincronizar_diccionario.rpc_id(
			pid,
			PlayerData.players
		)
	
	
func _on_texture_button_pressed():
	if _usar_cliente_websocket():
		DisplayServer.clipboard_set(WS_SERVER_URL)
		return

	if tube:
		DisplayServer.clipboard_set(tube.session_id)

func _on_join_pressed():
	if _usar_cliente_websocket():
		conectar_websocket()
		return

	if tube:
		tube.join_session(%HostOnlineID.text)

	

	
func _add_player(pid):
	var player = PLAYER.instantiate()

	player.name = str(pid)

	var spawn_point = $Level/Piso.get_child(players.size())
	var spawn_pos = spawn_point.global_position

	player.global_position = spawn_pos
	player.my_spawn_position = spawn_pos

	players.append(player)
	
	player.dash_cooldown_started.connect(_on_dash_cooldown_started)
	player.shield_cooldown_started.connect(_on_shield_cooldown_started)
	player.invisibility_cooldown_started.connect(_on_invisibility_cooldown_started)
	
	if pid == multiplayer.get_unique_id():
		call_deferred("_enviar_mi_nombre")

	return player
	
func _remove_player(pid):

	if !multiplayer.is_server():
		return

	PlayerData.players.erase(pid)

	actualizar_marcador()

	var player = get_node_or_null(str(pid))

	if player:
		player.queue_free()

	

func _cleanup_room():
	%LeaveRoom.hide()
	%Invitar.hide()
	%menu_principal.show()
	%Controles.hide()
	%IconosCooldowns.hide()
	%Scoreboard.hide()


func _on_leave_room_pressed():
	if _usar_cliente_websocket():
		multiplayer.multiplayer_peer = null
		ws_client_peer = null
		get_tree().reload_current_scene()
		return

	if tube:
		tube.leave_session()

	get_tree().reload_current_scene()


	
func _process(delta):
	
	if Input.is_action_just_pressed("ui_accept"):
		print(PlayerData.players)

	if Input.is_action_just_pressed("ui_accept"):
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
		
func actualizar_labels():

	for id in PlayerData.players.keys():

		var jugador = get_node_or_null(str(id))

		if jugador:

			jugador.nombre_label.text = PlayerData.players[id]["nombre"]
			
@rpc("any_peer","call_local","reliable")
func sincronizar_diccionario(diccionario:Dictionary):

	PlayerData.players = diccionario

	actualizar_labels()
	

	

	
	


func _on_nombre_text_changed(new_text: String) -> void:

	var habilitar: bool = !new_text.strip_edges().is_empty()

	%Host.disabled = !habilitar
	%Join.disabled = !habilitar
	%HostOnlineID.editable = habilitar
	
	
func actualizar_marcador():

	var vbox = %VBoxScore
	var plantilla = %Fila

	# borrar filas viejas
	for hijo in vbox.get_children():

		if hijo != plantilla:
			hijo.queue_free()

	plantilla.hide()

	for id in PlayerData.players.keys():

		var datos = PlayerData.players[id]

		var fila = plantilla.duplicate()

		fila.show()

		fila.get_node("NombreScore").text = datos["nombre"]
		fila.get_node("Kills").text = str(datos["kills"])
		fila.get_node("Deaths").text = str(datos["deaths"])

		vbox.add_child(fila)
		
func _inmovilizar_jugadores():

	for p in players:
		p.game_over = true
		
func _on_session_created():

	print("Sesión creada:", tube.session_id)

	%OnlineID.text = "Para invitar a otros jugadores enviales esta ID: " + tube.session_id

	%menu_principal.hide()
	%Invitar.show()
	%LeaveRoom.show()
	%Controles.show()
	%IconosCooldowns.show()
	%Scoreboard.show()

	$MultiplayerSpawner.spawn(multiplayer.get_unique_id())

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
		
	
func _es_servidor_dedicado() -> bool:
	return OS.get_environment("SERVER_MODE") == "1"


func _usar_cliente_websocket() -> bool:
	return OS.get_name() == "Web" or OS.get_environment("WS_CLIENT") == "1"


func _iniciar_servidor_websocket() -> void:
	var port := 8080

	if OS.has_environment("PORT"):
		port = OS.get_environment("PORT").to_int()

	ws_server_peer = WebSocketMultiplayerPeer.new()

	# "*" significa escuchar en todas las interfaces de red.
	if ws_server_peer.create_server(port, "*") != OK:
		push_error("No se pudo crear el servidor WebSocket")
		get_tree().quit(1)
		return

	multiplayer.multiplayer_peer = ws_server_peer

	print("[SERVER] Servidor WebSocket escuchando en el puerto ", port)
	
	print("[SERVER] Ruta del spawner: ", $MultiplayerSpawner.get_path())


func _configurar_cliente_websocket() -> void:
	multiplayer.connected_to_server.connect(_on_session_joined)
	multiplayer.connection_failed.connect(_on_websocket_connection_failed)
	multiplayer.server_disconnected.connect(_on_session_left)

	# Con servidor dedicado no hay ID de sala que mostrar:
	%HostOnlineID.hide()

	# Ocultamos "Host" y usamos "Join" como botón de unirse:
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
		var nombres: Array = []
		for m in ws_client_peer.get_method_list():
			nombres.append(m["name"])
		push_error("Esta versión de Godot no tiene connect_to_url ni create_client. Métodos disponibles: " + str(nombres))
		return

	if resultado != OK:
		push_error("No se pudo iniciar la conexión WebSocket, error: " + str(resultado))
		return

	multiplayer.multiplayer_peer = ws_client_peer
	print("Conectando a WebSocket: ", WS_SERVER_URL)


func _on_websocket_connection_failed() -> void:
	push_error("Falló la conexión WebSocket")
