#version 310 es
#define attribute in
#define varying in
#define shadow2D(_sampler, _coord) texture(_sampler, _coord)
#define shadow2DProj(_sampler, _coord) textureProj(_sampler, _coord)

#if GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
precision highp int;

layout(location = 0) out highp vec4 bgfx_FragData0;
flat varying highp vec3 v_absorbColor;
varying highp vec2 v_projPos;
flat varying highp vec3 v_scatterColor;
varying highp vec2 v_texcoord0;

vec3 instMul(vec3 _vec, mat3 _mtx) { return ( (_vec) * (_mtx) ); }
vec3 instMul(mat3 _mtx, vec3 _vec) { return ( (_mtx) * (_vec) ); }
vec4 instMul(vec4 _vec, mat4 _mtx) { return ( (_vec) * (_mtx) ); }
vec4 instMul(mat4 _mtx, vec4 _vec) { return ( (_mtx) * (_vec) ); }

float rcp(float _a) { return 1.0/_a; }
vec2 rcp(vec2 _a) { return vec2(1.0)/_a; }
vec3 rcp(vec3 _a) { return vec3(1.0)/_a; }
vec4 rcp(vec4 _a) { return vec4(1.0)/_a; }

vec2 vec2_splat(float _x) { return vec2(_x, _x); }
vec3 vec3_splat(float _x) { return vec3(_x, _x, _x); }
vec4 vec4_splat(float _x) { return vec4(_x, _x, _x, _x); }
uvec2 uvec2_splat(uint _x) { return uvec2(_x, _x); }
uvec3 uvec3_splat(uint _x) { return uvec3(_x, _x, _x); }
uvec4 uvec4_splat(uint _x) { return uvec4(_x, _x, _x, _x); }

mat4 mtxFromRows(vec4 _0, vec4 _1, vec4 _2, vec4 _3) { return transpose(mat4(_0, _1, _2, _3)); }
mat4 mtxFromCols(vec4 _0, vec4 _1, vec4 _2, vec4 _3) { return mat4(_0, _1, _2, _3); }
mat3 mtxFromRows(vec3 _0, vec3 _1, vec3 _2) { return transpose(mat3(_0, _1, _2)); }
mat3 mtxFromCols(vec3 _0, vec3 _1, vec3 _2) { return mat3(_0, _1, _2); }
mat2 mtxFromRows(vec2 _0, vec2 _1) { return transpose(mat2(_0, _1)); }
mat2 mtxFromCols(vec2 _0, vec2 _1) { return mat2(_0, _1); }

// --- UNIFORMS ---
uniform vec4 u_viewRect;
uniform vec4 u_viewTexel;
uniform mat4 u_view;
uniform mat4 u_invView;
uniform mat4 u_proj;
uniform mat4 u_invProj;
uniform mat4 u_viewProj;
uniform mat4 u_invViewProj;
uniform mat4 u_model[4];
uniform mat4 u_modelView;
uniform mat4 u_modelViewProj;
uniform vec4 u_alphaRef4;
uniform vec4 u_prevWorldPosOffset;
uniform mat4 u_prevViewProj;

uniform highp vec4 CameraLightIntensity;
uniform highp vec4 DimensionID;
uniform highp vec4 FogColor;
uniform highp vec4 SunDir;
uniform highp vec4 MoonDir;
uniform highp vec4 DirectionalLightSourceWorldSpaceDirection;
uniform highp vec4 Time;
uniform highp vec4 FogAndDistanceControl;
uniform highp vec4 RenderChunkFogAlpha;
uniform highp vec4 WorldOrigin;

uniform highp sampler2D s_SceneDepth;
uniform highp sampler2D s_DiffuseLighting;
uniform highp sampler2D s_SpecularLighting;
uniform highp sampler2D s_PreviousFrameAverageLuminance;

uniform highp sampler2DArray s_ScatteringBuffer;
uniform highp vec4 VolumeDimensions;
uniform highp vec4 VolumeNearFar;
uniform highp vec4 VolumeScatteringEnabledAndPointLightVolumetricsEnabled;

uniform highp sampler2DArray s_CausticsTexture;

