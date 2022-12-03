extends Node

# SIGNALS #
signal start
signal change
signal end

# CAMERA #

# Path to the camera to control with the orbit controls
export(NodePath) var _camera
export var debug: bool = false
var debug_layer: CanvasLayer = null
var debug_nodes = {}

var camera = null
#onready var viewport = get_tree().get_root()

# PROPERTIES
export var target: Vector3 = Vector3(0, 0, 0)
export var auto_rotate: bool = false
export var auto_rotate_speed: float = 0.5
export var enable_zoom: bool = true
export var enable_damping: bool = true
export var rotate_speed: float = 1.0
export var damping_factor: float = 0.05
export var radius: float = 1.0

# how far you can dolly in and out ( perspective camera only ) 
export var min_distance: float = 0.0
export var max_distance: float = 5.0

export(float, -6.28318 , 6.28318) var min_azimuth_angle = -6.283
export(float, -6.28318 , 6.28318) var max_azimuth_angle = 6.283
export(float, 0.0000001, 3.14159) var min_polar_angle = 0.0000001
export(float, 0.0000001, 3.14159) var max_polar_angle = PI - 0.0000001

# HELPERS
var spherical = Spherical.new()
var spherical_delta = Spherical.new()
const two_pi: float = PI * 2


# On rotate (left click)
var rotate_start = Vector2()
var rotate_end = Vector2()
var rotate_delta = Vector2()


var is_pressed: bool = false
var last_difference_in_x: float = 0.0
var start_point: Vector3 = Vector3(0, 0, 0)
var polar_angle: float = deg2rad(90.0) # also called inclination
var azimuth_angle: float = deg2rad(90.0) # left right angle

# on movement
var azimuth_start: float = 0.0
var event_start: Vector2 = Vector2(0, 0)
var prev_position: Vector2 = Vector2(0, 0)

# Other
var scale: float = 1
var pan_offset = Vector3(0, 0, 0)

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

var state = STATE.NONE

func _ready():
	check_camera()
	check_constraints()
	
	if debug:
		enable_debug()
		
	#camera.translation = get_polar_coordinates()

func _process(delta):
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

func rotate_left(angle: float) -> void:
	spherical_delta.theta -= angle

func rotate_up(angle: float) -> void:
	spherical_delta.phi -= angle

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
	
	print("%s --- %s" % [spherical.theta, spherical.phi])
	

func _input(event):
	if event is InputEventMouseButton:
		handle_mouse_down_rotate(event)
	if event is InputEventMouseMotion:
		handle_mouse_move_rotate(event)
	

func handle_mouse_down_rotate(event: InputEventMouseButton) -> void:
	if event.pressed:
		# if its a started left click, save the starting position
		if event.button_index == 1:
			print("rotate_start")
			rotate_start = event.position

func handle_mouse_move_rotate(event: InputEventMouseMotion) -> void:
	
	rotate_end = event.position
	
	rotate_delta = (rotate_end - rotate_start) * rotate_speed
	
	rotate_left(2 * PI * rotate_delta.x / get_viewport().size.y) # yes, height
	
	rotate_up(2 * PI * rotate_delta.y / get_viewport().size.y)
	
	rotate_start = rotate_end
	
	update()
	
	pass

		
# input radians only
func get_polar_coordinates():
	var x = radius * sin(polar_angle) * cos(azimuth_angle)
	var y = radius * cos(polar_angle)
	var z = radius * sin(polar_angle) * sin(azimuth_angle)
	return Vector3(x, y, z)


func check_constraints():
	# check azimuth constraints
	var azimuth_difference = max_azimuth_angle - min_azimuth_angle
	if not azimuth_difference <= 2 * PI:
		printerr("Azimuth angles are wrong: max angle - min angle must be smaller than 6.28318 (2 * PI). Angle is currently ", azimuth_difference)
		
	# check polar constraints
	
	# check other constraints
	pass

# Check if the camera variable is actually a camera, print an error if not
func check_camera():
	if _camera:
		camera = get_node(_camera)
		
		if not camera.is_class("Camera"):
			printerr("Selected Camera is not a camera.")
			return
	else:
		printerr("No camera provided")


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
