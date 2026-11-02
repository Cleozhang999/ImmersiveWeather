/*
 Portions of this file are derived from Apple sample code. See NOTICE.md.

 The plane mesh, height map and ripple simulation follow the Apple sample's
 HeightMapMesh / WaterSurfaceHeightMapGenerator design, merged into one type.
 Ambient waves, drop scheduling and the RealityKit system wiring were added here.
*/

import Metal
import RealityKit
import WaterShaderTypes

enum WaterError: Error {
    case metalUnavailable
    case shaderLibraryMissing
}

/// Device, queue and pipelines shared by every water surface.
@MainActor
final class WaterGPU {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let deriveNormals: MTLComputePipelineState
    let setVertexData: MTLComputePipelineState
    let reset: MTLComputePipelineState
    let disturb: MTLComputePipelineState
    let updateVelocity: MTLComputePipelineState
    let updateHeight: MTLComputePipelineState

    private static var cached: WaterGPU?

    static func shared() throws -> WaterGPU {
        if let cached { return cached }
        let gpu = try WaterGPU()
        cached = gpu
        return gpu
    }

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw WaterError.metalUnavailable
        }
        queue.label = "ImmersiveWeather"
        guard let library = try? device.makeDefaultLibrary(bundle: .module) else {
            throw WaterError.shaderLibraryMissing
        }
        func pipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let function = library.makeFunction(name: name) else { throw WaterError.shaderLibraryMissing }
            return try device.makeComputePipelineState(function: function)
        }
        self.device = device
        self.queue = queue
        deriveNormals = try pipeline("deriveNormalsFromHeightMap")
        setVertexData = try pipeline("setVertexData")
        reset = try pipeline("resetWaterSurface")
        disturb = try pipeline("disturbWaterSurface")
        updateVelocity = try pipeline("updateWaterVelocity")
        updateHeight = try pipeline("updateWaterHeight")
    }
}

/// A water surface simulated on a height map that drives a plane mesh in the XY plane.
@MainActor
final class WaterSimulation {
    /// Propagation speed of ripples across the surface.
    private static let rippleSpeed: Float = 0.2
    /// Simulation substeps per frame, for stability.
    private static let substeps = 5

    let mesh: LowLevelMesh
    let size: SIMD2<Float>
    let dimensions: SIMD2<UInt32>
    let cellSize: SIMD2<Float>
    var parameters: WaterSurfaceParameters

    private let gpu: WaterGPU
    private let heightMap: LowLevelTexture
    private let velocityMap: LowLevelTexture
    private var meshParams: MeshParams
    private let threadgroups: MTLSize
    private let threadsPerThreadgroup: MTLSize
    private var time: Float = 0
    private var needsReset = true
    private var pendingDisturbances: [(position: SIMD2<Float>, radius: Float, amount: Float)] = []

    init(size: SIMD2<Float>, dimensions: SIMD2<UInt32>, maxDepth: Float, parameters: WaterSurfaceParameters) throws {
        precondition(dimensions.x >= 2 && dimensions.y >= 2, "The water surface needs at least 2 cells in each dimension.")
        gpu = try WaterGPU.shared()
        self.size = size
        self.dimensions = dimensions
        self.cellSize = size / SIMD2<Float>(Float(dimensions.x - 1), Float(dimensions.y - 1))
        self.parameters = parameters
        meshParams = MeshParams(dimensions: dimensions, size: size, maxVertexDepth: maxDepth)

        mesh = try Self.makePlaneMesh(size: size, dimensions: dimensions, maxDepth: maxDepth)
        heightMap = try LowLevelTexture(descriptor: .init(
            pixelFormat: .rgba32Float, width: Int(dimensions.x), height: Int(dimensions.y),
            textureUsage: [.shaderRead, .shaderWrite]))
        velocityMap = try LowLevelTexture(descriptor: .init(
            pixelFormat: .r32Float, width: Int(dimensions.x), height: Int(dimensions.y),
            textureUsage: [.shaderRead, .shaderWrite]))

        let width = gpu.setVertexData.threadExecutionWidth
        let height = gpu.setVertexData.maxTotalThreadsPerThreadgroup / width
        threadsPerThreadgroup = MTLSize(width: width, height: height, depth: 1)
        threadgroups = MTLSize(width: (Int(dimensions.x) + width - 1) / width,
                               height: (Int(dimensions.y) + height - 1) / height,
                               depth: 1)
    }

