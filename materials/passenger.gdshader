shader_type spatial;
// Passenger figures drawn by one MultiMesh (checklist step 27, see
// passenger_crowd.gd). UV.x holds the part of the figure (see
// passenger_mesh.gd). Each instance's look comes from INSTANCE_CUSTOM:
// rgb is the shirt colour and a packs palette indices:
//   bits 0-1 skin tone, bits 2-3 trousers, bits 4-5 hair, bit 6 walking.
// Walking figures swing their legs and arms in the vertex shader.

uniform float walk_time = 0.0;
// Full leg cycles (two steps) per second at 1x.
uniform float stride_rate = 0.9;
// Leg swing either side of straight down, in radians.
uniform float swing_angle = 0.45;

const int PART_SKIN = 0;
const int PART_HAIR = 1;
const int PART_SHIRT = 2;
const int PART_ARM = 3;
const int PART_LEG = 4;
const int PART_SHOE = 5;
// Pivot heights, in metres; they must match passenger_mesh.gd.
const float HIP_Y = 0.88;
const float SHOULDER_Y = 1.42;

const vec3 SKIN[4] = vec3[4](vec3(0.96, 0.80, 0.68), vec3(0.85, 0.65, 0.50), vec3(0.62, 0.44, 0.32), vec3(0.40, 0.27, 0.20));
const vec3 HAIR[4] = vec3[4](vec3(0.15, 0.11, 0.08), vec3(0.42, 0.27, 0.14), vec3(0.85, 0.70, 0.40), vec3(0.62, 0.62, 0.62));
const vec3 TROUSERS[4] = vec3[4](vec3(0.16, 0.20, 0.32), vec3(0.18, 0.18, 0.20), vec3(0.55, 0.50, 0.40), vec3(0.30, 0.38, 0.52));
const vec3 SHOE = vec3(0.12, 0.11, 0.11);

varying vec3 part_colour;

vec2 rotate_x(vec2 yz, float pivot_y, float angle) {
	float y = yz.x - pivot_y;
	float c = cos(angle);
	float s = sin(angle);
	return vec2(y * c - yz.y * s + pivot_y, y * s + yz.y * c);
}

void vertex() {
	int part = int(round(UV.x));
	int look = int(round(INSTANCE_CUSTOM.a));
	bool walking = (look & 64) != 0;
	float side = VERTEX.x < 0.0 ? -1.0 : 1.0;
	// Each figure starts its stride at a different point so crowds don't march in step.
	float phase = fract(float(INSTANCE_ID) * 0.618034) * 6.2832;
	float swing = walking ? sin(walk_time * stride_rate * 6.2832 + phase) * swing_angle : 0.0;

	if (part == PART_LEG || part == PART_SHOE) {
		float a = swing * side;
		VERTEX.yz = rotate_x(VERTEX.yz, HIP_Y, a);
		NORMAL.yz = rotate_x(NORMAL.yz, 0.0, a);
	} else if (part == PART_ARM) {
		float a = -swing * side * 0.8;
		VERTEX.yz = rotate_x(VERTEX.yz, SHOULDER_Y, a);
		NORMAL.yz = rotate_x(NORMAL.yz, 0.0, a);
	}
	if (walking) {
		// A small bob, highest when the legs pass each other.
		VERTEX.y += abs(cos(walk_time * stride_rate * 6.2832 + phase)) * 0.03;
	}

	if (part == PART_SKIN) {
		part_colour = SKIN[look & 3];
	} else if (part == PART_HAIR) {
		part_colour = HAIR[(look >> 4) & 3];
	} else if (part == PART_SHIRT || part == PART_ARM) {
		part_colour = INSTANCE_CUSTOM.rgb;
	} else if (part == PART_LEG) {
		part_colour = TROUSERS[(look >> 2) & 3];
	} else {
		part_colour = SHOE;
	}
}

void fragment() {
	ALBEDO = part_colour;
	ROUGHNESS = 0.85;
}
