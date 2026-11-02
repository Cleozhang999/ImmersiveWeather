import Observation
import RealityKit

/// Keeps a weather environment and any number of water surfaces in sync with
/// the current weather and water mood.
///
/// ```swift
/// @State private var weather = WeatherController(catalog: .prefixed("Meadow"))
///
/// RealityView { content in
///     content.add(weather.environment)
///     let pond = try? await WaterSurfaceEntity(size: [3, 3])
///     if let pond {
///         weather.attach(pond)
///         content.add(pond)
///     }
/// }
/// .task(id: weather.condition) { await weather.refreshEnvironment() }
///
/// Picker("Weather", selection: $weather.condition) { ... }
/// ```
@MainActor
@Observable
public final class WeatherController {
    public var condition: WeatherCondition {
        didSet { updateWater() }
    }

    public var mood: WaterMood {
        didSet { updateWater() }
    }

    /// Asset failures from the most recent `refreshEnvironment()`.
    public private(set) var loadFailures: [WeatherEnvironmentEntity.LoadFailure] = []

    @ObservationIgnored public let environment = WeatherEnvironmentEntity()
    @ObservationIgnored public var catalog: WeatherAssetCatalog
    @ObservationIgnored private var waterSurfaces: [WeakWater] = []

    public init(catalog: WeatherAssetCatalog, condition: WeatherCondition = .clearMorning, mood: WaterMood = .moderate) {
        self.catalog = catalog
        self.condition = condition
        self.mood = mood
    }

    /// The water parameters for the current condition and mood.
    public var waterParameters: WaterSurfaceParameters {
        .preset(for: mood, in: condition)
    }

    /// Starts driving `water` from this controller, and lights it with the environment.
    public func attach(_ water: WaterSurfaceEntity) {
        waterSurfaces.append(WeakWater(entity: water))
        water.surfaceParameters = waterParameters
        environment.receiveLighting(on: water)
    }

    /// Loads the sky, lighting and sound for the current condition.
    public func refreshEnvironment() async {
        loadFailures = await environment.apply(condition, from: catalog)
    }

    private func updateWater() {
        waterSurfaces.removeAll { $0.entity == nil }
        let parameters = waterParameters
        for surface in waterSurfaces {
            surface.entity?.surfaceParameters = parameters
        }
    }

    private struct WeakWater {
        weak var entity: WaterSurfaceEntity?
    }
}
