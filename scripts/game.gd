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


func _input(event: InputEvent) -> void:
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
