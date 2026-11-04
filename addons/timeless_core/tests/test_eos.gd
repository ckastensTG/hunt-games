extends TestCase
## The EOS online backend on a pretend EOS (FakeEOSApi): login, lobbies,
## quick match, friend codes, the P2P link and a full match over it.

const IDS := {"product_name": "Test", "product_id": "p", "sandbox_id": "s", "deployment_id": "d",
	"client_id": "c", "client_secret": "x"}


func _resolve(id: String) -> HuntRuleSet:
	return HuntFixtures.tigers_and_goats() if id == "tg" else null


func _backend() -> EOSOnlineBackend:
	return EOSOnlineBackend.new(FakeEOSApi.new(), IDS)


func _pump(things: Array, frames := 8, now := 0) -> void:
	for _i in frames:
		for t in things:
			if t is NetMatch:
				t.poll(now)
			elif t is QuickMatch:
				t.poll(now)
			else:
				t.poll()


func test_unavailable_without_a_client() -> void:
	FakeEOSApi.reset_cloud()
	var ids := IDS.duplicate()
	ids.client_secret = ""
	var be := EOSOnlineBackend.new(FakeEOSApi.new(), ids)
	check(not be.is_available(), "no client secret: not available")
	var got := []
	be.logged_in.connect(func(ok: bool) -> void: got.append(ok))
	be.login()
	_pump([be], 3)
	check_eq(got, [false], "login fails at once")
	FakeEOSApi.reset_cloud()


func test_login_keeps_the_device_user() -> void:
	FakeEOSApi.reset_cloud()
	var be := _backend()
	check(be.is_available(), "available")
	be.login()
	_pump([be], 3)
	check(be.is_logged_in(), "logged in")
	var first := be.user_id()
	be.login()
	_pump([be], 3)
	check_eq(be.user_id(), first, "same user on a second login")
	be.reset_identity()
	_pump([be], 3)
	check(not be.is_logged_in(), "reset forgets the user")
	be.login()
	_pump([be], 3)
	check(be.user_id() != first and be.user_id() != "", "a new user after the reset")
	FakeEOSApi.reset_cloud()


func test_quick_match_over_eos() -> void:
	FakeEOSApi.reset_cloud()
	var a := QuickMatch.new(_backend(), "test", 1)
	var b := QuickMatch.new(_backend(), "test", 1)
	var other := QuickMatch.new(_backend(), "test", 2)   # another protocol version
	var got := []
	a.matched.connect(func(_t: NetTransport, h: bool) -> void: got.append(["a", h]))
	b.matched.connect(func(_t: NetTransport, h: bool) -> void: got.append(["b", h]))
	other.matched.connect(func(_t: NetTransport, h: bool) -> void: got.append(["other", h]))
	a.start(0)
	_pump([a], 8)
	check_eq(a.status, QuickMatch.Status.WAITING, "a hosts and waits")
	other.start(0)
	_pump([a, other], 8)
	check(got.is_empty(), "a different protocol never matches")
	b.start(0)
	_pump([a, b, other], 10)
	check_eq(got.size(), 2, "a and b matched")
	check_eq(got.filter(func(g: Array) -> bool: return g[1]).size(), 1, "exactly one host")
	FakeEOSApi.reset_cloud()


func test_friend_code_and_a_full_match_over_eos() -> void:
	FakeEOSApi.reset_cloud()
	var host := FriendMatch.new(_backend(), "test", 1)
	var codes := []
	host.code_ready.connect(func(c: String) -> void: codes.append(c))
	host.host()
	_pump([host], 6)
	check_eq(codes.size(), 1, "code shown")
	var friend := FriendMatch.new(_backend(), "test", 1)
	var nets := []
	var make := func(t: NetTransport, as_host: bool) -> void:
		if as_host:
			nets.append(NetMatch.as_host(t, "tg", HuntState.PREY, MatchSession.Kind.ONLINE_FRIEND, 0, "test", "b1", {}, _resolve))
		else:
			nets.append(NetMatch.as_guest(t, "test", "b1", {}, _resolve))
	host.matched.connect(make)
	friend.matched.connect(make)
	friend.join(codes[0])
	_pump([host, friend], 10)
	check_eq(nets.size(), 2, "both sides have a match")
	if nets.size() != 2:
		return
	for _i in 10:
		_pump([host, friend], 1)
		_pump(nets, 1, 1000)
	for n in nets:
		check_eq(n.phase, NetMatch.Phase.PLAYING, "playing over EOS P2P")
	# A move from the host (goats move first in this fixture).
	var hn: NetMatch = nets[0] if nets[0].is_host() else nets[1]
	var gn: NetMatch = nets[1] if hn == nets[0] else nets[0]
	var mover: NetMatch = hn if hn.session.state.side == hn.local_side else gn
	var other: NetMatch = gn if mover == hn else hn
	var m: PackedInt32Array = mover.session.state.legal_moves()[0]
	check(mover.session.commit(m, mover.local_side), "local move accepted")
	for _i in 6:
		_pump([host, friend], 1)
		_pump(nets, 1, 1100)
	check_eq(other.session.moves.size(), 1, "the move arrived on the other device")
	FakeEOSApi.reset_cloud()


