class_name UIKit
extends RefCounted
## Shared palette, theme and small widget helpers so every screen feels the same.

const INK := Color("3a2a22")
const INK_SOFT := Color("6b5544")
const PAPER := Color("f6ead0")
const PAPER_DARK := Color("e8d5ae")
const WOOD := Color("6b4a32")
const WOOD_DARK := Color("4a3222")
const NIGHT := Color("2b2135")
const TEAL := Color("3f8f8a")
const GOLD := Color("e9b44c")
const ROSE := Color("d46a6a")
const LEAF := Color("6aa84f")

const CARD_COLORS := {
	"ember": Color("d9653b"), "tide": Color("3d8fc4"), "grove": Color("4f9a4a"),
	"sun": Color("e3be4f"), "moon": Color("6e55a0"), "colorless": Color("a8a29a"),
	"multi": Color("c9a24a"),
}
const RARITY_COLORS := {
	"basic": Color("9a8f80"), "common": Color("d9d4c7"), "uncommon": Color("9fd6e0"),
	"rare": Color("f2c14e"), "ultra": Color("ff86d6"), "secret": Color("b8fff4"),
}


static func card_color(c: CardDef) -> Color:
	return CARD_COLORS.get(c.main_color(), CARD_COLORS["colorless"])


static func panel_style(bg: Color = PAPER, border: Color = WOOD, width: int = 3, radius: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 3
	s.shadow_offset = Vector2(0, 2)
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var btn := panel_style(Color("f2dfb4"), WOOD, 2, 5)
	btn.content_margin_top = 5
	btn.content_margin_bottom = 5
	var btn_hover := panel_style(Color("fff1cc"), Color("8a6240"), 2, 5)
	btn_hover.content_margin_top = 5
	btn_hover.content_margin_bottom = 5
	var btn_pressed := panel_style(Color("e0c890"), WOOD_DARK, 2, 5)
	btn_pressed.content_margin_top = 6
	btn_pressed.content_margin_bottom = 4
	btn_pressed.shadow_size = 0
	var btn_disabled := panel_style(Color("d8ccb4"), Color("a89880"), 2, 5)
	btn_disabled.content_margin_top = 5
	btn_disabled.content_margin_bottom = 5
	btn_disabled.shadow_size = 0
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_hover)
	t.set_stylebox("pressed", "Button", btn_pressed)
	t.set_stylebox("disabled", "Button", btn_disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color("9a8a78"))
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	var line := panel_style(Color("fffaf0"), WOOD, 2, 4)
	t.set_stylebox("normal", "LineEdit", line)
	t.set_stylebox("focus", "LineEdit", line)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_stylebox("panel", "TabContainer", panel_style())
	t.set_color("font_selected_color", "TabContainer", INK)
	t.set_color("font_unselected_color", "TabContainer", INK_SOFT)
	t.set_color("font_hovered_color", "TabContainer", INK)
	t.set_stylebox("tab_selected", "TabBar", panel_style(PAPER, WOOD, 2, 4))
	t.set_stylebox("tab_unselected", "TabBar", panel_style(PAPER_DARK, WOOD, 2, 4))
	t.set_stylebox("tab_hovered", "TabBar", panel_style(Color("fff1cc"), WOOD, 2, 4))
	t.set_stylebox("tab_selected", "TabContainer", panel_style(PAPER, WOOD, 2, 4))
	t.set_stylebox("tab_unselected", "TabContainer", panel_style(PAPER_DARK, WOOD, 2, 4))
	t.set_stylebox("tab_hovered", "TabContainer", panel_style(Color("fff1cc"), WOOD, 2, 4))
	t.set_color("font_color", "RichTextLabel", INK)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_color", "OptionButton", INK)
	return t


static func label(text: String, size: int = 15, color: Color = INK, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func button(text: String, cb: Callable, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.pressed.connect(func():
		Sfx.play("click")
		cb.call())
	return b


static func panel(bg: Color = PAPER, border: Color = WOOD) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, border))
	return p


static func backdrop(parent: Control, color: Color = Color("3b2c3f")) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = color
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	return bg


static func coins_text(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out + "c"
