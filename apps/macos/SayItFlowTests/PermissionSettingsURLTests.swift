import AppKit
import XCTest
@testable import SayItFlow

/// Guards the regression where the scheme was switched to `x-apple.systemsettings`,
/// which has no registered handler, so every "Open Settings" button raised
/// "There is no application set to open the URL …" instead of opening System Settings.
final class PermissionSettingsURLTests: XCTestCase {
    func testEveryCandidateUsesTheRegisteredScheme() {
        for kind in PermissionKind.allCases {
            let candidates = kind.settingsURLCandidates
            XCTAssertFalse(candidates.isEmpty, "\(kind.rawValue) has no settings URL")
            for url in candidates {
                XCTAssertEqual(
                    url.scheme,
                    "x-apple.systempreferences",
                    "\(kind.rawValue) uses an unregistered scheme: \(url)"
                )
            }
        }
    }

    func testEveryCandidateResolvesToAHandler() {
        for kind in PermissionKind.allCases {
            for url in kind.settingsURLCandidates {
                XCTAssertNotNil(
                    NSWorkspace.shared.urlForApplication(toOpen: url),
                    "No application is set to open \(url)"
                )
            }
        }
    }

    func testAnchorsAreDistinctPerKind() {
        let anchors = PermissionKind.allCases.map(\.settingsAnchor)
        XCTAssertEqual(Set(anchors).count, anchors.count, "Two permissions share a settings anchor")
    }
}
