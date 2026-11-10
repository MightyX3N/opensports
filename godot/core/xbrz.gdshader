shader_type canvas_item;
render_mode blend_disabled;
// xBRZ (Zenju, GPL-3.0) with Hyllian's xBR texel mapping (MIT), from libretro's
// xbrz-freescale.glsl, changed to carry transparency. See THIRD_PARTY.md.
uniform sampler2D Source : filter_nearest, repeat_enable;
uniform vec2 SourceSize;
uniform vec2 OutputSize;
vec4 P(vec2 coord, vec2 inv, float x, float y) { return texture(Source, coord + inv * vec2(x, y)); }

// colour distance in YCbCr (BT.2020 weights); transparency counts as a difference too
float Dist(vec4 a, vec4 b)
{
  const vec3 w = vec3(0.2627, 0.6780, 0.0593);
  const float scaleB = 0.5 / (1.0 - 0.0593);
  const float scaleR = 0.5 / (1.0 - 0.2627);
  vec3 diff = a.rgb * a.a - b.rgb * b.a;
  float Y = dot(diff, w);
  float Cb = scaleB * (diff.b - Y);
  float Cr = scaleR * (diff.r - Y);
  float A = a.a - b.a;
  return sqrt(Y * Y + Cb * Cb + Cr * Cr + A * A);
}
bool IsPixEqual(vec4 a, vec4 b) { return Dist(a, b) < (30.0/255.0); }

float get_left_ratio(vec2 center, vec2 origin, vec2 direction, vec2 scale)
{
  vec2 P0 = center - origin;
  vec2 proj = direction * (dot(P0, direction) / dot(direction, direction));
  vec2 distv = P0 - proj;
  vec2 orth = vec2(-direction.y, direction.x);
  float side = sign(dot(P0, orth));
  float v = side * length(distv * scale);
  return smoothstep(-sqrt(2.0) / 2.0, sqrt(2.0) / 2.0, v);
}


