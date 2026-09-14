import Foundation

enum PermissionsLogic {
    static func allGranted(statuses: [PermissionKind: PermissionStatus]) -> Bool {
        PermissionKind.allCases.allSatisfy { statuses[$0] == .granted }
    }

    static func nextUngranted(statuses: [PermissionKind: PermissionStatus]) -> PermissionKind? {
        PermissionKind.allCases.first { statuses[$0] != .granted }
    }
}
