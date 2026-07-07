import Combine

enum ActivityRegistryError: Error, Equatable {
    case duplicateID(ActivityID)
}

@resultBuilder
enum ActivityRegistryBuilder {
    @MainActor
    static func buildExpression<Activity: NotchActivity>(
        _ activity: Activity
    ) -> [AnyNotchActivity] {
        [AnyNotchActivity(activity)]
    }

    static func buildBlock(_ components: [AnyNotchActivity]...) -> [AnyNotchActivity] {
        components.flatMap { $0 }
    }

    static func buildOptional(_ component: [AnyNotchActivity]?) -> [AnyNotchActivity] {
        component ?? []
    }

    static func buildEither(first component: [AnyNotchActivity]) -> [AnyNotchActivity] {
        component
    }

    static func buildEither(second component: [AnyNotchActivity]) -> [AnyNotchActivity] {
        component
    }

    static func buildArray(_ components: [[AnyNotchActivity]]) -> [AnyNotchActivity] {
        components.flatMap { $0 }
    }
}

@MainActor
final class ActivityRegistry: ObservableObject {
    static let shared: ActivityRegistry = {
        do {
            return try ActivityRegistry {}
        } catch {
            preconditionFailure("Invalid default activity registry: \(error)")
        }
    }()

    let activities: [AnyNotchActivity]

    private let activitiesByID: [ActivityID: AnyNotchActivity]
    private var activityObservations: Set<AnyCancellable> = []

    init(@ActivityRegistryBuilder activities: () -> [AnyNotchActivity]) throws {
        let registeredActivities = activities()
        var indexedActivities: [ActivityID: AnyNotchActivity] = [:]

        for activity in registeredActivities {
            guard indexedActivities[activity.id] == nil else {
                throw ActivityRegistryError.duplicateID(activity.id)
            }
            indexedActivities[activity.id] = activity
        }

        self.activities = registeredActivities
        activitiesByID = indexedActivities

        for activity in registeredActivities {
            activity.objectWillChange
                .sink { [weak self] in
                    self?.objectWillChange.send()
                }
                .store(in: &activityObservations)
        }
    }

    var availableActivities: [AnyNotchActivity] {
        activities.filter(\.isAvailable)
    }

    var activeActivities: [AnyNotchActivity] {
        availableActivities.filter(\.isActive)
    }

    func activity(for id: ActivityID) -> AnyNotchActivity? {
        activitiesByID[id]
    }
}
