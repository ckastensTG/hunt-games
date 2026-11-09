extends TestCase
## Match session, network protocol, transports, codes and online matching.


func _resolve(id: String) -> HuntRuleSet:
	return HuntFixtures.tigers_and_goats() if id == "tg" else null


func _pair_matches(kind := MatchSession.Kind.NEARBY, turn_s := 0) -> Array:
	var links := LoopbackTransport.pair()
	var host := NetMatch.as_host(links[0], "tg", HuntState.PREY, kind, turn_s, "test", "b1",
		{"key": "scribe", "n": 1}, _resolve)
	var guest := NetMatch.as_guest(links[1], "test", "b1", {"key": "potter", "n": 2}, _resolve)
	return [host, guest, links]


func _pump(nets: Array, frames := 6, now := 1000) -> void:
	for _i in frames:
		for n in nets:
			n.poll(now)


func _first_legal(s: HuntState) -> PackedInt32Array:
	return s.legal_moves()[0]


# --- MatchSession --------------------------------------------------------------

func test_match_validates_turn_and_legality() -> void:
	var m := MatchSession.create(HuntFixtures.tigers_and_goats(), "tg", MatchSession.Kind.PASS_AND_PLAY,
		MatchSession.Driver.LOCAL, MatchSession.Driver.LOCAL)
	var place := _first_legal(m.state)
	check(not m.commit(place, HuntState.HUNTER), "out of turn refused")
	check(not m.commit(PackedInt32Array([HuntState.Kind.PLACE, 0]), HuntState.PREY), "occupied point refused")
	check(m.commit(place, HuntState.PREY), "legal move accepted")
	check_eq(m.moves.size(), 1, "one move")


func test_undo_count_against_the_ai() -> void:
	var m := MatchSession.create(HuntFixtures.tigers_and_goats(), "tg", MatchSession.Kind.VS_AI,
		MatchSession.Driver.AI, MatchSession.Driver.LOCAL)
	check_eq(m.undo_count(), 0, "nothing to undo")
	m.commit(_first_legal(m.state), HuntState.PREY)
	m.commit(_first_legal(m.state), HuntState.HUNTER)
	check_eq(m.undo_count(), 2, "back to the human's turn")
	m.undo(m.undo_count())
	check_eq(m.moves.size(), 0, "both moves gone")


func test_resign_and_save_round_trip() -> void:
	var m := MatchSession.create(HuntFixtures.tigers_and_goats(), "tg", MatchSession.Kind.VS_AI,
		MatchSession.Driver.AI, MatchSession.Driver.LOCAL)
	for _i in 6:
		m.commit(_first_legal(m.state), m.side_to_move())
	var saved := m.to_dict()
	var back := MatchSession.from_dict(saved, _resolve)
	check(back != null, "loads")
	check_eq(back.state.hash_key, m.state.hash_key, "same position")
	check_eq(back.control[HuntState.HUNTER], MatchSession.Driver.AI, "same players")
	var over := []
	m.game_over.connect(func(st: int, _r: int) -> void: over.append(st))
	m.resign(HuntState.PREY)
	check_eq(over, [HuntState.Status.HUNTER_WIN], "resigning goats lose")
	check(MatchSession.from_dict({"version": 99}, _resolve) == null, "unknown save version refused")


# --- Protocol ----------------------------------------------------------------------

func test_protocol_rejects_malformed_messages() -> void:
	var ok := NetProtocol.encode(NetProtocol.make(NetProtocol.Msg.MOVE,
		{"seq": 0, "move": PackedInt32Array([0, 3]), "hash": 5}))
	check(not NetProtocol.decode(ok).is_empty(), "valid move decodes")
	var wrong_type := NetProtocol.encode({"t": NetProtocol.Msg.MOVE, "seq": "0", "move": PackedInt32Array([0, 3]), "hash": 5})
	check(NetProtocol.decode(wrong_type).is_empty(), "wrong field type")
	check(NetProtocol.decode(var_to_bytes([1, 2, 3])).is_empty(), "not a dictionary")
	check(NetProtocol.decode(var_to_bytes({"t": 999})).is_empty(), "unknown message")
	check(NetProtocol.decode(PackedByteArray([1, 2, 3])).is_empty(), "garbage")


