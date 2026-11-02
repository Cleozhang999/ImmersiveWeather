import RealityKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A rectangular, GPU-simulated water surface lying in the XZ plane, facing +Y.
///
/// It combines a ripple simulation with ambient waves. Ripples come from drops, scheduled
/// by `surfaceParameters`, and from `disturb(atLocal:)`, which you can call from a gesture.
///
/// ```swift
/// let pond = try await WaterSurfaceEntity(size: [3, 3])
/// pond.surfaceParameters = .preset(for: .moderate, in: .rainy)
/// content.add(pond)
/// ```
@MainActor
public final class WaterSurfaceEntity: Entity {
    /// Motion and material settings. Changes take effect on the next frame.
    public var surfaceParameters: WaterSurfaceParameters {
        get { simulation?.parameters ?? .init() }
        set {
            simulation?.parameters = newValue
            updateMaterial()
        }
    }

    /// Base color and opacity of the water.
    public var tint: RealityKit.Material.Color = .init(red: 0.2, green: 0.5, blue: 0.7, alpha: 1) {
        didSet { updateMaterial() }
    }

    public var opacity: Float = 0.5 {
        didSet { updateMaterial() }
    }

    /// The width (X) and depth (Z) of the surface in meters.
    public var size: SIMD2<Float> { simulation?.size ?? .zero }

    private var simulation: WaterSimulation?
    private let surface = ModelEntity()

    /// Creates a water surface.
    ///
    /// - Parameters:
    ///   - size: Width (X) and depth (Z) in meters.
    ///   - resolution: Simulation cells along each side. Higher looks smoother and costs more GPU time.
    ///   - maxWaveHeight: Highest the surface can rise, in meters. Used for culling bounds.
    ///   - parameters: Initial motion and material settings.
    public init(
        size: SIMD2<Float> = [2, 2],
        resolution: SIMD2<UInt32> = [128, 128],
        maxWaveHeight: Float = 0.2,
        parameters: WaterSurfaceParameters = .preset(for: .moderate)
    ) async throws {
        super.init()
        WaterSimulationSystem.registerIfNeeded()

        let simulation = try WaterSimulation(size: size, dimensions: resolution, maxDepth: maxWaveHeight, parameters: parameters)
        self.simulation = simulation

        // The simulation works in the XY plane with heights along +Z. Rotate it to lie flat with +Y up.
        surface.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        surface.model = ModelComponent(mesh: try await MeshResource(from: simulation.mesh), materials: [])
        surface.components.set(WaterSimulationComponent(simulation: simulation))
        addChild(surface)
        updateMaterial()
    }

    /// Creates an empty entity with no water.
    public required init() {
        super.init()
    }

    /// Makes a ripple at a point given in this entity's local space. Only X and Z are used.
    ///
    /// - Parameters:
    ///   - radius: Radius of the ripple, in simulation cells.
    ///   - height: How far to lift the surface, in simulation cells. Negative values push it down.
    public func disturb(atLocal point: SIMD3<Float>, radius: Float = 7, height: Float = -3) {
        // Local +Z maps to the simulation's -Y after the rotation above.
        simulation?.disturb(at: [point.x, -point.z], radiusInCells: radius, heightInCells: height)
    }

    /// Flattens the surface and stops all ripples.
    public func reset() {
        simulation?.reset()
    }

    private func updateMaterial() {
        guard simulation != nil else { return }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint)
        material.roughness = .init(floatLiteral: surfaceParameters.roughness)
        material.clearcoat = .init(floatLiteral: surfaceParameters.clearcoat)
        material.metallic = 0.0
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        surface.model?.materials = [material]
    }
}
