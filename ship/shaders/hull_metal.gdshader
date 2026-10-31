// Coque du vaisseau en vue « coque » (mode pilotage) : métal gris brossé,
// découpé en plaques rivetées de teintes légèrement différentes.
// Calculé dans le repère du vaisseau (la texture tourne avec lui).
// Non éclairé : le brouillard de guerre ne l'assombrit pas.
// Les détails trop fins pour l'écran (vue dézoomée) s'estompent au lieu de
// scintiller ; les joints gardent au moins JOINT_MIN_SCREEN_WIDTH pixel.
shader_type canvas_item;
render_mode unshaded;

uniform vec3 base_color : source_color = vec3(0.50, 0.53, 0.57);
// Côté d'une plaque (px, 4 cases) et largeur de ses joints (px).
uniform float panel_size = 192.0;
uniform float joint_width = 6.0;
// Écart de teinte entre plaques, intensité du brossage et des reflets.
uniform float panel_variation = 0.10;
uniform float brush_strength = 0.22;
uniform float sheen_strength = 0.12;

const float JOINT_MIN_SCREEN_WIDTH = 1.0;
const float JOINT_DARKNESS = 0.4;

varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Brossage horizontal : bandes étirées, estompées quand leur hauteur
// [scale.y] px passe sous 2 pixels d'écran ([pixel] px du vaisseau par pixel).
float brush(vec2 p, vec2 scale, float pixel) {
	float fade = 1.0 - smoothstep(scale.y * 0.25, scale.y * 0.5, pixel);
	return (value_noise(p / scale) - 0.5) * fade;
}

void fragment() {
	vec2 p = local_position;
	float pixel = length(fwidth(p)) * 0.7071;

	vec2 panel = floor(p / panel_size);
	float tint = (hash(panel) - 0.5) * panel_variation;
	// Plaques brossées dans des sens alternés, comme posées une à une.
	vec2 q = mod(panel.x + panel.y, 2.0) < 1.0 ? p : p.yx;
	// Grosses bandes visibles en vue dézoomée, fines bandes de près.
	float brushed = brush(q, vec2(900.0, 120.0), pixel) * 0.6
			+ brush(q + 37.0, vec2(200.0, 16.0), pixel) * 0.4;
	// Reflet large et doux en diagonale.
	float sheen = sin(dot(p, vec2(0.0011, 0.0007)) + 1.3);

	vec3 color = base_color * (1.0 + tint + brushed * brush_strength * 2.0 + sheen * sheen_strength);

	// Joints entre les plaques.
	vec2 in_panel = abs(fract(p / panel_size) - 0.5) * panel_size;
	float to_joint = panel_size * 0.5 - max(in_panel.x, in_panel.y);
	float width = max(joint_width, pixel * JOINT_MIN_SCREEN_WIDTH);
	color *= 1.0 - JOINT_DARKNESS * (1.0 - smoothstep(0.0, width, to_joint));

	// Rivets aux coins des plaques, s'ils restent visibles à l'écran.
	vec2 to_corner = (0.5 - abs(fract(p / panel_size) - 0.5)) * panel_size;
	float rivet = 1.0 - smoothstep(10.0, 14.0, length(to_corner - vec2(18.0)));
	color *= 1.0 - 0.3 * rivet * (1.0 - smoothstep(4.0, 8.0, pixel));

	COLOR = vec4(color, 1.0) * COLOR;
}
