# ============================================================
# NetworkRPCs.gd - كل الـ RPC والـ Networking
# ============================================================

# ============================================================
# NETWORKING - HOST
# ============================================================
func _on_host_pressed() -> void:
	my_name = name_input.text.strip_edges()
	if my_name.is_empty():
		my_name = "Host"
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, 4)
	if error != OK:
		status_label.text = "❌ Failed to create server: " + str(error)
		status_label.modulate = Color.RED
		return
	
	multiplayer.multiplayer_peer = peer
	
	var room_code = str(randi() % 9000 + 1000)
	var local_ip = _get_local_ip()
	room_code_display.text = "🔑 Code: " + room_code + " | 🌐 IP: " + local_ip
	
	my_skin_index = 0
	var host_id = multiplayer.get_unique_id()
	players[host_id] = {"name": my_name, "skin_index": my_skin_index}
	_assign_slot_position(host_id)
	
	_show_lobby_ui()
	status_label.text = "✅ Waiting for players..."
	status_label.visible = true
	
	_replace_player_skin(host_id, my_name, my_skin_index)
	_update_player_list.rpc()
	
	var skin_data = []
	for s in skins:
		if s:
			skin_data.append({
				"name": s.name,
				"scene_path": s.scene.resource_path if s.scene else "",
				"icon_path": s.icon.resource_path if s.icon else ""
			})
	rpc("receive_skin_data", skin_data)
	
	var map_data = []
	for m in maps:
		if m:
			map_data.append({
				"name": m.name,
				"scene_path": m.scene.resource_path if m.scene else "",
				"icon_path": m.icon.resource_path if m.icon else ""
			})
	rpc("receive_map_data", map_data)
	
	var minigame_data = []
	for mg in minigames:
		if mg:
			var data = {
				"name": mg.name,
				"scene_path": mg.scene.resource_path if mg.scene else "",
				"icon_path": mg.icon.resource_path if mg.icon else ""
			}
			if "description" in mg:
				data["description"] = mg.description
			if "max_players" in mg:
				data["max_players"] = mg.max_players
			if "min_players" in mg:
				data["min_players"] = mg.min_players
			minigame_data.append(data)
	rpc("receive_minigame_data", minigame_data)

# ============================================================
# NETWORKING - CLIENT
# ============================================================
func _on_join_pressed() -> void:
	my_name = name_input.text.strip_edges()
	if my_name.is_empty():
		my_name = "Player"
	
	var room_code = room_code_input.text.strip_edges()
	if room_code.is_empty() or not room_code.is_valid_int():
		status_label.text = "⚠️ Please enter a valid room code"
		status_label.modulate = Color.RED
		return
	
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, DEFAULT_PORT)
	if error != OK:
		status_label.text = "❌ Failed to connect: " + str(error)
		status_label.modulate = Color.RED
		return
	
	multiplayer.multiplayer_peer = peer
	status_label.text = "🔄 Connecting to " + ip + "..."
	status_label.modulate = Color.YELLOW

func _on_connected_to_server() -> void:
	status_label.text = "✅ Connected! Registering..."
	status_label.modulate = Color.GREEN
	
	_show_lobby_ui()
	
	my_skin_index = 0
	send_my_name.rpc_id(1, my_name, my_skin_index)

func _on_connection_failed() -> void:
	status_label.text = "❌ Connection failed"
	status_label.modulate = Color.RED
	_reset_ui()

# ============================================================
# SLOT POSITION ASSIGNMENT
# ============================================================
func _assign_slot_position(peer_id: int) -> void:
	var slot_index = peer_slot_map.size()
	if slot_index < lobby_positions.size():
		player_positions[peer_id] = lobby_positions[slot_index]
		peer_slot_map[peer_id] = slot_index
	else:
		player_positions[peer_id] = Vector2(200 + (slot_index * 200), 300)
		peer_slot_map[peer_id] = slot_index

# ============================================================
# NETWORKING - RPCs
# ============================================================
@rpc("any_peer", "call_local", "reliable")
func send_my_name(name: String, skin_index: int) -> void:
	if not multiplayer.is_server():
		return
	
	var id = multiplayer.get_remote_sender_id()
	
	if players.has(id):
		return
	
	_assign_slot_position(id)
	players[id] = {"name": name, "skin_index": skin_index}
	_replace_player_skin(id, name, skin_index)
	_send_full_state_to_client(id)
	_update_all_players()
	
	var skin_data = []
	for s in skins:
		if s:
			skin_data.append({
				"name": s.name,
				"scene_path": s.scene.resource_path if s.scene else "",
				"icon_path": s.icon.resource_path if s.icon else ""
			})
	rpc_id(id, "receive_skin_data", skin_data)
	
	var map_data = []
	for m in maps:
		if m:
			map_data.append({
				"name": m.name,
				"scene_path": m.scene.resource_path if m.scene else "",
				"icon_path": m.icon.resource_path if m.icon else ""
			})
	rpc_id(id, "receive_map_data", map_data)
	
	var minigame_data = []
	for mg in minigames:
		if mg:
			var data = {
				"name": mg.name,
				"scene_path": mg.scene.resource_path if mg.scene else "",
				"icon_path": mg.icon.resource_path if mg.icon else ""
			}
			if "description" in mg:
				data["description"] = mg.description
			if "max_players" in mg:
				data["max_players"] = mg.max_players
			if "min_players" in mg:
				data["min_players"] = mg.min_players
			minigame_data.append(data)
	rpc_id(id, "receive_minigame_data", minigame_data)

