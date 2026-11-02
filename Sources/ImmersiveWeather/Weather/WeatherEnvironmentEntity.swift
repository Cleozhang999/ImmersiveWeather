import Foundation
import ImageIO
import RealityKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

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

    /// The volume rain or snow falls through, in meters: width (X), height (Y) and depth (Z).
    /// It sits on this entity's origin, so precipitation starts `y` meters above it.
    public var precipitationArea: SIMD3<Float> = [8, 5, 8] {
        didSet { updatePrecipitation() }
    }

    /// Scales how many drops or flakes fall. 1 is a steady shower; keep it modest on device.
    public var precipitationDensity: Float = 1 {
        didSet { updatePrecipitation() }
    }

    private let sky = ModelEntity()
    private let audio = Entity()
    private let precipitation = Entity()
    private var playback: AudioPlaybackController?
    private var condition: WeatherCondition?

    public required init() {
        super.init()
        // A unit sphere scaled by -1 on X so its inside faces are rendered.
        sky.model = ModelComponent(mesh: .generateSphere(radius: 1), materials: [])
        sky.scale = [-skyRadius, skyRadius, skyRadius]
        sky.isEnabled = false
        addChild(sky)

        audio.components.set(AmbientAudioComponent(gain: ambientGain))
        addChild(audio)

        addChild(precipitation)
    }

    /// Lights `entity` and its descendants with this environment's image-based light.
    public func receiveLighting(on entity: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: self))
    }

    /// Loads and shows the sky, lighting and sound for `condition`, and starts or stops rain or snow.
    ///
    /// Parts the catalog does not name are hidden. Parts that fail to load keep their
    /// previous state and are returned so you can report them. Precipitation needs no assets.
    @discardableResult
    public func apply(_ condition: WeatherCondition, from catalog: WeatherAssetCatalog) async -> [LoadFailure] {
        self.condition = condition
        updatePrecipitation()

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

    /// Particle settings for falling rain or snow, or `nil` for dry weather.
    static func precipitationEmitter(for condition: WeatherCondition?, area: SIMD3<Float>, density: Float) -> ParticleEmitterComponent? {
        let footprint = area.x * area.z
        var emitter = ParticleEmitterComponent()
        switch condition {
        case .rainy:
            // Thin streaks: camera-facing particles stretched along their velocity.
            // (`.billboardYAligned` collapses stretched particles to zero width.)
            emitter.speed = 7
            emitter.speedVariation = 1
            emitter.mainEmitter.birthRate = 150 * footprint * density
            emitter.mainEmitter.size = 0.006
            emitter.mainEmitter.stretchFactor = 14
            emitter.mainEmitter.billboardMode = .billboard
            // Slightly darker than white so streaks still read against a pale overcast sky.
            emitter.mainEmitter.color = .constant(.single(.init(red: 0.72, green: 0.76, blue: 0.82, alpha: 0.75)))
        case .snowy:
            // Soft flakes drifting down with a little turbulence.
            emitter.speed = 0.6
            emitter.speedVariation = 0.2
            emitter.mainEmitter.birthRate = 60 * footprint * density
            emitter.mainEmitter.size = 0.025
            emitter.mainEmitter.sizeVariation = 0.008
            emitter.mainEmitter.billboardMode = .billboard
            emitter.mainEmitter.noiseStrength = 0.15
            emitter.mainEmitter.noiseScale = 1
            emitter.mainEmitter.noiseAnimationSpeed = 0.3
            emitter.mainEmitter.color = .constant(.single(.init(white: 1, alpha: 0.95)))
        default:
            return nil
        }
        // Spawn on a thin slab at the top of the area, fall straight down, and disappear
        // shortly after reaching the bottom.
        emitter.emitterShape = .box
        emitter.birthLocation = .volume
        emitter.emitterShapeSize = [area.x, 0.1, area.z]
        emitter.birthDirection = .world
        emitter.emissionDirection = [0, -1, 0]
        emitter.mainEmitter.spreadingAngle = 0.02
        emitter.mainEmitter.acceleration = .zero
        emitter.mainEmitter.lifeSpan = Double(area.y / emitter.speed) * 1.1
        emitter.mainEmitter.opacityCurve = .constant
        emitter.mainEmitter.blendMode = .alpha
        emitter.mainEmitter.isLightingEnabled = false
        emitter.isEmitting = true
        return emitter
    }

    private func updatePrecipitation() {
        if let emitter = Self.precipitationEmitter(for: condition, area: precipitationArea, density: precipitationDensity) {
            precipitation.position = [0, precipitationArea.y, 0]
            precipitation.components.set(emitter)
        } else {
            precipitation.components.remove(ParticleEmitterComponent.self)
        }
    }
}
