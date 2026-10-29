class_name ToastLayer
extends CanvasLayer
## Little pop-up notifications (achievements, rank ups, hearts). Add one to any scene.

const ICONS := { "achievement": "★", "rank": "▲", "heart": "♥", "info": "•", "coin": "●" }

var _box := VBoxContainer.new()


func _ready() -> void:
	layer = 50
	_box.position = Vector2(330, 8)
	_box.custom_minimum_size = Vector2(300, 0)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	Game.toast.connect(show_toast)


func show_toast(text: String, kind: String = "info") -> void:
	var p := UIKit.panel(Color("fff6dc"), UIKit.GOLD if kind != "heart" else UIKit.ROSE)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UIKit.label("%s  %s" % [ICONS.get(kind, "•"), text], 14, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	p.add_child(l)
	p.modulate.a = 0.0
	_box.add_child(p)
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(2.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)