uniform highp vec4 PreExposureEnabled;
uniform highp vec4 AtmosphericScatteringToggles;
uniform highp vec4 CameraAmbientContribution;
uniform highp vec4 UndergroundFogColor;
uniform highp vec4 SunColor;
uniform highp vec4 MoonColor;
uniform highp vec4 SkyZenithColor;
uniform highp vec4 SkyHorizonColor;
uniform highp vec4 FogSkyBlend;
uniform highp vec4 AtmosphericScattering;
uniform highp vec4 DiffuseSpecularEmissiveAmbientTermToggles;
uniform highp vec4 BlockBaseAmbientLightColorIntensity;
uniform highp vec4 SkyAmbientLightColorIntensity;
uniform highp vec4 AmbientLightParams;
uniform highp vec4 EmissiveMultiplierAndDesaturationAndCloudPCFAndContribution;
uniform highp sampler2D s_ColorMetalnessSubsurface;
uniform highp usampler2D s_EmissiveAmbientLinearRoughness;
uniform highp vec4 ColorGrading_OptimizeGammaCorrection;
uniform highp vec4 SkySamplesConfig;
uniform highp sampler3D s_SkyAmbientSamples;

// --- MATH & HELPER FUNCTIONS ---
float luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float linearstep(float edge0, float edge1, float x) {
    return clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
}

vec3 saturation(vec3 color, float val) {
    float lum = luminance(color);
    return mix(vec3_splat(lum), color, val);
}

float PhaseHG(float costh, float g) {
    float g2 = g * g;
    float num = 1.0 - g2;
    float denom = 1.0 + g2 - 2.0 * g * costh;
    return (1.0 / (4.0 * 3.141592653589793)) * num / (denom * sqrt(max(denom, 0.0001)));
}

float PhaseR(float costh) {
    return 3.0 / (16.0 * 3.14159265358979) * (1.0 + costh * costh);
}

float pow2(float x) { return x * x; }

vec2 SphereIntersection(vec3 rayStart, vec3 rayDir, vec3 sphereCenter, float sphereRadius) {
    vec3 oc = rayStart - sphereCenter;
    float b = dot(oc, rayDir);
    float c = dot(oc, oc) - pow2(sphereRadius);
    float h = pow2(b) - c;
    if (h < 0.0) {
        return vec2(-1.0, -1.0);
    } else {
        h = sqrt(h);
        return vec2(-b-h, -b+h);
    }
}

vec3 GetLightTransmittance(vec3 lightDir, float multiplier, float ozoneMultiplier) {
    float lightExtinctionAmount = exp(-(clamp(lightDir.y + 0.03, 0.0, 1.0) * 40.0)) + exp(-(clamp(lightDir.y + 0.3, 0.0, 1.0) * 5.0)) * 0.4 + pow2(clamp(1.0-lightDir.y, 0.0, 1.0)) * 0.02 + 0.002;
    return exp(-(vec3(5.802e-6, 13.558e-6, 33.100e-6) + vec3(3.996e-6, 3.996e-6, 3.996e-6) + vec3(0.650e-6, 1.881e-6, 0.085e-6) * ozoneMultiplier) * lightExtinctionAmount * 1.0 * multiplier * 1e6);
}

vec3 GetSunTransmittance(vec3 sunDir) {
    return GetLightTransmittance(sunDir, 1.0, 1.0);
}

vec3 GetMoonTransmittance(vec3 moonDir) {
    return saturation(GetLightTransmittance(moonDir, 1.0, 1.0), 0.25);
}

struct AtmosphereParams {
    vec3 rayStart;
    vec3 rayDir;
    vec3 lightDir;
    float rayLength;
    float aerial;
    float occlusion;
    float mieMod;
};

