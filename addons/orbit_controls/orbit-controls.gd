tool
extends Control

# SIGNALS #
signal start
signal change
signal end

# ENUMS #

enum STATE {
	NONE = -1,
	ROTATE = 0,
	DOLLY = 1,
	PAN = 2,
	TOUCH_ROTATE = 3,
	TOUCH_PAN = 4,
	TOUCH_DOLLY_PAN = 5,
	TOUCH_DOLLY_ROTATE = 6
}

enum TOUCH {
	ROTATE,
	PAN,
	DOLLY_PAN,
	DOLLY_ROTATE
}

### PROPERTIES IN INSPECTOR ###

var enabled: bool
var debug: bool
var _camera: NodePath
var camera: Node
var target: Vector3

# AUTO-ROTATE
var auto_rotate: bool
var auto_rotate_speed: float

# ROTATE
var enable_rotate: bool
var rotate_speed: float

# DOLLY (Perspective Cam only)
var min_distance: float
var max_distance: float

# ZOOM (Orthographic Camera only)
var enable_zoom: bool
var zoom_speed: float
var min_zoom: float
var max_zoom: float

# LIMITS
var min_polar_angle: float
var max_polar_angle: float
var min_azimuth_angle: float
var max_azimuth_angle: float

# DAMPING
var enable_damping: bool
var damping_factor: float

# PAN
var enable_pan: bool
var pan_speed: float
var screen_space_panning: bool
var key_pan_speed: float

### END OF PROPERTIES ###

# Internal State
var radius: float = 1.0
var debug_layer: CanvasLayer = null
var debug_nodes = {}

# HELPERS
var spherical = Spherical.new()
var spherical_delta = Spherical.new()
const two_pi: float = PI * 2

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
var scale: float = 1
var pan_offset = Vector3(0, 0, 0)

var touches = { "ONE": TOUCH.ROTATE, "TWO": TOUCH.DOLLY_PAN }
var state = STATE.NONE

# for reset
var target0: Vector3 = Vector3(0, 0, 0)
var position0: Vector3 = Vector3(0, 0, 0)
var zoom0: float = 1.0
var valid: bool = false
	
func _ready():
	if check_camera():
		valid = true
	
	# for reset
	target0 = target
	position0 = camera.translation
	zoom0 = camera.fov
	
	if debug:
		enable_debug()

func _process(delta):
	if valid:
		update()
	
	if debug:
		debug_nodes["spherical_delta"].text = "phi: %s\ntheta:%s" % [ spherical_delta.phi, spherical_delta.theta]
		debug_nodes["camera_position"].text = "cam_x: %s\ncam_y: %s\ncam_z: %s" % [ camera.translation.x, camera.translation.y, camera.translation.z]
	

### Public Functions ###

func get_polar_angle() -> float:
	return spherical.phi

func get_azimuthal_angle() -> float:
	return spherical.theta

func get_distance() -> float:
	return camera.translation.distance_squared_to(target)

func get_auto_rotation_angle() -> float:
	return 2 * PI / 60 /60 * auto_rotate_speed
	
func get_zoom_scale() -> float:
	return pow(0.95, zoom_speed)

func rotate_left(angle: float) -> void:
	spherical_delta.theta -= angle

func rotate_up(angle: float) -> void:
	spherical_delta.phi -= angle
	
func dolly_out(dolly_scale: float) -> void:
	if camera.projection == Camera.PROJECTION_PERSPECTIVE:
		scale /= dolly_scale
	elif camera.projection == Camera.PROJECTION_ORTHOGONAL:
		camera.size = max(min_zoom, min(max_zoom, camera.size))
		#zoom changed = true
	else:
		print("Unknown camera type detected. Zooming disabled")
		enable_zoom = false
	
func dolly_in(dolly_scale: float) -> void:
	if camera.projection == Camera.PROJECTION_PERSPECTIVE:
		scale *= dolly_scale
	elif camera.projection == Camera.PROJECTION_ORTHOGONAL:
		camera.size = max(min_zoom, min(max_zoom, camera.size / dolly_scale))
	else:
		print("Unknown camera type detected. Zooming disabled")
		enable_zoom = false
	
