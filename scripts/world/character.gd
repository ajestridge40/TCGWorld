class_name Character
extends Node2D
## A walking pixel person. Position is the character's feet.

var look: Dictionary = CharacterSprite.PLAYER_LOOK
var facing := Vector2i.DOWN
var moving := false
var npc_id: String = ""
var display_name: String = ""
var sprite := Sprite2D.new()
var _anim_t := 0.0
var _name_label: Label


func _ready() -> void:
	sprite.centered = false
	sprite.offset = Vector2(-8, -15)
	add_child(sprite)
	if display_name != "":
		_name_label = Label.new()
		_name_label.text = display_name
		_name_label.add_theme_font_size_override("font_size", 8)
		_name_label.add_theme_color_override("font_color", Color.WHITE)
		_name_label.add_theme_color_override("font_outline_color", Color("2a211c"))
		_name_label.add_theme_constant_override("outline_size", 3)
		_name_label.position = Vector2(-30, -27)
		_name_label.size = Vector2(60, 10)
		_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name_label.visible = false
		add_child(_name_label)
	_update_sprite()


func show_name(on: bool) -> void:
	if _name_label:
		_name_label.visible = on


func _process(delta: float) -> void:
	if moving:
		_anim_t += delta
	else:
		_anim_t = 0.0
	_update_sprite()


func _update_sprite() -> void:
	var dir := 0
	if facing == Vector2i.UP:
		dir = 1
	elif facing.x != 0:
		dir = 2
	var frame := 0
	if moving:
		frame = 1 + int(_anim_t * 6.0) % 2
	sprite.texture = CharacterSprite.texture(look, dir, frame)
	sprite.flip_h = facing == Vector2i.RIGHT


func tile() -> Vector2i:
	return Vector2i(floori(position.x / WorldMap.T), floori((position.y - 2) / WorldMap.T))


func face_toward(p: Vector2) -> void:
	var d := p - position
	if absf(d.x) > absf(d.y):
		facing = Vector2i.RIGHT if d.x > 0 else Vector2i.LEFT
	else:
		facing = Vector2i.DOWN if d.y > 0 else Vector2i.UP
