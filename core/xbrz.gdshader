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

  vec4 pA = P(coord, inv, -1., -1.);
  vec4 pB = P(coord, inv,  0., -1.);
  vec4 pC = P(coord, inv,  1., -1.);
  vec4 pD = P(coord, inv, -1.,  0.);
  vec4 pE = P(coord, inv,  0.,  0.);
  vec4 pF = P(coord, inv,  1.,  0.);
  vec4 pG = P(coord, inv, -1.,  1.);
  vec4 pH = P(coord, inv,  0.,  1.);
  vec4 pI = P(coord, inv,  1.,  1.);

  ivec4 blendResult = ivec4(0, 0, 0, 0);

  if (!(((pE == pF) && (pH == pI)) || ((pE == pH) && (pF == pI))))
  {
    float dist_H_F = Dist(pG, pE) + Dist(pE, pC) + Dist(P(coord, inv, 0., 2.), pI) + Dist(pI, P(coord, inv, 2., 0.)) + (4.0 * Dist(pH, pF));
    float dist_E_I = Dist(pD, pH) + Dist(pH, P(coord, inv, 1., 2.)) + Dist(pB, pF) + Dist(pF, P(coord, inv, 2., 1.)) + (4.0 * Dist(pE, pI));
    bool dominantGradient = (3.6 * dist_H_F) < dist_E_I;
    blendResult.z = ((dist_H_F < dist_E_I) && (pE != pF) && (pE != pH)) ? ((dominantGradient) ? 2 : 1) : 0;
  }
  if (!(((pD == pE) && (pG == pH)) || ((pD == pG) && (pE == pH))))
  {
    float dist_G_E = Dist(P(coord, inv, -2., 1.), pD) + Dist(pD, pB) + Dist(P(coord, inv, -1., 2.), pH) + Dist(pH, pF) + (4.0 * Dist(pG, pE));
    float dist_D_H = Dist(P(coord, inv, -2., 0.), pG) + Dist(pG, P(coord, inv, 0., 2.)) + Dist(pA, pE) + Dist(pE, pI) + (4.0 * Dist(pD, pH));
    bool dominantGradient = (3.6 * dist_D_H) < dist_G_E;
    blendResult.w = ((dist_G_E > dist_D_H) && (pE != pD) && (pE != pH)) ? ((dominantGradient) ? 2 : 1) : 0;
  }
  if (!(((pB == pC) && (pE == pF)) || ((pB == pE) && (pC == pF))))
  {
    float dist_E_C = Dist(pD, pB) + Dist(pB, P(coord, inv, 1., -2.)) + Dist(pH, pF) + Dist(pF, P(coord, inv, 2., -1.)) + (4.0 * Dist(pE, pC));
    float dist_B_F = Dist(pA, pE) + Dist(pE, pI) + Dist(P(coord, inv, 0., -2.), pC) + Dist(pC, P(coord, inv, 2., 0.)) + (4.0 * Dist(pB, pF));
    bool dominantGradient = (3.6 * dist_B_F) < dist_E_C;
    blendResult.y = ((dist_E_C > dist_B_F) && (pE != pB) && (pE != pF)) ? ((dominantGradient) ? 2 : 1) : 0;
  }
  if (!(((pA == pB) && (pD == pE)) || ((pA == pD) && (pB == pE))))
  {
    float dist_D_B = Dist(P(coord, inv, -2., 0.), pA) + Dist(pA, P(coord, inv, 0., -2.)) + Dist(pG, pE) + Dist(pE, pC) + (4.0 * Dist(pD, pB));
    float dist_A_E = Dist(P(coord, inv, -2., -1.), pD) + Dist(pD, pH) + Dist(P(coord, inv, -1., -2.), pB) + Dist(pB, pF) + (4.0 * Dist(pA, pE));
    bool dominantGradient = (3.6 * dist_D_B) < dist_A_E;
    blendResult.x = ((dist_D_B < dist_A_E) && (pE != pD) && (pE != pB)) ? ((dominantGradient) ? 2 : 1) : 0;
  }

  vec4 res = pE;

  if (blendResult.z != 0)
  {
    float dist_F_G = Dist(pF, pG);
    float dist_H_C = Dist(pH, pC);
    bool doLineBlend = (blendResult.z == 2 ||
      !((blendResult.y != 0 && !IsPixEqual(pE, pG)) || (blendResult.w != 0 && !IsPixEqual(pE, pC)) ||
        (IsPixEqual(pG, pH) && IsPixEqual(pH, pI) && IsPixEqual(pI, pF) && IsPixEqual(pF, pC) && !IsPixEqual(pE, pI))));
    vec2 origin = vec2(0.0, 1.0 / sqrt(2.0));
    vec2 direction = vec2(1.0, -1.0);
    if (doLineBlend)
    {
      bool haveShallowLine = (2.2 * dist_F_G <= dist_H_C) && (pE != pG) && (pD != pG);
      bool haveSteepLine = (2.2 * dist_H_C <= dist_F_G) && (pE != pC) && (pB != pC);
      origin = haveShallowLine ? vec2(0.0, 0.25) : vec2(0.0, 0.5);
      direction.x += haveShallowLine ? 1.0 : 0.0;
      direction.y -= haveSteepLine ? 1.0 : 0.0;
    }
    vec4 blendPix = mix(pH, pF, step(Dist(pE, pF), Dist(pE, pH)));
    res = mix(res, blendPix, get_left_ratio(pos, origin, direction, scale));
  }
  if (blendResult.w != 0)
  {
    float dist_H_A = Dist(pH, pA);
    float dist_D_I = Dist(pD, pI);
    bool doLineBlend = (blendResult.w == 2 ||
      !((blendResult.z != 0 && !IsPixEqual(pE, pA)) || (blendResult.x != 0 && !IsPixEqual(pE, pI)) ||
        (IsPixEqual(pA, pD) && IsPixEqual(pD, pG) && IsPixEqual(pG, pH) && IsPixEqual(pH, pI) && !IsPixEqual(pE, pG))));
    vec2 origin = vec2(-1.0 / sqrt(2.0), 0.0);
    vec2 direction = vec2(1.0, 1.0);
    if (doLineBlend)
    {
      bool haveShallowLine = (2.2 * dist_H_A <= dist_D_I) && (pE != pA) && (pB != pA);
      bool haveSteepLine = (2.2 * dist_D_I <= dist_H_A) && (pE != pI) && (pF != pI);
      origin = haveShallowLine ? vec2(-0.25, 0.0) : vec2(-0.5, 0.0);
      direction.y += haveShallowLine ? 1.0 : 0.0;
      direction.x += haveSteepLine ? 1.0 : 0.0;
    }
    vec4 blendPix = mix(pH, pD, step(Dist(pE, pD), Dist(pE, pH)));
    res = mix(res, blendPix, get_left_ratio(pos, origin, direction, scale));
  }
  if (blendResult.y != 0)
  {
    float dist_B_I = Dist(pB, pI);
    float dist_F_A = Dist(pF, pA);
    bool doLineBlend = (blendResult.y == 2 ||
      !((blendResult.x != 0 && !IsPixEqual(pE, pI)) || (blendResult.z != 0 && !IsPixEqual(pE, pA)) ||
        (IsPixEqual(pI, pF) && IsPixEqual(pF, pC) && IsPixEqual(pC, pB) && IsPixEqual(pB, pA) && !IsPixEqual(pE, pC))));
    vec2 origin = vec2(1.0 / sqrt(2.0), 0.0);
    vec2 direction = vec2(-1.0, -1.0);
    if (doLineBlend)
    {
      bool haveShallowLine = (2.2 * dist_B_I <= dist_F_A) && (pE != pI) && (pH != pI);
      bool haveSteepLine = (2.2 * dist_F_A <= dist_B_I) && (pE != pA) && (pD != pA);
      origin = haveShallowLine ? vec2(0.25, 0.0) : vec2(0.5, 0.0);
      direction.y -= haveShallowLine ? 1.0 : 0.0;
      direction.x -= haveSteepLine ? 1.0 : 0.0;
    }
    vec4 blendPix = mix(pF, pB, step(Dist(pE, pB), Dist(pE, pF)));
    res = mix(res, blendPix, get_left_ratio(pos, origin, direction, scale));
  }
  if (blendResult.x != 0)
  {
    float dist_D_C = Dist(pD, pC);
    float dist_B_G = Dist(pB, pG);
    bool doLineBlend = (blendResult.x == 2 ||
      !((blendResult.w != 0 && !IsPixEqual(pE, pC)) || (blendResult.y != 0 && !IsPixEqual(pE, pG)) ||
        (IsPixEqual(pC, pB) && IsPixEqual(pB, pA) && IsPixEqual(pA, pD) && IsPixEqual(pD, pG) && !IsPixEqual(pE, pA))));
    vec2 origin = vec2(0.0, -1.0 / sqrt(2.0));
    vec2 direction = vec2(-1.0, 1.0);
    if (doLineBlend)
    {
      bool haveShallowLine = (2.2 * dist_D_C <= dist_B_G) && (pE != pC) && (pF != pC);
      bool haveSteepLine = (2.2 * dist_B_G <= dist_D_C) && (pE != pG) && (pH != pG);
      origin = haveShallowLine ? vec2(0.0, -0.25) : vec2(0.0, -0.5);
      direction.x -= haveShallowLine ? 1.0 : 0.0;
      direction.y += haveSteepLine ? 1.0 : 0.0;
    }
    vec4 blendPix = mix(pD, pB, step(Dist(pE, pB), Dist(pE, pD)));
    res = mix(res, blendPix, get_left_ratio(pos, origin, direction, scale));
  }
  return res;
}

void fragment() {
  COLOR = xbrz(UV);
}