#func pan_left() -> void:
#	var v = Vector3(0, 0, 0)	
#	v
	
func save_state() -> void:
	target0 = target
	position0 = camera.translation
	zoom0 = camera.fov

func reset() -> void:
	target = target0
	camera.translation = position0
	camera.fov = zoom0
	
	#camera.updateProjectionMatrix()
	# dispatchevent changevent
	
	update()
	state = STATE.NONE

# Gets called 60 frames per second
func update():
	var offset: Vector3 = Vector3(0, 0, 0)
	
	# the current position of the camera 
	var position: Vector3 = camera.translation
	
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
	var _min = min_azimuth_angle
	var _max = max_azimuth_angle
	
	# some is_finite() check missing here, as godot does not seem to allow infinite numbers anyway
	if _min < - PI:
		_min += two_pi
	elif _min > PI:
		_min -= two_pi
		
	if _max < - PI:
		_max += two_pi
	elif _max > PI:
		_max -= two_pi
	
	if _min <= _max:
		spherical.theta = max(_min, min(_max, spherical.theta))
	else:
		if spherical.theta > (_min + _max / float(2)):
			spherical.theta = max(_min, spherical.theta)
		else:
			spherical.theta = min(_max, spherical.theta)
 
	# restrict phi to be between desired limits
	spherical.phi = max(min_polar_angle, min(max_polar_angle, spherical.phi))
	
	spherical.make_safe()
	
	spherical.radius *= scale

	# restrict radius to be between desired limits
	spherical.radius = max(min_distance, min(max_distance, spherical.radius))
	
	# move target to panned location
	
	if enable_damping:
		target += pan_offset * damping_factor
	else:
		target += pan_offset

	# setFromSpherical in three.js
	offset = spherical.apply_to_vector(offset)
	
	# set the cameras position to the target and apply the offset
	position = target + offset
	
	camera.translation = position

	# make the camera look at the target
	camera.look_at(target, Vector3(0, 1, 0))

	# Dampen the delta spherical by the damping factor
	if enable_damping:
		spherical_delta.theta *= (1 - damping_factor)
		spherical_delta.phi *= (1 - damping_factor)
		pan_offset *= (1 - damping_factor)
	else:
		spherical_delta.set(0, 0, 0)
		pan_offset.set(0, 0, 0)
		
	scale = 1
	

func _input(event):
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		handle_mouse_down_rotate(event)
	#if event is InputEventMouseMotion:
	#	handle_mouse_move_rotate(event)
	if event is InputEventMouseButton and (event.button_index == BUTTON_WHEEL_DOWN or event.button_index == BUTTON_WHEEL_UP):
		handle_mouse_wheel(event)
	if event is InputEventScreenTouch:
		handle_touch(event)#
	if event is InputEventScreenDrag:
		on_touch_move(event)

func handle_mouse_down_rotate(event: InputEventMouseButton) -> void:
	if event.pressed && event.button_index == 1:
		# if its a started left click, save the starting position
		rotate_start = event.position
	else: # event not pressed
		pass

func handle_mouse_move_rotate(event: InputEventMouseMotion) -> void:
	rotate_end = event.position
	
	rotate_delta = (rotate_end - rotate_start) * rotate_speed
	
	rotate_left(2 * PI * rotate_delta.x / get_viewport().size.y) # yes, height
	
	rotate_up(2 * PI * rotate_delta.y / get_viewport().size.y)
	
	rotate_start = rotate_end
	
	update()
	
	pass

func handle_mouse_wheel(event):
	if enabled == false or enable_zoom == false or state != STATE.NONE:
		return
	if event.button_index == BUTTON_WHEEL_UP:
		dolly_in(get_zoom_scale())
	elif event.button_index == BUTTON_WHEEL_DOWN:
		dolly_out(get_zoom_scale())
		pass

func handle_touch(event):
	if event.pressed:
		on_pointer_down(event)
	elif not event.pressed:
		on_pointer_up(event)

func on_pointer_down(event):
	add_pointer(event)
	on_touch_start(event)
	pass

func on_pointer_up(event):
	remove_pointer(event)
	pass

func add_pointer(event):
	pointers.push_back(event)