vec3 GetAtmosphere(AtmosphereParams params, out vec4 transmittance) {
    vec2 t1 = SphereIntersection(params.rayStart, params.rayDir, vec3(0, -6371000.0, 0), 6371000.0);
    vec2 t2 = SphereIntersection(params.rayStart, params.rayDir, vec3(0, -6371000.0, 0), 6371000.0 + 100000.0);
    float normAltitude = params.rayStart.y / 100000.0;
    if (t2.y < 0.0) {
        transmittance = vec4(1.0, 1.0, 1.0, 1.0);
        return vec3(0.0, 0.0, 0.0);
    } else {
        t2.y -= max(0.0, t2.x);
        float opticalDepth = t2.y;
        opticalDepth = min(params.rayLength, opticalDepth);
        opticalDepth = min(opticalDepth * params.aerial * 2.5 * 1.0, t2.y);
        float hbias = 1.0 - 1.0 / (2.0 + pow2(t2.y) * 1e-12);
        hbias = pow(hbias, 1.0 + normAltitude * 10.0);
        float sqhbias = pow2(hbias);
        float densityR = sqhbias * 1.0;
        float densityM = pow2(sqhbias) * hbias * 1.0;
        float ly = params.lightDir.y;
        ly += clamp(-params.lightDir.y + 0.02, 0.0, 1.0) * clamp(params.lightDir.y + 0.7, 0.0, 1.0);
        ly = clamp(ly, -1.0, 1.0);
        vec3 lightColor = GetLightTransmittance(vec3(params.lightDir.x, ly, params.lightDir.z), hbias, 5.0);
        vec3 R = (1.0 - exp(-opticalDepth * densityR * vec3(5.802e-6, 13.558e-6, 33.100e-6) / 2.5)) * 2.5;
        vec3 M = (1.0 - exp(-opticalDepth * densityM * vec3(3.996e-6, 3.996e-6, 3.996e-6) / 0.5)) * 0.5;
        vec3 E = (vec3(5.802e-6, 13.558e-6, 33.100e-6) * densityR + vec3(3.996e-6, 3.996e-6, 3.996e-6) * densityM + vec3(0.650e-6, 1.881e-6, 0.085e-6) * densityR * 1.5) * pow2(pow2(1.0 - normAltitude)) * 0.25;
        float costh = dot(params.rayDir, params.lightDir);
        float phaseR = PhaseR(costh);
        float phaseM = PhaseHG(costh, 0.8);
        float desaturate = smoothstep(0.0, 0.1, params.lightDir.y) * 0.75 + 0.25;
        vec3 rayleigh = (phaseR * params.occlusion + phaseR * 0.3) * saturation(lightColor, desaturate);
        vec3 mie = (phaseM * params.occlusion + phaseR * 0.3) * lightColor * params.mieMod;
        vec3 scattering = mie * M + rayleigh * R;
        transmittance.rgb = exp(-(opticalDepth + pow2(pow2(pow2(opticalDepth * 4.5e-6)))) * E);
        transmittance.rgb = saturation(transmittance.rgb, desaturate);
        transmittance.a = step(t1.x, 0.0);
        if (t1.y > 0.0 && t1.y < params.rayLength) {
            float planetOpticalDepth = t1.y - max(0.0, t1.x);
            float skyWeight = exp(-planetOpticalDepth * 1e-6);
            scattering *= mix(vec3(0.2, 0.3, 0.4), vec3(1.0, 1.0, 1.0), skyWeight);
        }
        return scattering * 0.23;
    }
}

vec3 GetAtmosphere(AtmosphereParams params) {
    vec4 transmittance;
    return GetAtmosphere(params, transmittance);
}

// --- NOISE SAMPLING ---
float worleyR(vec2 uv) {
    uv -= 0.5;
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    vec4 t = textureGather(s_CausticsTexture, vec3((i + 0.5) * 0.00390625, 3.0), 0);
    return mix(mix(t.w, t.z, f.x), mix(t.x, t.y, f.x), f.y);
}

float worleyG(vec2 uv) {
    uv -= 0.5;
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    vec4 t = textureGather(s_CausticsTexture, vec3((i + 0.5) * 0.00390625, 3.0), 1);
    return mix(mix(t.w, t.z, f.x), mix(t.x, t.y, f.x), f.y);
}

float worley3d(vec3 pos) {
    pos = mod(pos, vec3(32.0, 32.0, 36.0));
    float col = mod(floor(pos.z), 6.0) * 34.0;
    float row = floor(pos.z / 6.0) * 34.0;
    vec2 uv = vec2(pos.x + col, pos.y - 34.0 - row) + 1.0;
    float a = worleyR(uv);
    float b = worleyG(uv);
    return mix(a, b, fract(pos.z));
}

float valueNoise(vec2 uv) {
    uv -= 0.5;
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    f = f * f * (3.0 - 2.0 * f);
    vec4 t = textureGather(s_CausticsTexture, vec3((i + 0.5) * 0.00390625, 0.0), 0);
    return mix(mix(t.w, t.z, f.x), mix(t.x, t.y, f.x), f.y);
}

