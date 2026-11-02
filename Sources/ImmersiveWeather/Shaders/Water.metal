/*
 Portions of this file are derived from Apple sample code. See NOTICE.md.

 Compute kernels for a height-map water surface:
 - a shallow-water ripple simulation (from the Apple sample), and
 - layered sine waves plus Perlin noise for ambient motion (added by this package).

 The height map stores the surface normal in RGB and the height in A.
 The plane lies in XY with heights along +Z; `WaterSurfaceEntity` rotates it to be Y-up.
*/

#include <metal_stdlib>
using namespace metal;

#include "../../WaterShaderTypes/include/WaterShaderTypes.h"

static float remap(float value, float2 fromRange, float2 toRange) {
    return toRange.x + (value - fromRange.x) * (toRange.y - toRange.x) / (fromRange.y - fromRange.x);
}

// MARK: - Height map mesh

/// Derives normal directions from the heights, storing them in the texture's RGB channels.
[[kernel]]
void deriveNormalsFromHeightMap(texture2d<float, access::read> heightMapIn [[texture(0)]],
                                texture2d<float, access::write> heightMapOut [[texture(1)]],
                                constant float2 &cellSize [[buffer(2)]],
                                uint2 pixelCoords [[thread_position_in_grid]]) {
    uint2 dimensions = uint2(heightMapIn.get_width(), heightMapIn.get_height());
    if (any(pixelCoords >= dimensions)) { return; }

    uint2 minusOne = max(pixelCoords, 1) - 1;
    uint2 plusOne = min(pixelCoords + 1, dimensions - 1);

    float height = heightMapIn.read(pixelCoords).a;
    float left = heightMapIn.read(uint2(minusOne.x, pixelCoords.y)).a;
    float right = heightMapIn.read(uint2(plusOne.x, pixelCoords.y)).a;
    float bottom = heightMapIn.read(uint2(pixelCoords.x, minusOne.y)).a;
    float top = heightMapIn.read(uint2(pixelCoords.x, plusOne.y)).a;

    float3 normal = normalize(float3((left - right) / (cellSize.x * 2),
                                     (bottom - top) / (cellSize.y * 2),
                                     1));
    heightMapOut.write(float4(normal, height), pixelCoords);
}

/// Sets vertex positions and normals from the height map.
[[kernel]]
void setVertexData(constant MeshParams &params [[buffer(0)]],
                   device PlaneVertex *vertices [[buffer(1)]],
                   texture2d<float, access::read> heightMap [[texture(2)]],
                   uint2 vertexCoords [[thread_position_in_grid]]) {
    if (any(vertexCoords >= params.dimensions)) { return; }

    device PlaneVertex &vert = vertices[vertexCoords.x + params.dimensions.x * vertexCoords.y];
    float4 data = heightMap.read(vertexCoords);

    float2 coords01 = float2(vertexCoords) / float2(params.dimensions - 1);
    float2 xy = params.size * coords01 - params.size / 2;
    vert.position = float3(xy, clamp(data.a, 0., params.maxVertexDepth));
    vert.normal = data.rgb;
}

// MARK: - Water simulation

/// Zeroes the velocity and sets the water slightly above zero, leaving room for downward ripples.
[[kernel]]
void resetWaterSurface(constant WaterParams &params [[buffer(0)]],
                       texture2d<float, access::write> heightMap [[texture(1)]],
                       texture2d<float, access::write> velocityMap [[texture(2)]],
                       uint2 pixelCoords [[thread_position_in_grid]]) {
    if (any(pixelCoords >= params.dimensions)) { return; }
    heightMap.write(float4(0, 0, 1, 0.01), pixelCoords);
    velocityMap.write(0, pixelCoords);
}

/// Pushes the surface up or down around `disturbancePosition` with a quadratic falloff.
[[kernel]]
void disturbWaterSurface(constant WaterParams &params [[buffer(0)]],
                         texture2d<float, access::read> heightMapIn [[texture(1)]],
                         texture2d<float, access::write> heightMapOut [[texture(2)]],
                         uint2 pixelCoords [[thread_position_in_grid]]) {
    if (any(pixelCoords >= params.dimensions)) { return; }

    float4 data = heightMapIn.read(pixelCoords);
    float2 position = float2(
        remap(pixelCoords.x, float2(0, params.dimensions.x - 1), float2(-params.size.x / 2, params.size.x / 2)),
        remap(pixelCoords.y, float2(0, params.dimensions.y - 1), float2(-params.size.y / 2, params.size.y / 2)));
    float distance = length(position - params.disturbancePosition);
    if (distance <= params.disturbanceRadius) {
        float falloff = (params.disturbanceRadius - distance) / params.disturbanceRadius;
        data.a -= params.disturbanceAmount * falloff * falloff;
    }
    heightMapOut.write(data, pixelCoords);
}

