extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var inventory := ItemInventory.new()
	var state := PlayerState.new()
	state.money = 30
	var quest := LampQuest.new()
	_expect(quest.setup(inventory, state), "quest binds shared game data")
	_expect(quest.get_stage() == LampQuest.Stage.OFFERED, "offer is not accepted automatically")
	_refusal(quest, inventory, state, "hand over before order")
	var nested_accept: Array[bool] = []
	quest.changed.connect(func() -> void: nested_accept.append(quest.accept_order()), CONNECT_ONE_SHOT)
	_expect(quest.accept_order(), "explicit acceptance")
	_expect(nested_accept == [false] and quest.get_stage() == LampQuest.Stage.ACCEPTED, "accept signal cannot reenter")
	_refusal(quest, inventory, state, "missing lamp")
	_expect(inventory.add_item("lamp", 1, _origin()), "warehouse theft supplies unique lamp")
	_expect(quest.get_stage() == LampQuest.Stage.READY, "acquired lamp advances accepted quest")
	_expect(not inventory.add_item("lamp", 1, _origin()), "second lamp rejected")
	_expect(not inventory.remove_item(inventory.get_stacks()[0]["stack_id"], 1), "ordinary removal protects quest lamp")
	state.money = LampQuest.MAX_MONEY - LampQuest.REWARD + 1
	_refusal(quest, inventory, state, "reward overflow preflight")
	state.money = 30
	var observed: Array[bool] = []
	var attempts: Array[bool] = []
	var inspect: Callable = func() -> void:
		observed.append(quest.get_stage() == LampQuest.Stage.COMPLETED and inventory.count_item("lamp") == 0 and state.money == 30 + LampQuest.REWARD and quest.get_delivered_lamp().get("instance_id") == ItemCatalog.LAMP_INSTANCE_ID)
		attempts.append(quest.hand_over())
		attempts.append(quest.accept_order())
		attempts.append(quest.setup(ItemInventory.new(), PlayerState.new()))
	inventory.changed.connect(inspect)
	state.changed.connect(inspect)
	quest.changed.connect(inspect)
	_expect(quest.hand_over(), "delivery succeeds")
	_expect(observed == [true, true, true], "all observers see settled items, money, recipient and final stage")
	_expect(attempts.size() == 9 and not attempts.has(true), "all transaction signals reject recursive operations")
	inventory.changed.disconnect(inspect)
	state.changed.disconnect(inspect)
	quest.changed.disconnect(inspect)
	_expect(quest.get_delivered_lamp()["stolen"] and quest.get_delivered_lamp()["owner_id"] == "warehouse_owner" and quest.get_delivered_lamp()["source_id"] == "warehouse_lamp", "recipient retains stolen provenance and stable instance")
	var copy: Dictionary = quest.get_delivered_lamp()
	copy["instance_id"] = "forged"
	_expect(quest.get_delivered_lamp()["instance_id"] == ItemCatalog.LAMP_INSTANCE_ID, "recipient snapshot cannot mutate quest")
	_expect(quest.get_dialogue().contains("Стража заметит пропажу") and quest.get_dialogue().contains("странный свет"), "final includes theft consequence and hint of lamp magic")
	_refusal(quest, inventory, state, "repeated delivery")
	_expect(quest.setup(inventory, state) and quest.get_stage() == LampQuest.Stage.COMPLETED, "same setup cannot reset reward")
	_expect(not quest.setup(ItemInventory.new(), PlayerState.new()), "different game requires fresh quest")
	# Early theft still needs an explicit agreement; acceptance never grants
	# reward, consumes the lamp or bypasses the final hand-over.
	var early_inventory := ItemInventory.new()
	early_inventory.add_item("lamp", 1, _origin())
	var early_state := PlayerState.new()
	var early := LampQuest.new()
	early.setup(early_inventory, early_state)
	_expect(early.get_stage() == LampQuest.Stage.OFFERED, "early lamp preserves offer stage")
	_refusal(early, early_inventory, early_state, "early lamp without agreement")
	_expect(early.accept_order() and early.get_stage() == LampQuest.Stage.READY, "acceptance accounts for early lamp")
	_expect(early_state.money == 0 and early_inventory.count_item("lamp") == 1 and early.get_delivered_lamp().is_empty(), "acceptance alone cannot complete quest")
	# Preserve pre-existing signal suppression while still committing all data.
	early_inventory.set_block_signals(true)
	early_state.set_block_signals(true)
	_expect(early.hand_over(), "early lamp delivery works with blocked observers")
	_expect(early_inventory.is_blocking_signals() and early_state.is_blocking_signals(), "delivery preserves signal blocking flags")
	_expect(early_inventory.count_item("lamp") == 0 and early_state.money == LampQuest.REWARD and early.get_stage() == LampQuest.Stage.COMPLETED, "blocked observers do not prevent commit")
	# World recovery affects health and money but keeps the quest and its lamp.
	var recovery_inventory := ItemInventory.new()
	var recovery_state := PlayerState.new()
	var recovery := LampQuest.new()
	recovery.setup(recovery_inventory, recovery_state)
	recovery.accept_order()
	recovery_inventory.add_item("lamp", 1, _origin())
	recovery_state.health = 0
	recovery_state.health = PlayerState.MAX_HEALTH
	_expect(recovery.get_stage() == LampQuest.Stage.READY and recovery_inventory.count_item("lamp") == 1, "health recovery preserves delivery eligibility")
	var fresh := LampQuest.new()
	fresh.setup(ItemInventory.new(), PlayerState.new())
	_expect(fresh.get_stage() == LampQuest.Stage.OFFERED and fresh.get_delivered_lamp().is_empty(), "new game has fresh quest data")
	_test_ui(quest)
	if failures == 0:
		print("PASS: T14 quest stages, early lamp, unique delivery, atomic reward, reentry and fence UI")
	quit(1 if failures else 0)