func remove_pointer(event):
		
	for i in pointers.size():
		if pointers[i].index == event.index:
			pointers.remove(i)
			return
	pass

func track_pointer(event):	
	if not event.index in pointerPositions:
		pointerPositions[event.index] = Vector2(0, 0)
	
	pointerPositions[event.index].x = event.position.x
	pointerPositions[event.index].y = event.position.y
	pass

func get_second_pointer_position(event) -> Vector2:
	var pointer = Vector2(0, 0)
	if event.index == pointers[0].index:
		pointer = pointers[1]
	else:
		pointer = pointers[0]
	return pointerPositions[pointer.index]
	
# decides which function is called depending on  number of pointers
func on_touch_move(event):
	track_pointer(event)
	
	match state:
		STATE.TOUCH_ROTATE:
			
			if enable_rotate == false:
				return
			
			handle_touch_move_rotate(event)
			
			update()
			
		STATE.TOUCH_PAN:
			print("touch_pan")
		STATE.TOUCH_DOLLY_PAN:
			print("touch dolly pan")
		STATE.TOUCH_DOLLY_ROTATE:
			print("touch dolly rotate")
		_:
			state = STATE.NONE
	pass

# decides which function is called depending on  number of pointers
func on_touch_start(event):
	track_pointer(event)
	
	match pointers.size():
		1:
			print("one pointer")
			match touches.ONE:
				TOUCH.ROTATE:
					if enable_rotate == false:
						return

					handle_touch_start_rotate()
					
					state = STATE.TOUCH_ROTATE
				TOUCH.PAN:
					if enable_pan == false:
						return
					
					#handle_touch_start_pan()
					state = STATE.TOUCH_PAN
				_:
					state = STATE.NONE
		2: 
			print("two pointers")
			#todo
		_:
			print("no pointers")
			state = STATE.NONE
	pass
	
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
		rotate_end.x = event.position.x
		rotate_end.y = event.position.y
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

### HELPER FUNCTIONS AND UTILITIES ###

# Check if the camera variable is actually a camera, print an error if not
func check_camera() -> bool:
	if _camera:
		camera = get_node(_camera)
		return true
		
		if not camera.is_class("Camera"):
			printerr("Selected Camera is not a camera.")
			return false
	else:
		printerr("No camera provided")
		return false

func enable_debug():
	debug_layer = CanvasLayer.new()
	debug_layer.name = "debug_layer"
	var v_box_container = VBoxContainer.new()
	v_box_container.name = "list"
	debug_layer.add_child(v_box_container)
	
	var root_viewport = get_tree().get_root()
	var label = Label.new()
	label.text = "OrbitControls Debug"
	label.set("custom_colors/font_color", Color(1.0, 0.3, 0.3))
	add_to_debug(label, "Heading")
	
	add_string_to_debug("spherical_delta")
	add_string_to_debug("camera_position")
	add_string_to_debug("azimuth")

	root_viewport.call_deferred("add_child", debug_layer)

# adds a string to the debug ui
func add_string_to_debug(name: String):
	var string = Label.new()
	string.name = name
	add_to_debug(string, name)

# general function, adds Control nodes of any type to debug ui
func add_to_debug(control: Control, name: String) -> void:
	var list = debug_layer.get_node("list")
	list.add_child(control)
	debug_nodes[name] = control

# Handlers for custom inspector properties

func _get(p):
	if p == 'enabled':
		return enabled
	if p == 'debug':
		return debug
	if p == '_camera':
		return _camera
	if p == "target/target":
		return target
	if p == "auto_rotate/enabled":
		return auto_rotate
	if p == "auto_rotate/speed":
		return auto_rotate_speed
	if p == "rotate/enabled":
		return enable_rotate
	if p == "rotate/speed":
		return rotate_speed
	if p == "dolly/minimum_distance":
		return min_distance
	if p == "dolly/maximum_distance":
		return max_distance
	if p == "zoom/enabled":
		return enable_zoom
	if p == "zoom/speed":
		return zoom_speed
	if p == "zoom/minimum_zoom":
		return min_zoom
	if p == "zoom/maximum_zoom":
		return max_zoom
	if p == "limits/min_polar_angle":
		return min_polar_angle
	if p == "limits/max_polar_angle":
		return max_polar_angle
	if p == "limits/min_azimuth_angle":
		return min_azimuth_angle
	if p == "limits/max_azimuth_angle":
		return max_azimuth_angle
	if p == "damping/enabled":
		return enable_damping
	if p == "damping/damping_factor":
		return damping_factor
	if p == "pan/enabled":
		return enable_pan
	if p == "pan/speed":
		return pan_speed
	if p == "pan/screen_space_panning":
		return screen_space_panning
	if p == "pan/key_pan_speed":
		return key_pan_speed

