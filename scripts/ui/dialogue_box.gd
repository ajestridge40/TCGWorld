class_name DialogueBox
extends PanelContainer
## Bottom-of-screen dialogue with typewriter text and choice buttons.
## open(speaker, lines, choices) where choices = [{ "text": String, "cb": Callable }].

signal closed

var _name := UIKit.label("", 16, UIKit.WOOD)
var _text := RichTextLabel.new()
var _choices := HBoxContainer.new()
var _lines: Array = []
var _line_idx := 0
var _pending_choices: Array = []
var _typing := false
var _portrait := TextureRect.new()
var _tween: Tween


func _ready() -> void:
	add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.PAPER, UIKit.WOOD, 4, 8))
	position = Vector2(80, 370)
	custom_minimum_size = Vector2(800, 150)
	size = custom_minimum_size
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	add_child(h)
	_portrait.custom_minimum_size = Vector2(96, 96)
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	h.add_child(_portrait)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(_name)
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(640, 60)
	_text.add_theme_font_size_override("normal_font_size", 16)
	_text.add_theme_color_override("default_color", UIKit.INK)
	_text.scroll_active = false
	v.add_child(_text)
	_choices.add_theme_constant_override("separation", 8)
	v.add_child(_choices)
	visible = false


func is_open() -> bool:
	return visible


func open(speaker: String, lines: Array, choices: Array = [], portrait: Texture2D = null) -> void:
	_name.text = speaker
	_lines = lines
	_line_idx = 0
	_pending_choices = choices
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	visible = true
	_show_line()


func _show_line() -> void:
	for c in _choices.get_children():
		c.queue_free()
	_text.text = _lines[_line_idx]
	_text.visible_ratio = 0.0
	_typing = true
	_tween = create_tween()
	_tween.tween_property(_text, "visible_ratio", 1.0, clampf(_text.text.length() * 0.018, 0.15, 1.6))
	_tween.tween_callback(_line_done)


func _line_done() -> void:
	_typing = false
	_text.visible_ratio = 1.0
	if _line_idx == _lines.size() - 1:
		var list := _pending_choices
		if list.is_empty():
			list = [{ "text": "OK", "cb": Callable() }]
		for ch in list:
			var cb: Callable = ch.get("cb", Callable())
			var b := UIKit.button(ch["text"], func(): _choose(cb))
			b.disabled = ch.get("disabled", false)
			if ch.has("tooltip"):
				b.tooltip_text = ch["tooltip"]
			_choices.add_child(b)
	else:
		_choices.add_child(UIKit.label("▼", 14, UIKit.INK_SOFT))


func advance() -> void:
	if _typing:
		if _tween:
			_tween.kill()
		_line_done()
		return
	if _line_idx < _lines.size() - 1:
		_line_idx += 1
		_show_line()
	elif _pending_choices.is_empty():
		_choose(Callable())


func _choose(cb: Callable) -> void:
	visible = false
	closed.emit()
	if cb.is_valid():
		cb.call()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		advance()
		accept_event()
