// SPDX-FileCopyrightText: 2023 Unity Technologies and the glTFast authors
// SPDX-License-Identifier: Apache-2.0

// Based on Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)


#ifndef UNITY_STANDARD_CORE_FORWARD_SIMPLE_INCLUDED
#define UNITY_STANDARD_CORE_FORWARD_SIMPLE_INCLUDED

#include "glTFUnityStandardCore.cginc"

//  Does not support: _PARALLAXMAP, DIRLIGHTMAP_COMBINED
#define GLOSSMAP (defined(_SPECGLOSSMAP) || defined(_METALLICGLOSSMAP))

#ifndef SPECULAR_HIGHLIGHTS
    #define SPECULAR_HIGHLIGHTS (!defined(_SPECULAR_HIGHLIGHTS_OFF))
#endif

struct VertexOutputBaseSimple
{
    UNITY_POSITION(pos);
    float4 tex                          : TEXCOORD0;
    float4 eyeVec                        : TEXCOORD1; // w: grazingTerm

    float4 ambientOrLightmapUV           : TEXCOORD2; // SH or Lightmap UV
    SHADOW_COORDS(3)
    UNITY_FOG_COORDS_PACKED(4, float4) // x: fogCoord, yzw: reflectVec

    float4 normalWorld                   : TEXCOORD5; // w: fresnelTerm

#ifdef _NORMALMAP
    float3 tangentSpaceLightDir          : TEXCOORD6;
    #if SPECULAR_HIGHLIGHTS
        float3 tangentSpaceEyeVec        : TEXCOORD7;
    #endif
#endif
#if UNITY_REQUIRE_FRAG_WORLDPOS
    float3 posWorld                     : TEXCOORD8;
#endif

#if defined(_OCCLUSION) || defined(_METALLICGLOSSMAP) || defined(_SPECGLOSSMAP)
    float4 texORM                       : TEXCOORD9;
#endif
#ifdef _EMISSION
    float2 texEmission                  : TEXCOORD10;
#endif

    float4 color                         : COLOR;
    float pointSize                     : PSIZE;
    UNITY_VERTEX_OUTPUT_STEREO
};

// UNIFORM_REFLECTIVITY(): workaround to get (uniform) reflecivity based on UNITY_SETUP_BRDF_INPUT
float MetallicSetup_Reflectivity()
{
    return 1.0h - OneMinusReflectivityFromMetallic(metallicFactor);
}

float SpecularSetup_Reflectivity()
{
    return SpecularStrength(specularFactor.rgb);
}

float RoughnessSetup_Reflectivity()
{
    return MetallicSetup_Reflectivity();
}

#define JOIN2(a, b) a##b
#define JOIN(a, b) JOIN2(a,b)
#define UNIFORM_REFLECTIVITY JOIN(UNITY_SETUP_BRDF_INPUT, _Reflectivity)


#ifdef _NORMALMAP

float3 TransformToTangentSpace(float3 tangent, float3 binormal, float3 normal, float3 v)
{
    // Mali400 shader compiler prefers explicit dot product over using a float3x3 matrix
    return float3(dot(tangent, v), dot(binormal, v), dot(normal, v));
}

void TangentSpaceLightingInput(float3 normalWorld, float4 vTangent, float3 lightDirWorld, float3 eyeVecWorld, out float3 tangentSpaceLightDir, out float3 tangentSpaceEyeVec)
{
    float3 tangentWorld = UnityObjectToWorldDir(vTangent.xyz);
    float sign = float(vTangent.w) * float(unity_WorldTransformParams.w);
    float3 binormalWorld = cross(normalWorld, tangentWorld) * sign;
    tangentSpaceLightDir = TransformToTangentSpace(tangentWorld, binormalWorld, normalWorld, lightDirWorld);
    #if SPECULAR_HIGHLIGHTS
        tangentSpaceEyeVec = normalize(TransformToTangentSpace(tangentWorld, binormalWorld, normalWorld, eyeVecWorld));
    #else
        tangentSpaceEyeVec = 0;
    #endif
}

#endif // _NORMALMAP