func _set(p, v) -> bool:
	if p == 'enabled':
		enabled = v
	if p == "_camera":
		_camera = v
	if p == "target/target":
		target = v
	if p == "auto_rotate/enabled":
		auto_rotate = v
	if p == "auto_rotate/speed":
		var clamped = clamp(v, 0.001, 10.0)
		auto_rotate_speed = clamped
	if p == "rotate/enabled":
		enable_rotate = v
	if p == "rotate/speed":
		var clamped = clamp(v, 0.001, 10.0)
		rotate_speed = clamped
	if p == "dolly/minimum_distance":
		var clamped = clamp(v, 0.001, 100.0)
		min_distance = clamped
	if p == "dolly/maximum_distance":
		var clamped = clamp(v, 0.001, 100.0)
		max_distance = clamped
	if p == "zoom/enabled":
		enable_zoom = v
	if p == "zoom/speed":
		var clamped = clamp(v, 0.001, 100.0)
		zoom_speed = clamped
	if p == "zoom/minimum_zoom":
		var clamped = clamp(v, 0.001, 100.0)
		min_zoom = clamped
	if p == "zoom/maximum_zoom":
		var clamped = clamp(v, 0.001, 100.0)
		max_zoom = clamped
	if p == "limits/min_polar_angle":
		var clamped = clamp(v, 0.000001, PI - 0.0000001)
		min_polar_angle = clamped
	if p == "limits/max_polar_angle":
		var clamped = clamp(v, 0.000001, PI - 0.0000001)
		max_polar_angle = clamped
	if p == "limits/min_azimuth_angle":
		var clamped = clamp(v, - PI * 2.0 + 0.000001, 2.0 * PI - 0.000001)
		min_azimuth_angle = clamped
	if p == "limits/max_azimuth_angle":
		var clamped = clamp(v, - PI * 2.0 + 0.000001, 2.0 * PI + 0.000001)
		max_azimuth_angle = clamped
	if p == "damping/enabled":
		enable_damping = v
	if p == "damping/damping_factor":
		var clamped = clamp(v, 0.001, 0.99)
		damping_factor = clamped
	if p == "pan/enabled":
		enable_pan = v
	if p == "pan/speed":
		var clamped = clamp(v, 0.001, 10.00)
		pan_speed = clamped
	if p == "pan/screen_space_panning":
		screen_space_panning = v
	if p == "pan/key_pan_speed":
		var clamped = clamp(v, 0.001, 100.00)
		key_pan_speed = clamped
		
	return true