func test_transport_joins_big_messages() -> void:
	FakeEOSApi.reset_cloud()
	var api_a := FakeEOSApi.new()
	var api_b := FakeEOSApi.new()
	var a := EOSOnlineBackend.new(api_a, IDS)
	var b := EOSOnlineBackend.new(api_b, IDS)
	a.login()
	b.login()
	_pump([a, b], 3)
	var ta := a.open_transport("lobbyX", b.user_id(), true)
	var tb := b.open_transport("lobbyX", a.user_id(), false)
	var got: Array[PackedByteArray] = []
	tb.packet.connect(func(bytes: PackedByteArray) -> void: got.append(bytes))
	var big := PackedByteArray()
	for i in 5000:
		big.append(i % 251)
	ta.send(PackedByteArray([1, 2, 3]))
	ta.send(big)
	ta.send(PackedByteArray([4]))
	_pump([a, b, ta, tb], 3)
	check_eq(got.size(), 3, "three messages")
	if got.size() == 3:
		check_eq(got[0], PackedByteArray([1, 2, 3]), "first")
		check_eq(got[1], big, "5000 bytes, joined from chunks")
		check_eq(got[2], PackedByteArray([4]), "order kept")
	FakeEOSApi.reset_cloud()


func test_drop_and_return_of_the_link() -> void:
	FakeEOSApi.reset_cloud()
	var api_a := FakeEOSApi.new()
	var api_b := FakeEOSApi.new()
	var a := EOSOnlineBackend.new(api_a, IDS)
	var b := EOSOnlineBackend.new(api_b, IDS)
	a.login()
	b.login()
	_pump([a, b], 3)
	var ta := a.open_transport("lobbyY", b.user_id(), true)
	var tb := b.open_transport("lobbyY", a.user_id(), false)
	var events := []
	tb.connected.connect(func() -> void: events.append("up"))
	tb.disconnected.connect(func() -> void: events.append("down"))
	_pump([a, b, ta, tb], 2)
	api_a.drop_link(b.user_id(), EOSOnlineBackend.socket_for("lobbyY"))
	_pump([a, b, ta, tb], 3)
	check(not tb.is_open() and not tb.is_closed(), "dropped, not closed")
	api_a.restore_link(b.user_id(), EOSOnlineBackend.socket_for("lobbyY"))
	_pump([a, b, ta, tb], 3)
	check_eq(events, ["up", "down", "up"], "down and back up")
	ta.close()
	_pump([a, b, ta, tb], 3)
	check(tb.is_closed(), "closed when the other side closes")
	FakeEOSApi.reset_cloud()


func test_host_leaving_tells_the_guest() -> void:
	FakeEOSApi.reset_cloud()
	var a := _backend()
	var b := _backend()
	a.login()
	b.login()
	_pump([a, b], 3)
	var ids := []
	a.lobby_created.connect(func(id: String) -> void: ids.append(id))
	a.create_lobby({"game": "test", "proto": 1, "code": "TG-AAAA"}, true)
	_pump([a, b], 3)
	b.join_lobby(ids[0])
	_pump([a, b], 3)
	var left := []
	b.member_left.connect(func(l: String, u: String) -> void: left.append([l, u]))
	a.leave_lobby(ids[0])
	_pump([a, b], 3)
	check_eq(left, [[ids[0], a.user_id()]], "the guest hears the host left")
	FakeEOSApi.reset_cloud()
