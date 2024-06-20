@tool
extends Node3D

# SIGNALS #
signal start
signal change
signal end

# ENUMS #

enum MOUSE {
	LEFT = 0,
	MIDDLE = 1,
	RIGHT = 2,
	ROTATE = 0,
	DOLLY = 1,
	PAN = 2
}

enum STATE {
	NONE = 0,
	ROTATE = 1,
	DOLLY = 2,
	PAN = 3,
	TOUCH_ROTATE = 4,
	TOUCH_PAN = 5,
	TOUCH_DOLLY_PAN = 6,
	TOUCH_DOLLY_ROTATE = 7
}

enum TOUCH {
	ROTATE,
	PAN,
	DOLLY_PAN,
	DOLLY_ROTATE
}

const EPSILON:float = 0.0001

### PROPERTIES IN INSPECTOR ###

@export_category("Orbit Control Settings")
@export
var enabled: bool = true
@export
var debug: bool = false
@export_node_path("Camera3D")
var _camera: NodePath = NodePath():
	set(value):
		_camera = value
		update_configuration_warnings()
var camera:Camera3D = null

@export_group("Target")
@export
var target: Vector3 = Vector3(0, 0, 0)

# AUTO-ROTATE
@export_group("Auto Rotate")
@export
var auto_rotate: bool = false
@export_range(0.001, 10.0)
var auto_rotate_speed: float = 1.0

# ROTATE
@export_group("Rotate")
@export
var enable_rotate: bool = true
@export_range(0.001, 10.0)
var rotate_speed: float = 1.0

# DOLLY (Perspective Cam only)
@export_group("Dolly")
@export_range(0.001, 100.0)
var min_distance: float = 0.001
@export_range(0.001, 100.0)
var max_distance: float = 100.0

# ZOOM (Orthographic Camera only)
@export_group("Zoom")
@export
var enable_zoom: bool = true
@export_range(0.001, 100.0)
var zoom_speed: float = 1.0
@export_range(0.001, 100.0)
var min_zoom: float = 0.001
@export_range(0.001, 100.0)
var max_zoom: float = 100.0

# LIMITS
@export_group("Limits")
@export_range(0, 180, 0.001, "radians")
var min_polar_angle: float = 0
@export_range(0, 180, 0.001, "radians")
var max_polar_angle: float = PI
@export_range(-360, 360, 0.001, "radians")
var min_azimuth_angle: float = - TAU
@export_range(-360, 360, 0.001, "radians")
var max_azimuth_angle: float = TAU

# DAMPING
@export_group("Damping")
@export
var enable_damping: bool = true
@export_range(0.001, 0.99)
var damping_factor: float = 0.05

# PAN
@export_group("Pan")
@export
var enable_pan: bool = true
@export_range(0.001, 10.00)
var pan_speed: float = 2.0
@export
var screen_space_panning: bool = false
@export_range(0.001, 100.00)
var key_pan_speed: float = 7.0

### END OF PROPERTIES ###

# Internal State
var radius: float = 1.0
var debug_layer: CanvasLayer = null
var debug_nodes = {}

# HELPERS
var spherical = Spherical.new()
var spherical_delta = Spherical.new()

# On rotate (left click)
var rotate_start = Vector2(0, 0)
var rotate_end = Vector2(0, 0)
var rotate_delta = Vector2(0, 0)

# On pan (right click)
var pan_start = Vector2(0, 0)
var pan_end = Vector2(0, 0)
var pan_delta = Vector2(0, 0)

# on Dolly
var dolly_start = Vector2(0, 0)
var dolly_end = Vector2(0, 0)
var dolly_delta = Vector2(0, 0) 

var pointers = []
var pointerPositions = {}

# Other
var orbit_scale: float = 1
var pan_offset = Vector3(0, 0, 0)
var needs_update:bool = true

var mouse_buttons = { "LEFT": MOUSE.ROTATE, "MIDDLE": MOUSE.DOLLY, "RIGHT": MOUSE.PAN }
var touches = { "ONE": TOUCH.ROTATE, "TWO": TOUCH.DOLLY_PAN }
var state = STATE.NONE

# for reset
var target0: Vector3 = Vector3(0, 0, 0)
var position0: Vector3 = Vector3(0, 0, 0)
var zoom0: float = 1.0
var valid: bool = false

func _get_configuration_warnings():
	if not _camera:
		return ["Please assign a camera to orbit with in the inspector."]
	
