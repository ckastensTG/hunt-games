extends EOSApi
## EOSApi on the EOSG plugin (Epic Online Services Godot, 3ddelano, MIT),
## installed in the game project at addons/epic-online-services-godot with
## its EOSGRuntime autoload, which ticks EOS every frame.
##
## No class_name: EOSOnlineBackend.plugin_api() loads this file by path only
## when the plugin's IEOS singleton exists, so projects and tests without the
## plugin never parse it.
##
## Uses the plugin's low-level layer (the EOS class and the IEOS signals),
## not its High Level autoloads: their anonymous login deletes the device ID
## first, which would give the player a new online ID on every start.
## Results come back as IEOS signals; each kind of request waits in its own
## queue and is answered in order.
##
## P2P: EOSG only offers it as a MultiplayerPeer (EOSGMultiplayerPeer), one
## per socket: the host runs it as a server, the guest as a client of the
## host. We drive the peer object directly, not Godot's high-level
## multiplayer. Packets sent before the two ends have found each other wait
## here and go out as soon as they have.

var _ids := {}
var _user := ""
var _display_name := "Player"
var _pending := {}          # IEOS signal name -> Array of Callables
var _details := {}          # lobby id -> EOSGLobbyDetails from the last search
var _sockets := {}          # socket -> {mp, peer, host, id, out}
var _inbox: Array = []


func start(ids: Dictionary) -> bool:
	_ids = ids
	if OS.get_name() == "Android" and not _start_android():
		return false
	var init := EOS.Platform.InitializeOptions.new()
	init.product_name = str(ids.get("product_name", "Timeless Games"))
	init.product_version = str(ProjectSettings.get_setting("application/config/version", ""))
	if init.product_version == "":
		init.product_version = "1.0"
	var res: int = EOS.Platform.PlatformInterface.initialize(init)
	if not (EOS.is_success(res) or res == EOS.Result.AlreadyConfigured):
		push_warning("EOS: initialize failed: %s" % EOS.result_str(res))
		return false
	var create := EOS.Platform.CreateOptions.new()
	create.product_id = str(ids.product_id)
	create.sandbox_id = str(ids.sandbox_id)
	create.deployment_id = str(ids.deployment_id)
	create.client_id = str(ids.client_id)
	create.client_secret = str(ids.client_secret)
	create.tick_budget_in_milliseconds = 2
	# The plugin always turns on EOS voice chat (RTC); passing no RTC options
	# to turn it off crashes it, so it stays on, unused.
	if not EOS.Platform.PlatformInterface.create(create):
		push_warning("EOS: platform create failed")
		return false
	# EOS's own warnings and errors go to the log (Xcode, logcat).
	IEOS.logging_interface_callback.connect(_on_eos_log)
	EOS.Logging.set_log_level(EOS.Logging.LogCategory.AllCategories, EOS.Logging.LogLevel.Warning)
	# The unused voice chat complains whenever the app is in the background.
	EOS.Logging.set_log_level(EOS.Logging.LogCategory.Rtc, EOS.Logging.LogLevel.Error)
	EOS.Logging.set_log_level(EOS.Logging.LogCategory.RTCAdmin, EOS.Logging.LogLevel.Error)
	if OS.is_debug_build():
		# Test builds: the steps of login, lobbies and the P2P link too.
		for c in [EOS.Logging.LogCategory.Connect, EOS.Logging.LogCategory.Lobby, EOS.Logging.LogCategory.P2P]:
			EOS.Logging.set_log_level(c, EOS.Logging.LogLevel.Info)
	for s in ["connect_interface_create_device_id_callback", "connect_interface_login_callback",
			"connect_interface_create_user_callback", "connect_interface_delete_device_id_callback",
			"lobby_interface_create_lobby_callback", "lobby_interface_update_lobby_callback",
			"lobby_search_find_callback", "lobby_interface_join_lobby_callback"]:
		_pending[s] = []
		IEOS.connect(s, _on_result.bind(s))
	IEOS.lobby_interface_lobby_member_status_received_callback.connect(_on_member_status)
	IEOS.connect_interface_auth_expiration.connect(_on_auth_expiring)
	return true


