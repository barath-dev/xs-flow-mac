import AppKit
import CoreGraphics

/// Ties everything together: intercepts mouse events, works out which mouse sent
/// each one, and applies the current config to the mice it manages. Main-thread only.
public final class MappingEngine {
    public var config: Config {
        didSet { applyPointerSettings() }
    }

    /// Only used for connect/disconnect notifications; no input is read.
    public let monitor = DeviceMonitor()
    public let registry = PointingDeviceRegistry()
    public private(set) var isRunning = false
    public private(set) var frontmostBundleID: String?

    public var onDevicesChanged: (() -> Void)?
    /// Called for each action the engine performs, for logging.
    public var onAction: ((Int, Action) -> Void)?
    /// Called for every button press on an external mouse (HID numbering: 1 = left).
    public var onButtonPress: ((Int, PointingDevice) -> Void)?

    private let performer = ActionPerformer()
    private lazy var pointer = PointerApplier(registry: registry)
    private lazy var tap = EventTap { [unowned self] type, event in self.handle(type, event) }
    private var appObserver: NSObjectProtocol?

    /// Buttons whose press we handled, with the action chosen at press time.
    private var active: [Int: Action] = [:]
    private var scrollModifier: ScrollModifier?
    private var captureHandler: ((Int) -> Void)?
    /// A captured button whose release we still have to swallow.
    private var capturedButton: Int?

    public init(config: Config) {
        self.config = config
    }

    public enum StartError: Error {
        case accessibilityDenied
    }

    public func start() throws {
        guard !isRunning else { return }
        monitor.onChange = { [unowned self] in
            registry.invalidate()
            applyPointerSettings()
            onDevicesChanged?()
        }
        monitor.start(readInput: false)
        guard tap.start() else {
            monitor.stop()
            throw StartError.accessibilityDenied
        }

        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [unowned self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            frontmostBundleID = app?.bundleIdentifier
        }
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        tap.stop()
        monitor.stop()
        pointer.restore()
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        active.removeAll()
        scrollModifier = nil
        cancelCapture()
        isRunning = false
    }

    /// Calls `handler` with the next non-left button pressed on an external mouse
    /// and swallows that press. Left clicks pass through so the UI stays usable.
    public func captureNextButton(_ handler: @escaping (Int) -> Void) {
        captureHandler = handler
    }

    public func cancelCapture() {
        captureHandler = nil
    }

    private func applyPointerSettings() {
        guard isRunning else { return }
        let config = config
        pointer.apply(config.pointer) { config.manages($0) }
    }

    // MARK: Event handling

    private func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        guard config.enabled else { return event }
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return buttonDown(event)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return buttonUp(event)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return dragged(event)
        case .scrollWheel:
            return scroll(event)
        default:
            return event
        }
    }

    private func hidButton(_ event: CGEvent) -> Int {
        Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
    }

    private func buttonDown(_ event: CGEvent) -> CGEvent? {
        let button = hidButton(event)
        guard let device = registry.device(for: event), device.isExternalMouse else { return event }
        onButtonPress?(button, device)
        if let handler = captureHandler, button != 1 {
            captureHandler = nil
            capturedButton = button
            handler(button)
            return nil
        }
        guard config.manages(device),
              let action = config.action(forButton: button, bundleID: frontmostBundleID)
        else { return event }

        active[button] = action
        onAction?(button, action)
        switch action {
        case .mouseButton(let target):
            return retarget(event, to: target, down: true)
        case .scrollModifier(let mode):
            scrollModifier = mode
            return nil
        default:
            performer.press(action)
            return nil
        }
    }

    private func buttonUp(_ event: CGEvent) -> CGEvent? {
        let button = hidButton(event)
        if button == capturedButton {
            capturedButton = nil
            return nil
        }
        guard let action = active.removeValue(forKey: button) else { return event }
        switch action {
        case .mouseButton(let target):
            return retarget(event, to: target, down: false)
        case .scrollModifier:
            scrollModifier = nil
            return nil
        default:
            performer.release(action)
            return nil
        }
    }

    private func dragged(_ event: CGEvent) -> CGEvent? {
        let button = hidButton(event)
        guard let action = active[button] else { return event }
        if case .mouseButton(let target) = action {
            event.type = Self.draggedType(for: target)
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(target - 1))
        } else {
            // The button now does something else; keep the pointer moving as a plain move.
            event.type = .mouseMoved
        }
        return event
    }

    private func scroll(_ event: CGEvent) -> CGEvent? {
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard !continuous, let device = registry.device(for: event), config.manages(device) else { return event }
        ScrollProcessor.process(event, settings: config.scrollSettings(bundleID: frontmostBundleID), modifier: scrollModifier)
        return event
    }

    private func retarget(_ event: CGEvent, to target: Int, down: Bool) -> CGEvent {
        switch target {
        case 1: event.type = down ? .leftMouseDown : .leftMouseUp
        case 2: event.type = down ? .rightMouseDown : .rightMouseUp
        default: event.type = down ? .otherMouseDown : .otherMouseUp
        }
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(target - 1))
        return event
    }

    private static func draggedType(for target: Int) -> CGEventType {
        switch target {
        case 1: .leftMouseDragged
        case 2: .rightMouseDragged
        default: .otherMouseDragged
        }
    }
}