func _get_property_list() -> Array:
	var props = []
	
	props.append({
		'name': 'Orbit Control Settings',
		'type': TYPE_NIL,
		'usage': PROPERTY_USAGE_CATEGORY
	})
	
	props.append({
		'name': 'enabled',
		'type': TYPE_BOOL,
	})
	
	props.append({
		'name': 'debug',
		'type': TYPE_BOOL,
	})
	
	props.append({
		'name': '_camera',
		'type': TYPE_NODE_PATH,
	})
	
	props.append({
		'name': 'target/target',
		'type': TYPE_VECTOR3,
	})
	
	props.append({
		'name': 'auto_rotate/enabled',
		'type': TYPE_BOOL,
	})
	
	props.append({
		'name': 'auto_rotate/speed',
		'type': TYPE_REAL,
	})
	
	props.append({
		'name': "rotate/enabled",
		'type': TYPE_BOOL,
	})
	
	props.append({
		'name': "rotate/speed",
		'type': TYPE_REAL,
	})
	
	props.append({
		'name': "dolly/minimum_distance",
		'type': TYPE_REAL,
	})
	
	props.append({
		'name': "dolly/maximum_distance",
		'type': TYPE_REAL,
	})
	
	props.append({
		'name': "zoom/enabled",
		'type': TYPE_BOOL,
	})
	
	props.append({
		'name': "zoom/speed",
		'type': TYPE_REAL,
	})
	
	props.append({
		'name': "zoom/minimum_zoom",
		'type': TYPE_REAL,
	})
	
	props.append({
		'name': "zoom/maximum_zoom",
		'type': TYPE_REAL,
	})
	
	props.append({
		'name': "limits/min_polar_angle",
		'type': TYPE_REAL,
	})
	
	props.append({
		'name': "limits/max_polar_angle",
		'type': TYPE_REAL,
	})
	
	props.append({
		'name': "limits/min_azimuth_angle",
		'type': TYPE_REAL,
	})
	
	props.append({
		'name': "limits/max_azimuth_angle",
		'type': TYPE_REAL,
	})
	
	props.append({
		'name': "damping/enabled",
		'type': TYPE_BOOL,
	})
	
	props.append({
		'name': 'damping/damping_factor',
		'type': TYPE_REAL,
	})
	
	props.append({
		'name': 'pan/enabled',
		'type': TYPE_BOOL,
	})
	
	props.append({
		'name': 'pan/speed',
		'type': TYPE_REAL,
	})
	
	props.append({
		'name': 'pan/screen_space_panning',
		'type': TYPE_BOOL,
	})
	
	props.append({
		'name': 'pan/key_pan_speed',
		'type': TYPE_REAL,
	})

	return props

func property_can_revert(p):
	if p == "enabled":
		return true
	if p == "debug":
		return true
	if p == "_camera":
		return true
	if p == "target/target":
		return true
	if p == "auto_rotate/enabled":
		return true
	if p == "auto_rotate/speed":
		return true
	if p == "rotate/enabled":
		return true
	if p == "rotate/speed":
		return true
	if p == "dolly/minimum_distance":
		return true
	if p == "dolly/maximum_distance":
		return true
	if p == "zoom/enabled":
		return true
	if p == "zoom/speed":
		return true
	if p == "zoom/minimum_zoom":
		return true
	if p == "zoom/maximum_zoom":
		return true
	if p == "limits/min_polar_angle":
		return true
	if p == "limits/max_polar_angle":
		return true
	if p == "limits/min_azimuth_angle":
		return true
	if p == "limits/max_azimuth_angle":
		return true
	if p == "damping/enabled":
		return true
	if p == "damping/damping_factor":
		return true
	if p == "pan/enabled":
		return true
	if p == "pan/speed":
		return true
	if p == "pan/screen_space_panning":
		return true
	if p == "pan/key_pan_speed":
		return true
	
	# for every other built-in property, return false
	return false

func property_get_revert(p):
	if p == "enabled":
		return true
	if p == "debug":
		return false
	if p == "_camera":
		return NodePath()
	if p == "target/target":
		return Vector3(0, 0, 0)
	if p == "auto_rotate/enabled":
		return false
	if p == "auto_rotate/speed":
		return 1.0
	if p == "rotate/enabled":
		return true
	if p == "rotate/speed":
		return 1.0
	if p == "dolly/minimum_distance":
		return 0.001
	if p == "dolly/maximum_distance":
		return 100.0
	if p == "zoom/enabled":
		return true
	if p == "zoom/speed":
		return 1.0
	if p == "zoom/minimum_zoom":
		return 0.001
	if p == "zoom/maximum_zoom":
		return 100.0
	if p == "limits/min_polar_angle":
		return 0.000001
	if p == "limits/max_polar_angle":
		return PI - 0.0000001
	if p == "limits/min_azimuth_angle":
		return - PI * 2.0
	if p == "limits/max_azimuth_angle":
		return PI * 2.0
	if p == "damping/enabled":
		return true
	if p == "damping/damping_factor":
		return 0.05
	if p == "pan/enabled":
		return true
	if p == "pan/speed":
		return 1.0
	if p == "pan/screen_space_panning":
		return false
	if p == "pan/key_pan_speed":
		return 7.0
