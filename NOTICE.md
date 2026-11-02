# Third-party notices

## Apple sample code

Parts of these files are adapted from Apple's sample code [Generating interactive geometry with RealityKit](https://developer.apple.com/documentation/realitykit/generating-interactive-geometry-with-realitykit) (WWDC24):

- `Sources/WaterShaderTypes/include/WaterShaderTypes.h`
- `Sources/ImmersiveWeather/Shaders/Water.metal`: `deriveNormalsFromHeightMap`, `setVertexData`, `resetWaterSurface`, `disturbWaterSurface`, `updateWaterVelocity`, and the velocity integration in `updateWaterHeight`
- `Sources/ImmersiveWeather/Water/WaterSimulation.swift`: plane mesh construction and the simulation dispatch order

The ambient waves and Perlin noise, drop scheduling, weather presets, environment loading and public API are original to this package.

That code is distributed under the following license, reproduced from the sample's `LICENSE.txt`:

```text
Copyright © 2024 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