// --- HÀO QUANG CỰC QUANG / TÍM HUYỀN BÍ (COSMIC PURPLE AURA) ---
vec3 calcAurora(vec3 viewDir, float time, float nightFactor) {
    if (viewDir.y < 0.01 || nightFactor <= 0.0) return vec3(0.0);
    
    // Ánh xạ góc nhìn lên bầu trời dạng hình vòm
    float y = max(viewDir.y, 0.02);
    vec2 uv = viewDir.xz / (y + 0.3);
    float t = time * 0.08; // Tốc độ trôi nhẹ nhàng
    
    // TẠO DẢI SÁNG THẲNG ĐỨNG VÀ DẢI MÂY HUYỀN BÍ (Curtain & Nebula Noise)
    float n1 = valueNoise(uv * 1.5 + vec2(t * 0.3, -t * 0.2));
    float n2 = valueNoise(uv * 3.5 - vec2(t * 0.5, t * 0.4));
    
    // Tạo sóng dọc giả lập tia sáng cuộn theo phương đứng
    float wave = sin(uv.x * 4.0 + n1 * 6.0 + t) * 0.5 + 0.5;
    wave *= sin(uv.y * 2.0 - n2 * 4.0 + t * 0.5) * 0.5 + 0.5;
    
    // Nhân công suất để tạo độ tương phản giữa dải sáng và dải tối
    float curtain = pow(wave, 1.8) * 1.5;
    curtain += pow(n2, 2.0) * 0.8;
    
    // MÀU SẮC DẢI HÀO QUANG (Tím Đậm -> Hồng Tím Magenta -> Tím Xanh)
    vec3 colBase = vec3(0.0, 0.85, 0.55);  // Tím thẫm nền
    vec3 colMid  = vec3(0.75, 0.20, 0.85);  // Hồng tím hào quang (Magenta)
    vec3 colTop  = vec3(0.50, 0.30, 0.95);  // Tím mờ phía trên
    
    vec3 finalAurora = mix(colBase, colMid, smoothstep(0.1, 0.7, curtain));
    finalAurora = mix(finalAurora, colTop, y * 0.8);
    
    // Khử vết viền sắc cạnh ở chân trời và đỉnh đầu
    float fade = smoothstep(0.02, 0.2, y) * (1.0 - smoothstep(0.6, 1.0, y));
    
    return finalAurora * curtain * fade * nightFactor * 2.2;
}

// --- CLOUD SYSTEM ---
struct CloudSetup {
    float tMin;
    float tMax;
    bool isValidCloud;
};

CloudSetup calcCloudSetup(vec3 rayDir, float camAltitude) {
    CloudSetup setup;
    setup.tMin = 0.0;
    setup.tMax = 1e6;
    setup.isValidCloud = true;

    const float cloudBottomY = 180.0;
    const float cloudTopY    = 260.0;

    float tBottomPlane = (cloudBottomY - camAltitude) / rayDir.y;
    float tTopPlane = (cloudTopY - camAltitude) / rayDir.y;

    if (camAltitude > cloudTopY) {
        if (rayDir.y >= 0.0) { setup.isValidCloud = false; return setup; }
        setup.tMin = max(tTopPlane, 0.0);
        setup.tMax = tBottomPlane;
    }
    else if (camAltitude < cloudBottomY) {
        if (rayDir.y <= 0.0) { setup.isValidCloud = false; return setup; }
        setup.tMin = max(tBottomPlane, 0.0);
        setup.tMax = tTopPlane;
    }
    else {
        setup.tMin = 0.0;
        setup.tMax = rayDir.y > 0.0 ? tTopPlane : tBottomPlane;
    }

    if (setup.tMax <= setup.tMin) {
        setup.isValidCloud = false;
    }
    return setup;
}