func _ready() -> void:
	
	# Code to run in-game
	if not Engine.is_editor_hint():
		
		valid = check_camera()
	
		# for reset
		target0 = target
		position0 = camera.position
		zoom0 = camera.fov
		
		if debug:
			enable_debug()

func _process(delta: float) -> void:
	if not valid:
		return
	
	if needs_update:
		update()
	
	if debug:
		debug_nodes["state"].text = "STATE: " + STATE.keys()[state]

func update() -> void:
	needs_update = auto_rotate
	var offset: Vector3 = Vector3(0, 0, 0)
	
	# the current position of the camera 
	var position: Vector3 = camera.position
	
	# the current offset, copies the position into offset
	# and subtracts the target vector
	
	# copy the camera position to offset
	offset = position
	
	# subtract the target position
	offset -= target
	
	# set the spherical coords to this offset vector
	spherical.set_from_vector(offset)
	
	# enable auto rotate if configured
	if auto_rotate && state == STATE.NONE:
		rotate_left(get_auto_rotation_angle())
		
#	# Dampen the actual spherical with the damping every frame
	if enable_damping:
		spherical.theta += spherical_delta.theta * damping_factor
		spherical.phi += spherical_delta.phi * damping_factor
	else: # or without damping
		spherical.theta += spherical_delta.theta
		spherical.phi += spherical_delta.phi 

	# restrict theta to be between desired limits
	var _min = min_azimuth_angle + EPSILON
	var _max = max_azimuth_angle - EPSILON
	
	# some is_finite() check missing here, as godot does not seem to allow infinite numbers anyway
	if _min < - PI:
		_min += TAU
	elif _min > PI:
		_min -= TAU
		
	if _max < - PI:
		_max += TAU
	elif _max > PI:
		_max -= TAU
	
	if _min <= _max:
		spherical.theta = max(_min, min(_max, spherical.theta))
	else:
		if spherical.theta > (_min + _max / float(2)):
			spherical.theta = max(_min, spherical.theta)
		else:
			spherical.theta = min(_max, spherical.theta)
 
	# restrict phi to be between desired limits
	spherical.phi = clampf(spherical.phi, min_polar_angle + EPSILON, max_polar_angle - EPSILON)

	spherical.make_safe()
	
	spherical.radius *= orbit_scale

	# restrict radius to be between desired limits
	spherical.radius = max(min_distance, min(max_distance, spherical.radius))
	
	# move target to panned location
	if enable_damping:
		target += pan_offset * damping_factor
	else:
		target += pan_offset

	offset = spherical.apply_to_vector(offset)
	
	position = target + offset
	
	camera.look_at_from_position(position, target, Vector3.UP)
	emit_signal("change")

	# Dampen the delta spherical by the damping factor
	if enable_damping:
		# only update during _process when still dampening
		needs_update = spherical_delta.dampen(damping_factor) or auto_rotate
		pan_offset *= (1 - damping_factor)
		if pan_offset.length_squared() > 0.001:
			needs_update = true
		
	else:
		spherical_delta.set_from_cartesian_coords(0, 0, 0)
		pan_offset = Vector3.ZERO
		
	orbit_scale = 1

func _unhandled_input(event: InputEvent) -> void:
	if enabled == false:
		return
		
	# ON MOUSE DOWN (left, middle, right)
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE) and event.pressed:
		on_mouse_down(event)
	
	# ON MOUSE UP
	if event is InputEventMouseButton and not event.pressed:
		on_mouse_up(event)
	
	if event is InputEventMouseMotion:
		
		# Windows has a bug that triggers an InputEventMouseMotion event on
		# releasing button clicks # with event.relative = 0, 0
		# so filtering that out
		if not event.relative == Vector2.ZERO:
			on_mouse_move(event)

	# ON MOUSE WHEEL
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_UP):
		on_mouse_wheel(event)
		
	# ON TOUCH
	if event is InputEventScreenTouch:
		if event.pressed:
			on_touch_down(event)
		else:
			on_touch_up(event)
			
	# ON TOUCH DRAG
	if event is InputEventScreenDrag:
		on_touch_move(event)

func save_state() -> void:
	target0 = target
	position0 = camera.position
	zoom0 = camera.fov

func reset() -> void:
	target = target0
	camera.position = position0
	camera.fov = zoom0
	
	update()
	
	state = STATE.NONE

### Functions ###

## Getters

func get_polar_angle() -> float:
	return spherical.phi

func get_azimuthal_angle() -> float:
	return spherical.theta

func get_distance() -> float:
	return camera.position.distance_squared_to(target)

func get_auto_rotation_angle() -> float:
	return (TAU / 360) * auto_rotate_speed
	
