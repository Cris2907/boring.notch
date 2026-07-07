import Combine
import SwiftUI
import XCTest
@testable import boringNotch

@MainActor
final class ActivityArchitectureTests: XCTestCase {
    func testActivityIDHasStableValueSemantics() {
        let first = ActivityID("example")
        let second = ActivityID(rawValue: "example")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.rawValue, "example")
        XCTAssertEqual(first.description, "example")
        XCTAssertEqual(Set([first, second]).count, 1)
    }

    func testRegistryPreservesRegistrationOrderAndMetadata() throws {
        let first = TestActivity(id: "first", name: "First")
        let second = TestActivity(id: "second", name: "Second")
        let registry = try ActivityRegistry {
            first
            second
        }

        XCTAssertEqual(registry.activities.map(\.id), [first.id, second.id])
        XCTAssertEqual(registry.activity(for: second.id)?.metadata.name, "Second")
        XCTAssertNil(registry.activity(for: ActivityID("missing")))
    }

    func testRegistryRejectsDuplicateIDs() {
        XCTAssertThrowsError(
            try ActivityRegistry {
                TestActivity(id: "duplicate", name: "First")
                TestActivity(id: "duplicate", name: "Second")
            }
        ) { error in
            XCTAssertEqual(
                error as? ActivityRegistryError,
                .duplicateID(ActivityID("duplicate"))
            )
        }
    }

    func testAvailabilityAndActiveStateAreEvaluatedFromActivity() throws {
        let activity = TestActivity(id: "state", name: "State")
        let registry = try ActivityRegistry { activity }

        XCTAssertEqual(registry.availableActivities.map(\.id), [activity.id])
        XCTAssertTrue(registry.activeActivities.isEmpty)

        activity.isAvailable = false
        activity.isActive = true
        XCTAssertTrue(registry.availableActivities.isEmpty)
        XCTAssertTrue(registry.activeActivities.isEmpty)

        activity.isAvailable = true
        XCTAssertEqual(registry.activeActivities.map(\.id), [activity.id])
    }

    func testStateChangesPropagateThroughTypeErasureAndRegistry() throws {
        let activity = TestActivity(id: "observable", name: "Observable")
        let registry = try ActivityRegistry { activity }
        let erased = try XCTUnwrap(registry.activity(for: activity.id))
        var erasedUpdates = 0
        var registryUpdates = 0
        let erasedObservation = erased.objectWillChange.sink { erasedUpdates += 1 }
        let registryObservation = registry.objectWillChange.sink { registryUpdates += 1 }

        activity.isActive = true

        XCTAssertEqual(erasedUpdates, 1)
        XCTAssertEqual(registryUpdates, 1)
        withExtendedLifetime((erasedObservation, registryObservation)) {}
    }

    func testExampleActivityUsesConcreteViewsBeforeErasure() throws {
        let example = ExampleActivity()
        let registry = try ActivityRegistry { example }
        let erased = try XCTUnwrap(registry.activity(for: ExampleActivity.activityID))

        let _: AnyView = erased.makeExpandedView()
        let _: AnyView = erased.makeCompactView()
        XCTAssertTrue(erased.supportsCompactPresentation)
        XCTAssertFalse(erased.supportsConfiguration)
        XCTAssertFalse(ActivityRegistry.shared.activities.contains { $0.id == example.id })
    }

    func testDefaultRegistryContainsCalendarMetadataAndConfiguration() throws {
        let calendar = try XCTUnwrap(ActivityRegistry.shared.activity(for: .calendar))

        XCTAssertEqual(calendar.metadata.name, "Calendar")
        XCTAssertEqual(calendar.metadata.systemImage, "calendar")
        XCTAssertEqual(calendar.metadata.preferredExpandedHeight, calendarOpenNotchHeight)
        XCTAssertTrue(calendar.supportsConfiguration)
        XCTAssertFalse(calendar.supportsCompactPresentation)
    }
}

@MainActor
private final class TestActivity: NotchActivity {
    let id: ActivityID
    let metadata: ActivityMetadata

    @Published var isAvailable = true
    @Published var isActive = false

    init(id: String, name: String) {
        self.id = ActivityID(id)
        metadata = ActivityMetadata(name: name, systemImage: "circle")
    }

    func makeExpandedView() -> some View {
        Text(metadata.name)
    }
}
