import Foundation
import SwiftData
import Testing
@testable import MoneyPlanner

@MainActor
@Suite("AppSettingsRepository")
struct AppSettingsRepositoryTests {
    @Test func settingsSurviveReopeningTemporaryStore() throws {
        let directory = URL.temporaryDirectory.appending(path: "AppSettingsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "Test.store")
        let createdAt = Date(timeIntervalSince1970: 1_790_000_000)

        do {
            let container = try ModelContainerFactory.makePersistent(at: storeURL)
            let repository = AppSettingsRepository(container: container, now: { createdAt })
            #expect(try repository.load().hasCompletedOnboarding == false)
            _ = try repository.setOnboardingCompleted(true)
        }

        let reopened = try ModelContainerFactory.makePersistent(at: storeURL)
        let settings = try AppSettingsRepository(container: reopened).load()

        #expect(settings.hasCompletedOnboarding)
        #expect(settings.createdAt == createdAt)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }

    @Test func loadCreatesSingleRecord() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let repository = AppSettingsRepository(container: container)

        let first = try repository.load()
        let second = try repository.load()

        #expect(first == second)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<AppSettings>()) == 1)
    }

    @Test func inMemoryStoresAreIsolated() throws {
        let first = try ModelContainerFactory.makeInMemory()
        let second = try ModelContainerFactory.makeInMemory()

        _ = try AppSettingsRepository(container: first).setOnboardingCompleted(true)

        #expect(try AppSettingsRepository(container: second).load().hasCompletedOnboarding == false)
        let configuration = try #require(first.configurations.first)
        #expect(configuration.isStoredInMemoryOnly)
        #expect(configuration.url != ModelContainerFactory.defaultStoreURL)
        #expect(configuration.cloudKitContainerIdentifier == nil)
    }

    @Test func testProcessNeverUsesUserStore() throws {
        let mode = LaunchMode.detect()

        #expect(mode == .unitTesting)
        #expect(mode.usesPersistentStore == false)
        #expect(mode.allowsNetwork == false)

        let dependencies = try AppDependencies.make(
            mode: mode,
            configuration: AppConfiguration(apiBaseURL: URL(string: "https://example.test"), appVersion: "1", buildNumber: "1")
        )
        #expect(dependencies.modelContainer.configurations.allSatisfy { $0.isStoredInMemoryOnly })
        #expect(dependencies.healthService == nil)
    }
}