## On Android EOS has a Java half that must be loaded and handed the activity
## before the platform starts. The plugin's instructions do this in the
## Android template's GodotApp.java; doing it here keeps the template stock.
## (The Java library and its AndroidX dependencies go into the build through
## timeless_core's export plugin, editor/eos_android_export.gd.)
func _start_android() -> bool:
	if not Engine.has_singleton("AndroidRuntime"):
		push_warning("EOS: no AndroidRuntime singleton")
		return false
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	var system := JavaClassWrapper.wrap("java.lang.System")
	var sdk := JavaClassWrapper.wrap("com.epicgames.mobile.eossdk.EOSSDK")
	if activity == null or system == null or sdk == null:
		push_warning("EOS: the EOS Android library isn't in this build")
		return false
	system.loadLibrary("EOSSDK")
	sdk.init(activity)
	var err = JavaClassWrapper.get_exception()
	if err != null:
		push_warning("EOS: Android setup failed: %s" % err)
		return false
	return true


func tick() -> void:
	# EOSGRuntime ticks EOS itself; here we drive the P2P peers.
	for socket in _sockets.keys():
		var s: Dictionary = _sockets[socket]
		var mp: EOSGMultiplayerPeer = s.mp
		mp.poll()
		if s.get("dead", false):
			continue
		if s.id <= 0:
			s.id = mp.get_peer_id(s.peer)
			if s.id > 0:
				# The two ends found each other: send what was waiting.
				for bytes in s.out:
					_put(s, bytes)
				s.out.clear()
				p2p_connected.emit(s.peer, socket)
		while mp.get_available_packet_count() > 0:
			var from := mp.get_packet_peer()
			var bytes := mp.get_packet()
			if mp.get_peer_user_id(from) == s.peer:
				_inbox.append({"peer": s.peer, "socket": socket, "bytes": bytes})


# --- Login -------------------------------------------------------------------

func login(display_name: String, done: Callable) -> void:
	_display_name = display_name.substr(0, 32) if display_name != "" else "Player"
	var opts := EOS.Connect.CreateDeviceIdOptions.new()
	opts.device_model = " ".join(PackedStringArray([OS.get_name(), OS.get_model_name()])).substr(0, 60)
	_wait("connect_interface_create_device_id_callback", _on_device_id.bind(done))
	EOS.Connect.ConnectInterface.create_device_id(opts)


func _on_device_id(data: Dictionary, done: Callable) -> void:
	var res: int = data.get("result_code", -1)
	# DuplicateNotAllowed: this device already has its ID, as it should.
	if not (EOS.is_success(res) or res == EOS.Result.DuplicateNotAllowed):
		push_warning("EOS: device ID failed: %s" % EOS.result_str(res))
		done.call(false, "")
		return
	_login_device(done, true)


func _login_device(done: Callable, may_create: bool) -> void:
	var opts := EOS.Connect.LoginOptions.new()
	opts.credentials = EOS.Connect.Credentials.new()
	opts.credentials.type = EOS.ExternalCredentialType.DeviceidAccessToken
	opts.credentials.token = null
	opts.user_login_info = EOS.Connect.UserLoginInfo.new()
	opts.user_login_info.display_name = _display_name
	_wait("connect_interface_login_callback", _on_login.bind(done, may_create))
	EOS.Connect.ConnectInterface.login(opts)


func _on_login(data: Dictionary, done: Callable, may_create: bool) -> void:
	var res: int = data.get("result_code", -1)
	if res == EOS.Result.InvalidUser and may_create:
		# The first login from this device: create its EOS user, then log in
		# again so the plugin's own bookkeeping sees an ordinary login.
		var create := EOS.Connect.CreateUserOptions.new()
		create.continuance_token = data.continuance_token
		_wait("connect_interface_create_user_callback", _on_user_created.bind(done))
		EOS.Connect.ConnectInterface.create_user(create)
		return
	if not EOS.is_success(res) or str(data.get("local_user_id", "")) == "":
		push_warning("EOS: login failed: %s" % EOS.result_str(res))
		done.call(false, "")
		return
	_user = str(data.local_user_id)
	done.call(true, _user)


func _on_user_created(data: Dictionary, done: Callable) -> void:
	if not EOS.is_success(data):
		push_warning("EOS: create user failed: %s" % EOS.result_str(data))
		done.call(false, "")
		return
	_login_device(done, false)


