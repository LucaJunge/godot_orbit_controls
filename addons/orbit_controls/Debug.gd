extends CanvasLayer

signal azimuth_slider_changed
signal polar_slider_changed

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func set_key(key_name: String, value: String):
	get_node("List/"+key_name).text = key_name + ": " + value

func set_toggle(toggle_name: String, value: bool):
	var node = get_node("List/" + toggle_name)
	if(value):
		node.set("custom_colors/default_color", Color(0, 0.6, 0, 1))
	else:
		node.set("custom_colors/default_color", Color(0.6, 0, 0, 1))
		
	node.text = toggle_name + ": " + str(value)
	
func _on_azimuth_slider_value_changed(value):
	emit_signal("azimuth_slider_changed", value)

func _on_polar_slider_value_changed(value):
	emit_signal("polar_slider_changed", value)

