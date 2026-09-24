import Darwin
import Foundation

/// Decides whether a CGEvent came from the XS Flow.
///
/// CGEvents don't carry their source device, so we listen to the mouse's raw HID
/// input in parallel and match on "the same button changed the same way very
/// recently". Both callbacks run on the main run loop.
public final class DeviceCorrelator {
    /// How far apart the HID value and the CGEvent may arrive.
    public var window: TimeInterval = 0.15

    /// When no HID record exists yet (the CGEvent won the race), claim buttons ≥ 3
    /// anyway as long as the mouse is connected. The built-in trackpad never sends
    /// those, so this only misfires if a second multi-button mouse is attached.
    public var claimUnmatchedExtraButtons = true

    public var isConnected = false

    private var buttons: [Int: (down: Bool, time: UInt64)] = [:]
    private var lastWheel: UInt64 = 0
    private let ticksPerSecond: Double = {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        return 1e9 * Double(info.denom) / Double(info.numer)
    }()

    public init() {}

    public func record(_ event: HIDInputEvent) {
        let now = mach_absolute_time()
        if event.isButton {
            buttons[event.usage] = (event.value != 0, now)
        } else if event.isWheel || event.isHorizontalWheel {
            lastWheel = now
        }
    }

    private func isRecent(_ time: UInt64) -> Bool {
        let now = mach_absolute_time()
        let delta = now >= time ? now - time : time - now
        return Double(delta) / ticksPerSecond <= window
    }

    /// `button` uses HID numbering (1 = left).
    public func isOurs(button: Int, down: Bool) -> Bool {
        guard isConnected else { return false }
        if let record = buttons[button], record.down == down, isRecent(record.time) { return true }
        return claimUnmatchedExtraButtons && button >= 3
    }

    /// Call only for non-continuous (wheel) scroll events; trackpads are continuous.
    public func isOursScroll() -> Bool {
        guard isConnected else { return false }
        return isRecent(lastWheel) || claimUnmatchedExtraButtons
    }
}
