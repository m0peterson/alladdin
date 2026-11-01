extends SceneTree

class SaveContext extends Node:
	var world: Control
	var player: Node2D
	var player_state: PlayerState
	var inventory: ItemInventory
	var trades: TradeService
	var quest: LampQuest
	var guards: Array[GuardPatrol]
	var clock: GameClock = GameClock.new()

var failures: int = 0
var context: SaveContext
var game: Node
var saves: WorldSave
var test_dir: String


func _initialize() -> void:
	call_deferred("_run")


func _expect(value: bool, label: String) -> void:
	if value:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _run() -> void:
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game._new_game()
	context = SaveContext.new()
	root.add_child(context)
	context.add_child(context.clock)
	context.clock.set_process(false)
	for field: String in ["world", "player", "player_state", "inventory", "trades", "quest", "guards"]:
		context.set(field, game.get(field))
	for actor: Node in context.world.find_children("*", "Node", true, false):
		actor.set_physics_process(false)
	test_dir = "user://world-save-test-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(test_dir)
	saves = WorldSave.new(test_dir + "/save.json")
	var initial: Dictionary = saves.capture_world(context)
	_expect(saves.validate(initial).is_empty(), "new quarter full snapshot valid")
	_expect(saves.write(initial).is_empty(), "world JSON written in isolated directory")
	_expect(saves.read_file().get("ok", false), "world JSON validated after read")
	var row: Dictionary = context.trades.get_merchant("merchantwest")["stacks"][0]
	_expect(context.trades.buy("merchantwest", row["stack_id"], 1, context.player_state, context.inventory), "real buy changes player and merchant")
	var goods: TheftTarget = context.world.get_node("World/MarketGoods/Interaction")
	context.player.position = goods.global_position + Vector2(0, 20)
	await physics_frame
	await physics_frame
	_expect(not goods.transfer_to(context.inventory, context.player).is_empty(), "real ordinary goods theft clears finite source")
	var lamp: TheftTarget = context.world.get_node("World/WarehouseLamp/Interaction")
	context.player.position = lamp.global_position + Vector2(0, 20)
	await physics_frame
	await physics_frame
	_expect(not lamp.transfer_to(context.inventory, context.player).is_empty(), "real theft transfers the sole lamp")
	_expect(context.quest.accept_order(), "early lamp permits ready order")
	context.guards[0].report_crime(Vector2(250, 250))
	var bandit: BazaarBandit = context.world.get_node("World/Bandit")
	bandit.health = 40
	bandit.phase = BazaarBandit.Phase.WINDUP
	var wounded: Dictionary = bandit.save_snapshot()
	_expect(bandit.restore_snapshot(wounded) and bandit.health == 40 and bandit.phase == BazaarBandit.Phase.IDLE, "unfinished bandit attack normalizes without healing")
	bandit.receive_damage(60)
	(context.world.get_node("World/Chest/Interaction") as InteractionTarget).opened = true
	var changed: Dictionary = saves.capture_world(context)
	_expect(saves.validate(changed).is_empty(), "purchase theft quest and active alarm snapshot valid")
	_expect(saves.write(changed).is_empty(), "changed world safely replaces initial file")
	_expect(saves.has_backup(), "complete previous world is recoverable backup")
	_expect(saves.apply(initial, context).is_empty(), "initial snapshot applies")
	_expect(saves.apply(changed, context).is_empty(), "changed snapshot applies atomically")
	_expect(saves.capture_world(context) == changed, "all persisted fields round trip exactly")
	_expect(bandit.health == 0 and bandit.phase == BazaarBandit.Phase.DEFEATED and not bandit.is_in_group("damageable"), "load does not resurrect defeated bandit")
	_expect(lamp.stock.get_stacks().is_empty() and context.inventory.count_item("lamp") == 1, "load cannot restore stolen source or duplicate lamp")
	_expect(context.guards[0].state == GuardPatrol.State.CHASE and context.guards[0].last_known_position == Vector2(250, 250), "load retains alarm and evidence position")
	_expect(saves.apply(changed, context).is_empty() and saves.capture_world(context) == changed, "repeated load is idempotent")
	var duplicate: Dictionary = changed.duplicate(true)
	duplicate["world"]["containers"]["warehouse_lamp"] = initial["world"]["containers"]["warehouse_lamp"].duplicate(true)
	_reject_unchanged(duplicate, "duplicate lamp across container and player")
	var missing: Dictionary = changed.duplicate(true)
	missing["world"]["guards"].erase("guard_market")
	_reject_unchanged(missing, "missing stable world ID")
	var bad_tail: Dictionary = changed.duplicate(true)
	bad_tail["world"]["guards"]["guard_warehouse"]["state_time"] = "wrong"
	bad_tail["player"]["money"] = 0
	_reject_unchanged(bad_tail, "invalid final guard record cannot partially apply")
	var bad_money: Dictionary = changed.duplicate(true)
	bad_money["world"]["merchants"]["fence"]["budget"] = -1
	_reject_unchanged(bad_money, "negative merchant budget")
	var signals_seen: Array[bool] = []
	context.inventory.changed.connect(func(): signals_seen.append(saves.capture_world(context) == initial))
	_expect(saves.apply(initial, context).is_empty() and signals_seen == [true], "inventory observer sees only fully committed snapshot")
	_expect(saves.apply(changed, context).is_empty(), "restore changed state after observer check")
	var reentry: Array[bool] = []
	context.clock.setup(context.trades)
	context.clock.day_changed.connect(func(_day: int):
		var before: Dictionary = saves.capture_world(context)
		reentry.append(not saves.apply(initial, context).is_empty() and saves.capture_world(context) == before))
	_expect(context.clock.advance(GameClock.DAY_SECONDS) and reentry == [true], "clock callback reentry rejects before any mutation")
	_expect(saves.apply(changed, context).is_empty(), "normal restore works after day commit")
	var bad_refill: Dictionary = changed.duplicate(true)
	bad_refill["world"]["merchants"]["fence"]["last_refill_day"] += 1
	_reject_unchanged(bad_refill, "clock and refill mismatch")
	_reject_unchanged(PlayerSave.new().capture(context.player.position, context.player_state, context.inventory), "legacy player-only save")
	_test_busy_guards(initial, lamp)
	_expect(context.quest.hand_over(), "real quest hands over and pays once")
	var final: Dictionary = saves.capture_world(context)
	_expect(saves.validate(final).is_empty(), "terminal quest and delivered lamp valid")
	var money: int = context.player_state.money
	_expect(saves.apply(final, context).is_empty() and saves.apply(final, context).is_empty(), "final world loads repeatedly")
	_expect(not context.quest.hand_over() and context.player_state.money == money, "repeat final dialogue cannot repeat reward")
	var bad_reward: Dictionary = final.duplicate(true)
	bad_reward["world"]["quest"]["reward_given"] = false
	_reject_unchanged(bad_reward, "completed quest missing reward flag")
	_expect(saves.restore_backup().get("ok", false), "explicit full backup restoration")
	_expect(saves.read_file().get("data", {}) == JSON.parse_string(JSON.stringify(initial)), "backup preserves full earlier world")
	_test_trail_limit(final)
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		DirAccess.remove_absolute(saves.path + suffix)
	DirAccess.remove_absolute(test_dir)
	game.queue_free()
	context.queue_free()
	await process_frame
	print("PASS: T16 world persistence" if failures == 0 else "FAIL: T16 world persistence")
	quit(0 if failures == 0 else 1)