float calcCumulusModel(vec3 pos) {
    vec2 flow = vec2(Time.x * 0.85, Time.x * 0.35);
    vec2 warpCoord = pos.xz * 0.003 + flow * 0.1;
    
    vec2 warp = vec2(
        valueNoise(warpCoord),
        valueNoise(warpCoord + vec2(5.2, 1.3))
    ) * 1.5;

    vec2 basePos = (pos.xz + flow + warp * 12.0) * 0.004;

    float base = valueNoise(basePos);
    base += valueNoise(basePos * 2.2 + vec2(1.7, -3.2)) * 0.5;

    base = clamp(base * 0.75 - 0.05, 0.0, 1.0);
    float coverage = valueNoise(basePos * 0.3 + vec2(-9.4, 12.1));
    base *= mix(0.3, 1.0, smoothstep(0.1, 0.9, coverage));

    float heightFraction = clamp((pos.y - 180.0) / 80.0, 0.0, 1.0);
    float heightGradient = sin(heightFraction * 3.14159265);
    heightGradient = pow(heightGradient, 0.4);
    base *= heightGradient;

    vec2 camXZ = -WorldOrigin.xz;
    float distToCamXZ = length(pos.xz - camXZ);
    float edgeFade = 1.0 - smoothstep(3200.0, 4800.0, distToCamXZ);
    base *= edgeFade;

    if (base <= 0.005) return 0.0;

    vec3 worleyCoord = pos * 0.055 + vec3(-flow * 1.5, Time.x * 0.25);
    float wSculpt = worley3d(worleyCoord);
    base = linearstep(wSculpt * 0.22, 1.0, base);

    return clamp(base * 2.4, 0.0, 1.0);
}

vec3 calcCloud(vec3 worldDir, vec3 lightDir, float worldDist, float dither, bool isTerrain, CloudSetup setup) {
    if (!setup.isValidCloud) return vec3(0.0, 0.0, 1.0);

    vec3 rayOrigin = -WorldOrigin.xyz;
    vec3 rayDir = worldDir;
    float costh = dot(worldDir, lightDir);

    if (isTerrain) setup.tMax = min(setup.tMax, worldDist);
    if (setup.tMax <= setup.tMin) return vec3(0.0, 0.0, 1.0);

    const int MAX_STEPS = 12; 
    float rayLength = setup.tMax - setup.tMin;
    float stepSize = rayLength / float(MAX_STEPS);
    float currentT = setup.tMin + dither * stepSize;

    float accumulatedScattering = 0.0;
    float weightedDepth = 0.0;
    float totalWeight = 0.0;
    float transmittance = 1.0;

    float fPhase = PhaseHG(costh, 0.65);
    float bPhase = PhaseHG(costh, -0.25);
    float phase = mix(fPhase, bPhase, 0.35);

    for (int i = 0; i < MAX_STEPS; i++) {
        if (currentT >= setup.tMax || transmittance < 0.01) break;

        vec3 samplePos = rayOrigin + rayDir * currentT;
        float density = calcCumulusModel(samplePos);

        if (density > 0.001) {
            float lightShadow = 0.0;
            float lightStepSize = 24.0;
            vec3 lightSamplePos = samplePos;

            for (int j = 0; j < 1; j++) {
                lightSamplePos += lightDir * lightStepSize;
                lightShadow += calcCumulusModel(lightSamplePos);
            }

            float stepExtinction = density * stepSize * 0.085;
            float shadowExtinction = lightShadow * lightStepSize * 0.085;
            
            float attenuation = exp(-shadowExtinction);
            float powderEffect = 1.0 - exp(-stepExtinction * 2.0);
            float stepScattering = attenuation * powderEffect * phase * density;

            float stepTransmittance = exp(-stepExtinction);
            accumulatedScattering += transmittance * stepScattering;
            
            weightedDepth += transmittance * currentT;
            totalWeight += transmittance;
            transmittance *= stepTransmittance;
        }
        currentT += stepSize;
    }

    weightedDepth = totalWeight > 0.0001 ? (weightedDepth / totalWeight) : 0.0;
    return vec3(accumulatedScattering, weightedDepth, transmittance);
}

