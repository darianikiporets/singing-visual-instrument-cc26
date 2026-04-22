extends Node2D

@onready var start_btn = $VBoxContainer/Start
@onready var quit_btn = $VBoxContainer/Quit

func _ready():
	start_btn.pressed.connect(_on_start)
	quit_btn.pressed.connect(_on_quit)

func _on_start():
	get_tree().change_scene_to_file("res://main.tscn")

func _on_quit():
	get_tree().quit()