func get_zoom_scale() -> float:
	return pow(0.95, zoom_speed)

### ROTATION ###

func rotate_left(angle: float) -> void:
	spherical_delta.theta -= angle

func rotate_up(angle: float) -> void:
	spherical_delta.phi -= angle

### DOLLY ###

func dolly_out(dolly_scale: float) -> void:
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		orbit_scale /= dolly_scale
	elif camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = max(min_zoom, min(max_zoom, camera.size))
		#zoom changed = true
	else:
		print("Unknown camera type detected. Zooming disabled")
		enable_zoom = false
	
func dolly_in(dolly_scale: float) -> void:
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		orbit_scale *= dolly_scale
	elif camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = max(min_zoom, min(max_zoom, camera.size / dolly_scale))
	else:
		print("Unknown camera type detected. Zooming disabled")
		enable_zoom = false

### PAN ###

func pan(delta_x, delta_y) -> void: 
	var offset = Vector3()
	
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		var position = camera.position
		offset = position - target
		var target_distance = offset.length()
		
		# half of the FOV is the vertical center of the screen
		target_distance *= tan(camera.fov / 2.0) * PI / 180.0

		pan_left(-2 * delta_x * target_distance / get_viewport().get_size().y, camera.transform)
		
		#pan_up(1, camera.transform)
		pan_up(-2 * delta_y * target_distance / get_viewport().get_size().y, camera.transform)
	
	elif camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		#pan_left(delta_y)
		pass
		
	else:
		print("Unknown camera type - pan disabled")
		enable_pan = false

func pan_left(distance, matrix) -> void:
	var v = Vector3()
	
	# get x column of camera
	v = matrix.basis.x
	
	v *= - distance
	
	pan_offset += v
	
func pan_up(distance, matrix) -> void:
	var v = Vector3()
	
	if screen_space_panning:
		v = matrix.basis.x
	else:
		v = matrix.basis.y
		v.cross(Vector3(0, 1, 0))
	
	v *= distance
	
	pan_offset += v

### POINTER HANDLING

func add_pointer(event):
	pointers.push_back(event)

func remove_pointer(event):
	
	pointerPositions.erase(event.index)
	
	for i in pointers.size():
		if pointers[i].index == event.index:
			pointers.remove(i)
			return

func track_pointer(event):

	var pointer_index = 0
	var position = Vector2()
	
	# a mouse event does not have an index
	# and assume there are no more than one mouse pointer
	if not event is InputEventMouse:
		pointer_index = event.index

	if not pointerPositions.has(pointer_index):
		pointerPositions[pointer_index] = Vector2(0, 0)
	
	pointerPositions[pointer_index].x = event.position.x
	pointerPositions[pointer_index].y = event.position.y

# "on_" functions define the first action after the input event

func on_mouse_down(event):	
	var mouse_action = null
	
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			mouse_action = mouse_buttons.LEFT
		MOUSE_BUTTON_MIDDLE:
			mouse_action = mouse_buttons.MIDDLE
		MOUSE_BUTTON_RIGHT:
			mouse_action = mouse_buttons.RIGHT
		_:
			mouse_action = -1 # why not none?
			
	match mouse_action:
		MOUSE.DOLLY:
			if not enable_zoom: return
			
			handle_mouse_down_dolly(event)
			
			state = STATE.DOLLY
		MOUSE.ROTATE:
			#if event.ctrlKey or event.metaKey or event.shiftkey
				#if not enable pan: return
				#handle_mouse_down_pan(event)
				#state = STATE.PAN
			#else
			if not enable_rotate: return
			
			handle_mouse_down_rotate(event)
			
			state = STATE.ROTATE
		
		MOUSE.PAN: 
			#if event.ctrlKey or event.metaKey or event.shiftkey
				#if not enable pan: return
				#handle_mouse_down_rotate(event)
				#state = STATE.PAN
			#else
			if not enable_pan: return
			
			handle_mouse_down_pan(event)
			
			state = STATE.PAN 
		
		_:
			state = STATE.NONE
			
	if not state == STATE.NONE:
		emit_signal("start")

func on_mouse_move(event):
	#print("on_mouse_move")
	#track_pointer(event)

	match state:
		STATE.ROTATE:
			if not enable_rotate: return
			
			handle_mouse_move_rotate(event)
		
		STATE.DOLLY:
			if not enable_zoom: return
			
			handle_mouse_move_dolly(event)
		
		STATE.PAN:
			if not enable_pan: return
			
			handle_mouse_move_pan(event)

