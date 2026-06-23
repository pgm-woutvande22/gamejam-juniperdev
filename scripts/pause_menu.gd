extends Control

# In-game pause overlay. Esc toggles it; while shown the SceneTree is paused so all
# gameplay (physics, spawners, the top) freezes. Continue resumes, Restart reloads the level.
# The root node's process_mode must be ALWAYS (set in the scene) so this script and its
# buttons keep responding even though the rest of the tree is paused.

@export_file("*.tscn") var menu_scene: String = "res://scences/main_menu.tscn"

@onready var continue_button: Button = $CenterContainer/VBoxContainer/ContinueButton
@onready var restart_button: Button = $CenterContainer/VBoxContainer/RestartButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton


func _ready() -> void:
	continue_button.pressed.connect(_on_continue_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	visible = false   # start hidden; gameplay runs until Esc is pressed


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):   # Esc by default
		if visible:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()


func _pause() -> void:
	get_tree().paused = true
	visible = true
	continue_button.grab_focus()   # so the menu is keyboard/controller navigable


func _resume() -> void:
	get_tree().paused = false
	visible = false


func _on_continue_pressed() -> void:
	_resume()


func _on_restart_pressed() -> void:
	get_tree().paused = false   # always unpause before swapping scenes
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	get_tree().paused = false   # always unpause before swapping scenes
	get_tree().change_scene_to_file(menu_scene)
