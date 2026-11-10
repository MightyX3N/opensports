## Bowling field as data. Real lane dimensions, which are also what the original game uses
## (1 unit = 10 cm): a 1.05 m lane with 22 cm gutters, 18.29 m from the foul line to the
## head pin, pins 30.48 cm apart.
## World axes: x right, y up, z towards the player. The foul line is z = 0, the lane runs to -z.
class_name BowlingSetup

const HALF_WIDTH := 0.527
const GUTTER_WIDTH := 0.22
const GUTTER_DEPTH := 0.045
const LENGTH := 18.29        # foul line to head pin
const DECK_END := 19.15      # end of the pin deck (pit starts here)
const PIT_DEPTH := 0.30
const PIT_BACK := 19.95      # back cushion
const KICKBACK := 0.80       # side walls around the pin deck (x)
const KICKBACK_START := 17.4
const APPROACH := 4.6        # approach length behind the foul line
const ARROW_DIST := 4.57
const ARROW_SPACING := 0.127
const DOTS_DIST := 2.13
const BOARD_WIDTH := 0.0266

const PIN_HEIGHT := 0.381
const PIN_COM := 0.145       # centre of mass height
## lathe profile {height, radius} from the base (38.1 cm tall, 12.1 cm across the belly)
const PIN_PROFILE := [[0.000, 0.000], [0.000, 0.026], [0.030, 0.040], [0.070, 0.054], [0.114, 0.0605],
	[0.160, 0.056], [0.205, 0.042], [0.245, 0.0255], [0.270, 0.0232], [0.300, 0.027],
	[0.335, 0.0322], [0.360, 0.028], [0.375, 0.017], [0.381, 0.000]]
const PIN_STRIPES := [[0.232, 0.244], [0.252, 0.264]]

## triangle of `rows` rows, the head pin first, numbered like real pins
static func triangle(rows := 4, spacing := 0.3048, head_z := -LENGTH) -> Array:
	var gap := spacing * sqrt(3.0) / 2.0
	var out := []
	for r in rows:
		for i in r + 1:
			out.append(Vector2((i - r / 2.0) * spacing, head_z - r * gap))
	return out

static func pins() -> Array:
	return triangle(4)

## collision spheres in pin space (base at y = 0): a ring of small feet so the pin stands,
## then a stack up the body like the original's pins. Each is Vector4(x, y, z, radius).
static func pin_spheres() -> Array:
	var out := []
	for i in 6:
		var a := i / 6.0 * TAU
		out.append(Vector4(cos(a) * 0.017, 0.010, sin(a) * 0.017, 0.010))
	for s in [[0.045, 0.045], [0.090, 0.058], [0.130, 0.058], [0.170, 0.051], [0.210, 0.037], [0.255, 0.024], [0.300, 0.026], [0.340, 0.030]]:
		out.append(Vector4(0, s[0], 0, s[1]))
	return out
