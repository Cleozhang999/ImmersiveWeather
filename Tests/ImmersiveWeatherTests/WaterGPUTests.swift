import Metal
import RealityKit
import Testing
import WaterShaderTypes
@testable import ImmersiveWeather

/// Runs the water simulation on the GPU and checks the mesh it produces.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "Needs a Metal device"))
struct WaterGPUTests {
    private func step(_ simulation: WaterSimulation, frames: Int) throws {
        let queue = try WaterGPU.shared().queue
        for _ in 0..<frames {
            let commandBuffer = try #require(queue.makeCommandBuffer())
            let encoder = try #require(commandBuffer.makeComputeCommandEncoder())
            simulation.encode(deltaTime: 1 / 90, commandBuffer: commandBuffer, encoder: encoder)
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
    }

    private func vertices(_ simulation: WaterSimulation) -> [PlaneVertex] {
        var result: [PlaneVertex] = []
        simulation.mesh.withUnsafeBytes(bufferIndex: 0) { result = Array($0.bindMemory(to: PlaneVertex.self)) }
        return result
    }

    @Test func calmWaterStaysFlatAndInBounds() throws {
        var still = WaterSurfaceParameters.preset(for: .peaceful)
        still.waveAmplitude = 0
        let simulation = try WaterSimulation(size: [2, 2], dimensions: [32, 32], maxDepth: 0.2, parameters: still)
        try step(simulation, frames: 10)

        let vertices = vertices(simulation)
        #expect(vertices.count == 32 * 32)
        for vertex in vertices {
            #expect(abs(vertex.position.z - 0.01) < 1e-4)
            #expect(abs(vertex.normal.z - 1) < 1e-4)
        }
        // Grid covers the requested size.
        #expect(abs(vertices.first!.position.x + 1) < 1e-5 && abs(vertices.last!.position.y - 1) < 1e-5)
    }

    @Test func dropMakesARippleThatSpreads() throws {
        var still = WaterSurfaceParameters.preset(for: .peaceful)
        still.waveAmplitude = 0
        let simulation = try WaterSimulation(size: [2, 2], dimensions: [64, 64], maxDepth: 0.2, parameters: still)
        try step(simulation, frames: 1)
        simulation.disturb(at: .zero, radiusInCells: 4, heightInCells: 3)
        try step(simulation, frames: 1)

        func height(_ vertices: [PlaneVertex], x: Int, y: Int) -> Float { vertices[x + 64 * y].position.z }
        let afterDrop = vertices(simulation)
        #expect(height(afterDrop, x: 32, y: 32) > 0.05, "center lifted")
        #expect(abs(height(afterDrop, x: 5, y: 5) - 0.01) < 1e-4, "far corner untouched")
        // 6 cells out is beyond the 4-cell drop radius.
        #expect(abs(height(afterDrop, x: 32, y: 38) - 0.01) < 1e-6, "outside the drop untouched")

        try step(simulation, frames: 60)
        let later = vertices(simulation)
        #expect(height(later, x: 32, y: 32) < height(afterDrop, x: 32, y: 32), "center settles")
        // Ripples travel at 0.2 m/s: about 4 cells (2/63 m each) in 60 frames, past the 6-cell mark.
        #expect(abs(height(later, x: 32, y: 38) - 0.01) > 1e-4, "ripple spread past the drop")
        for vertex in later {
            #expect(vertex.position.z >= 0 && vertex.position.z <= 0.2)
            #expect(vertex.position.z.isFinite && abs(simd_length(vertex.normal) - 1) < 1e-3)
        }
    }

    @Test func ambientWavesMoveTheSurface() throws {
        let simulation = try WaterSimulation(size: [2, 2], dimensions: [32, 32], maxDepth: 0.2,
                                             parameters: .init(waveAmplitude: 0.001))
        try step(simulation, frames: 30)
        let heights = vertices(simulation).map(\.position.z)
        #expect((heights.max()! - heights.min()!) > 1e-4)
    }

    @Test func entityLiesFlatFacingUp() async throws {
        let water = try await WaterSurfaceEntity(size: [2, 4])
        let surface = try #require(water.children.first)
        let bounds = surface.visualBounds(relativeTo: water)
        #expect(abs(bounds.extents.x - 2) < 1e-3)
        #expect(abs(bounds.extents.z - 4) < 1e-3)
        #expect(bounds.min.y >= -1e-3)
    }
}