    func reset() {
        needsReset = true
    }

    /// Queues a disturbance for the next frame. `position` is in plane coordinates (meters, centered).
    func disturb(at position: SIMD2<Float>, radiusInCells: Float, heightInCells: Float) {
        pendingDisturbances.append((position, radiusInCells * cellSize.x, -heightInCells * cellSize.x))
    }

    /// Probability that a drop lands during a frame of length `deltaTime`.
    nonisolated static func dropProbability(dropsPerSecond: Float, deltaTime: Float) -> Float {
        guard dropsPerSecond > 0, deltaTime > 0 else { return 0 }
        return 1 - exp(-dropsPerSecond * deltaTime)
    }

    func encode(deltaTime: Float, commandBuffer: MTLCommandBuffer, encoder: MTLComputeCommandEncoder) {
        time += deltaTime

        var params = WaterParams(
            // Clamp so the simulation stays stable through frame hitches.
            deltaTime: min(deltaTime, cellSize.x / Self.rippleSpeed),
            waterSpeed: Self.rippleSpeed,
            disturbancePosition: [.infinity, .infinity],
            disturbanceRadius: 0,
            disturbanceAmount: 0,
            dimensions: dimensions,
            size: size,
            cellSize: cellSize,
            waveTime: time,
            waveAmplitude: parameters.waveAmplitude,
            waveSpeed: parameters.waveSpeed,
            wavelength: parameters.wavelength
        )

        if needsReset {
            needsReset = false
            dispatch(gpu.reset, encoder, &params, textures: [
                heightMap.replace(using: commandBuffer), velocityMap.replace(using: commandBuffer),
            ])
        }

        if Float.random(in: 0..<1) < Self.dropProbability(dropsPerSecond: parameters.dropsPerSecond, deltaTime: deltaTime) {
            let position: SIMD2<Float> = parameters.dropsAtRandomPositions
                ? [Float.random(in: -size.x / 2...size.x / 2), Float.random(in: -size.y / 2...size.y / 2)]
                : .zero
            disturb(at: position, radiusInCells: parameters.dropRadius, heightInCells: parameters.dropHeight)
        }
        for disturbance in pendingDisturbances {
            params.disturbancePosition = disturbance.position
            params.disturbanceRadius = disturbance.radius
            params.disturbanceAmount = disturbance.amount
            dispatch(gpu.disturb, encoder, &params, textures: [
                heightMap.read(), heightMap.replace(using: commandBuffer),
            ])
        }
        pendingDisturbances.removeAll()

        params.deltaTime /= Float(Self.substeps)
        for _ in 0..<Self.substeps {
            dispatch(gpu.updateVelocity, encoder, &params, textures: [
                heightMap.read(), velocityMap.read(), velocityMap.replace(using: commandBuffer),
            ])
            dispatch(gpu.updateHeight, encoder, &params, textures: [
                velocityMap.read(), heightMap.read(), heightMap.replace(using: commandBuffer),
            ])
        }

        // Normals from the final heights, then copy everything into the mesh.
        var cellSize = cellSize
        encoder.setComputePipelineState(gpu.deriveNormals)
        encoder.setTexture(heightMap.read(), index: 0)
        encoder.setTexture(heightMap.replace(using: commandBuffer), index: 1)
        encoder.setBytes(&cellSize, length: MemoryLayout<SIMD2<Float>>.size, index: 2)
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)