func _send_full_state_to_client(client_id: int) -> void:
	var player_data = []
	for pid in players.keys():
		player_data.append({
			"id": pid,
			"name": players[pid]["name"],
			"skin_index": players[pid]["skin_index"],
			"position": player_positions[pid]
		})
	rpc_id(client_id, "receive_full_state", player_data, selected_map_index, selected_minigame_index)

@rpc("authority", "call_local", "reliable")
func receive_full_state(player_data: Array, map_index: int, minigame_index: int) -> void:
	players.clear()
	player_positions.clear()
	peer_slot_map.clear()
	_clear_level()
	
	for data in player_data:
		var pid = data.get("id", 0)
		var name = data.get("name", "Player")
		var skin_index = data.get("skin_index", 0)
		var position = data.get("position", Vector2(200, 300))
		
		players[pid] = {"name": name, "skin_index": skin_index}
		player_positions[pid] = position
		peer_slot_map[pid] = peer_slot_map.size()
	
	selected_map_index = map_index
	selected_minigame_index = minigame_index
	_update_slot_highlight(map_index)
	update_minigame_selection(minigame_index)
	_update_player_list()
	
	spawned_players.clear()
	
	for pid in players.keys():
		var skin_index = players[pid]["skin_index"]
		var skin_path = skins[skin_index].scene.resource_path if skin_index < skins.size() and skins[skin_index] != null else "res://Player.tscn"
		spawn_player(pid, players[pid]["name"], skin_path, game_started)

@rpc("authority", "call_local", "reliable")
func receive_skin_data(data: Array) -> void:
	skins.clear()
	for item in data:
		var skin = SkinData.new()
		skin.name = item.get("name", "Unknown")
		
		var scene_path = item.get("scene_path", "")
		if ResourceLoader.exists(scene_path):
			skin.scene = load(scene_path)
		
		var icon_path = item.get("icon_path", "")
		if ResourceLoader.exists(icon_path):
			skin.icon = load(icon_path)
		
		skins.append(skin)
	
	_create_skin_buttons()
	if not skins.is_empty():
		_on_skin_selected(0)

@rpc("authority", "call_local", "reliable")
func receive_map_data(data: Array) -> void:
	maps.clear()
	for item in data:
		var map = MapData.new()
		map.name = item.get("name", "Unknown")
		
		var scene_path = item.get("scene_path", "")
		if ResourceLoader.exists(scene_path):
			map.scene = load(scene_path)
		
		var icon_path = item.get("icon_path", "")
		if ResourceLoader.exists(icon_path):
			map.icon = load(icon_path)
		
		maps.append(map)
	
	_create_map_buttons()

@rpc("authority", "call_local", "reliable")
func receive_minigame_data(data: Array) -> void:
	minigames.clear()
	for item in data:
		var mg = MiniGameData.new()
		mg.name = item.get("name", "Unknown")
		mg.description = item.get("description", "")
		mg.max_players = item.get("max_players", 4)
		mg.min_players = item.get("min_players", 2)
		
		var scene_path = item.get("scene_path", "")
		if ResourceLoader.exists(scene_path):
			mg.scene = load(scene_path)
		
		var icon_path = item.get("icon_path", "")
		if ResourceLoader.exists(icon_path):
			mg.icon = load(icon_path)
		
		minigames.append(mg)
	
	_create_minigame_buttons()
	if not minigames.is_empty():
		_on_minigame_selected(0)

@rpc("authority", "call_local", "reliable")
func _update_player_list() -> void:
	player_list.clear()
	for id in players.keys():
		var name = players[id].get("name", "Player")
		var skin_index = players[id].get("skin_index", 0)
		var skin_name = skins[skin_index].name if skin_index < skins.size() and skins[skin_index] != null else "?"
		
		var icon = null
		if skin_index < skins.size() and skins[skin_index] != null and skins[skin_index].icon:
			icon = skins[skin_index].icon
		
		player_list.add_item("🎮 " + skin_name + " - " + name)
		if icon:
			player_list.set_item_icon(player_list.item_count - 1, icon)

func _update_all_players() -> void:
	_update_player_list.rpc()
	spawned_players.clear()
	for pid in players.keys():
		var skin_index = players[pid]["skin_index"]
		var skin_path = skins[skin_index].scene.resource_path if skin_index < skins.size() and skins[skin_index] != null else "res://Player.tscn"
		spawn_player.rpc(pid, players[pid]["name"], skin_path, game_started)

# ============================================================
# PEER EVENTS
# ============================================================
func _on_player_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("🔗 Player connected: ", id)

func _on_player_disconnected(id: int) -> void:
	if multiplayer.is_server():
		print("🔌 Player disconnected: ", id)
		players.erase(id)
		player_positions.erase(id)
		peer_slot_map.erase(id)
		
		_update_player_list.rpc()
		remove_player.rpc(id)

@rpc("authority", "call_local", "reliable")
func remove_player(id: int) -> void:
	var node_name = str(id)
	var node = level_node.get_node_or_null(node_name)
	if node:
		node.name = node_name + "_deleting"
		level_node.remove_child(node)
		node.queue_free()

# ============================================================
# UTILITY FUNCTIONS
# ============================================================
func _get_local_ip() -> String:
	var addresses = IP.get_local_addresses()
	for addr in addresses:
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return addresses[0] if addresses.size() > 0 else "127.0.0.1"