func _on_auth_expiring(_data: Dictionary) -> void:
	# A login lasts about an hour; renew it quietly.
	_login_device(_ignore_login, false)


func _ignore_login(_ok: bool, _uid: String) -> void:
	pass


func delete_identity(done: Callable) -> void:
	for socket in _sockets.keys():
		p2p_close(_sockets[socket].peer, socket)
	_wait("connect_interface_delete_device_id_callback", _on_identity_deleted.bind(done))
	EOS.Connect.ConnectInterface.delete_device_id(EOS.Connect.DeleteDeviceIdOptions.new())


func _on_identity_deleted(_data: Dictionary, done: Callable) -> void:
	_user = ""
	done.call()


# --- Lobbies -----------------------------------------------------------------

func create_lobby(bucket: String, attrs: Dictionary, public: bool, max_members: int, done: Callable) -> void:
	var opts := EOS.Lobby.CreateLobbyOptions.new()
	opts.local_user_id = _user
	opts.bucket_id = bucket
	opts.max_lobby_members = max_members
	opts.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised if public else EOS.Lobby.LobbyPermissionLevel.InviteOnly
	opts.presence_enabled = false
	opts.allow_invites = false
	opts.enable_rtc_room = false
	opts.disable_host_migration = true
	_wait("lobby_interface_create_lobby_callback", _on_lobby_created.bind(attrs, done))
	EOS.Lobby.LobbyInterface.create_lobby(opts)


func _on_lobby_created(data: Dictionary, attrs: Dictionary, done: Callable) -> void:
	if not EOS.is_success(data):
		push_warning("EOS: create lobby failed: %s" % EOS.result_str(data))
		done.call("")
		return
	var lobby_id := str(data.lobby_id)
	# The attributes go on in a second step, before anyone is told the lobby
	# exists, so the searches that find it always see them.
	var opts := EOS.Lobby.UpdateLobbyModificationOptions.new()
	opts.local_user_id = _user
	opts.lobby_id = lobby_id
	var ret: Dictionary = EOS.Lobby.LobbyInterface.update_lobby_modification(opts)
	if not EOS.is_success(ret):
		push_warning("EOS: lobby modification failed: %s" % EOS.result_str(ret))
		destroy_lobby(lobby_id)
		done.call("")
		return
	var mod: EOSGLobbyModification = ret.lobby_modification
	for k in attrs:
		var res := mod.add_attribute(str(k), attrs[k], EOS.Lobby.LobbyAttributeVisibility.Public)
		if not EOS.is_success(res):
			push_warning("EOS: lobby attribute %s failed: %s" % [k, EOS.result_str(res)])
	var update := EOS.Lobby.UpdateLobbyOptions.new()
	update.lobby_modification = mod
	_wait("lobby_interface_update_lobby_callback", _on_lobby_ready.bind(lobby_id, done))
	EOS.Lobby.LobbyInterface.update_lobby(update)


func _on_lobby_ready(data: Dictionary, lobby_id: String, done: Callable) -> void:
	if not EOS.is_success(data):
		push_warning("EOS: lobby attributes failed: %s" % EOS.result_str(data))
		destroy_lobby(lobby_id)
		done.call("")
		return
	done.call(lobby_id)


func search_lobbies(bucket: String, filter: Dictionary, max_results: int, done: Callable) -> void:
	var opts := EOS.Lobby.CreateLobbySearchOptions.new()
	opts.max_results = max_results
	var ret: Dictionary = EOS.Lobby.LobbyInterface.create_lobby_search(opts)
	if not EOS.is_success(ret):
		push_warning("EOS: lobby search failed: %s" % EOS.result_str(ret))
		done.call_deferred([])
		return
	var search: EOSGLobbySearch = ret.lobby_search
	search.set_parameter(EOS.Lobby.SEARCH_BUCKET_ID, bucket, EOS.ComparisonOp.Equal)
	for k in filter:
		search.set_parameter(str(k), filter[k], EOS.ComparisonOp.Equal)
	_wait("lobby_search_find_callback", _on_found.bind(search, done))
	search.find(_user)


