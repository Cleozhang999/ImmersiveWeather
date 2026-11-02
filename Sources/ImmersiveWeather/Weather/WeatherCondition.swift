/// The weather shown in an immersive scene.
public enum WeatherCondition: String, Sendable, Hashable, CaseIterable {
    case clearMorning
    case clearNight
    case foggy
    case rainy
    case snowy

    /// Whether something falls from the sky. Precipitation keeps the water surface busy with drops.
    public var hasPrecipitation: Bool {
        self == .rainy || self == .snowy
    }

    /// The suffix used by `WeatherAssetCatalog.prefixed(_:in:)` to name asset files.
    /// Snow reuses the rain assets.
    public var assetKey: String {
        switch self {
        case .clearMorning: "sunny_morning"
        case .clearNight: "sunny_night"
        case .foggy: "foggy"
        case .rainy, .snowy: "rainy"
        }
    }
}

/// How agitated a body of water looks, independent of the weather.
///
/// This was designed to mirror a user's mood in a meditation app, but works for any scene
/// that wants calm or restless water.
public enum WaterMood: String, Sendable, Hashable, CaseIterable {
    /// Still water with only gentle ambient waves.
    case peaceful
    /// Occasional ripples spreading out from the center.
    case moderate
    /// Frequent drops all over the surface.
    case turbulent
}
