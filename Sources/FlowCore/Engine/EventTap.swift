import CoreGraphics
import Foundation

/// A session-level CGEventTap on the main run loop. Returning nil from the
/// handler swallows the event.
public final class EventTap {
    public typealias Handler = (CGEventType, CGEvent) -> CGEvent?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public static let mouseEvents: [CGEventType] = [
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
        .otherMouseDown, .otherMouseUp,
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .scrollWheel,
    ]

    /// Fails (returns false) without the Accessibility permission.
    public func start() -> Bool {
        let mask = Self.mouseEvents.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                let me = Unmanaged<EventTap>.fromOpaque(context!).takeUnretainedValue()
                return me.handle(type, event)
            },
            userInfo: context
        ) else { return false }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables slow taps; turn it straight back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }
        return handler(type, event).map { Unmanaged.passUnretained($0) }
    }
}
