import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let openAdvancedSettings: () -> Void
    private let showTranscript: () -> Void
    private let quitApp: () -> Void
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let outsideClickMonitor = PopoverOutsideClickMonitor()
    private var cancellables = Set<AnyCancellable>()

    init(
        model: AppModel,
        openAdvancedSettings: @escaping () -> Void,
        showTranscript: @escaping () -> Void,
        quitApp: @escaping () -> Void
    ) {
        self.model = model
        self.openAdvancedSettings = openAdvancedSettings
        self.showTranscript = showTranscript
        self.quitApp = quitApp
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        configurePopover()
        bindModel()
        updateStatusIcon(for: model.sessionState)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.action = #selector(togglePopover(_:))
        button.target = self
        button.imagePosition = .imageOnly
        button.toolTip = "HearSub"
    }

    private func configurePopover() {
        popover.delegate = self
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 420)
    }

    private func bindModel() {
        model.$sessionState
            .sink { [weak self] state in
                self?.updateStatusIcon(for: state)
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon(for state: SessionState) {
        let image = StatusBarIconFactory.image(
            size: 18,
            template: true,
            showsDot: state == .running,
            showsError: state == .error
        )
        statusItem.button?.image = image
    }

    /// Screen rect of the status bar button, for animation targeting.
    var statusItemScreenRect: NSRect? {
        guard let button = statusItem.button,
              let window = button.window else { return nil }
        let rect = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rect)
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            model.refreshSources()
            popover.contentViewController = NSHostingController(
                rootView: StatusBarPopoverView(
                    model: model,
                    closePopover: { [weak self] in
                        self?.popover.performClose(nil)
                    },
                    openAdvancedSettings: { [weak self] in
                        self?.popover.performClose(nil)
                        self?.openAdvancedSettings()
                    },
                    showTranscript: { [weak self] in
                        self?.popover.performClose(nil)
                        self?.showTranscript()
                    },
                    quitApp: { [weak self] in
                        self?.popover.performClose(nil)
                        self?.quitApp()
                    }
                )
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverWillShow(_ notification: Notification) {
        outsideClickMonitor.start(
            shouldIgnoreClick: { [weak self] screenPoint in
                self?.clickShouldKeepPopoverOpen(at: screenPoint) ?? true
            },
            onOutsideClick: { [weak self] in
                guard let self, self.popover.isShown else {
                    return
                }

                self.popover.performClose(nil)
            }
        )
    }

    func popoverDidClose(_ notification: Notification) {
        outsideClickMonitor.stop()
        popover.contentViewController = nil
    }

    private func clickShouldKeepPopoverOpen(at screenPoint: NSPoint) -> Bool {
        statusItemScreenRect?.contains(screenPoint) == true
            || popover.contentViewController?.view.window?.frame.contains(screenPoint) == true
    }
}

enum StatusBarIconFactory {
    static func image(
        size: CGFloat,
        template: Bool,
        showsDot: Bool = false,
        showsError: Bool = false
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        let scale = size / 24.0
        let strokeWidth = max(1.7, 2.4 * scale)
        let color = template ? NSColor.black : NSColor.labelColor
        color.setStroke()
        color.setFill()

        let earPath = NSBezierPath()
        earPath.lineWidth = strokeWidth
        earPath.lineCapStyle = .round
        earPath.lineJoinStyle = .round
        earPath.move(to: NSPoint(x: 13.2 * scale, y: 3.2 * scale))
        earPath.curve(
            to: NSPoint(x: 8.8 * scale, y: 8.0 * scale),
            controlPoint1: NSPoint(x: 9.8 * scale, y: 3.0 * scale),
            controlPoint2: NSPoint(x: 8.0 * scale, y: 5.2 * scale)
        )
        earPath.curve(
            to: NSPoint(x: 8.0 * scale, y: 20.0 * scale),
            controlPoint1: NSPoint(x: 6.0 * scale, y: 11.6 * scale),
            controlPoint2: NSPoint(x: 5.0 * scale, y: 17.0 * scale)
        )
        earPath.curve(
            to: NSPoint(x: 17.5 * scale, y: 8.8 * scale),
            controlPoint1: NSPoint(x: 13.6 * scale, y: 25.0 * scale),
            controlPoint2: NSPoint(x: 23.5 * scale, y: 17.0 * scale)
        )
        earPath.stroke()

        let innerPath = NSBezierPath()
        innerPath.lineWidth = strokeWidth
        innerPath.lineCapStyle = .round
        innerPath.lineJoinStyle = .round
        innerPath.move(to: NSPoint(x: 10.7 * scale, y: 15.8 * scale))
        innerPath.curve(
            to: NSPoint(x: 13.0 * scale, y: 10.7 * scale),
            controlPoint1: NSPoint(x: 12.8 * scale, y: 17.6 * scale),
            controlPoint2: NSPoint(x: 16.2 * scale, y: 14.6 * scale)
        )
        innerPath.curve(
            to: NSPoint(x: 12.0 * scale, y: 6.8 * scale),
            controlPoint1: NSPoint(x: 11.6 * scale, y: 9.1 * scale),
            controlPoint2: NSPoint(x: 10.9 * scale, y: 8.0 * scale)
        )
        innerPath.stroke()

        let bubbleRect = NSRect(x: 12.5 * scale, y: 2.4 * scale, width: 9.2 * scale, height: 6.8 * scale)
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: 1.8 * scale, yRadius: 1.8 * scale)
        bubblePath.lineWidth = strokeWidth
        bubblePath.stroke()
        let tailPath = NSBezierPath()
        tailPath.lineWidth = strokeWidth
        tailPath.lineCapStyle = .round
        tailPath.lineJoinStyle = .round
        tailPath.move(to: NSPoint(x: 15.4 * scale, y: 2.5 * scale))
        tailPath.line(to: NSPoint(x: 13.8 * scale, y: 0.8 * scale))
        tailPath.line(to: NSPoint(x: 13.8 * scale, y: 2.5 * scale))
        tailPath.stroke()

        if showsDot || showsError {
            let dotRect = NSRect(x: 18.4 * scale, y: 17.0 * scale, width: 4.4 * scale, height: 4.4 * scale)
            (showsError ? NSColor.systemRed : NSColor.systemGreen).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        image.unlockFocus()
        image.isTemplate = template
        return image
    }
}