func on_mouse_wheel(event):
	if enabled == false or enable_zoom == false or state != STATE.NONE:
		return
	
	emit_signal("start")
	
	handle_mouse_wheel(event)
	
	emit_signal("end")

func on_touch_down(event):
	add_pointer(event)
	
	track_pointer(event)
	
	match pointers.size():
		
		1:
			
			match touches.ONE:
				
				TOUCH.ROTATE:
					if enable_rotate == false:
						return

					handle_touch_start_rotate()
					
					state = STATE.TOUCH_ROTATE
				
				TOUCH.PAN:
					if enable_pan == false:
						return
					
					handle_touch_start_pan()
					
					state = STATE.TOUCH_PAN
					
				_:
					state = STATE.NONE
					
		2: 
			
			match touches.TWO:
				
				TOUCH.DOLLY_PAN:
					if enable_zoom == false && enable_pan == false:
						return
						
					handle_touch_start_dolly_pan()
					
					state = STATE.TOUCH_DOLLY_PAN
				
				TOUCH.DOLLY_ROTATE:
					if enable_zoom == false && enable_rotate == false:
						return
					
					state = STATE.TOUCH_DOLLY_ROTATE
				
				_:
					state = STATE.NONE
					
		_:
			state = STATE.NONE
	
	if state != STATE.NONE:
		emit_signal("start")

func on_touch_up(event):
	remove_pointer(event)
	
	# how can I re-evaluate the state?
	# e.g. we are in touch_dolly_pan and lift one finger.
	# We should be in touch_rotate state then and not NONE
	state = STATE.NONE

func on_mouse_up(event):	
	# remove_pointer not needed here
	
	# how can I re-evaluate the state?
	# e.g. we are in touch_dolly_pan and lift one finger.
	# We should be in touch_rotate state then and not NONE
	state = STATE.NONE

# calls handle_-functions depending on number of pointers
func on_touch_move(event):
	
	track_pointer(event)
	
	match state:

		STATE.TOUCH_ROTATE:
			
			if enable_rotate == false:
				return
			
			handle_touch_move_rotate(event)
			
			update()
			
		STATE.TOUCH_PAN:
			
			if enable_pan == false:
				return
				
			handle_touch_move_pan(event)
			
			update()
			
		STATE.TOUCH_DOLLY_PAN:
			
			if enable_zoom == false && enable_pan == false:
				return
			
			handle_touch_move_dolly_pan(event)
			
			update()
			
		STATE.TOUCH_DOLLY_ROTATE:
			
			if enable_zoom == false && enable_rotate == false:
				return
				
			#handle_touch_move_dolly_rotate(event)
			
			update()
			
		_:
			state = STATE.NONE

func handle_mouse_down_rotate(event: InputEventMouseButton) -> void:
	rotate_start = event.position

func handle_mouse_move_rotate(event: InputEventMouseMotion) -> void:
	rotate_end = event.position
	
	rotate_delta = (rotate_end - rotate_start) * rotate_speed
	
	rotate_left(2 * PI * rotate_delta.x / get_viewport().size.y) # yes, height
	
	rotate_up(2 * PI * rotate_delta.y / get_viewport().size.y)
	
	rotate_start = rotate_end
	
	update()

func handle_mouse_down_pan(event: InputEventMouseButton) -> void:
	pan_start = event.position

func handle_mouse_move_pan(event: InputEventMouseMotion) -> void:
	pan_end = event.position
	
	pan_delta = (pan_end - pan_start) * pan_speed * 20.0
	
	pan(pan_delta.x, pan_delta.y)
	
	pan_start = pan_end
	
	update()

func handle_mouse_down_dolly(event: InputEventMouseButton) -> void:
	dolly_start = event.position

func handle_mouse_move_dolly(event: InputEventMouseMotion) -> void:
	dolly_end = event.position
	
	dolly_delta = dolly_end - dolly_start
	
	if dolly_delta.y > 0:
		dolly_out(get_zoom_scale())
	elif dolly_delta.y < 0:
		dolly_in(get_zoom_scale())
		
	dolly_start = dolly_end
	
	update()

func handle_mouse_wheel(event):
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		dolly_in(get_zoom_scale())
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		dolly_out(get_zoom_scale())
	
	update()

func get_second_pointer_position(event) -> Vector2:
	
	var pointer = null
	
	if event.index == pointers[0].index:
		pointer = pointers[1]
	else:
		pointer = pointers[0]
		
	return pointerPositions[pointer.index]

