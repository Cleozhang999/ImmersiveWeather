import Foundation
import ImageIO
import RealityKit

/// The sky, lighting and ambient sound for a weather condition.
///
/// Add it to your scene, call `receiveLighting(on:)` for the content that should be lit
/// by the sky, then call `apply(_:from:)` whenever the weather changes.
@MainActor
public final class WeatherEnvironmentEntity: Entity {
    /// Something in the catalog that could not be found or loaded.
    public struct LoadFailure: Error, Sendable, Equatable {
        public enum Part: Sendable, Equatable {
            case skybox, imageBasedLight, ambientAudio
        }
        public var part: Part
        public var name: String
    }

    /// Radius of the sky sphere in meters.
    public var skyRadius: Float = 1000 {
        didSet { sky.scale = [-skyRadius, skyRadius, skyRadius] }
    }

    /// Volume of the ambient sound in decibels.
    public var ambientGain: Audio.Decibel = -10 {
        didSet { audio.components[AmbientAudioComponent.self]?.gain = ambientGain }
    }

    private let sky = ModelEntity()
    private let audio = Entity()
    private var playback: AudioPlaybackController?

    public required init() {
        super.init()
        // A unit sphere scaled by -1 on X so its inside faces are rendered.
        sky.model = ModelComponent(mesh: .generateSphere(radius: 1), materials: [])
        sky.scale = [-skyRadius, skyRadius, skyRadius]
        sky.isEnabled = false
        addChild(sky)

        audio.components.set(AmbientAudioComponent(gain: ambientGain))
        addChild(audio)
    }

    /// Lights `entity` and its descendants with this environment's image-based light.
    public func receiveLighting(on entity: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: self))
    }

    /// Loads and shows the sky, lighting and sound for `condition`.
    ///
    /// Parts the catalog does not name are hidden. Parts that fail to load keep their
    /// previous state and are returned so you can report them.
    @discardableResult
    public func apply(_ condition: WeatherCondition, from catalog: WeatherAssetCatalog) async -> [LoadFailure] {
        let names = catalog.names(condition)
        var failures: [LoadFailure] = []

        if let name = names.skybox {
            do {
                guard let url = catalog.url(for: name) else { throw CocoaError(.fileNoSuchFile) }
                let texture = try await TextureResource(contentsOf: url)
                var material = UnlitMaterial()
                material.color = .init(texture: .init(texture))
                sky.model?.materials = [material]
                sky.isEnabled = true
            } catch {
                failures.append(LoadFailure(part: .skybox, name: name))
            }
        } else {
            sky.isEnabled = false
        }

        if let name = names.imageBasedLight {
            do {
                guard let url = catalog.url(for: name),
                      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let environment = try await EnvironmentResource(equirectangular: image, withName: name)
                components.set(ImageBasedLightComponent(source: .single(environment)))
            } catch {
                failures.append(LoadFailure(part: .imageBasedLight, name: name))
            }
        } else {
            components.remove(ImageBasedLightComponent.self)
        }

        playback?.stop()
        playback = nil
        if let name = names.ambientAudio {
            do {
                guard let url = catalog.url(for: name) else { throw CocoaError(.fileNoSuchFile) }
                let resource = try await AudioFileResource(contentsOf: url, configuration: .init(shouldLoop: true))
                playback = audio.playAudio(resource)
            } catch {
                failures.append(LoadFailure(part: .ambientAudio, name: name))
            }
        }

        return failures
    }
}
