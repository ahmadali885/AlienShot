// Port of alienwavegroup.com's hero background (js/hero-gl.js): a slowly
// flowing, domain-warped fBm gradient in the brand's ink/teal palette that
// leans toward the cursor.
#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform vec2 uMouse; // logical px, y measured from the bottom like WebGL
uniform float uLight; // 0 = the site's ink hero, 1 = its paper sections

out vec4 fragColor;

vec2 hash(vec2 p) {
  p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
  return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(dot(hash(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
        dot(hash(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
    mix(dot(hash(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
        dot(hash(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x),
    u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise(p);
    p *= 2.0;
    a *= 0.5;
  }
  return v;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  // WebGL's origin is bottom-left; flip so the composition matches the site.
  vec2 uv = vec2(frag.x, uSize.y - frag.y) / uSize;
  vec2 p = uv;
  p.x *= uSize.x / uSize.y;

  float t = uTime * 0.045;
  vec2 m = uMouse / uSize - 0.5;

  vec2 q = vec2(fbm(p + t), fbm(p + vec2(5.2, 1.3) - t));
  vec2 r = vec2(fbm(p + 2.0 * q + vec2(1.7, 9.2) + m * 0.7),
                fbm(p + 2.0 * q + vec2(8.3, 2.8) - t));
  float f = fbm(p + 2.0 * r);

  // The site's palette: --ink, --deep, --teal, --accent.
  vec3 ink = vec3(0.016, 0.078, 0.094);
  vec3 deep = vec3(0.0, 0.282, 0.345);
  vec3 teal = vec3(0.0, 0.372, 0.454);
  vec3 acc = vec3(0.122, 0.592, 0.690);

  vec3 dark = mix(ink, deep, smoothstep(-0.25, 0.6, f));
  dark = mix(dark, teal, smoothstep(0.15, 0.95, r.x));
  dark = mix(dark, acc, pow(smoothstep(0.5, 1.0, f + r.y * 0.35), 1.7) * 0.8);

  float vig = smoothstep(1.45, 0.1, length(uv - vec2(0.62, 0.45)));

  // Light theme: the same marbling, tone-inverted. Recolouring the ramp alone
  // squeezed every band into near-whites and the pattern washed out; mapping
  // the dark render's luminance instead keeps each vein exactly where it is —
  // the bright teal veins become the strongest light blue, the ink becomes
  // white.
  // The dark render mostly spans luminance 0.06–0.22: plenty of contrast
  // against near-black, far too little against white unless stretched.
  float l = dot(dark, vec3(0.2126, 0.7152, 0.0722));
  vec3 sky = vec3(0.940, 0.970, 1.000);
  vec3 vein = vec3(0.300, 0.620, 0.910);
  vec3 light = mix(sky, vein, smoothstep(0.06, 0.22, l));
  light *= 0.96 + 0.05 * vig;

  vec3 col = mix(dark * (0.72 + 0.5 * vig), light, uLight);
  fragColor = vec4(col, 1.0);
}