func _on_found(data: Dictionary, search: EOSGLobbySearch, done: Callable) -> void:
	if not EOS.is_success(data):
		# NotFound is just an empty result.
		if int(data.get("result_code", -1)) != EOS.Result.NotFound:
			push_warning("EOS: lobby search failed: %s" % EOS.result_str(data))
		done.call([])
		return
	var out: Array = []
	for i in search.get_search_result_count():
		var copied: Dictionary = search.copy_search_result_by_index(i)
		if not EOS.is_success(copied):
			continue
		var details: EOSGLobbyDetails = copied.lobby_details
		var lobby := _read(details)
		if lobby.is_empty():
			continue
		_details[lobby.id] = details
		out.append(lobby)
	done.call(out)


func _read(details: EOSGLobbyDetails) -> Dictionary:
	var info: Dictionary = details.copy_info()
	if not EOS.is_success(info):
		return {}
	var d: Dictionary = info.lobby_details
	var attrs := {}
	for i in details.get_attribute_count():
		var a: Dictionary = details.copy_attribute_by_index(i)
		if EOS.is_success(a):
			# EOS may hand keys back in another case; ours are lowercase.
			attrs[str(a.attribute.data.key).to_lower()] = a.attribute.data.value
	var max_members := int(d.get("max_members", 0))
	return {
		"id": str(d.get("lobby_id", "")),
		"owner": str(d.get("lobby_owner_user_id", "")),
		"members": max_members - int(d.get("available_slots", 0)),
		"max": max_members,
		"attrs": attrs,
	}


func join_lobby(lobby_id: String, done: Callable) -> void:
	var details: EOSGLobbyDetails = _details.get(lobby_id)
	if details == null:
		done.call_deferred(false, "", "gone")
		return
	var opts := EOS.Lobby.JoinLobbyOptions.new()
	opts.local_user_id = _user
	opts.lobby_details = details
	opts.presence_enabled = false
	_wait("lobby_interface_join_lobby_callback", _on_joined.bind(details.get_lobby_owner(), done))
	EOS.Lobby.LobbyInterface.join_lobby(opts)


func _on_joined(data: Dictionary, owner: String, done: Callable) -> void:
	var res: int = data.get("result_code", -1)
	if EOS.is_success(res):
		done.call(true, owner, "")
	elif res == EOS.Result.LobbyTooManyPlayers:
		done.call(false, "", "full")
	elif res == EOS.Result.NotFound:
		done.call(false, "", "gone")
	else:
		push_warning("EOS: join lobby failed: %s" % EOS.result_str(res))
		done.call(false, "", "failed")


func leave_lobby(lobby_id: String) -> void:
	var opts := EOS.Lobby.LeaveLobbyOptions.new()
	opts.local_user_id = _user
	opts.lobby_id = lobby_id
	EOS.Lobby.LobbyInterface.leave_lobby(opts)


func destroy_lobby(lobby_id: String) -> void:
	var opts := EOS.Lobby.DestroyLobbyOptions.new()
	opts.local_user_id = _user
	opts.lobby_id = lobby_id
	EOS.Lobby.LobbyInterface.destroy_lobby(opts)


func _on_member_status(data: Dictionary) -> void:
	var lobby_id := str(data.get("lobby_id", ""))
	var who := str(data.get("target_user_id", ""))
	match int(data.get("current_status", -1)):
		EOS.Lobby.LobbyMemberStatus.Joined:
			member_joined.emit(lobby_id, who)
		EOS.Lobby.LobbyMemberStatus.Left, EOS.Lobby.LobbyMemberStatus.Disconnected, EOS.Lobby.LobbyMemberStatus.Kicked:
			member_left.emit(lobby_id, who)
		EOS.Lobby.LobbyMemberStatus.Closed:
			lobby_closed.emit(lobby_id)


# --- P2P ---------------------------------------------------------------------