        encoder.setComputePipelineState(gpu.setVertexData)
        encoder.setBytes(&meshParams, length: MemoryLayout<MeshParams>.size, index: 0)
        encoder.setBuffer(mesh.replace(bufferIndex: 0, using: commandBuffer), offset: 0, index: 1)
        encoder.setTexture(heightMap.read(), index: 2)
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
    }

    /// Dispatches a water kernel that takes `WaterParams` at buffer 0 and textures from index 1.
    private func dispatch(_ pipeline: MTLComputePipelineState, _ encoder: MTLComputeCommandEncoder,
                          _ params: inout WaterParams, textures: [MTLTexture]) {
        encoder.setComputePipelineState(pipeline)
        encoder.setBytes(&params, length: MemoryLayout<WaterParams>.size, index: 0)
        for (offset, texture) in textures.enumerated() {
            encoder.setTexture(texture, index: offset + 1)
        }
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
    }

    /// A flat grid in the XY plane, centered on the origin, with heights along +Z.
    private static func makePlaneMesh(size: SIMD2<Float>, dimensions: SIMD2<UInt32>, maxDepth: Float) throws -> LowLevelMesh {
        let vertexCount = Int(dimensions.x * dimensions.y)
        let indexCount = 6 * Int((dimensions.x - 1) * (dimensions.y - 1))
        let descriptor = LowLevelMesh.Descriptor(
            vertexCapacity: vertexCount,
            vertexAttributes: [
                .init(semantic: .position, format: .float3, offset: MemoryLayout<PlaneVertex>.offset(of: \.position)!),
                .init(semantic: .normal, format: .float3, offset: MemoryLayout<PlaneVertex>.offset(of: \.normal)!),
            ],
            vertexLayouts: [.init(bufferIndex: 0, bufferStride: MemoryLayout<PlaneVertex>.stride)],
            indexCapacity: indexCount
        )
        let mesh = try LowLevelMesh(descriptor: descriptor)

        mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
            let vertices = rawBytes.bindMemory(to: PlaneVertex.self)
            for y in 0..<dimensions.y {
                for x in 0..<dimensions.x {
                    let uv = SIMD2<Float>(Float(x) / Float(dimensions.x - 1), Float(y) / Float(dimensions.y - 1))
                    let xy = size * uv - size / 2
                    vertices[Int(x + dimensions.x * y)] = PlaneVertex(position: [xy.x, xy.y, 0], normal: [0, 0, 1])
                }
            }
        }

        mesh.withUnsafeMutableIndices { rawIndices in
            let indices = rawIndices.bindMemory(to: UInt32.self)
            var i = 0
            for y in 0..<dimensions.y - 1 {
                for x in 0..<dimensions.x - 1 {
                    let bottomLeft = x + dimensions.x * y
                    let bottomRight = bottomLeft + 1
                    let topLeft = bottomLeft + dimensions.x
                    let topRight = topLeft + 1
                    // Two counterclockwise triangles per cell.
                    for index in [bottomLeft, bottomRight, topLeft, topLeft, bottomRight, topRight] {
                        indices[i] = index
                        i += 1
                    }
                }
            }
        }

        mesh.parts.replaceAll([LowLevelMesh.Part(
            indexCount: indexCount,
            topology: .triangle,
            bounds: BoundingBox(min: [-size.x / 2, -size.y / 2, 0], max: [size.x / 2, size.y / 2, maxDepth])
        )])
        return mesh
    }
}

/// Links an entity to its water simulation. Added by `WaterSurfaceEntity`.
struct WaterSimulationComponent: Component {
    let simulation: WaterSimulation
}

/// Steps every water simulation in the scene, batching them into one command buffer per frame.
@MainActor
final class WaterSimulationSystem: System {
    private static let query = EntityQuery(where: .has(WaterSimulationComponent.self))
    private static var isRegistered = false

    static func registerIfNeeded() {
        guard !isRegistered else { return }
        isRegistered = true
        WaterSimulationComponent.registerComponent()
        registerSystem()
    }

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        let entities = context.entities(matching: Self.query, updatingSystemWhen: .rendering)
        var commandBuffer: MTLCommandBuffer?
        var encoder: MTLComputeCommandEncoder?
        for entity in entities {
            guard let simulation = entity.components[WaterSimulationComponent.self]?.simulation else { continue }
            if encoder == nil {
                commandBuffer = try? WaterGPU.shared().queue.makeCommandBuffer()
                encoder = commandBuffer?.makeComputeCommandEncoder()
            }
            guard let commandBuffer, let encoder else { return }
            simulation.encode(deltaTime: Float(context.deltaTime), commandBuffer: commandBuffer, encoder: encoder)
        }
        encoder?.endEncoding()
        commandBuffer?.commit()
    }
}
