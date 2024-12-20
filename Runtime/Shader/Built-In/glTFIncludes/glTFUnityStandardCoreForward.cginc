// SPDX-FileCopyrightText: 2023 Unity Technologies and the glTFast authors
// SPDX-License-Identifier: Apache-2.0

// Based on Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)


#ifndef UNITY_STANDARD_CORE_FORWARD_INCLUDED
#define UNITY_STANDARD_CORE_FORWARD_INCLUDED

#if defined(UNITY_NO_FULL_STANDARD_SHADER)
#   define UNITY_STANDARD_SIMPLE 1
#endif

#include "UnityStandardConfig.cginc"

#if UNITY_STANDARD_SIMPLE
    #include "glTFUnityStandardCoreForwardSimple.cginc"
    VertexOutputBaseSimple vertBase (VertexInput v) { return vertForwardBaseSimple(v); }
    VertexOutputForwardAddSimple vertAdd (VertexInput v) { return vertForwardAddSimple(v); }
    float4 fragBase (VertexOutputBaseSimple i) : SV_Target { return fragForwardBaseSimpleInternal(i); }
    float4 fragAdd (VertexOutputForwardAddSimple i) : SV_Target { return fragForwardAddSimpleInternal(i); }

    float4 fragBaseFacing (VertexOutputBaseSimple i, half facing : VFACE) : SV_Target
    {
        i.normalWorld.xyz *= facing;
#ifdef _NORMALMAP
        i.tangentSpaceLightDir *= facing;
    #if SPECULAR_HIGHLIGHTS
        i.tangentSpaceEyeVec *= facing;
    #endif
#endif
        return fragBase(i);
    }
    half4 fragAddFacing (VertexOutputForwardAddSimple i, half facing : VFACE) : SV_Target {
#if defined(_NORMALMAP)
    #if SPECULAR_HIGHLIGHTS
        i.tangentSpaceEyeVec *= facing;
    #endif
#else
        i.normalWorld *= facing;
#endif
        return fragAdd(i);
    }
#else
    #include "glTFUnityStandardCore.cginc"
    VertexOutputForwardBase vertBase (VertexInput v) { return vertForwardBase(v); }
    VertexOutputForwardAdd vertAdd (VertexInput v) { return vertForwardAdd(v); }
    float4 fragBase (VertexOutputForwardBase i) : SV_Target { return fragForwardBaseInternal(i); }
    float4 fragAdd (VertexOutputForwardAdd i) : SV_Target { return fragForwardAddInternal(i); }

    float4 fragBaseFacing (VertexOutputForwardBase i, half facing : VFACE) : SV_Target
    {
#ifdef _TANGENT_TO_WORLD
        i.tangentToWorldAndPackedData[0].xyz = normalize(i.tangentToWorldAndPackedData[0].xyz) * facing;
        i.tangentToWorldAndPackedData[1].xyz = normalize(i.tangentToWorldAndPackedData[1].xyz) * facing;
#endif
        i.tangentToWorldAndPackedData[2].xyz = normalize(i.tangentToWorldAndPackedData[2].xyz) * facing;
        return fragBase(i);
    }
    float4 fragAddFacing (VertexOutputForwardAdd i, half facing : VFACE) : SV_Target {
#ifdef _TANGENT_TO_WORLD
        i.tangentToWorldAndLightDir[0].xyz = normalize(i.tangentToWorldAndLightDir[0].xyz) * facing;
        i.tangentToWorldAndLightDir[1].xyz = normalize(i.tangentToWorldAndLightDir[1].xyz) * facing;
#endif
        i.tangentToWorldAndLightDir[2].xyz = normalize(i.tangentToWorldAndLightDir[2].xyz) * facing;
        return fragAdd(i);
    }
#endif

#endif // UNITY_STANDARD_CORE_FORWARD_INCLUDED
