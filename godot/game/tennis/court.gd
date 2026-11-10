## Tennis court measurements (ITF rules), in metres. The net is at z = 0; team 1 plays on
## the near half (z > 0, facing -z), team 2 on the far half. x is across (+x is right when
## facing -z), y is up.
class_name TennisCourt

const HALF_LEN := 11.885        # baseline to net
const HALF_W := 5.485           # doubles sideline (Wii tennis is always doubles)
const SINGLES_HALF_W := 4.115
const SERVICE := 6.40           # service line, from the net
const NET_CENTRE := 0.914
const NET_POST := 1.07
const POST_X := HALF_W + 0.914  # posts stand 0.914 m outside the doubles sideline
const LINE_W := 0.05
const RUNOFF_SIDE := 3.66
const RUNOFF_BACK := 6.40

## net height at x (the cord sags between the posts)
static func net_height(x: float) -> float:
	var k := minf(1.0, absf(x) / POST_X)
	return NET_CENTRE + (NET_POST - NET_CENTRE) * k * k

## is (x, z) inside the doubles court on side (1 = near, -1 = far)? Lines are in.
static func in_court(x: float, z: float, side: int, r := 0.033) -> bool:
	if absf(x) > HALF_W + r:
		return false
	if side == 1:
		return z >= -r and z <= HALF_LEN + r
	return z <= r and z >= -HALF_LEN - r

## the service box a serve must land in: side = receiving half, deuce = the receiver's right.
## Returns [xmin, xmax, zmin, zmax].
static func service_box(side: int, deuce: bool) -> Array:
	var right := 1 if side == 1 else -1
	var sgn := right if deuce else -right
	var x0 := 0.0
	var x1 := SINGLES_HALF_W * sgn
	if x0 > x1:
		var t := x0; x0 = x1; x1 = t
	var z0 := 0.0
	var z1 := SERVICE * side
	if z0 > z1:
		var t := z0; z0 = z1; z1 = t
	return [x0, x1, z0, z1]

static func in_box(x: float, z: float, box: Array, r := 0.033) -> bool:
	return x >= box[0] - r and x <= box[1] + r and z >= box[2] - r and z <= box[3] + r