void applyCumulusClouds(inout vec3 outColor, vec3 absorbColor, vec3 worldDir, float worldDist, float dither, bool isTerrain) {
    CloudSetup cloudSetup = calcCloudSetup(worldDir, -WorldOrigin.y);
    vec3 clouds = calcCloud(worldDir, DirectionalLightSourceWorldSpaceDirection.xyz, worldDist, dither, isTerrain, cloudSetup);

    if (clouds.b >= 0.999) return;

    AtmosphereParams sunAtmParams;
    sunAtmParams.rayStart = vec3(0.0, 10.0, 0.0);
    sunAtmParams.rayDir = worldDir;
    sunAtmParams.lightDir = SunDir.xyz;
    sunAtmParams.rayLength = clouds.g;
    sunAtmParams.aerial = 80.0;
    sunAtmParams.occlusion = 1.0;
    sunAtmParams.mieMod = 1.0;

    vec4 transmittance;
    vec3 atmContrib = GetAtmosphere(sunAtmParams, transmittance) * 100.0;

    float dayFactor = smoothstep(-0.08, 0.12, SunDir.y);
    vec3 dayCloudColor = absorbColor * transmittance.rgb * 1.85;
    vec3 nightCloudColor = SkyAmbientLightColorIntensity.rgb * 0.65 + SkyHorizonColor.rgb * 0.35 + MoonColor.rgb * 0.25;

    vec3 environmentCloudColor = mix(nightCloudColor, dayCloudColor, dayFactor);
    vec3 cloudsColor = clouds.r * environmentCloudColor;
    cloudsColor += SkyZenithColor.rgb * (1.0 - clouds.b) * 0.18 * dayFactor;

    float atmosphereThroughCloud = mix(0.15, 0.45, dayFactor);
    cloudsColor += atmContrib * (1.0 - clouds.b) * atmosphereThroughCloud;

    float sunViewDot = max(dot(worldDir, SunDir.xyz), 0.0);
    float sunsetFactor = smoothstep(-0.15, 0.15, SunDir.y) * (1.0 - smoothstep(0.0, 0.3, SunDir.y));
    float aura = pow(sunViewDot, 5.0) * sunsetFactor * 4.0; 
    vec3 auraColor = vec3(1.0, 0.45, 0.1); 
    
    float edgeGlow = smoothstep(0.0, 0.6, clouds.b) * smoothstep(1.0, 0.4, clouds.b);
    cloudsColor += auraColor * aura * edgeGlow * (1.0 - clouds.b);

    outColor = clouds.b * outColor + cloudsColor;
}

