## short messages over every screen
class_name ToastUI
extends UICanvas

var app

func _draw() -> void:
	if app == null or app.toast_t <= 0 or app.toast_text == "" or app.screen == "bowling":
		return
	var tw := text_width(app.toast_text, 16) + 48
	rect(640 - tw / 2, 600, tw, 42, 21, COL.ink)
	text(app.toast_text, 640 - tw / 2, 611, 16, COL.card, "center", tw)