func handle_touch_start_rotate():
	if pointers.size() == 1:
		rotate_start.x = pointers[0].position.x
		rotate_start.y = pointers[0].position.y
	else:
		var x = 0.5 * (pointers[0].position.x + pointers[1].position.x)
		var y = 0.5 * (pointers[0].position.y + pointers[1].position.y)
		
		rotate_start.x = x
		rotate_start.y = y

func handle_touch_move_rotate(event):
	if pointers.size() == 1:
		rotate_end = event.position
	else:
		var position = get_second_pointer_position(event)
		var x = 0.5 * (event.position.x + position.x)
		var y = 0.5 * (event.position.y + position.y)
		
		rotate_end.x = x
		rotate_end.y = y
	
	rotate_delta = (rotate_end - rotate_start) * rotate_speed
		
	rotate_left(2 * PI * rotate_delta.x / get_viewport().size.y)
	
	rotate_up(2 * PI * rotate_delta.y / get_viewport().size.y)
	
	rotate_start = rotate_end

func handle_touch_move_pan(event):
	if pointers.size() == 1:
		pan_end.x = event.position.x
		pan_end.y = event.position.y
	else:
		var position = get_second_pointer_position(event)
		var x = 0.5 * (event.position.x + position.x)
		var y = 0.5 * (event.position.y + position.y)
		
		pan_end.x = x
		pan_end.y = y
	
	pan_delta = (pan_end - pan_start) * pan_speed * 20.0
	
	pan(pan_delta.x, pan_delta.y)
	
	pan_start = pan_end

func handle_touch_start_dolly_pan():
	if enable_zoom:
		handle_touch_start_dolly()
	if enable_pan:
		handle_touch_start_pan()

func handle_touch_start_dolly():
	var dx = pointers[0].position.x - pointers[1].position.x
	var dy = pointers[0].position.y - pointers[1].position.y
	
	var distance = sqrt(dx * dx + dy * dy)
	
	dolly_start.x = 0
	dolly_start.y = distance

func handle_touch_start_pan():
	if pointers.size() == 1:
		pan_start.x = pointers[0].position.x
		pan_start.y = pointers[0].position.y
	else:
		var x = 0.5 * (pointers[0].position.x + pointers[1].position.x)
		var y = 0.5 * (pointers[0].position.y + pointers[1].position.y)
		
		pan_start.x = x
		pan_start.y = y

func handle_touch_move_dolly_pan(event):
	if enable_zoom:
		handle_touch_move_dolly(event)
	if enable_pan:
		handle_touch_move_pan(event)

func handle_touch_move_dolly(event):
	var position = get_second_pointer_position(event)
	
	var dx = event.position.x - position.x
	var dy = event.position.y - position.y
	
	var distance = sqrt(dx * dx + dy * dy)
	
	dolly_end.x = 0
	dolly_end.y = distance
	
	dolly_delta.x = 0
	dolly_delta.y = pow(dolly_end.y / dolly_start.y, zoom_speed)
	
	dolly_out(dolly_delta.y)
	
	dolly_start = dolly_end

### HELPER FUNCTIONS AND UTILITIES ###

# Check if the camera variable is actually a camera, print an error if not
func check_camera() -> bool:
	if _camera:
		camera = get_node(_camera)
		
		if not camera.is_class("Camera3D"):
			printerr("Selected Camera3D is not a camera.")
			return false
		else:
			return true
	else:
		printerr("No camera provided")
		return false

# Adds a debug overlay that shows current projection mode and state
func enable_debug():
	debug_layer = CanvasLayer.new()
	debug_layer.name = "debug_layer"
	var v_box_container = VBoxContainer.new()
	v_box_container.name = "list"
	v_box_container.offset_left = 15
	v_box_container.offset_top = 15
	debug_layer.add_child(v_box_container)
	
	var root_viewport = get_tree().get_root()
	var label = Label.new()
	var projection = "PERSPECTIVE" if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else "ORTHOGRAPHIC"
	label.text = "OrbitControls Debug (%s)" % projection
	label.set("theme_override_colors/font_color", Color(1.0, 0.5, 0.5))
	add_to_debug(label, "Heading")
	
	add_string_to_debug("state")
	add_string_to_debug("pointers")

	root_viewport.call_deferred("add_child", debug_layer)

# Adds a string to the debug UI
func add_string_to_debug(name: String):
	var string = Label.new()
	string.name = name
	add_to_debug(string, name)

# Adds Control nodes of any type to debug UI
func add_to_debug(control: Control, name: String) -> void:
	var list = debug_layer.get_node("list")
	list.add_child(control)
	debug_nodes[name] = control