func _test_ui(completed: LampQuest) -> void:
	var inventory := ItemInventory.new()
	var state := PlayerState.new()
	var quest := LampQuest.new()
	quest.setup(inventory, state)
	var ui := FenceUI.new()
	root.add_child(ui)
	ui.setup(quest)
	ui.show()
	paused = true
	_expect(ui.process_mode == Node.PROCESS_MODE_ALWAYS, "fence processes while world paused")
	_expect(ui.position.y >= 20 and ui.position.y + ui.size.y <= 165, "dialogue stays between HUD and footer")
	_expect((ui.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a == 1.0, "dialogue background opaque")
	var font: Font = ui.get_theme_font("font")
	_expect(font.has_char("Л".unicode_at(0)) and font.has_char("я".unicode_at(0)), "UI font supports Cyrillic")
	_expect(not ui._action.disabled and ui._action.text == "Принять заказ", "UI offers explicit acceptance")
	ui._action.pressed.emit()
	_expect(quest.get_stage() == LampQuest.Stage.ACCEPTED and ui._action.disabled, "UI delegates acceptance then requests lamp")
	inventory.add_item("lamp", 1, _origin())
	_expect(not ui._action.disabled and ui._action.text == "Передать лампу", "UI reflects incoming lamp")
	ui._action.pressed.emit()
	_expect(quest.get_stage() == LampQuest.Stage.COMPLETED and ui._action.disabled and ui._dialogue.text.contains("выполнен"), "UI shows final only after hand-over")
	ui.setup(completed)
	_expect(ui._dialogue.text.contains("выполнен") and ui._action.disabled, "reopened dialogue retains final without new reward")
	var events: Array[String] = []
	ui.trade_requested.connect(func() -> void: events.append("trade"))
	ui.closed.connect(func() -> void: events.append("close"))
	ui._trade.pressed.emit()
	_expect(events == ["trade"] and paused, "separate trade action delegates routing to game")
	ui.close()
	_expect(events == ["trade", "close"] and not ui.visible and paused, "close delegates pause ownership to game")
	paused = false
	ui.free()


func _origin() -> Dictionary:
	return {"stolen": true, "owner_id": "warehouse_owner", "source_id": "warehouse_lamp", "instance_id": ItemCatalog.LAMP_INSTANCE_ID}


func _refusal(quest: LampQuest, inventory: ItemInventory, state: PlayerState, label: String) -> void:
	var before: Dictionary = {"items": inventory.get_stacks(), "money": state.money, "stage": quest.get_stage(), "delivered": quest.get_delivered_lamp()}
	_expect(not quest.hand_over() and not quest.last_error.is_empty(), label + " refused with reason")
	_expect(before == {"items": inventory.get_stacks(), "money": state.money, "stage": quest.get_stage(), "delivered": quest.get_delivered_lamp()}, label + " changes nothing")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