# --- NetMatch over a loopback pair ------------------------------------------------

func test_handshake_and_moves() -> void:
	var p := _pair_matches()
	var host: NetMatch = p[0]
	var guest: NetMatch = p[1]
	var started := []
	host.started.connect(func(_m: MatchSession, side: int) -> void: started.append(["host", side]))
	guest.started.connect(func(_m: MatchSession, side: int) -> void: started.append(["guest", side]))
	_pump([host, guest])
	check_eq(started.size(), 2, "both started")
	check_eq(host.local_side, HuntState.PREY, "host plays the goats")
	check_eq(guest.local_side, HuntState.HUNTER, "guest plays the tigers")
	check_eq(host.opponent_name.get("key"), "potter", "host knows the guest's name")
	# Goats (host) move first.
	check(host.session.commit(_first_legal(host.session.state), HuntState.PREY), "host moves")
	_pump([host, guest])
	check_eq(guest.session.moves.size(), 1, "guest got the move")
	check(guest.session.commit(_first_legal(guest.session.state), HuntState.HUNTER), "guest moves")
	_pump([host, guest])
	check_eq(host.session.state.hash_key, guest.session.state.hash_key, "same position on both")


func test_out_of_turn_and_illegal_moves_are_refused() -> void:
	var p := _pair_matches()
	var host: NetMatch = p[0]
	var guest: NetMatch = p[1]
	var links: Array = p[2]
	_pump([host, guest])
	# The guest (tigers) tries to move before the goats: never reaches the host.
	links[1].send(NetProtocol.encode(NetProtocol.make(NetProtocol.Msg.MOVE,
		{"seq": 0, "move": PackedInt32Array([HuntState.Kind.STEP, 0, 1]), "hash": 0})))
	_pump([host, guest])
	check_eq(host.session.moves.size(), 0, "out-of-turn move ignored")


func test_resign_draw_and_undo() -> void:
	var p := _pair_matches()
	var host: NetMatch = p[0]
	var guest: NetMatch = p[1]
	_pump([host, guest])
	host.session.commit(_first_legal(host.session.state), HuntState.PREY)
	_pump([host, guest])
	# Undo: the host asks to take back its move; the guest agrees.
	var asked := []
	guest.undo_requested.connect(func() -> void: asked.append(true))
	host.request_undo()
	_pump([host, guest])
	check_eq(asked.size(), 1, "guest is asked")
	guest.answer_undo(true)
	_pump([host, guest])
	check_eq(host.session.moves.size(), 0, "host took it back")
	check_eq(guest.session.moves.size(), 0, "guest took it back too")
	# Draw offer accepted.
	host.offer_draw()
	_pump([host, guest])
	guest.answer_draw(true)
	_pump([host, guest])
	check_eq(host.session.status(), HuntState.Status.DRAW, "draw on the host")
	check_eq(guest.session.status(), HuntState.Status.DRAW, "draw on the guest")


func test_resignation_reaches_the_other_side() -> void:
	var p := _pair_matches()
	var host: NetMatch = p[0]
	var guest: NetMatch = p[1]
	_pump([host, guest])
	guest.resign()
	_pump([host, guest])
	check_eq(host.session.status(), HuntState.Status.PREY_WIN, "tigers resigned: goats win")


func test_reconnect_resyncs() -> void:
	var p := _pair_matches()
	var host: NetMatch = p[0]
	var guest: NetMatch = p[1]
	var links: Array = p[2]
	_pump([host, guest])
	host.session.commit(_first_legal(host.session.state), HuntState.PREY)
	links[0].drop()
	_pump([host, guest], 3, 2000)
	check_eq(host.phase, NetMatch.Phase.RECONNECTING, "host waits")
	check_eq(guest.session.moves.size(), 0, "guest missed the move")
	links[0].restore()
	_pump([host, guest], 8, 3000)
	check_eq(guest.session.moves.size(), 1, "guest caught up")
	check_eq(guest.phase, NetMatch.Phase.PLAYING, "playing again")


