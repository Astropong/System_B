// Gel : voile bleuté et givre qui gagne la salle depuis les murs, avec quelques
// cristaux scintillants. Utilisé par Module (voir _create_climate_effects) en
// dessous de FROST_THRESHOLD. Éclairé normalement : invisible dans le brouillard.
shader_type canvas_item;

// Intensité de l'effet (0–1), réglée selon la température.
uniform float strength : hint_range(0.0, 1.0) = 0.0;
// Taille de la salle (px).
uniform vec2 room_size = vec2(768.0);
// Profondeur du givre depuis les murs à pleine intensité (px).
uniform float max_reach = 200.0;
uniform vec4 film_color : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform vec4 frost_color : source_color = vec4(0.9, 0.96, 1.0, 1.0);

varying vec2 local_pos;

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

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	// Distance au mur le plus proche.
	float wall_distance = min(min(local_pos.x, room_size.x - local_pos.x),
			min(local_pos.y, room_size.y - local_pos.y));

	// Bord du givre irrégulier.
	float n = value_noise(local_pos / 22.0) * 0.6 + value_noise(local_pos / 8.0) * 0.3
			+ value_noise(local_pos / 3.0) * 0.1;
	float reach = max_reach * mix(0.35, 1.0, strength);
	float frost = 1.0 - smoothstep(0.0, reach, wall_distance + (n - 0.5) * reach * 0.9);

	// Cristaux : petits points brillants qui scintillent dans le givre.
	vec2 cell = floor(local_pos / 4.0);
	float crystal = step(0.985, hash(cell)) * (0.6 + 0.4 * sin(TIME * 2.5 + hash(cell + 7.0) * 40.0));

	float alpha = strength * (0.12 + frost * 0.6) + crystal * frost * strength * 0.5;
	vec3 color = mix(film_color.rgb, frost_color.rgb, clamp(frost + crystal, 0.0, 1.0));
	COLOR = vec4(color, clamp(alpha, 0.0, 0.85));
}
