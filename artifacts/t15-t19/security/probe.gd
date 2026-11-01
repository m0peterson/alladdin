extends SceneTree
var failures: int = 0
var checks: int = 0
var game: Node
var saves: WorldSave
var directory: String
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	directory = OS.get_temp_dir().path_join("alladdin-audit-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	saves = WorldSave.new(directory.path_join("world.json"))
	game = load("res://scenes/game.tscn").instantiate()
	game.saves = saves
	root.add_child(game)
	game._new_game()
	game.clock.set_process(false)
	var initial: Dictionary = saves.capture_world(game)
	check(saves.validate(initial).is_empty(), "initial world valid")
	for key: String in ["containers", "merchants", "quest", "guards", "clock", "bandit"]:
		for value: Variant in [null, [], true, "res://scripts/game.gd", 1e100, {}]:
			var bad: Dictionary = initial.duplicate(true)
			bad["world"][key] = value
			check(not saves.apply(bad,game).is_empty() and saves.capture_world(game) == initial, "malformed section unchanged: " + key)
	var bad: Dictionary = initial.duplicate(true)
	bad["player"]["money"] = 123
	bad["world"]["bandit"]["health"] = -1
	check(not saves.apply(bad,game).is_empty() and saves.capture_world(game) == initial, "invalid late bandit cannot commit player")
	bad = initial.duplicate(true)
	bad["world"]["guards"]["guard_warehouse"]["position"]["x"] = "128"
	check(not saves.apply(bad,game).is_empty() and saves.capture_world(game) == initial, "guard numeric string rejected")
	var lamp: Dictionary = initial["world"]["containers"]["warehouse_lamp"]["inventory"]["stacks"][0].duplicate(true)
	lamp["stack_id"] = "stack_4"
	lamp["stolen"] = true
	bad = initial.duplicate(true)
	bad["player"]["inventory"]["stacks"].append(lamp)
	bad["player"]["inventory"]["next_stack_id"] = 5
	check(not saves.apply(bad,game).is_empty() and saves.capture_world(game) == initial, "duplicate cross-world lamp unchanged")
	bad["world"]["containers"]["warehouse_lamp"]["opened"] = true
	bad["world"]["containers"]["warehouse_lamp"]["inventory"]["stacks"] = []
	check(saves.apply(bad,game).is_empty(), "single lamp transferred snapshot valid")
	check(game.quest.accept_order() and game.quest.hand_over(), "quest terminal fixture")
	var final: Dictionary = saves.capture_world(game)
	var money: int = game.player_state.money
	check(saves.apply(final,game).is_empty() and saves.apply(final,game).is_empty() and not game.quest.hand_over() and game.player_state.money == money, "reload final cannot repeat reward")
	bad = final.duplicate(true)
	bad["world"]["quest"]["reward_given"] = false
	check(not saves.apply(bad,game).is_empty() and saves.capture_world(game) == final, "bad reward marker unchanged")
	var busy_results: Array[bool] = []
	game.clock.day_changed.connect(func(_day: int):
		var before: Dictionary = saves.capture_world(game)
		busy_results.append(not saves.apply(initial,game).is_empty() and saves.capture_world(game) == before))
	check(game.clock.advance(GameClock.DAY_SECONDS) and busy_results == [true], "busy day callback cannot partially restore")
	var day: Dictionary = saves.capture_world(game)
	check(saves.apply(day,game).is_empty(), "day restores")
	var merchant_before: Dictionary = game.trades.save_snapshot()
	check(game.trades.refill_for_day(1) and game.trades.save_snapshot() == merchant_before, "same-day refill no grant")
	check(not game.trades.refill_for_day(0) and game.trades.save_snapshot() == merchant_before, "backward refill unchanged")
	check(game.clock.advance(0) and saves.capture_world(game) == day, "zero delta after load no grant")
	check(not game.clock.advance(1e100) and saves.capture_world(game) == day, "overflow delta unchanged")
	var capped := ItemInventory.new()
	check(capped.restore_snapshot({"stacks":[],"next_stack_id":ItemInventory.MAX_QUANTITY}) and not capped.add_item("bread",1) and ItemInventory.validate_snapshot(capped.save_snapshot()).is_empty(), "ID boundary closed")
	for key: String in ["owner_id","source_id","instance_id"]:
		var strings := ItemInventory.new()
		check(strings.add_item("silk",1,{key:"x".repeat(128)}) and not strings.add_item("silk",1,{key:"x".repeat(129)}) and ItemInventory.validate_snapshot(strings.save_snapshot()).is_empty(), "runtime ID strings 128/129 boundary: " + key)
	var stacks: Array = []
	for i: int in range(4096):
		stacks.append({"stack_id":"stack_%d" % (i+1),"item_id":"bread","quantity":1,"stolen":false,"owner_id":"player","source_id":"source_%d" % i,"instance_id":""})
	var full := ItemInventory.new()
	check(full.restore_snapshot({"stacks":stacks,"next_stack_id":4097}), "4096 stack boundary accepted")
	check(not full.add_item("silk",1) and full.add_item("bread",1,{"owner_id":"player","source_id":"source_0"}) and ItemInventory.validate_snapshot(full.save_snapshot()).is_empty(), "capacity rejects new but permits merge")
	check(saves.write(day).is_empty(), "isolated safe write")
	var primary: String = FileAccess.get_file_as_string(saves.path)
	DirAccess.make_dir_absolute(saves.path + ".bak.tmp")
	check(not saves.write(initial).is_empty() and FileAccess.get_file_as_string(saves.path) == primary, "backup temp failure preserves primary")
	DirAccess.remove_absolute(saves.path + ".bak.tmp")
	check(saves.write(initial).is_empty(), "backup safely created")
	var file := FileAccess.open(saves.path,FileAccess.WRITE)
	file.store_string("{bad")
	file.close()
	check(not saves.read_file()["ok"] and not saves.write(initial).is_empty() and saves.has_backup(), "corrupt primary cannot overwrite")
	check(saves.restore_backup()["ok"] and saves.read_file()["data"] == JSON.parse_string(JSON.stringify(day)), "explicit backup restores whole world")
	var long_trail: Dictionary = day.duplicate(true)
	var trail: Array = []
	for i: int in range(4096):
		trail.append({"x":128.0,"y":144.0})
	var guard_data: Dictionary = long_trail["world"]["guards"]["guard_market"]
	guard_data["trail"] = trail
	guard_data["state"] = GuardPatrol.State.CHASE
	guard_data["position"] = {"x":200.0,"y":144.0}
	guard_data["last_known_position"] = {"x":215.0,"y":144.0}
	check(saves.apply(long_trail,game).is_empty(), "4096 trail save applies")
	game.guards[0]._update_alert_movement(1.0/60.0)
	print("KNOWN_LOW_S3: trail=%d error=%s" % [game.guards[0]._trail.size(),saves.validate(saves.capture_world(game))])
	check(game.guards[0]._trail.size() == 4097 and not saves.validate(saves.capture_world(game)).is_empty(), "S3 remains bounded documented rejection")
	for filename: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	game.queue_free()
	await process_frame
	print("SECURITY_CURRENT_RESULT: checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
