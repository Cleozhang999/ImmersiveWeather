/// Everything that controls how a `WaterSurfaceEntity` moves and looks.
public struct WaterSurfaceParameters: Sendable, Equatable {
    // MARK: Ambient waves

    /// Height of the ambient waves. Small values (around 0.0001) already read as gentle motion.
    public var waveAmplitude: Float
    /// How fast the ambient waves travel.
    public var waveSpeed: Float
    /// Number of wave crests across the surface. Higher values give a finer pattern.
    public var wavelength: Float

    // MARK: Drops

    /// Average number of drops hitting the surface per second. 0 disables drops.
    /// At most one drop lands per frame.
    public var dropsPerSecond: Float
    /// Radius of each drop, in simulation cells.
    public var dropRadius: Float
    /// How far each drop lifts the surface, in simulation cells. Negative values push it down.
    public var dropHeight: Float
    /// Whether drops land anywhere on the surface. When `false`, they all land in the center,
    /// which gives concentric rings.
    public var dropsAtRandomPositions: Bool

    // MARK: Material

    public var roughness: Float
    public var clearcoat: Float

    public init(
        waveAmplitude: Float = 0.0001,
        waveSpeed: Float = 2,
        wavelength: Float = 10,
        dropsPerSecond: Float = 0,
        dropRadius: Float = 1,
        dropHeight: Float = 2,
        dropsAtRandomPositions: Bool = false,
        roughness: Float = 0.05,
        clearcoat: Float = 1
    ) {
        self.waveAmplitude = waveAmplitude
        self.waveSpeed = waveSpeed
        self.wavelength = wavelength
        self.dropsPerSecond = dropsPerSecond
        self.dropRadius = dropRadius
        self.dropHeight = dropHeight
        self.dropsAtRandomPositions = dropsAtRandomPositions
        self.roughness = roughness
        self.clearcoat = clearcoat
    }

    /// The water for a mood in dry weather.
    public static func preset(for mood: WaterMood) -> WaterSurfaceParameters {
        switch mood {
        case .peaceful:
            WaterSurfaceParameters(dropsPerSecond: 0, dropHeight: 2, roughness: 0.03, clearcoat: 0.8)
        case .moderate:
            WaterSurfaceParameters(dropsPerSecond: 2.7, dropHeight: 10, roughness: 0.05, clearcoat: 1)
        case .turbulent:
            WaterSurfaceParameters(dropsPerSecond: 72, dropHeight: 2, dropsAtRandomPositions: true, roughness: 0.08, clearcoat: 1)
        }
    }

    /// The water for a mood under the given weather. Rain and snow override the mood's
    /// drops with a steady shower across the whole surface.
    public static func preset(for mood: WaterMood, in condition: WeatherCondition) -> WaterSurfaceParameters {
        var parameters = preset(for: mood)
        if condition.hasPrecipitation {
            parameters.dropsPerSecond = 90
            parameters.dropsAtRandomPositions = true
        }
        return parameters
    }
}