func test_a_link_that_comes_back_quietly() -> void:
	# The link drops and returns with no event (as EOS can do): both sides
	# notice the silence, and the guest's repeated HELLO ends the wait.
	var p := _pair_matches(MatchSession.Kind.ONLINE_FRIEND)
	var host: NetMatch = p[0]
	var guest: NetMatch = p[1]
	var links: Array = p[2]
	_pump([host, guest])
	links[0].drop(true)
	host.session.commit(_first_legal(host.session.state), HuntState.PREY)
	_pump([host, guest], 3, 1000 + NetMatch.SILENCE_MS + 500)
	check_eq(host.phase, NetMatch.Phase.RECONNECTING, "host waits")
	check_eq(guest.phase, NetMatch.Phase.RECONNECTING, "guest waits")
	links[0].restore()
	_pump([host, guest], 6, 1000 + NetMatch.SILENCE_MS + 500 + NetMatch.RECONNECT_TRY_MS)
	check_eq(host.phase, NetMatch.Phase.PLAYING, "host plays on")
	check_eq(guest.phase, NetMatch.Phase.PLAYING, "guest plays on")
	check_eq(guest.session.moves.size(), 1, "guest caught up")
	check_eq(guest.session.position_hash(), host.session.position_hash(), "same position")


func test_one_side_waiting_hears_the_other() -> void:
	# Only the host noticed a gap; the guest's next ping ends the host's wait
	# (the host sends the moves), so neither side gives up on the other.
	var p := _pair_matches(MatchSession.Kind.ONLINE_FRIEND)
	var host: NetMatch = p[0]
	var guest: NetMatch = p[1]
	_pump([host, guest])
	host._lose_connection()
	check_eq(host.phase, NetMatch.Phase.RECONNECTING, "host waits")
	var back := []
	host.reconnected.connect(func() -> void: back.append(true))
	_pump([host, guest], 4, 1000 + NetMatch.PING_MS + 10)
	check_eq(host.phase, NetMatch.Phase.PLAYING, "host plays on")
	check_eq(back.size(), 1, "reconnected once")
	check_eq(guest.phase, NetMatch.Phase.PLAYING, "guest never stopped")


func test_resync_redraws_without_move_signals() -> void:
	# A resync replaces the moves with a `reset`, not a move signal per move.
	var p := _pair_matches()
	var host: NetMatch = p[0]
	var guest: NetMatch = p[1]
	var links: Array = p[2]
	_pump([host, guest])
	links[0].drop()
	for _i in 3:
		host.session.commit(_first_legal(host.session.state), host.session.side_to_move())
	var moved := []
	var resets := []
	guest.session.move_committed.connect(func(_m: PackedInt32Array, _s: int) -> void: moved.append(true))
	guest.session.reset.connect(func() -> void: resets.append(true))
	links[0].restore()
	guest._ask_for_moves()
	_pump([host, guest], 6, 3000)
	check_eq(guest.session.moves.size(), 3, "caught up")
	check(resets.size() >= 1, "redrawn by reset")
	check_eq(moved.size(), 0, "no per-move signals")
	check_eq(guest.session.position_hash(), host.session.position_hash(), "same position")


func test_replay_refuses_an_illegal_list() -> void:
	var m := MatchSession.create(HuntFixtures.tigers_and_goats(), "tg", MatchSession.Kind.NEARBY,
		MatchSession.Driver.LOCAL, MatchSession.Driver.REMOTE)
	var first := _first_legal(m.state)
	check(not m.replay(m.start, [first, first]), "the same placement twice is refused")
	check_eq(m.moves.size(), 0, "nothing changed")
	check(m.replay(m.start, [first]), "a legal list is taken")
	check_eq(m.moves.size(), 1, "one move")


func test_opponent_gone_after_the_window() -> void:
	var p := _pair_matches()
	var host: NetMatch = p[0]
	var guest: NetMatch = p[1]
	var links: Array = p[2]
	_pump([host, guest])
	links[0].drop()
	_pump([host, guest], 2, 2000)
	var left := []
	host.opponent_left.connect(func() -> void: left.append(true))
	_pump([host], 2, 2000 + NetMatch.RECONNECT_WINDOW_MS + 10)
	check_eq(left.size(), 1, "host gives up")
	check_eq(host.session.status(), HuntState.Status.PREY_WIN, "the goats (host) win by forfeit")


func _advance(nets: Array, from_ms: int, to_ms: int) -> void:
	var t := from_ms
	while t <= to_ms:
		_pump(nets, 2, t)
		t += 1000


