extends Control

const BAZAAR: PackedScene = preload("res://scenes/start.tscn")
const Player = preload("res://scripts/player.gd")
const BANDIT: PackedScene = preload("res://scenes/bandit.tscn")
const CONTAINER: PackedScene = preload("res://scenes/bazaar_prop.tscn")
const STARTING_MONEY: int = 30

var world: Control
var player_state: PlayerState
var player: Player
var inventory: ItemInventory
var inventory_ui: InventoryUI
var trades: TradeService
var trade_ui: TradeUI
var guards: Array[GuardPatrol] = []
var detection_ui: GuardDetectionUI
var theft: TheftController
var theft_ui: TheftUI
var crime: CrimeService
var quest: LampQuest
var fence_ui: FenceUI
var _waiting_inventory_release: bool = true
var saves: PlayerSave = WorldSave.new()
var clock: GameClock
var save_panel: Panel
var save_message: Label
var save_close: Button
var backup_button: Button

@onready var main_menu: Control = $Interface/MainMenu
@onready var pause_menu: Control = $Interface/PauseMenu
@onready var hud: Control = $Interface/HUD
@onready var health_label: Label = $Interface/HUD/Health
@onready var money_label: Label = $Interface/HUD/Money
@onready var new_game_button: Button = $Interface/MainMenu/NewGame
@onready var resume_button: Button = $Interface/PauseMenu/Resume
@onready var interactions: InteractionController = $Interactions
@onready var interaction_hint: Label = $Interface/HUD/InteractionHint
@onready var dialogue: Control = $Interface/Dialogue
@onready var dialogue_text: Label = $Interface/Dialogue/Text
@onready var dialogue_close: Button = $Interface/Dialogue/Close


func _ready() -> void:
	new_game_button.pressed.connect(_new_game)
	$Interface/MainMenu/Continue.pressed.connect(_load_player)
	_setup_save_panel()
	_refresh_continue()
	$Interface/MainMenu/Exit.pressed.connect(_exit_game)
	resume_button.pressed.connect(_resume)
	$Interface/PauseMenu/MainMenu.pressed.connect(_return_to_menu)
	$Interface/PauseMenu/Exit.pressed.connect(_exit_game)
	interactions.prompt_changed.connect(_update_interaction_hint)
	interactions.interaction_completed.connect(_on_interaction_completed)
	dialogue_close.pressed.connect(_close_dialogue)
	new_game_button.grab_focus()


func _process(_delta: float) -> void:
	if _waiting_inventory_release:
		_waiting_inventory_release = Input.is_action_pressed("inventory")
	if clock != null:
		var seconds: int = int(clock.seconds_in_day)
		$Interface/HUD/Day.text = "День %d\n%02d:%02d / 06:00" % [clock.day_index + 1, seconds / 60, seconds % 60]


func _input(event: InputEvent) -> void:
	if save_panel.visible:
		if event.is_action_pressed("ui_cancel") and not event.is_echo():
			_close_save_panel()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("quick_save") or event.is_action_pressed("quick_load"):
		get_viewport().set_input_as_handled()
		if event.is_echo() or world == null or get_tree().paused:
			return
		if event.is_action_pressed("quick_save"):
			_save_player()
		else:
			_load_player()
		return
	if world != null and event.is_action_pressed("inventory") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if not _waiting_inventory_release:
			if inventory_ui.visible:
				_close_inventory()
			elif not get_tree().paused:
				_pause_world()
				inventory_ui.show()
				inventory_ui.focus_default()
		return
	if world != null and event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if dialogue.visible:
			_close_dialogue()
		elif inventory_ui.visible:
			_close_inventory()
		elif trade_ui.visible:
			trade_ui.close()
		elif fence_ui.visible:
			fence_ui.close()
		elif get_tree().paused:
			_resume()
		else:
			_pause_world()
			pause_menu.show()
			resume_button.grab_focus()


func _new_game() -> void:
	if world != null:
		return
	player_state = PlayerState.new()
	player_state.money = STARTING_MONEY
	inventory = ItemInventory.new()
	for item_id: String in ["bread", "silk", "spices"]:
		inventory.add_item(item_id, 2 if item_id == "bread" else 1, {"owner_id": "player", "source_id": "starter"})
	trades = TradeService.new()
	inventory_ui = InventoryUI.new()
	$Interface.add_child(inventory_ui)
	inventory_ui.setup(player_state, inventory)
	inventory_ui.closed.connect(_close_inventory)
	inventory_ui.hide()
	trade_ui = TradeUI.new()
	$Interface.add_child(trade_ui)
	trade_ui.closed.connect(_resume)
	trade_ui.hide()
	quest = LampQuest.new()
	quest.setup(inventory, player_state)
	fence_ui = FenceUI.new()
	$Interface.add_child(fence_ui)
	fence_ui.setup(quest)
	fence_ui.closed.connect(_resume)
	fence_ui.trade_requested.connect(_open_fence_trade)
	fence_ui.hide()
	world = BAZAAR.instantiate() as Control
	# The controller and its menus keep running; all world descendants pause.
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	clock = GameClock.new()
	clock.name = "GameClock"
	clock.setup(trades)
	world.add_child(clock)
	player = world.get_node("World/Player") as Player
	player.state = player_state
	player.suppress_movement_until_release()
	player.suppress_combat_until_release()
	$WorldContainer.add_child(world)
	_install_actors()
	interactions.set_player(player)
	theft = TheftController.new()
	add_child(theft)
	theft.setup(player, inventory, interactions)
	theft_ui = TheftUI.new()
	$Interface.add_child(theft_ui)
	theft_ui.setup(theft)
	theft.theft_completed.connect(crime.on_theft_completed)
	detection_ui = GuardDetectionUI.new()
	$Interface.add_child(detection_ui)
	detection_ui.setup(guards)
	player_state.changed.connect(_update_hud)
	_update_hud()
	new_game_button.release_focus()
	main_menu.hide()
	hud.show()
	_waiting_inventory_release = true


