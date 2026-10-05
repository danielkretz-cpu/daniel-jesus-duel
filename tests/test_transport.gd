extends SceneTree
## Transport backlog regression tests independent of renderer speed.
var failures := 0
var checks := 0
var packets: Array = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	else:
		print("PASS: ", label)
func run() -> void:
	var net = load("res://NetSession.gd").new()
	root.add_child(net)
	net.received.connect(func(data): packets.append(data))
	for seq in range(1, 51):
		net._queue_received({"type": "state", "seq": seq, "snapshot": {"terrain_version": seq}})
	check(packets.is_empty(), "Backlogged states do not replay intermediate game/terrain work")
	net._flush_received_state()
	check(packets.size() == 1 and packets[0].seq == 50 and net.coalesced_states == 49, "50 queued snapshots produce one newest authoritative application")
	packets.clear()
	net._queue_received({"type": "state", "seq": 60, "snapshot": {}})
	net._queue_received({"type": "state", "seq": 59, "snapshot": {}})
	net._queue_received({"type": "input", "seq": 1, "action": "fire"})
	net._queue_received({"type": "state", "seq": 61, "snapshot": {}})
	net._flush_received_state()
	check(packets.size() == 3 and packets[0].seq == 60 and packets[1].action == "fire" and packets[2].seq == 61, "Stale sequence cannot replace latest; input action remains an ordering barrier")
	net.seat = 0
	net.started = true
	net.status = "connected"
	for seq in range(1, 501):
		net.send_state({"marker": seq}, seq == 1)
	check(net._pending_state.snapshot.marker == 500 and net._pending_state.seq == 500 and net._pending_state.commit, "500 unsent snapshots retain only the newest state with sticky commit")
	net._flush_pending_state()
	check(net._pending_state.snapshot.marker == 500, "Unavailable transport retains newest state for a later writable flush")
	net._queue_received({"type": "state", "seq": 99, "snapshot": {}})
	net._pending_state = {"seq": 99}
	net.leave()
	check(net._incoming_state.is_empty() and net._pending_state.is_empty(), "Leaving clears both bounded queues before the next room")
	check(net.INBOUND_BUFFER == 2097152 and net.STATE_QUEUE_BUDGET == 16384, "Inbound and outbound backlog have explicit bounded budgets")
	net.queue_free()
	await process_frame
	print("RESULT: %d transport checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