func test_turn_clock() -> void:
	var p := _pair_matches(MatchSession.Kind.QUICK_MATCH, 60)
	var host: NetMatch = p[0]
	var guest: NetMatch = p[1]
	_pump([host, guest], 6, 1000)
	var timeouts := []
	host.turn_timed_out.connect(func() -> void: timeouts.append(true))
	_advance([host, guest], 1000, 62000)
	check_eq(timeouts.size(), 1, "the host's clock ran out once")
	check(host.seconds_left() >= 0, "clock shown")
	_advance([host, guest], 62000, 184000)
	check_eq(host.session.status(), HuntState.Status.HUNTER_WIN, "third timeout forfeits")
	check_eq(guest.session.status(), HuntState.Status.HUNTER_WIN, "the guest sees it too")


func test_version_mismatch_fails() -> void:
	var links := LoopbackTransport.pair()
	var host := NetMatch.as_host(links[0], "tg", HuntState.PREY, MatchSession.Kind.NEARBY, 0, "test", "b1", {}, _resolve)
	var guest := NetMatch.as_guest(links[1], "other_title", "b1", {}, _resolve)
	var why := []
	host.failed.connect(func(r: String) -> void: why.append(r))
	guest.failed.connect(func(r: String) -> void: why.append(r))
	_pump([host, guest])
	check(why.has("title"), "different title refused")
	check(host.phase != NetMatch.Phase.PLAYING and guest.phase != NetMatch.Phase.PLAYING, "no game")


func test_rematch_swaps_sides() -> void:
	var p := _pair_matches()
	var host: NetMatch = p[0]
	var guest: NetMatch = p[1]
	_pump([host, guest])
	guest.resign()
	_pump([host, guest])
	host.request_rematch()
	_pump([host, guest])
	guest.answer_rematch(true)
	_pump([host, guest])
	check_eq(host.local_side, HuntState.HUNTER, "host now plays the tigers")
	check_eq(guest.local_side, HuntState.PREY, "guest now plays the goats")
	check(host.session.is_ongoing() and guest.session.is_ongoing(), "new game on")


# --- ENet on this machine ---------------------------------------------------------

func test_enet_round_trip() -> void:
	var server := ENetTransport.host(45990)
	check(server != null, "host listens")
	if server == null:
		return
	var client := ENetTransport.join("127.0.0.1", 45990)
	var got := []
	server.packet.connect(func(b: PackedByteArray) -> void: got.append(b))
	var t0 := Time.get_ticks_msec()
	while not client.is_open() and Time.get_ticks_msec() - t0 < 3000:
		server.poll()
		client.poll()
		OS.delay_msec(5)
	check(client.is_open(), "connected")
	client.send(PackedByteArray([7, 8, 9]))
	t0 = Time.get_ticks_msec()
	while got.is_empty() and Time.get_ticks_msec() - t0 < 3000:
		server.poll()
		client.poll()
		OS.delay_msec(5)
	check_eq(got, [PackedByteArray([7, 8, 9])], "packet arrived")
	client.close()
	server.close()


# --- Codes and discovery -------------------------------------------------------------

func test_nearby_codes() -> void:
	for ip in ["192.168.1.23", "10.0.0.1", "172.20.10.2", "0.0.0.0", "255.255.255.255"]:
		var code := JoinCode.from_ipv4(ip)
		check_eq(code.length(), 8, "%s -> %s" % [ip, code])
		check_eq(JoinCode.to_ipv4(code), ip, "round trip " + ip)
		check_eq(JoinCode.to_ipv4(code.to_lower().replace("-", " ")), ip, "typed loosely")
	check_eq(JoinCode.to_ipv4("ABC"), "", "too short")
	check_eq(JoinCode.normalize_online(" tg 7k4q "), "TG-7K4Q", "online code typed loosely")
	check_eq(JoinCode.normalize_online("TG-7K4"), "", "too short")


