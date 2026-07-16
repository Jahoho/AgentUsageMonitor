import Foundation
import ServiceManagement

struct LaunchAtLoginState: Equatable {
    let isOn: Bool
    let statusText: String
    let detailText: String
}

enum LaunchAtLoginController {
    static func currentState(errorMessage: String? = nil) -> LaunchAtLoginState {
        let baseState: LaunchAtLoginState

        switch SMAppService.mainApp.status {
        case .enabled:
            baseState = LaunchAtLoginState(
                isOn: true,
                statusText: "Starts at login",
                detailText: "Agent Usage Monitor opens quietly in the menu bar."
            )
        case .requiresApproval:
            baseState = LaunchAtLoginState(
                isOn: true,
                statusText: "Needs macOS approval",
                detailText: "Approve it in System Settings -> Login Items."
            )
        case .notRegistered:
            baseState = LaunchAtLoginState(
                isOn: false,
                statusText: "Manual start",
                detailText: "Turn this on to keep the monitor available after restart."
            )
        case .notFound:
            baseState = LaunchAtLoginState(
                isOn: false,
                statusText: "Available in packaged app",
                detailText: "Run the .app build before enabling login startup."
            )
        @unknown default:
            baseState = LaunchAtLoginState(
                isOn: false,
                statusText: "Unknown login status",
                detailText: "macOS returned a login item state this version does not recognize."
            )
        }

        guard let errorMessage else {
            return baseState
        }

        return LaunchAtLoginState(
            isOn: baseState.isOn,
            statusText: baseState.statusText,
            detailText: errorMessage
        )
    }

    static func setEnabled(_ isEnabled: Bool) -> LaunchAtLoginState {
        do {
            if isEnabled {
                try registerIfNeeded()
            } else {
                try unregisterIfNeeded()
            }
            return currentState()
        } catch {
            return currentState(errorMessage: "Could not update login item: \(error.localizedDescription)")
        }
    }

    private static func registerIfNeeded() throws {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return
        case .notRegistered, .notFound:
            try SMAppService.mainApp.register()
        @unknown default:
            try SMAppService.mainApp.register()
        }
    }

    private static func unregisterIfNeeded() throws {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            try SMAppService.mainApp.unregister()
        case .notRegistered, .notFound:
            return
        @unknown default:
            try SMAppService.mainApp.unregister()
        }
    }
}
