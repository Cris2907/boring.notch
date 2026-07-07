import Combine
import SwiftUI

public struct ActivityID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var description: String { rawValue }
}

struct ActivityMetadata {
    let name: String
    let systemImage: String
    let tint: Color
    let preferredExpandedHeight: CGFloat?

    init(
        name: String,
        systemImage: String,
        tint: Color = .accentColor,
        preferredExpandedHeight: CGFloat? = nil
    ) {
        self.name = name
        self.systemImage = systemImage
        self.tint = tint
        self.preferredExpandedHeight = preferredExpandedHeight
    }
}

@MainActor
protocol NotchActivity: ObservableObject {
    associatedtype ExpandedContent: View
    associatedtype CompactContent: View = EmptyView
    associatedtype ConfigurationContent: View = EmptyView

    var id: ActivityID { get }
    var metadata: ActivityMetadata { get }
    var isAvailable: Bool { get }
    var isActive: Bool { get }
    var supportsCompactPresentation: Bool { get }
    var supportsConfiguration: Bool { get }

    @ViewBuilder func makeExpandedView() -> ExpandedContent
    @ViewBuilder func makeCompactView() -> CompactContent
    @ViewBuilder func makeConfigurationView() -> ConfigurationContent

    func activityDidAppear()
    func activityDidDisappear()
}

extension NotchActivity {
    var isAvailable: Bool { true }
    var isActive: Bool { false }
    var supportsCompactPresentation: Bool { false }
    var supportsConfiguration: Bool { false }

    func activityDidAppear() {}
    func activityDidDisappear() {}
}

extension NotchActivity where CompactContent == EmptyView {
    func makeCompactView() -> EmptyView {
        EmptyView()
    }
}

extension NotchActivity where ConfigurationContent == EmptyView {
    func makeConfigurationView() -> EmptyView {
        EmptyView()
    }
}

@MainActor
final class AnyNotchActivity: @MainActor ObservableObject, Identifiable {
    let objectWillChange = ObservableObjectPublisher()

    let id: ActivityID
    let metadata: ActivityMetadata

    private let availability: () -> Bool
    private let activeState: () -> Bool
    private let compactPresentationSupport: () -> Bool
    private let configurationSupport: () -> Bool
    private let expandedView: () -> AnyView
    private let compactView: () -> AnyView
    private let configurationView: () -> AnyView
    private let didAppear: () -> Void
    private let didDisappear: () -> Void
    private var activityObservation: AnyCancellable?

    init<Activity: NotchActivity>(_ activity: Activity) {
        id = activity.id
        metadata = activity.metadata
        availability = { activity.isAvailable }
        activeState = { activity.isActive }
        compactPresentationSupport = { activity.supportsCompactPresentation }
        configurationSupport = { activity.supportsConfiguration }
        expandedView = { AnyView(activity.makeExpandedView()) }
        compactView = { AnyView(activity.makeCompactView()) }
        configurationView = { AnyView(activity.makeConfigurationView()) }
        didAppear = activity.activityDidAppear
        didDisappear = activity.activityDidDisappear

        activityObservation = activity.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var isAvailable: Bool { availability() }
    var isActive: Bool { activeState() }
    var supportsCompactPresentation: Bool { compactPresentationSupport() }
    var supportsConfiguration: Bool { configurationSupport() }

    func makeExpandedView() -> AnyView { expandedView() }
    func makeCompactView() -> AnyView { compactView() }
    func makeConfigurationView() -> AnyView { configurationView() }

    func activityDidAppear() { didAppear() }
    func activityDidDisappear() { didDisappear() }
}

struct ExpandedActivityView: View {
    @ObservedObject var activity: AnyNotchActivity

    var body: some View {
        Group {
            if let height = activity.metadata.preferredExpandedHeight {
                activity.makeExpandedView()
                    .preferredOpenNotchHeight(height)
            } else {
                activity.makeExpandedView()
            }
        }
        .onAppear {
            activity.activityDidAppear()
        }
        .onDisappear {
            activity.activityDidDisappear()
        }
    }
}

struct ActivityConfigurationView: View {
    let activityID: ActivityID

    @ObservedObject private var registry = ActivityRegistry.shared

    var body: some View {
        if let activity = registry.activity(for: activityID), activity.supportsConfiguration {
            RegisteredActivityConfigurationView(activity: activity)
        } else {
            EmptyView()
        }
    }
}

private struct RegisteredActivityConfigurationView: View {
    @ObservedObject var activity: AnyNotchActivity

    var body: some View {
        activity.makeConfigurationView()
    }
}