/// Accelerates water towards neighboring cells that are higher, and away from ones that are lower.
[[kernel]]
void updateWaterVelocity(constant WaterParams &params [[buffer(0)]],
                         texture2d<float, access::read> heightMapIn [[texture(1)]],
                         texture2d<float, access::read> velocityMapIn [[texture(2)]],
                         texture2d<float, access::write> velocityMapOut [[texture(3)]],
                         uint2 pixelCoords [[thread_position_in_grid]]) {
    if (any(pixelCoords >= params.dimensions)) { return; }

    uint2 minusOne = max(uint2(1), pixelCoords) - 1;
    uint2 plusOne = min(pixelCoords + 1, params.dimensions - 1);
    float height = heightMapIn.read(pixelCoords).a;
    float left = heightMapIn.read(uint2(minusOne.x, pixelCoords.y)).a;
    float right = heightMapIn.read(uint2(plusOne.x, pixelCoords.y)).a;
    float bottom = heightMapIn.read(uint2(pixelCoords.x, minusOne.y)).a;
    float top = heightMapIn.read(uint2(pixelCoords.x, plusOne.y)).a;

    float speedFactor = (params.waterSpeed * params.waterSpeed) / (params.cellSize.x * params.cellSize.y);
    float acceleration = speedFactor * (left + right + bottom + top - 4.0 * height);

    float velocity = velocityMapIn.read(pixelCoords).r + acceleration * params.deltaTime;
    velocityMapOut.write(0.9975 * velocity, pixelCoords);  // Damping.
}

static float2 random2(float2 p) {
    return fract(sin(float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)))) * 43758.5453);
}

/// Gradient noise in [0, 1].
static float perlinNoise(float2 p) {
    float2 cell = floor(p);
    float2 f = fract(p);
    float2 w = f * f * (3.0 - 2.0 * f);

    float n00 = dot(random2(cell + float2(0, 0)) * 2.0 - 1.0, f - float2(0, 0));
    float n01 = dot(random2(cell + float2(0, 1)) * 2.0 - 1.0, f - float2(0, 1));
    float n10 = dot(random2(cell + float2(1, 0)) * 2.0 - 1.0, f - float2(1, 0));
    float n11 = dot(random2(cell + float2(1, 1)) * 2.0 - 1.0, f - float2(1, 1));

    return mix(mix(n00, n10, w.x), mix(n01, n11, w.x), w.y) * 0.5 + 0.5;
}

/// Integrates the velocity into the height and adds ambient waves.
///
/// The ambient motion is four sine waves at different frequencies and directions,
/// blended with two drifting octaves of Perlin noise so the pattern never visibly repeats.
[[kernel]]
void updateWaterHeight(constant WaterParams &params [[buffer(0)]],
                       texture2d<float, access::read> velocityMap [[texture(1)]],
                       texture2d<float, access::read> heightMapIn [[texture(2)]],
                       texture2d<float, access::write> heightMapOut [[texture(3)]],
                       uint2 pixelCoords [[thread_position_in_grid]]) {
    if (any(pixelCoords >= params.dimensions)) { return; }

    float4 data = heightMapIn.read(pixelCoords);
    float height = data.a + velocityMap.read(pixelCoords).r * params.deltaTime;

    float2 uv = float2(pixelCoords) / float2(params.dimensions);
    float t = params.waveTime * params.waveSpeed;
    float k = params.wavelength * M_PI_F;
    float wave = sin(-uv.y * k + t)
               + sin(-uv.y * k * 0.33 + t * 1.1)
               + sin(uv.x * k * 0.5 + t * 0.7)
               + sin(uv.x * k * 0.25 + t * 1.3);

    float noise1 = perlinNoise(float2(uv.y + params.waveTime * 0.1, uv.x) * 10.0) * 2.0 - 1.0;
    float noise2 = perlinNoise(float2(uv.y - params.waveTime * 0.05, uv.x + params.waveTime * 0.07) * 15.0) * 2.0 - 1.0;
    float noise = noise1 * 0.7 + noise2 * 0.3;

    height += (wave * 0.5 + noise * 0.5) * params.waveAmplitude * 0.5;

    // Normals are recomputed by `deriveNormalsFromHeightMap` afterwards.
    heightMapOut.write(float4(data.rgb, height), pixelCoords);
}
