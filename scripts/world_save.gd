class_name WorldSave
extends PlayerSave

const WORLD_VERSION: int = 2
const WORLD_PATH: String = "user://world-save.json"
const CONTAINERS: Dictionary = {"market_goods": "merchantwest", "warehouse_lamp": "warehouse"}
const GUARDS: Array[String] = ["guard_market", "guard_alley", "guard_warehouse"]
var _applying: bool = false


func _init(save_path: String = WORLD_PATH) -> void:
	super(save_path)


func capture_world(game: Node) -> Dictionary:
	var data: Dictionary = super.capture(game.player.position, game.player_state, game.inventory)
	data["version"] = WORLD_VERSION
	data["scope"] = "world"
	var containers: Dictionary = {}
	for target: InteractionTarget in game.world.find_children("*", "InteractionTarget", true, false):
		if target is TheftTarget:
			containers[target.target_id] = target.save_snapshot()
		elif target.kind == InteractionTarget.Kind.CONTAINER:
			containers[target.target_id] = {"opened": target.opened}
	var guards: Dictionary = {}
	for guard: GuardPatrol in game.guards:
		guards[String(guard.guard_id)] = guard.save_snapshot()
	data["world"] = {"id": "bazaar", "containers": containers,
		"merchants": game.trades.save_snapshot(), "quest": game.quest.save_snapshot(),
		"guards": guards, "clock": game.clock.save_snapshot(),
		"bandit": game.world.get_node("World/Bandit").save_snapshot()}
	return data


func validate(data: Variant) -> String:
	if data is not Dictionary or not integer_in(data.get("version"), WORLD_VERSION, WORLD_VERSION) or data.get("scope") != "world":
		return "Нужен полный save квартала версии 2. Старый save игрока не содержит состояния мира."
	var problem: String = PlayerSave.new().validate({"version": 1, "scope": "player", "player": data.get("player")})
	if not problem.is_empty():
		return problem
	var saved: Variant = data.get("world")
	if saved is not Dictionary or saved.get("id") != "bazaar":
		return "Неверный квартал в сохранении."
	if not _same_ids(saved.get("containers"), ["market_goods", "warehouse_lamp", "fence_chest"]) or not _same_ids(saved.get("guards"), GUARDS):
		return "Отсутствующий, неизвестный или повторный ID мира."
	for id: String in CONTAINERS:
		var target: TheftTarget = TheftTarget.new()
		target.target_id = id
		target.owner_id = CONTAINERS[id]
		problem = target.validate_snapshot(saved["containers"][id])
		target.free()
		if not problem.is_empty():
			return problem
		var stacks: Array = saved["containers"][id]["inventory"]["stacks"]
		if not stacks.is_empty() and (stacks[0]["item_id"] != ("lamp" if id == "warehouse_lamp" else "silk") or int(stacks[0]["quantity"]) != 1):
			return "Подменено содержимое конечного контейнера."
	var chest: Variant = saved["containers"]["fence_chest"]
	if chest is not Dictionary or chest.get("opened") is not bool:
		return "Неверный пустой сундук."
	problem = LampQuest.validate_snapshot(saved.get("quest"))
	if not problem.is_empty():
		return problem
	problem = GameClock.validate_snapshot(saved.get("clock"))
	if not problem.is_empty():
		return problem
	var trades: TradeService = TradeService.new()
	problem = trades.validate_snapshot(saved.get("merchants"))
	if not problem.is_empty():
		return problem
	for merchant: Dictionary in saved["merchants"].values():
		if merchant["last_refill_day"] != saved["clock"]["day_index"]:
			return "День пополнения не совпадает с игровыми часами."
	for id: String in GUARDS:
		var guard: GuardPatrol = GuardPatrol.new()
		guard.route = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		problem = guard.validate_snapshot(saved["guards"][id])
		guard.free()
		if not problem.is_empty():
			return problem
	problem = BazaarBandit.validate_snapshot(saved.get("bandit"))
	if not problem.is_empty():
		return problem
	return _validate_unique_items(data)


func _same_ids(data: Variant, ids: Array) -> bool:
	if data is not Dictionary or data.size() != ids.size():
		return false
	for id: String in ids:
		if not data.has(id):
			return false
	return true


