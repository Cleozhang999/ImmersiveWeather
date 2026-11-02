/*
 Portions of this file are derived from Apple sample code. See NOTICE.md.

 Structures shared between Swift and the Metal compute shaders.
*/

#pragma once

#include <simd/simd.h>

/// One vertex of the height map plane mesh.
struct PlaneVertex {
    simd_float3 position;
    simd_float3 normal;
};

/// Describes the plane mesh to the vertex compute shader.
struct MeshParams {
    simd_uint2 dimensions;
    simd_float2 size;
    float maxVertexDepth;
};

/// Parameters for one step of the water surface simulation.
struct WaterParams {
    float deltaTime;
    /// Propagation speed of ripples.
    float waterSpeed;
    simd_float2 disturbancePosition;
    float disturbanceRadius;
    float disturbanceAmount;
    simd_uint2 dimensions;
    simd_float2 size;
    simd_float2 cellSize;

    /// Seconds since the simulation started; drives the ambient waves.
    float waveTime;
    float waveAmplitude;
    float waveSpeed;
    float wavelength;
};
