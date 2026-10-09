import AppKit
import XCTest
@testable import HearSub

final class DockVisibilityControllerTests: XCTestCase {
    @MainActor
    func testClosingSettingsKeepsDockEntryWhileApplicationIsRunning() async {
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        defer { application.setActivationPolicy(originalPolicy) }
        let controller = DockVisibilityController()

        controller.setVisible(true, for: .applicationLifetime)
        controller.setVisible(true, for: .settingsWindow)
        controller.setVisible(false, for: .settingsWindow)

        XCTAssertEqual(application.activationPolicy(), .regular)
    }

    @MainActor
    func testRepeatedSettingsCloseAndReopenKeepsDockEntry() async {
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        defer { application.setActivationPolicy(originalPolicy) }
        let controller = DockVisibilityController()
        controller.setVisible(true, for: .applicationLifetime)

        for _ in 0..<5 {
            controller.setVisible(true, for: .settingsWindow)
            controller.setVisible(false, for: .settingsWindow)
            XCTAssertEqual(application.activationPolicy(), .regular)
        }
    }

    @MainActor
    func testDockHidesOnlyWhenAllVisibilityReasonsAreRemoved() async {
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        defer { application.setActivationPolicy(originalPolicy) }
        let controller = DockVisibilityController()
        controller.setVisible(true, for: .applicationLifetime)
        controller.setVisible(true, for: .settingsWindow)
        controller.setVisible(false, for: .applicationLifetime)
        XCTAssertEqual(application.activationPolicy(), .regular)

        controller.setVisible(false, for: .settingsWindow)
        XCTAssertEqual(application.activationPolicy(), .accessory)
    }
}