// --- MAIN FRAGMENT SHADER ---
void main()
{
    highp vec4 _2471 = texture(s_SceneDepth, v_texcoord0);
    highp float _2475 = (_2471.x * 2.0) - 1.0;
    highp vec4 _2260 = vec4(v_projPos, _2475, 1.0);
    highp mat4 _2530 = u_invProj;
    highp mat4 _2549 = u_invProj;
    highp mat4 _2568 = u_invProj;
    highp mat4 _2587 = u_invProj;
    highp mat4 _2606 = u_invProj;
    highp float _2503 = _2260.x;
    highp float _2507 = _2260.y;
    highp float _2511 = _2260.w;
    highp float _2515 = _2260.z;
    highp float _2519 = _2260.w;
    highp vec4 _2523 = vec4(_2503 * _2530[0].x, _2507 * _2549[1].y, _2511 * _2568[3].z, (_2515 * _2587[2].w) + (_2519 * _2606[3].w));
    _2260 = _2523;
    highp float _2525 = _2260.w;
    highp vec4 _2528 = _2523 / vec4(_2525);
    _2260 = _2528;
    highp vec4 _2895 = texture(s_ColorMetalnessSubsurface, v_texcoord0);
    uvec4 _2285 = texelFetch(s_EmissiveAmbientLinearRoughness, ivec2(vec2(textureSize(s_EmissiveAmbientLinearRoughness, 0)) * v_texcoord0), 0);
    uint _2924 = _2285.x & 65535u;
    uvec2 _2904 = uvec2(_2924 >> 8u, _2924 & 255u);
    highp vec2 _2286 = vec2(float(_2904.x), float(_2904.y)) * vec2(0.0039215688593685626983642578125);
    highp float _4293;
    if (_2475 == 1.0)
    {
        highp vec2 _2293 = v_texcoord0;
        highp float _4292;
        if (SkySamplesConfig.x > 0.5)
        {
            _4292 = textureLod(s_SkyAmbientSamples, vec3(_2293.x, _2293.y, 1.0), 0.0).y;
        }
        else
        {
            _4292 = 1.0;
        }
        _4293 = _4292;
    }
    else
    {
        _4293 = float(_2285.w) * 0.0039215688593685626983642578125;
    }
    highp vec3 _2430 = vec3(v_projPos, _2475);
    highp vec3 _2442 = _2895.xyz;
    highp vec3 _4297;
    
    if (ColorGrading_OptimizeGammaCorrection.x != 0.0)
    {
        _4297 = pow(max(_2442, vec3(0.0)), vec3(2.2000000476837158203125));
    }
    else
    {
        highp vec3 _3012 = _2442;
        highp vec3 _3024 = _2442 * vec3(0.077399380505084991455078125);
        highp vec3 _3025 = pow((_2442 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625));
        
        _3012.x = (_3012.x <= 0.040449999272823333740234375) ? _3024.x : _3025.x;
        _3012.y = (_3012.y <= 0.040449999272823333740234375) ? _3024.y : _3025.y;
        _3012.z = (_3012.z <= 0.040449999272823333740234375) ? _3024.z : _3025.z;
        _4297 = _3012;
    }

    highp vec3 _4261 = _2430;
    highp vec3 _4309;
    highp vec3 _4310;
    if (_4261.z != 1.0)
    {
        _4310 = _4297 * texture(s_DiffuseLighting, v_texcoord0).xyz;
        _4309 = texture(s_SpecularLighting, v_texcoord0).xyz;
    }
    else
    {
        _4310 = vec3(0.0);
        _4309 = vec3(0.0);
    }
    
    highp vec3 _3330 = normalize((u_invView * vec4(_2528.xyz, 1.0)).xyz - (u_invView * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
    bool _3346 = AtmosphericScatteringToggles.y != 0.0;
    bool _3352 = _3346 ? (AtmosphericScatteringToggles.z != 0.0) : _3346;
    bool _3358 = _3352 ? (DiffuseSpecularEmissiveAmbientTermToggles.w != 0.0) : _3352;
    
    highp vec3 _4311 = _3358 ? max(((vec3(1.0) + (vec3(1.0) * vec4(1.0).w)) * BlockBaseAmbientLightColorIntensity.w) + ((SkyAmbientLightColorIntensity.xyz * mix(1.0, 1.0, CameraLightIntensity.y)) * SkyAmbientLightColorIntensity.w), AmbientLightParams.xyz * AmbientLightParams.w) * AtmosphericScatteringToggles.z : vec3(0.0);
    
    highp vec3 _4314;
    highp float _4318;
    if (AtmosphericScatteringToggles.x != 0.0)
    {
        highp float _3619 = clamp((((length(_2528.xyz) / FogAndDistanceControl.z) + RenderChunkFogAlpha.x) - FogAndDistanceControl.x) * FogAndDistanceControl.y, 0.0, 1.0);
        if (_3619 > 0.0)
        {
            if (AtmosphericScatteringToggles.y != 0.0)
            {
                _4314 = FogColor.xyz * max(_4311, vec3(1.0));
            }
            else
            {
                highp vec4 _4130 = SunColor;
                highp vec4 _4131 = MoonColor;
                highp float _3816 = 1.0 - smoothstep(FogSkyBlend.x - FogSkyBlend.w, FogSkyBlend.z - FogSkyBlend.w, _3330.y);
                highp float _3729 = dot(_3330, SunDir.xyz);
                highp float _3733 = dot(_3330, MoonDir.xyz);
                highp float _3879 = 1.0 - smoothstep(FogSkyBlend.x - FogSkyBlend.w, FogSkyBlend.y, _3330.y);
                highp float _3762 = clamp(pow(max(_3729, 0.0), AtmosphericScattering.w), 0.0, 1.0);
                highp float _3767 = clamp(pow(max(_3733, 0.0), AtmosphericScattering.w), 0.0, 1.0);
                highp float _3771 = 1.809999942779541015625 - (_3762 * 1.7999999523162841796875);
                highp float _3777 = 1.809999942779541015625 - (_3767 * 1.7999999523162841796875);
                highp vec3 _3808 = (((mix(SkyZenithColor.xyz, SkyHorizonColor.xyz, vec3((_3879 * _3879) * _3879)) * AtmosphericScattering.x) * 0.079577468335628509521484375) * ((_4130.w * (0.75 * ((_3729 * _3729) + 1.0))) + (_4131.w * (0.75 * ((_3733 * _3733) + 1.0))))) + (((SkyHorizonColor.xyz * ((_3816 * _3816) * _3816)) * 0.079577468335628509521484375) * (((((SunColor.xyz * _4130.w) * AtmosphericScattering.y) * _3762) * (0.0361000001430511474609375 / (_3771 * sqrt(_3771)))) + ((((MoonColor.xyz * _4131.w) * AtmosphericScattering.z) * _3767) * (0.0361000001430511474609375 / (_3777 * sqrt(_3777))))));
                _4314 = AtmosphericScatteringToggles.w != 0.0 ? mix(UndergroundFogColor.xyz, _3808, vec3(max(CameraAmbientContribution.y, _4293))) : _3808;
            }
        }
        else
        {
            _4314 = vec3(0.0);
        }
        _4318 = _3619;
    }
    else
    {
        _4318 = 0.0;
        _4314 = vec3(0.0);
    }
    
    highp vec4 _3584 = vec4(_4314, _4318);
    highp vec4 _4322;
    if (VolumeScatteringEnabledAndPointLightVolumetricsEnabled.x != 0.0)
    {
        highp vec2 _3950 = (_2430.xy + vec2(1.0)) * 0.5;
        highp vec4 _3942 = u_invProj * vec4(v_projPos, _2475, 1.0);
        highp vec3 _3924 = vec3(_3950.x, _3950.y, log((53.598148345947265625 * ((((-_3942.z) / _3942.w) - VolumeNearFar.x) / (VolumeNearFar.y - VolumeNearFar.x))) + 1.0) * 0.25);
        highp float _4002 = (_3924.z * float(VolumeDimensions.z)) - 0.5;
        int _4008 = clamp(int(_4002), 0, int(VolumeDimensions.z) - 2);
        _4322 = mix(textureLod(s_ScatteringBuffer, vec3(_3950.x, _3950.y, float(_4008)), 0.0), textureLod(s_ScatteringBuffer, vec3(_3950.x, _3950.y, float(_4008 + 1)), 0.0), vec4(clamp(_4002 - float(_4008), 0.0, 1.0)));
    }
    else
    {
        _4322 = vec4(0.0, 0.0, 0.0, 1.0);
    }
    
    highp vec4 _3306 = vec4(_4322.xyz + (mix((_4310 + _4309) + (((mix(_4297, vec3(dot(_4297, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875))), vec3(EmissiveMultiplierAndDesaturationAndCloudPCFAndContribution.y)) * DiffuseSpecularEmissiveAmbientTermToggles.z) * vec3(_2286.y)) * EmissiveMultiplierAndDesaturationAndCloudPCFAndContribution.x), _3584.xyz, vec3(_3584.w)) * _4322.w), 1.0);

    // --- RENDER CLOUDS & BẦU TRỜI ---
    highp vec3 _cloudWorldPos = (u_invView * vec4(_2528.xyz, 1.0)).xyz - (u_invView * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    highp float _cloudWorldDist = length(_cloudWorldPos);
    bool _cloudIsTerrain = _2475 < 1.0;
    
    if (int(DimensionID.r) == 0)
    {
        // 1. Hòa trộn Hào quang Tím / Cực quang ban đêm
        if (!_cloudIsTerrain) {
            float nightFactor = smoothstep(0.0, -0.15, SunDir.y);
            _3306.xyz += calcAurora(_3330, Time.x, nightFactor);
        }

        // 2. Hòa trộn Mây khối (Clouds)
        highp vec3 _cloudAbsorb = GetSunTransmittance(SunDir.xyz) * smoothstep(0.0, 0.1, SunDir.y) * 100.0;
        _cloudAbsorb += GetMoonTransmittance(MoonDir.xyz) * smoothstep(0.0, 0.1, MoonDir.y) * 0.1;
        
        highp float _cloudDither = texelFetch(s_CausticsTexture, ivec3((ivec2(gl_FragCoord.xy) & 255), 1), 0).r;
        highp vec3 _cloudOut = _3306.xyz;
        
        applyCumulusClouds(_cloudOut, _cloudAbsorb, _3330, _cloudWorldDist, _cloudDither, _cloudIsTerrain);
        _3306.xyz = _cloudOut;
    }

    if (PreExposureEnabled.x > 0.0)
    {
        highp vec3 _4082 = _3306.xyz * ((0.180000007152557373046875 / texture(s_PreviousFrameAverageLuminance, vec2(0.5)).x) + 9.9999997473787516355514526367188e-05);
        bgfx_FragData0 = vec4(_4082, _3306.w);
    }
    else
    {
        bgfx_FragData0 = _3306;
    }
}
