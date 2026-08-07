shader_type spatial;
// Вырезает кусок тела: фрагменты внутри разреза РЕАЛЬНО исчезают (discard),
// а не закрываются накладкой. Сквозь дыру видна блендеровская чаша полости,
// поэтому грани не отсекаем — иначе на просвет пропадает изнанка.
render_mode cull_disabled;

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap;
uniform bool has_tex = true;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rough : hint_range(0.0, 1.0) = 0.7;
uniform float metal : hint_range(0.0, 1.0) = 0.0;
uniform float flash = 0.0;          // красная вспышка при попадании

// Разрез задан В СИСТЕМЕ КООРДИНАТ РАНЫ (кость груди), а не в мировой.
// Мировая сфера резала кожу тем меньше, чем дальше кожа от кости, и дырка
// выходила меньше вставленной в неё начинки. Цилиндр вдоль оси груди даёт
// отверстие ровно заданного радиуса, где бы кожа ни проходила.
uniform mat4 wound_inv;
uniform float wound_r = 0.0;        // радиус разреза; 0 — резать нечего
uniform float wound_near = 0.0;     // от какой глубины режем…
uniform float wound_far = 0.28;     // …и до какой (спина остаётся целой)
uniform float burn_r = 0.0;         // ширина обугленного пояска снаружи

varying vec3 world_pos;


float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


float n21(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x),
			mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	float burn = 0.0;
	if (wound_r > 0.0) {
		vec3 lp = (wound_inv * vec4(world_pos, 1.0)).xyz;
		if (lp.z > wound_near && lp.z < wound_far) {
			float r = length(lp.xy);
			float ang = atan(lp.y, lp.x);
			// Край рваный: радиус гуляет по углу двумя частотами — крупные
			// лоскуты и мелкая бахрома. Ровная окружность читалась бы как
			// дырка в текстуре, а не как разрез.
			float tear = (n21(vec2(ang * 2.4, 0.0)) - 0.5) * 0.20
					+ (n21(vec2(ang * 7.3, 3.1)) - 0.5) * 0.08;
			float rr = wound_r * (1.0 + tear);
			if (r < rr) {
				discard;
			}
			if (burn_r > 0.0) {
				burn = 1.0 - smoothstep(rr, rr + burn_r, r);
			}
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
	// Обугленный поясок: кожа вокруг разреза спеклась и ещё тлеет.
	if (burn > 0.0) {
		ALBEDO = mix(ALBEDO, vec3(0.055, 0.035, 0.03), burn * 0.92);
		ROUGHNESS = mix(ROUGHNESS, 0.85, burn);
		EMISSION += vec3(1.0, 0.32, 0.06) * burn * burn * 0.3;
	}
}