func _validate_unique_items(data: Dictionary) -> String:
	var inventories: Array = [data["player"]["inventory"]]
	var world: Dictionary = data["world"]
	for id: String in CONTAINERS:
		inventories.append(world["containers"][id]["inventory"])
	for merchant: Dictionary in world["merchants"].values():
		inventories.append(merchant["inventory"])
	var instances: Dictionary = {}
	var lamp_count: int = 0
	for inventory: Dictionary in inventories:
		for stack: Dictionary in inventory["stacks"]:
			var instance: String = stack["instance_id"]
			if not instance.is_empty():
				if instances.has(instance):
					return "Повторный уникальный экземпляр предмета в мире."
				instances[instance] = true
			if stack["item_id"] == "lamp":
				lamp_count += 1
	var quest: Dictionary = world["quest"]
	if not quest["delivered_lamp"].is_empty():
		lamp_count += 1
	if lamp_count != 1:
		return "Лампа должна существовать ровно в одном месте."
	for merchant: Dictionary in world["merchants"].values():
		for stack: Dictionary in merchant["inventory"]["stacks"]:
			if stack["item_id"] == "lamp":
				return "Лампа не может находиться в торговом запасе."
	var player_has_lamp: bool = false
	for stack: Dictionary in data["player"]["inventory"]["stacks"]:
		player_has_lamp = player_has_lamp or stack["item_id"] == "lamp"
	var stage: int = int(quest["stage"])
	if (stage == LampQuest.Stage.READY and not player_has_lamp) or (stage == LampQuest.Stage.ACCEPTED and player_has_lamp):
		return "Стадия заказа не согласована с лампой игрока."
	return ""


# The complete preflight is read-only. Each restore then receives the same
# validated data, all busy guards are checked, and no callback sees a partial world.
func apply(data: Variant, game: Node) -> String:
	if _applying:
		return "Загрузка уже выполняется."
	var problem: String = validate(data)
	if not problem.is_empty():
		return problem
	if game.world == null or game.quest == null or game.clock == null:
		return "Квартал ещё не подготовлен для загрузки."
	var targets: Dictionary = {}
	for target: InteractionTarget in game.world.find_children("*", "InteractionTarget", true, false):
		if target.kind != InteractionTarget.Kind.CONTAINER:
			continue
		if targets.has(target.target_id):
			return "Повторный ID контейнера в текущем мире."
		targets[target.target_id] = target
	if not _same_ids(targets, data["world"]["containers"].keys()):
		return "ID контейнеров текущего мира не совпадают с сохранением."
	var guards: Dictionary = {}
	for guard: GuardPatrol in game.guards:
		if guards.has(String(guard.guard_id)):
			return "Повторный ID стражника в текущем мире."
		guards[String(guard.guard_id)] = guard
	if not _same_ids(guards, GUARDS):
		return "ID стражи текущего мира не совпадают с сохранением."
	for id: String in CONTAINERS:
		if targets[id] is not TheftTarget:
			return "Неверный тип контейнера текущего мира."
		problem = targets[id].validate_snapshot(data["world"]["containers"][id])
		if not problem.is_empty():
			return problem
	for id: String in GUARDS:
		problem = guards[id].validate_snapshot(data["world"]["guards"][id])
		if not problem.is_empty():
			return problem
	problem = game.trades.validate_snapshot(data["world"]["merchants"])
	if not problem.is_empty():
		return problem
	if game.world.get_node_or_null("World/Bandit") is not BazaarBandit:
		return "Бандит текущего мира отсутствует."
	if game.quest._busy or game.trades.is_busy() or game.clock.is_busy():
		return "Дождитесь завершения игровой операции."
	for id: String in CONTAINERS:
		if targets[id]._busy:
			return "Дождитесь завершения кражи."
	_applying = true
	var was_paused: bool = game.get_tree().paused
	game.get_tree().paused = true
	var observers: Array = [game.inventory, game.player_state, game.quest, game.trades, game.clock]
	var blocked: Array[bool] = []
	for observer: Object in observers:
		blocked.append(observer.is_blocking_signals())
		observer.set_block_signals(true)
	game.inventory.restore_snapshot(data["player"]["inventory"])
	game.player_state.health = int(data["player"]["health"])
	game.player_state.money = int(data["player"]["money"])
	game.player.position = Vector2(data["player"]["position"]["x"], data["player"]["position"]["y"])
	game.player.velocity = Vector2.ZERO
	game.player.reset_combat()
	for id: String in targets:
		if targets[id] is TheftTarget:
			targets[id].restore_snapshot(data["world"]["containers"][id])
		else:
			targets[id].opened = data["world"]["containers"][id]["opened"]
	game.trades.restore_snapshot(data["world"]["merchants"])
	game.clock.restore_snapshot(data["world"]["clock"])
	game.quest.restore_snapshot(data["world"]["quest"])
	game.world.get_node("World/Bandit").restore_snapshot(data["world"]["bandit"])
	for id: String in guards:
		guards[id].restore_snapshot(data["world"]["guards"][id])
	for index: int in range(observers.size()):
		observers[index].set_block_signals(blocked[index])
	# Inventory's quest listener now sees the restored matching stage.
	for index: int in range(observers.size()):
		if not blocked[index] and observers[index].has_signal("changed"):
			observers[index].emit_signal("changed")
	game.get_tree().paused = was_paused
	_applying = false
	return ""
