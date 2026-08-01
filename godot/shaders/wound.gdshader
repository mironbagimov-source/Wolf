shader_type spatial;
// Вырезает кусок тела: фрагменты внутри сферы РЕАЛЬНО исчезают (discard),
// а не закрываются накладкой. Внутренности видно насквозь, поэтому грани
// не отсекаются (cull_disabled) — сквозь дыру виден изнанок спины.
render_mode cull_disabled;

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap;
uniform bool has_tex = true;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rough : hint_range(0.0, 1.0) = 0.7;
uniform float metal : hint_range(0.0, 1.0) = 0.0;
uniform float flash = 0.0;          // красная вспышка при попадании

uniform vec3 wound_pos = vec3(0.0); // центр разреза, МИРОВЫЕ координаты
uniform float wound_r = 0.0;        // радиус; 0 — резать нечего
uniform float wound_h = 1.0;        // сплюснутость по вертикали (разрез — щель)

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (wound_r > 0.0) {
		vec3 d = world_pos - wound_pos;
		d.y /= max(wound_h, 0.05);   // вертикальный разрез, а не круглая дырка
		if (length(d) < wound_r) {
			discard;
		}
	}
	vec4 c = has_tex ? texture(tex_albedo, UV) * tint : tint;
	ALBEDO = c.rgb;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = vec3(1.0, 0.25, 0.2) * flash;
	// Мясо на срезе: изнанка темнее и краснее, чтобы дыра читалась объёмом.
	if (!FRONT_FACING) {
		ALBEDO = mix(ALBEDO * 0.25, vec3(0.22, 0.02, 0.03), 0.75);
		ROUGHNESS = 0.35;
	}
}