func _install_actors() -> void:
	var actors: Node2D = world.get_node("World") as Node2D
	actors.get_node("Bandit").free()
	actors.get_node("Guard").free()
	var bandit: Node2D = BANDIT.instantiate() as Node2D
	bandit.name = "Bandit"
	bandit.position = Vector2(552, 344)
	actors.add_child(bandit)
	bandit.configure(player)
	var recovery: DefeatRecovery = DefeatRecovery.new()
	actors.add_child(recovery)
	recovery.configure(player, player_state, Vector2(136, 368), bandit)
	guards = GuardPatrol.install(actors)
	for guard: GuardPatrol in guards:
		guard.configure(player)
	_install_theft_container(actors, "MarketGoods", "market_goods", "Чужой шёлк",
		Vector2(96, 248), "merchantwest", "silk")
	_install_theft_container(actors, "WarehouseLamp", "warehouse_lamp", "Складская лампа",
		Vector2(520, 160), "warehouse", "lamp")
	var owners: Array[CrimeWitness] = []
	for npc_name: String in ["MerchantWest", "MerchantEast"]:
		var npc: Node2D = actors.get_node(npc_name) as Node2D
		var witness: CrimeWitness = CrimeWitness.new()
		witness.owner_id = String(npc.get_meta("world_id"))
		witness.facing = Vector2.DOWN
		npc.add_child(witness)
		owners.append(witness)
	crime = CrimeService.new()
	crime.configure(guards, owners)


func _install_theft_container(actors: Node2D, node_name: String, stable_id: String,
		title: String, location: Vector2, owner_id: String, item_id: String) -> void:
	var body: StaticBody2D = CONTAINER.instantiate() as StaticBody2D
	body.name = node_name
	body.position = location
	body.set("footprint", Vector2(20, 12))
	body.set("rise", 10.0)
	body.set("tint", Color("a48039") if item_id == "lamp" else Color("84563b"))
	body.set_meta("world_id", stable_id)
	actors.add_child(body)
	var target: TheftTarget = TheftTarget.new()
	target.name = "Interaction"
	target.target_id = stable_id
	target.display_name = title
	target.owner_id = owner_id
	target.kind = InteractionTarget.Kind.CONTAINER
	target.seed(item_id)
	body.add_child(target)


func _pause_world() -> void:
	interaction_hint.hide()
	theft.suppress_until_release()
	theft_ui.hide()
	get_tree().paused = true


func _resume() -> void:
	# GUI consumes events, but Input polling still sees held navigation keys.
	player.suppress_movement_until_release()
	player.suppress_combat_until_release()
	interactions.suppress_until_release()
	theft.suppress_until_release()
	_waiting_inventory_release = true
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	pause_menu.hide()
	get_tree().paused = false


func _return_to_menu() -> void:
	interactions.set_player(null)
	player_state.changed.disconnect(_update_hud)
	$WorldContainer.remove_child(world)
	world.queue_free()
	world = null
	clock = null
	player = null
	player_state = null
	get_tree().paused = false
	pause_menu.hide()
	hud.hide()
	dialogue.hide()
	inventory_ui.queue_free()
	trade_ui.queue_free()
	fence_ui.queue_free()
	theft_ui.queue_free()
	detection_ui.queue_free()
	theft.queue_free()
	inventory_ui = null
	trade_ui = null
	inventory = null
	trades = null
	quest = null
	fence_ui = null
	theft_ui = null
	detection_ui = null
	theft = null
	crime = null
	guards.clear()
	main_menu.show()
	_refresh_continue()
	new_game_button.grab_focus()


func _update_interaction_hint(text: String) -> void:
	interaction_hint.text = text
	interaction_hint.visible = not text.is_empty()


func _show_dialogue(message: String) -> void:
	dialogue_text.text = message
	interaction_hint.hide()
	_pause_world()
	dialogue.show()
	dialogue_close.grab_focus()


