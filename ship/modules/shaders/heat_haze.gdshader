// Déformation par la chaleur : ondulation de l'image déjà dessinée de la salle.
// Utilisé par Module (voir _create_climate_effects) au-dessus de HEAT_THRESHOLD.
// « unshaded » : l'image lue est déjà éclairée et assombrie par le brouillard,
// il ne faut pas l'assombrir une seconde fois.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
// Intensité de l'effet (0–1), réglée selon la température.
uniform float strength : hint_range(0.0, 1.0) = 0.0;
// Taille de la salle (px).
uniform vec2 room_size = vec2(768.0);
// Décalage maximal de l'image (px à l'écran).
uniform float max_offset = 5.0;
// Vitesse des ondulations.
uniform float speed = 1.0;
// Teinte chaude ajoutée à pleine intensité.
uniform vec3 warm_tint : source_color = vec3(1.08, 0.96, 0.86);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	// Positions en cases (1 case = 48 px), pour des ondes indépendantes de la taille.
	vec2 p = local_pos / 48.0;
	float t = TIME * speed;
	// Ondes surtout verticales, comme l'air chaud qui monte.
	vec2 wave = vec2(
		sin(p.y * 2.3 + t * 2.1) * 0.6 + sin((p.x + p.y) * 4.1 - t * 3.3) * 0.4,
		sin(p.x * 1.7 + p.y * 3.1 + t * 3.7) * 0.7 + sin(p.y * 6.3 - t * 2.9) * 0.3);

	// Atténuation près des murs, pour ne pas faire entrer l'extérieur dans la salle.
	vec2 uv = local_pos / room_size;
	float edge = smoothstep(0.0, 0.06, uv.x) * smoothstep(0.0, 0.06, 1.0 - uv.x)
			* smoothstep(0.0, 0.06, uv.y) * smoothstep(0.0, 0.06, 1.0 - uv.y);

	vec2 offset = wave * max_offset * strength * edge * SCREEN_PIXEL_SIZE;
	vec3 color = texture(screen_texture, SCREEN_UV + offset).rgb;
	color *= mix(vec3(1.0), warm_tint, strength * 0.6);
	COLOR = vec4(color, 1.0);
}
