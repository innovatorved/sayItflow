import XCTest
@testable import SayItFlow

final class PermissionsLogicTests: XCTestCase {
    func testAllGrantedWhenEveryKindGranted() {
        var statuses: [PermissionKind: PermissionStatus] = [:]
        for kind in PermissionKind.allCases {
            statuses[kind] = .granted
        }
        XCTAssertTrue(PermissionsLogic.allGranted(statuses: statuses))
    }

    func testNotAllGrantedWhenOneMissing() {
        var statuses: [PermissionKind: PermissionStatus] = [:]
        for kind in PermissionKind.allCases {
            statuses[kind] = .granted
        }
        statuses[.microphone] = .denied
        XCTAssertFalse(PermissionsLogic.allGranted(statuses: statuses))
    }

    func testPermissionStatusBadgeMapping() {
        XCTAssertEqual(PermissionStatus.granted.badgeKind, .granted)
        XCTAssertEqual(PermissionStatus.needsSettings.badgeKind, .warning)
        XCTAssertEqual(PermissionStatus.denied.label, "Denied")
    }

    func testNextUngrantedKind() {
        let statuses: [PermissionKind: PermissionStatus] = [
            .microphone: .granted,
            .accessibility: .notDetermined,
            .inputMonitoring: .granted,
        ]
        XCTAssertEqual(PermissionsLogic.nextUngranted(statuses: statuses), .accessibility)
    }
}
