extends Node
class_name Spherical
	
var _radius: float
var _phi: float
var _theta: float

func _init(radius: float = 1, phi: float = 0, theta: float = 0):
	_radius = radius
	_phi = phi
	_theta = theta

func set_to(radius: float, phi: float, theta: float):
	_radius = radius
	_phi = phi
	_theta = theta

func copy(other_spherical: Spherical):
	_radius = other_spherical._radius
	_phi = other_spherical._phi
	_theta = other_spherical._theta

func makeSafe():
	var precision: float = 0.0000000000001
	_phi = max(precision, min(PI - precision, _phi))

func set_from_vector(v: Vector3):
	self.set_from_cartesian_coords(v.x, v.y, v.z)
	
func set_from_cartesian_coords(x: float, y: float, z: float):
	_radius = sqrt(x * x + y * y + z * z)
	if _radius == 0:
		_theta = 0
		_phi = 0
	else:
		_theta = atan2(x, z)
		_phi = acos(clamp(y / _radius, -1, 1))