func test_lan_discovery_hears_a_beacon() -> void:
	var listener := LanDiscovery.new()
	listener.set_probe_targets([])  # beacons only
	check(listener.listen(45991), "listening")
	var host := LanDiscovery.new()
	host.set_probe_port(45995)
	host.set_destination("127.0.0.1", 45991)
	host.advertise({"title": "test", "name": {"key": "scribe", "n": 7}, "code": "60N-0G0Q"})
	var t0 := Time.get_ticks_msec()
	while listener.hosts().is_empty() and Time.get_ticks_msec() - t0 < 2000:
		host.poll()
		listener.poll()
		OS.delay_msec(10)
	var found := listener.hosts()
	check_eq(found.size(), 1, "one game heard")
	if not found.is_empty():
		check_eq(found[0].get("code"), "60N-0G0Q", "with its code")
	host.stop_advertising()
	listener.stop_listening()


## iPhones can't hear broadcasts: the joiner asks each address directly and
## the host answers with its beacon.
func test_lan_discovery_finds_a_host_by_probing() -> void:
	var host := LanDiscovery.new()
	host.set_probe_port(45993)
	host.set_destination("127.0.0.1", 45999)  # its broadcasts reach nobody
	host.advertise({"title": "test", "name": {"key": "potter", "n": 12}, "code": "60N-0G0R"})
	var joiner := LanDiscovery.new()
	joiner.set_probe_port(45993)
	joiner.set_probe_targets(["127.0.0.1"])
	check(joiner.listen(45992), "listening")
	var t0 := Time.get_ticks_msec()
	while joiner.hosts().is_empty() and Time.get_ticks_msec() - t0 < 2000:
		joiner.poll()
		host.poll()
		OS.delay_msec(10)
	var found := joiner.hosts()
	check_eq(found.size(), 1, "the host answered")
	if not found.is_empty():
		check_eq(found[0].get("code"), "60N-0G0R", "with its code")
		check_eq(found[0].get("ip"), "127.0.0.1", "from its address")
	# A host that stopped answers nothing; the game drops out of the list.
	host.stop_advertising()
	var t1 := Time.get_ticks_msec()
	while not joiner.hosts().is_empty() and Time.get_ticks_msec() - t1 < 6000:
		joiner.poll()
		OS.delay_msec(20)
	check(joiner.hosts().is_empty(), "gone once it stops")
	joiner.stop_listening()


func test_lan_probe_targets() -> void:
	var t := LanDiscovery.probe_targets(["192.168.1.23", "127.0.0.1", "fe80::1", "169.254.3.4", "100.64.0.2"])
	check_eq(t.size(), 254, "253 neighbours and the broadcast address")
	check(not t.has("192.168.1.23"), "not itself")
	check(t.has("192.168.1.1") and t.has("192.168.1.254"), "the whole /24")
	check(not t.has("192.168.1.0") and not t.has("192.168.1.255"), "no network or broadcast address of the /24")
	check_eq(t[t.size() - 1], LanDiscovery.BROADCAST, "the broadcast last")
	var two := LanDiscovery.probe_targets(["10.0.0.5", "172.20.1.9", "10.0.0.7", "172.40.1.1"])
	check_eq(two.size(), 253 * 2 + 1, "two private networks, each once; 172.40 isn't private")
	check_eq(LanDiscovery.probe_targets([]), [LanDiscovery.BROADCAST], "no network: only the broadcast")


# --- Online matching (fake backend) -------------------------------------------------

func _pump_online(things: Array, frames := 8, now := 0) -> void:
	for _i in frames:
		for t in things:
			if t is QuickMatch:
				t.poll(now)
			else:
				t.poll()


func test_quick_match_pairs_two_players() -> void:
	FakeOnlineBackend.reset_cloud()
	var a := QuickMatch.new(FakeOnlineBackend.new(), "test", 1)
	var b := QuickMatch.new(FakeOnlineBackend.new(), "test", 1)
	var got := []
	a.matched.connect(func(t: NetTransport, h: bool) -> void: got.append(["a", h]))
	b.matched.connect(func(t: NetTransport, h: bool) -> void: got.append(["b", h]))
	a.start(0)
	_pump_online([a], 6, 0)
	check_eq(a.status, QuickMatch.Status.WAITING, "a hosts and waits")
	b.start(0)
	_pump_online([a, b], 10, 0)
	check_eq(got.size(), 2, "both matched")
	var hosts := got.filter(func(g: Array) -> bool: return g[1])
	check_eq(hosts.size(), 1, "exactly one host")