VertexOutputBaseSimple vertForwardBaseSimple (VertexInput v)
{
    UNITY_SETUP_INSTANCE_ID(v);
    VertexOutputBaseSimple o;
#ifdef UNITY_COLORSPACE_GAMMA
    o.color.rgb = LinearToGammaSpace(v.color.rgb);
    o.color.a = v.color.a;
#else
    o.color = v.color;
#endif
    UNITY_INITIALIZE_OUTPUT(VertexOutputBaseSimple, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

    float4 posWorld = mul(unity_ObjectToWorld, v.vertex);
    o.pos = UnityObjectToClipPos(v.vertex);
    o.tex = TexCoords(v);

    float3 eyeVec = normalize(posWorld.xyz - _WorldSpaceCameraPos);
    float3 normalWorld = UnityObjectToWorldNormal(v.normal);

    o.normalWorld.xyz = normalWorld;
    o.eyeVec.xyz = eyeVec;

    #ifdef _NORMALMAP
        float3 tangentSpaceEyeVec;
        TangentSpaceLightingInput(normalWorld, v.tangent, _WorldSpaceLightPos0.xyz, eyeVec, o.tangentSpaceLightDir, tangentSpaceEyeVec);
        #if SPECULAR_HIGHLIGHTS
            o.tangentSpaceEyeVec = tangentSpaceEyeVec;
        #endif
    #endif

    //We need this for shadow receiving
    TRANSFER_SHADOW(o);

    o.ambientOrLightmapUV = VertexGIForward(v, posWorld, normalWorld);

    o.fogCoord.yzw = reflect(eyeVec, normalWorld);

    o.normalWorld.w = Pow4(1 - saturate(dot(normalWorld, -eyeVec))); // fresnel term
    #if !GLOSSMAP
        o.eyeVec.w = saturate(glossinessFactor + UNIFORM_REFLECTIVITY()); // grazing term
    #endif
    o.pointSize = 1;

    UNITY_TRANSFER_FOG(o, o.pos);
    return o;
}


FragmentCommonData FragmentSetupSimple(VertexOutputBaseSimple i)
{
    float alpha = Alpha(i.tex.xy);
    #if defined(_ALPHATEST_ON)
        clip (alpha - alphaCutoff);
    #endif

    
#if defined(_METALLICGLOSSMAP) || defined(_SPECGLOSSMAP)
    FragmentCommonData s = UNITY_SETUP_BRDF_INPUT (i.tex,i.texORM.zw,i.color);
#else
    FragmentCommonData s = UNITY_SETUP_BRDF_INPUT (i.tex,i.color);
#endif
    
    // NOTE: shader relies on pre-multiply alpha-blend (_SrcBlend = One, _DstBlend = OneMinusSrcAlpha)
    s.diffColor = PreMultiplyAlpha (s.diffColor, alpha, s.oneMinusReflectivity, /*out*/ s.alpha);

    s.normalWorld = i.normalWorld.xyz;
    s.eyeVec = i.eyeVec.xyz;
    s.posWorld = IN_WORLDPOS(i);
    s.reflUVW = i.fogCoord.yzw;

    #ifdef _NORMALMAP
        s.tangentSpaceNormal =  NormalInTangentSpace(i.tex);
    #else
        s.tangentSpaceNormal =  0;
    #endif

    return s;
}

UnityLight MainLightSimple(VertexOutputBaseSimple i, FragmentCommonData s)
{
    UnityLight mainLight = MainLight();
    return mainLight;
}

float PerVertexGrazingTerm(VertexOutputBaseSimple i, FragmentCommonData s)
{
    #if GLOSSMAP
        return saturate(s.smoothness + (1-s.oneMinusReflectivity));
    #else
        return i.eyeVec.w;
    #endif
}

float PerVertexFresnelTerm(VertexOutputBaseSimple i)
{
    return i.normalWorld.w;
}

#if !SPECULAR_HIGHLIGHTS
#   define REFLECTVEC_FOR_SPECULAR(i, s) float3(0, 0, 0)
#elif defined(_NORMALMAP)
#   define REFLECTVEC_FOR_SPECULAR(i, s) reflect(i.tangentSpaceEyeVec, s.tangentSpaceNormal)
#else
#   define REFLECTVEC_FOR_SPECULAR(i, s) s.reflUVW
#endif

float3 LightDirForSpecular(VertexOutputBaseSimple i, UnityLight mainLight)
{
    #if SPECULAR_HIGHLIGHTS && defined(_NORMALMAP)
        return i.tangentSpaceLightDir;
    #else
        return mainLight.dir;
    #endif
}

float3 BRDF3DirectSimple(float3 diffColor, float3 specColor, float smoothness, float rl)
{
    #if SPECULAR_HIGHLIGHTS
        return BRDF3_Direct(diffColor, specColor, Pow4(rl), smoothness);
    #else
        return diffColor;
    #endif
}

float4 fragForwardBaseSimpleInternal (VertexOutputBaseSimple i)
{
    UNITY_APPLY_DITHER_CROSSFADE(i.pos.xy);

    FragmentCommonData s = FragmentSetupSimple(i);

    UnityLight mainLight = MainLightSimple(i, s);

    #if !defined(LIGHTMAP_ON) && defined(_NORMALMAP)
    float ndotl = saturate(dot(s.tangentSpaceNormal, i.tangentSpaceLightDir));
    #else
    float ndotl = saturate(dot(s.normalWorld, mainLight.dir));
    #endif

    //we can't have worldpos here (not enough interpolator on SM 2.0) so no shadow fade in that case.
    float shadowMaskAttenuation = UnitySampleBakedOcclusion(i.ambientOrLightmapUV, 0);
    float realtimeShadowAttenuation = SHADOW_ATTENUATION(i);
    float atten = UnityMixRealtimeAndBakedShadows(realtimeShadowAttenuation, shadowMaskAttenuation, 0);

    float occlusion =
#ifdef _OCCLUSION
        Occlusion(i.texORM.xy);
#else
        1;
#endif
    float rl = dot(REFLECTVEC_FOR_SPECULAR(i, s), LightDirForSpecular(i, mainLight));

    UnityGI gi = FragmentGI (s, occlusion, i.ambientOrLightmapUV, atten, mainLight);
    float3 attenuatedLightColor = gi.light.color * ndotl;

    float3 c = BRDF3_Indirect(s.diffColor, s.specColor, gi.indirect, PerVertexGrazingTerm(i, s), PerVertexFresnelTerm(i));
    c += BRDF3DirectSimple(s.diffColor, s.specColor, s.smoothness, rl) * attenuatedLightColor;
    c += Emission(i.tex.xy);

    UNITY_APPLY_FOG(i.fogCoord, c);

    return OutputForward (float4(c, 1), s.alpha);
}

float4 fragForwardBaseSimple (VertexOutputBaseSimple i) : SV_Target  // backward compatibility (this used to be the fragment entry function)
{
    return fragForwardBaseSimpleInternal(i);
}

struct VertexOutputForwardAddSimple
{
    UNITY_POSITION(pos);
    float4 tex                          : TEXCOORD0;
    float3 posWorld                     : TEXCOORD1;

#if !defined(_NORMALMAP) && SPECULAR_HIGHLIGHTS
    UNITY_FOG_COORDS_PACKED(2, float4) // x: fogCoord, yzw: reflectVec
#else
    UNITY_FOG_COORDS_PACKED(2, float1)
#endif

    float3 lightDir                      : TEXCOORD3;

#if defined(_NORMALMAP)
    #if SPECULAR_HIGHLIGHTS
        float3 tangentSpaceEyeVec        : TEXCOORD4;
    #endif
#else
    float3 normalWorld                   : TEXCOORD4;
#endif

#if defined(_OCCLUSION) || defined(_METALLICGLOSSMAP) || defined(_SPECGLOSSMAP)
    float4 texORM                       : TEXCOORD7;
#endif
#ifdef _EMISSION
    float2 texEmission                  : TEXCOORD8;
#endif
    float4 color                         : COLOR;
    float pointSize                     : PSIZE;

    UNITY_LIGHTING_COORDS(5, 6)

    UNITY_VERTEX_OUTPUT_STEREO
};

VertexOutputForwardAddSimple vertForwardAddSimple (VertexInput v)
{
    VertexOutputForwardAddSimple o;
    UNITY_SETUP_INSTANCE_ID(v);
    UNITY_INITIALIZE_OUTPUT(VertexOutputForwardAddSimple, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

    float4 posWorld = mul(unity_ObjectToWorld, v.vertex);
    o.pos = UnityObjectToClipPos(v.vertex);
    o.tex = TexCoords(v);
    o.posWorld = posWorld.xyz;

    //We need this for shadow receiving and lighting
    UNITY_TRANSFER_LIGHTING(o, v.uv1);

    float3 lightDir = _WorldSpaceLightPos0.xyz - posWorld.xyz * _WorldSpaceLightPos0.w;
    #ifndef USING_DIRECTIONAL_LIGHT
        lightDir = NormalizePerVertexNormal(lightDir);
    #endif

    #if SPECULAR_HIGHLIGHTS
        float3 eyeVec = normalize(posWorld.xyz - _WorldSpaceCameraPos);
    #endif

    float3 normalWorld = UnityObjectToWorldNormal(v.normal);

    #ifdef _NORMALMAP
        #if SPECULAR_HIGHLIGHTS
            TangentSpaceLightingInput(normalWorld, v.tangent, lightDir, eyeVec, o.lightDir, o.tangentSpaceEyeVec);
        #else
            float3 ignore;
            TangentSpaceLightingInput(normalWorld, v.tangent, lightDir, 0, o.lightDir, ignore);
        #endif
    #else
        o.lightDir = lightDir;
        o.normalWorld = normalWorld;
        #if SPECULAR_HIGHLIGHTS
            o.fogCoord.yzw = reflect(eyeVec, normalWorld);
        #endif
    #endif
    o.pointSize = 1;

    UNITY_TRANSFER_FOG(o,o.pos);
    return o;
}

FragmentCommonData FragmentSetupSimpleAdd(VertexOutputForwardAddSimple i)
{
    float alpha = Alpha(i.tex.xy);
    #if defined(_ALPHATEST_ON)
        clip (alpha - alphaCutoff);
    #endif
   
#if defined(_METALLICGLOSSMAP) || defined(_SPECGLOSSMAP)
    FragmentCommonData s = UNITY_SETUP_BRDF_INPUT (i.tex,i.texORM.zw,i.color);
#else
    FragmentCommonData s = UNITY_SETUP_BRDF_INPUT (i.tex,i.color);
#endif

    // NOTE: shader relies on pre-multiply alpha-blend (_SrcBlend = One, _DstBlend = OneMinusSrcAlpha)
    s.diffColor = PreMultiplyAlpha (s.diffColor, alpha, s.oneMinusReflectivity, /*out*/ s.alpha);

    s.eyeVec = 0;
    s.posWorld = i.posWorld;

    #ifdef _NORMALMAP
        s.tangentSpaceNormal = NormalInTangentSpace(i.tex);
        s.normalWorld = 0;
    #else
        s.tangentSpaceNormal = 0;
        s.normalWorld = i.normalWorld;
    #endif

    #if SPECULAR_HIGHLIGHTS && !defined(_NORMALMAP)
        s.reflUVW = i.fogCoord.yzw;
    #else
        s.reflUVW = 0;
    #endif

    return s;
}

float3 LightSpaceNormal(VertexOutputForwardAddSimple i, FragmentCommonData s)
{
    #ifdef _NORMALMAP
        return s.tangentSpaceNormal;
    #else
        return i.normalWorld;
    #endif
}

float4 fragForwardAddSimpleInternal (VertexOutputForwardAddSimple i)
{
    UNITY_APPLY_DITHER_CROSSFADE(i.pos.xy);

    FragmentCommonData s = FragmentSetupSimpleAdd(i);

    float3 c = BRDF3DirectSimple(s.diffColor, s.specColor, s.smoothness, dot(REFLECTVEC_FOR_SPECULAR(i, s), i.lightDir));

    #if SPECULAR_HIGHLIGHTS // else diffColor has premultiplied light color
        c *= _LightColor0.rgb;
    #endif

    UNITY_LIGHT_ATTENUATION(atten, i, s.posWorld)
    c *= atten * saturate(dot(LightSpaceNormal(i, s), i.lightDir));

    UNITY_APPLY_FOG_COLOR(i.fogCoord, c.rgb, float4(0,0,0,0)); // fog towards black in additive pass
    return OutputForward (float4(c, 1), s.alpha);
}

float4 fragForwardAddSimple (VertexOutputForwardAddSimple i) : SV_Target // backward compatibility (this used to be the fragment entry function)
{
    return fragForwardAddSimpleInternal(i);
}

#endif // UNITY_STANDARD_CORE_FORWARD_SIMPLE_INCLUDED