vec4 xbrz(vec2 vTexCoord)
{
  vec2 inv = 1.0 / SourceSize;
  vec2 scale = OutputSize * inv;
  vec2 pos = fract(vTexCoord * SourceSize) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * inv;

  vec4 A = P(coord, inv, -1., -1.);
  vec4 B = P(coord, inv,  0., -1.);
  vec4 C = P(coord, inv,  1., -1.);
  vec4 D = P(coord, inv, -1.,  0.);
  vec4 E = P(coord, inv,  0.,  0.);
  vec4 F = P(coord, inv,  1.,  0.);
  vec4 G = P(coord, inv, -1.,  1.);
  vec4 H = P(coord, inv,  0.,  1.);
  vec4 I = P(coord, inv,  1.,  1.);

  ivec4 blendResult = ivec4(0, 0, 0, 0);

  if (!(((E == F) && (H == I)) || ((E == H) && (F == I))))
  {
    float dist_H_F = Dist(G, E) + Dist(E, C) + Dist(P(coord, inv, 0., 2.), I) + Dist(I, P(coord, inv, 2., 0.)) + (4.0 * Dist(H, F));
    float dist_E_I = Dist(D, H) + Dist(H, P(coord, inv, 1., 2.)) + Dist(B, F) + Dist(F, P(coord, inv, 2., 1.)) + (4.0 * Dist(E, I));
    bool dominantGradient = (3.6 * dist_H_F) < dist_E_I;
    blendResult.z = ((dist_H_F < dist_E_I) && (E != F) && (E != H)) ? ((dominantGradient) ? 2 : 1) : 0;
  }
  if (!(((D == E) && (G == H)) || ((D == G) && (E == H))))
  {
    float dist_G_E = Dist(P(coord, inv, -2., 1.), D) + Dist(D, B) + Dist(P(coord, inv, -1., 2.), H) + Dist(H, F) + (4.0 * Dist(G, E));
    float dist_D_H = Dist(P(coord, inv, -2., 0.), G) + Dist(G, P(coord, inv, 0., 2.)) + Dist(A, E) + Dist(E, I) + (4.0 * Dist(D, H));
    bool dominantGradient = (3.6 * dist_D_H) < dist_G_E;
    blendResult.w = ((dist_G_E > dist_D_H) && (E != D) && (E != H)) ? ((dominantGradient) ? 2 : 1) : 0;
  }
  if (!(((B == C) && (E == F)) || ((B == E) && (C == F))))
  {
    float dist_E_C = Dist(D, B) + Dist(B, P(coord, inv, 1., -2.)) + Dist(H, F) + Dist(F, P(coord, inv, 2., -1.)) + (4.0 * Dist(E, C));
    float dist_B_F = Dist(A, E) + Dist(E, I) + Dist(P(coord, inv, 0., -2.), C) + Dist(C, P(coord, inv, 2., 0.)) + (4.0 * Dist(B, F));
    bool dominantGradient = (3.6 * dist_B_F) < dist_E_C;
    blendResult.y = ((dist_E_C > dist_B_F) && (E != B) && (E != F)) ? ((dominantGradient) ? 2 : 1) : 0;
  }
  if (!(((A == B) && (D == E)) || ((A == D) && (B == E))))
  {
    float dist_D_B = Dist(P(coord, inv, -2., 0.), A) + Dist(A, P(coord, inv, 0., -2.)) + Dist(G, E) + Dist(E, C) + (4.0 * Dist(D, B));
    float dist_A_E = Dist(P(coord, inv, -2., -1.), D) + Dist(D, H) + Dist(P(coord, inv, -1., -2.), B) + Dist(B, F) + (4.0 * Dist(A, E));
    bool dominantGradient = (3.6 * dist_D_B) < dist_A_E;
    blendResult.x = ((dist_D_B < dist_A_E) && (E != D) && (E != B)) ? ((dominantGradient) ? 2 : 1) : 0;
  }

  vec4 res = E;

  if (blendResult.z != 0)
  {
    float dist_F_G = Dist(F, G);
    float dist_H_C = Dist(H, C);
    bool doLineBlend = (blendResult.z == 2 ||
      !((blendResult.y != 0 && !IsPixEqual(E, G)) || (blendResult.w != 0 && !IsPixEqual(E, C)) ||
        (IsPixEqual(G, H) && IsPixEqual(H, I) && IsPixEqual(I, F) && IsPixEqual(F, C) && !IsPixEqual(E, I))));
    vec2 origin = vec2(0.0, 1.0 / sqrt(2.0));
    vec2 direction = vec2(1.0, -1.0);
    if (doLineBlend)
    {
      bool haveShallowLine = (2.2 * dist_F_G <= dist_H_C) && (E != G) && (D != G);
      bool haveSteepLine = (2.2 * dist_H_C <= dist_F_G) && (E != C) && (B != C);
      origin = haveShallowLine ? vec2(0.0, 0.25) : vec2(0.0, 0.5);
      direction.x += haveShallowLine ? 1.0 : 0.0;
      direction.y -= haveSteepLine ? 1.0 : 0.0;
    }
    vec4 blendPix = mix(H, F, step(Dist(E, F), Dist(E, H)));
    res = mix(res, blendPix, get_left_ratio(pos, origin, direction, scale));
  }
  if (blendResult.w != 0)
  {
    float dist_H_A = Dist(H, A);
    float dist_D_I = Dist(D, I);
    bool doLineBlend = (blendResult.w == 2 ||
      !((blendResult.z != 0 && !IsPixEqual(E, A)) || (blendResult.x != 0 && !IsPixEqual(E, I)) ||
        (IsPixEqual(A, D) && IsPixEqual(D, G) && IsPixEqual(G, H) && IsPixEqual(H, I) && !IsPixEqual(E, G))));
    vec2 origin = vec2(-1.0 / sqrt(2.0), 0.0);
    vec2 direction = vec2(1.0, 1.0);
    if (doLineBlend)
    {
      bool haveShallowLine = (2.2 * dist_H_A <= dist_D_I) && (E != A) && (B != A);
      bool haveSteepLine = (2.2 * dist_D_I <= dist_H_A) && (E != I) && (F != I);
      origin = haveShallowLine ? vec2(-0.25, 0.0) : vec2(-0.5, 0.0);
      direction.y += haveShallowLine ? 1.0 : 0.0;
      direction.x += haveSteepLine ? 1.0 : 0.0;
    }
    vec4 blendPix = mix(H, D, step(Dist(E, D), Dist(E, H)));
    res = mix(res, blendPix, get_left_ratio(pos, origin, direction, scale));
  }
  if (blendResult.y != 0)
  {
    float dist_B_I = Dist(B, I);
    float dist_F_A = Dist(F, A);
    bool doLineBlend = (blendResult.y == 2 ||
      !((blendResult.x != 0 && !IsPixEqual(E, I)) || (blendResult.z != 0 && !IsPixEqual(E, A)) ||
        (IsPixEqual(I, F) && IsPixEqual(F, C) && IsPixEqual(C, B) && IsPixEqual(B, A) && !IsPixEqual(E, C))));
    vec2 origin = vec2(1.0 / sqrt(2.0), 0.0);
    vec2 direction = vec2(-1.0, -1.0);
    if (doLineBlend)
    {
      bool haveShallowLine = (2.2 * dist_B_I <= dist_F_A) && (E != I) && (H != I);
      bool haveSteepLine = (2.2 * dist_F_A <= dist_B_I) && (E != A) && (D != A);
      origin = haveShallowLine ? vec2(0.25, 0.0) : vec2(0.5, 0.0);
      direction.y -= haveShallowLine ? 1.0 : 0.0;
      direction.x -= haveSteepLine ? 1.0 : 0.0;
    }
    vec4 blendPix = mix(F, B, step(Dist(E, B), Dist(E, F)));
    res = mix(res, blendPix, get_left_ratio(pos, origin, direction, scale));
  }
  if (blendResult.x != 0)
  {
    float dist_D_C = Dist(D, C);
    float dist_B_G = Dist(B, G);
    bool doLineBlend = (blendResult.x == 2 ||
      !((blendResult.w != 0 && !IsPixEqual(E, C)) || (blendResult.y != 0 && !IsPixEqual(E, G)) ||
        (IsPixEqual(C, B) && IsPixEqual(B, A) && IsPixEqual(A, D) && IsPixEqual(D, G) && !IsPixEqual(E, A))));
    vec2 origin = vec2(0.0, -1.0 / sqrt(2.0));
    vec2 direction = vec2(-1.0, 1.0);
    if (doLineBlend)
    {
      bool haveShallowLine = (2.2 * dist_D_C <= dist_B_G) && (E != C) && (F != C);
      bool haveSteepLine = (2.2 * dist_B_G <= dist_D_C) && (E != G) && (H != G);
      origin = haveShallowLine ? vec2(0.0, -0.25) : vec2(0.0, -0.5);
      direction.x -= haveShallowLine ? 1.0 : 0.0;
      direction.y += haveSteepLine ? 1.0 : 0.0;
    }
    vec4 blendPix = mix(D, B, step(Dist(E, B), Dist(E, D)));
    res = mix(res, blendPix, get_left_ratio(pos, origin, direction, scale));
  }
  return res;
}

void fragment() {
  COLOR = xbrz(UV);
}
