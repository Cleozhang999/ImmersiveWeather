import Foundation

/// Resource file names for one weather condition. A `nil` name skips that part.
public struct WeatherAssetNames: Sendable, Equatable {
    /// An equirectangular image (PNG, JPEG, ...) shown as the sky.
    public var skybox: String?
    /// An equirectangular image, ideally HDR, used for image-based lighting.
    public var imageBasedLight: String?
    /// A looping ambient sound, such as rain.
    public var ambientAudio: String?

    public init(skybox: String? = nil, imageBasedLight: String? = nil, ambientAudio: String? = nil) {
        self.skybox = skybox
        self.imageBasedLight = imageBasedLight
        self.ambientAudio = ambientAudio
    }
}

/// Maps each weather condition to resource files in a bundle.
///
/// The package ships no images or sounds; bring your own and describe where they are here.
public struct WeatherAssetCatalog: Sendable {
    public var bundle: Bundle
    public var names: @Sendable (WeatherCondition) -> WeatherAssetNames

    public init(bundle: Bundle = .main, names: @escaping @Sendable (WeatherCondition) -> WeatherAssetNames) {
        self.bundle = bundle
        self.names = names
    }

    /// A naming scheme built from a scene prefix and `WeatherCondition.assetKey`:
    ///
    /// | Part | File name |
    /// |------|-----------|
    /// | Sky | `<prefix>_sky_<key>.png` |
    /// | Lighting | `<prefix>_ibl_<key>.hdr` |
    /// | Audio | `<audioName>` when it rains or snows |
    ///
    /// For example `Meadow_sky_sunny_morning.png` and `Meadow_ibl_rainy.hdr`.
    public static func prefixed(
        _ prefix: String,
        in bundle: Bundle = .main,
        skyExtension: String = "png",
        lightExtension: String = "hdr",
        precipitationAudio: String? = "rain.mp3"
    ) -> WeatherAssetCatalog {
        WeatherAssetCatalog(bundle: bundle) { condition in
            WeatherAssetNames(
                skybox: "\(prefix)_sky_\(condition.assetKey).\(skyExtension)",
                imageBasedLight: "\(prefix)_ibl_\(condition.assetKey).\(lightExtension)",
                ambientAudio: condition.hasPrecipitation ? precipitationAudio : nil
            )
        }
    }

    func url(for name: String?) -> URL? {
        name.flatMap { bundle.url(forResource: $0, withExtension: nil) }
    }
}
