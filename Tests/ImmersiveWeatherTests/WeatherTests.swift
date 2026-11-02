import Foundation
import RealityKit
import Testing
@testable import ImmersiveWeather

@Suite struct WaterPresetTests {
    @Test func peacefulWaterHasNoDrops() {
        #expect(WaterSurfaceParameters.preset(for: .peaceful).dropsPerSecond == 0)
    }

    @Test func moderateDropsLandInTheCenter() {
        let water = WaterSurfaceParameters.preset(for: .moderate)
        #expect(water.dropsPerSecond > 0)
        #expect(!water.dropsAtRandomPositions)
    }

    @Test func precipitationOverridesMood() {
        for mood in WaterMood.allCases {
            for condition in [WeatherCondition.rainy, .snowy] {
                let water = WaterSurfaceParameters.preset(for: mood, in: condition)
                #expect(water.dropsPerSecond == 90)
                #expect(water.dropsAtRandomPositions)
                // The mood still decides the material.
                #expect(water.roughness == WaterSurfaceParameters.preset(for: mood).roughness)
            }
        }
    }

    @Test func dryWeatherKeepsMood() {
        for condition in [WeatherCondition.clearMorning, .clearNight, .foggy] {
            #expect(WaterSurfaceParameters.preset(for: .turbulent, in: condition) == .preset(for: .turbulent))
        }
    }
}

@Suite struct DropProbabilityTests {
    @Test func zeroRateNeverDrops() {
        #expect(WaterSimulation.dropProbability(dropsPerSecond: 0, deltaTime: 1 / 90) == 0)
    }

    @Test func isIndependentOfFrameRate() {
        // Over one second, the expected number of frames with a drop should be similar at 60 and 120 Hz.
        let at60 = WaterSimulation.dropProbability(dropsPerSecond: 3, deltaTime: 1 / 60) * 60
        let at120 = WaterSimulation.dropProbability(dropsPerSecond: 3, deltaTime: 1 / 120) * 120
        #expect(abs(at60 - at120) < 0.05)
        #expect(abs(at120 - 3) < 0.05)
    }

    @Test func staysAProbability() {
        #expect(WaterSimulation.dropProbability(dropsPerSecond: 10_000, deltaTime: 1) <= 1)
    }
}

@Suite struct AssetCatalogTests {
    @Test func prefixedNaming() {
        let catalog = WeatherAssetCatalog.prefixed("Meadow")
        #expect(catalog.names(.clearNight) == WeatherAssetNames(
            skybox: "Meadow_sky_sunny_night.png",
            imageBasedLight: "Meadow_ibl_sunny_night.hdr",
            ambientAudio: nil))
        #expect(catalog.names(.snowy).ambientAudio == "rain.mp3")
        #expect(catalog.names(.snowy).skybox == "Meadow_sky_rainy.png")
    }
}

@MainActor
@Suite struct PrecipitationTests {
    @Test func onlyRainAndSnowFall() {
        for condition in WeatherCondition.allCases {
            let emitter = WeatherEnvironmentEntity.precipitationEmitter(for: condition, area: [8, 5, 8], density: 1)
            #expect((emitter != nil) == condition.hasPrecipitation, "\(condition)")
        }
    }

    @Test func snowFallsSlowerThanRain() throws {
        let rain = try #require(WeatherEnvironmentEntity.precipitationEmitter(for: .rainy, area: [8, 5, 8], density: 1))
        let snow = try #require(WeatherEnvironmentEntity.precipitationEmitter(for: .snowy, area: [8, 5, 8], density: 1))
        #expect(snow.speed < rain.speed)
        #expect(rain.emissionDirection == [0, -1, 0])
        #expect(rain.emitterShapeSize == [8, 0.1, 8])
    }

    @Test func densityScalesBirthRate() throws {
        let light = try #require(WeatherEnvironmentEntity.precipitationEmitter(for: .rainy, area: [4, 5, 4], density: 0.5))
        let heavy = try #require(WeatherEnvironmentEntity.precipitationEmitter(for: .rainy, area: [4, 5, 4], density: 2))
        #expect(heavy.mainEmitter.birthRate == light.mainEmitter.birthRate * 4)
    }

    @Test func entityStartsAndStopsPrecipitation() async {
        let environment = WeatherEnvironmentEntity()
        let catalog = WeatherAssetCatalog { _ in WeatherAssetNames() }
        await environment.apply(.snowy, from: catalog)
        #expect(environment.children.contains { $0.components.has(ParticleEmitterComponent.self) })
        await environment.apply(.clearMorning, from: catalog)
        #expect(!environment.children.contains { $0.components.has(ParticleEmitterComponent.self) })
    }
}