func _reject_unchanged(data: Dictionary, label: String) -> void:
	var before: Dictionary = saves.capture_world(context)
	_expect(not saves.apply(data, context).is_empty(), label + " rejected")
	_expect(saves.capture_world(context) == before, label + " leaves whole game unchanged")


func _test_busy_guards(data: Dictionary, lamp: TheftTarget) -> void:
	for busy_owner: Object in [context.quest, context.trades, context.clock, lamp]:
		busy_owner.set("_busy", true)
		_reject_unchanged(data, "busy " + busy_owner.get_class())
		busy_owner.set("_busy", false)


func _test_trail_limit(data: Dictionary) -> void:
	var guard: GuardPatrol = context.guards[0]
	var original: Dictionary = guard.save_snapshot()
	guard._trail.clear()
	for index: int in range(4096):
		guard._trail.append(Vector2(100, 100))
	_expect(saves.validate(saves.capture_world(context)).is_empty(), "4096 trail points remain saveable")
	guard._trail.append(Vector2(100, 100))
	var too_long: Dictionary = saves.capture_world(context)
	_expect(not saves.validate(too_long).is_empty(), "documented 4097 trail-point limitation is explicit")
	_expect(not saves.write(too_long).is_empty(), "oversized trail cannot overwrite previous valid file")
	_expect(saves.read_file().get("ok", false), "previous file remains valid after long chase save refusal")
	guard.restore_snapshot(original)
	_expect(saves.apply(data, context).is_empty(), "restored bounded trail permits normal loading")