func test_quick_match_merges_two_waiting_hosts() -> void:
	FakeOnlineBackend.reset_cloud()
	var a := QuickMatch.new(FakeOnlineBackend.new(), "test", 1)
	var b := QuickMatch.new(FakeOnlineBackend.new(), "test", 1)
	# Both start at once: both find nothing and both host.
	a.start(0)
	b.start(0)
	_pump_online([a, b], 6, 0)
	check(a.status == QuickMatch.Status.WAITING or b.status == QuickMatch.Status.WAITING, "someone waits")
	var got := []
	a.matched.connect(func(_t: NetTransport, h: bool) -> void: got.append(h))
	b.matched.connect(func(_t: NetTransport, h: bool) -> void: got.append(h))
	_pump_online([a, b], 10, 5000)  # the next search round
	check_eq(got.size(), 2, "they found each other")


func test_quick_match_times_out_but_keeps_looking() -> void:
	FakeOnlineBackend.reset_cloud()
	var a := QuickMatch.new(FakeOnlineBackend.new(), "test", 1)
	var timeouts := []
	a.timed_out.connect(func() -> void: timeouts.append(true))
	a.start(0)
	_pump_online([a], 6, 0)
	_pump_online([a], 2, 61000)
	_pump_online([a], 2, 70000)
	check_eq(timeouts.size(), 1, "one time-out")
	check_eq(a.status, QuickMatch.Status.WAITING, "still waiting in the background")
	var b := QuickMatch.new(FakeOnlineBackend.new(), "test", 1)
	var got := []
	a.matched.connect(func(_t: NetTransport, h: bool) -> void: got.append(h))
	b.start(70000)
	_pump_online([a, b], 10, 70000)
	check_eq(got, [true], "a late opponent still finds a")


func test_quick_match_offline_fails() -> void:
	FakeOnlineBackend.reset_cloud()
	var be := FakeOnlineBackend.new()
	be.available = false
	var a := QuickMatch.new(be, "test", 1)
	var why := []
	a.failed.connect(func(r: String) -> void: why.append(r))
	a.start(0)
	_pump_online([a], 4, 0)
	check_eq(why, ["offline"], "offline reported")


func test_friend_code() -> void:
	FakeOnlineBackend.reset_cloud()
	var host := FriendMatch.new(FakeOnlineBackend.new(), "test", 1)
	var codes := []
	host.code_ready.connect(func(c: String) -> void: codes.append(c))
	host.host()
	_pump_online([host], 4)
	check_eq(codes.size(), 1, "code shown")
	var friend := FriendMatch.new(FakeOnlineBackend.new(), "test", 1)
	var got := []
	host.matched.connect(func(_t: NetTransport, h: bool) -> void: got.append(h))
	friend.matched.connect(func(_t: NetTransport, h: bool) -> void: got.append(h))
	friend.join(codes[0].to_lower())
	_pump_online([host, friend], 8)
	check_eq(got.size(), 2, "friend joined")
	var stranger := FriendMatch.new(FakeOnlineBackend.new(), "test", 1)
	var why := []
	stranger.failed.connect(func(r: String) -> void: why.append(r))
	stranger.join("TG-ZZZZ")
	_pump_online([stranger], 4)
	check_eq(why, ["not_found"], "unknown code")


func test_online_match_end_to_end() -> void:
	FakeOnlineBackend.reset_cloud()
	var a := QuickMatch.new(FakeOnlineBackend.new(), "test", 1)
	var b := QuickMatch.new(FakeOnlineBackend.new(), "test", 1)
	var nets := []
	var make := func(t: NetTransport, as_host: bool) -> void:
		if as_host:
			nets.append(NetMatch.as_host(t, "tg", HuntState.HUNTER, MatchSession.Kind.QUICK_MATCH, 60, "test", "b1", {}, _resolve))
		else:
			nets.append(NetMatch.as_guest(t, "test", "b1", {}, _resolve))
	a.matched.connect(make)
	b.matched.connect(make)
	a.start(0)
	_pump_online([a], 6)
	b.start(0)
	_pump_online([a, b], 10)
	check_eq(nets.size(), 2, "two net matches")
	_pump(nets, 8)
	for n in nets:
		check_eq(n.phase, NetMatch.Phase.PLAYING, "playing")
	FakeOnlineBackend.reset_cloud()