func p2p_open(peer: String, socket: String, as_host: bool) -> void:
	if _sockets.has(socket):
		return
	var mp := EOSGMultiplayerPeer.new()
	# EOS keeps packets for a link that is still being set up.
	mp.set_allow_delayed_delivery(true)
	var err: int
	if as_host:
		# Only the player from our lobby gets in.
		mp.set_auto_accept_connection_requests(false)
		mp.incoming_connection_request.connect(_on_request.bind(socket, mp))
		err = mp.create_server(socket)
	else:
		err = mp.create_client(socket, peer)
	if err != OK:
		push_warning("EOS: P2P socket failed: %s" % error_string(err))
		return
	mp.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	# Bound to this peer too: a socket opened again under the same name
	# mustn't hear the old one's events.
	mp.peer_connection_established.connect(_on_link_up.bind(socket, mp))
	mp.peer_connection_interrupted.connect(_on_link_down.bind(socket, mp))
	mp.peer_connection_closed.connect(_on_link_closed.bind(socket, mp))
	_sockets[socket] = {"mp": mp, "peer": peer, "host": as_host, "id": 0, "out": []}


func p2p_send(peer: String, socket: String, bytes: PackedByteArray) -> bool:
	var s: Dictionary = _sockets.get(socket, {})
	if s.is_empty() or s.peer != peer or bytes.size() > MAX_PACKET or s.get("dead", false):
		return false
	if s.id <= 0:
		s.out.append(bytes)
		return true
	return _put(s, bytes)


func _put(s: Dictionary, bytes: PackedByteArray) -> bool:
	var mp: EOSGMultiplayerPeer = s.mp
	mp.set_target_peer(s.id)
	var err := mp.put_packet(bytes)
	if err != OK:
		push_warning("EOS: P2P send failed: %s" % error_string(err))
	return err == OK


func p2p_receive() -> Array:
	var out := _inbox
	_inbox = []
	return out


func p2p_close(_peer: String, socket: String) -> void:
	var s: Dictionary = _sockets.get(socket, {})
	if s.is_empty():
		return
	_sockets.erase(socket)
	(s.mp as EOSGMultiplayerPeer).close()


func _on_request(data: Dictionary, socket: String, mp: EOSGMultiplayerPeer) -> void:
	var s: Dictionary = _sockets.get(socket, {})
	if s.is_empty() or s.mp != mp or s.get("dead", false):
		return
	var who := str(data.get("remote_user_id", ""))
	if who == s.peer:
		mp.accept_connection_request(who)
	else:
		mp.deny_connection_request(who)


func _on_link_up(data: Dictionary, socket: String, mp: EOSGMultiplayerPeer) -> void:
	var s: Dictionary = _sockets.get(socket, {})
	# The first time, tick() reports the link once the two ends have paired.
	if not s.is_empty() and s.mp == mp and not s.get("dead", false) and s.id > 0 and str(data.get("remote_user_id", s.peer)) == s.peer:
		p2p_connected.emit(s.peer, socket)


func _on_link_down(data: Dictionary, socket: String, mp: EOSGMultiplayerPeer) -> void:
	var s: Dictionary = _sockets.get(socket, {})
	if not s.is_empty() and s.mp == mp and not s.get("dead", false) and str(data.get("remote_user_id", s.peer)) == s.peer:
		p2p_interrupted.emit(s.peer, socket)


func _on_link_closed(data: Dictionary, socket: String, mp: EOSGMultiplayerPeer) -> void:
	var s: Dictionary = _sockets.get(socket, {})
	if not s.is_empty() and s.mp == mp and str(data.get("remote_user_id", s.peer)) == s.peer:
		# Done with this socket: it neither pairs nor sends again (its old peer
		# id may linger). The transport opens a fresh one on each side
		# (EOSP2PTransport.reconnect); what's sent meanwhile is dropped, and
		# NetMatch asks again once the new link is up.
		s.dead = true
		s.out.clear()
		if OS.is_debug_build():
			print("[eos] P2P link closed (reason %d)" % int(data.get("reason", 0)))
		p2p_closed.emit(s.peer, socket)


# --- Results in order ----------------------------------------------------------

func _on_result(data: Dictionary, signal_name: String) -> void:
	var q: Array = _pending[signal_name]
	if q.is_empty():
		return
	var cb: Callable = q.pop_front()
	cb.call(data)


func _wait(signal_name: String, cb: Callable) -> void:
	_pending[signal_name].append(cb)


func _on_eos_log(msg: Dictionary) -> void:
	print("EOS [%s] %s" % [msg.get("category", ""), msg.get("message", "")])