func _on_interaction_completed(message: String) -> void:
	var target: InteractionTarget = interactions.current_target
	if target != null and target.target_id == "fence":
		_pause_world()
		fence_ui.show()
		fence_ui.focus_default()
	elif target != null and target.target_id in trades.get_merchant_ids():
		trade_ui.setup(trades, player_state, inventory, target.target_id)
		_pause_world()
		trade_ui.show()
	else:
		_show_dialogue(message)


func _open_fence_trade() -> void:
	fence_ui.hide()
	trade_ui.setup(trades, player_state, inventory, "fence")
	trade_ui.show()


func _close_inventory() -> void:
	inventory_ui.hide()
	_resume()


func _close_dialogue() -> void:
	dialogue.hide()
	_resume()


func _update_hud() -> void:
	health_label.text = "Здоровье: %d/%d" % [player_state.health, PlayerState.MAX_HEALTH]
	money_label.text = "Динары: %d" % player_state.money


func _exit_game() -> void:
	get_tree().quit()


func _refresh_continue() -> void:
	var button: Button = $Interface/MainMenu/Continue
	# Damaged saves remain actionable so errors and explicit recovery are reachable.
	button.disabled = not FileAccess.file_exists(saves.path) and not FileAccess.file_exists(saves.path + ".bak")
	button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL


func _setup_save_panel() -> void:
	save_panel = Panel.new()
	save_panel.name = "SaveMessage"
	save_panel.position = Vector2(8, 24)
	save_panel.size = Vector2(304, 132)
	save_panel.theme = main_menu.theme
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color("291f30")
	background.border_color = Color("b48b52")
	background.set_border_width_all(1)
	save_panel.add_theme_stylebox_override("panel", background)
	$Interface.add_child(save_panel)
	save_message = Label.new()
	save_message.position = Vector2(8, 6)
	save_message.size = Vector2(288, 74)
	save_message.add_theme_font_size_override("font_size", 10)
	save_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_panel.add_child(save_message)
	backup_button = Button.new()
	backup_button.position = Vector2(12, 82)
	backup_button.size = Vector2(280, 20)
	backup_button.add_theme_font_size_override("font_size", 10)
	backup_button.text = "Восстановить резервную копию"
	backup_button.pressed.connect(_recover_backup)
	save_panel.add_child(backup_button)
	save_close = Button.new()
	save_close.position = Vector2(72, 106)
	save_close.size = Vector2(160, 22)
	save_close.text = "Закрыть"
	save_close.pressed.connect(_close_save_panel)
	save_panel.add_child(save_close)
	save_panel.hide()


func _show_save_message(message: String, offer_backup: bool = false) -> void:
	if world != null:
		_pause_world()
	var notice: String = "Игрок, контейнеры, заказ, торговцы, тревога и игровой день сохраняются." if saves is WorldSave else PlayerSave.WORLD_NOTICE
	save_message.text = message + "\n" + notice
	backup_button.visible = offer_backup and saves.has_backup()
	$Interface.move_child(save_panel, -1)
	save_panel.show()
	save_close.grab_focus()


func _close_save_panel() -> void:
	save_panel.hide()
	if world != null:
		_resume()
	else:
		new_game_button.grab_focus()


func _save_player() -> void:
	var snapshot: Dictionary = (saves as WorldSave).capture_world(self) if saves is WorldSave else saves.capture(player.position, player_state, inventory)
	var problem: String = saves.write(snapshot)
	_refresh_continue()
	_show_save_message("Игра сохранена. F9 — загрузить." if problem.is_empty() else problem, not problem.is_empty())


func _load_player() -> void:
	var result: Dictionary = saves.read_file()
	if not result["ok"]:
		_show_save_message(result["error"], true)
		return
	var problem: String = _apply_player_save(result["data"])
	_show_save_message("Игра загружена." if problem.is_empty() else problem)


func _recover_backup() -> void:
	var result: Dictionary = saves.restore_backup()
	if not result["ok"]:
		_show_save_message(result["error"])
		return
	var problem: String = _apply_player_save(result["data"])
	_refresh_continue()
	_show_save_message("Резервная копия восстановлена и загружена." if problem.is_empty() else problem)


func _apply_player_save(data: Dictionary) -> String:
	# read_file validated the entire snapshot before any live state is changed.
	var problem: String = saves.validate(data)
	if not problem.is_empty():
		return problem
	if world == null:
		_new_game()
	if saves is WorldSave:
		problem = (saves as WorldSave).apply(data, self)
		if not problem.is_empty():
			return problem
		for window: Control in [pause_menu, dialogue, inventory_ui, trade_ui, fence_ui]:
			window.hide()
		theft.suppress_until_release()
		player.suppress_movement_until_release()
		player.suppress_combat_until_release()
		interactions.suppress_until_release()
		_waiting_inventory_release = true
		_update_hud()
		return ""
	var saved: Dictionary = data["player"]
	inventory.restore_snapshot(saved["inventory"])
	player_state.health = int(saved["health"])
	player_state.money = int(saved["money"])
	player.position = Vector2(saved["position"]["x"], saved["position"]["y"])
	player.reset_combat()
	player.suppress_movement_until_release()
	interactions.suppress_until_release()
	return ""
