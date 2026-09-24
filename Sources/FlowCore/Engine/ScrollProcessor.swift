import CoreGraphics

/// Rewrites wheel events from the XS Flow: reverse, speed, and hold-to-modify.
public enum ScrollProcessor {
    public static func process(_ event: CGEvent, settings: ScrollSettings, modifier: ScrollModifier?) {
        var v = axis(event, 1)
        var h = axis(event, 2)

        if settings.reverseVertical { v = v.scaled(-1) }
        if settings.reverseHorizontal { h = h.scaled(-1) }
        if settings.speed != 1 {
            v = v.scaled(settings.speed)
            h = h.scaled(settings.speed)
        }

        switch modifier {
        case .horizontal:
            // Only swap when the wheel moved vertically, so a tilt still works.
            if v.line != 0 || v.fixed != 0 { (h, v) = (v, .zero) }
        case .zoom:
            event.flags.insert(.maskCommand)
        case nil:
            break
        }

        setAxis(event, 1, v)
        setAxis(event, 2, h)
    }

    struct Delta {
        var line: Int64
        var fixed: Double
        var point: Int64
        static let zero = Delta(line: 0, fixed: 0, point: 0)

        func scaled(_ k: Double) -> Delta {
            var line = Int64((Double(self.line) * k).rounded())
            // Keep slow speeds from swallowing single notches entirely.
            if line == 0 && self.line != 0 { line = (self.line > 0) == (k > 0) ? 1 : -1 }
            return Delta(line: line, fixed: fixed * k, point: Int64((Double(point) * k).rounded()))
        }
    }

    static func axis(_ e: CGEvent, _ n: Int) -> Delta {
        n == 1
            ? Delta(line: e.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                    fixed: e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                    point: e.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            : Delta(line: e.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                    fixed: e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                    point: e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
    }

    static func setAxis(_ e: CGEvent, _ n: Int, _ d: Delta) {
        if n == 1 {
            e.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: d.line)
            e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: d.fixed)
            e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: d.point)
        } else {
            e.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: d.line)
            e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: d.fixed)
            e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: d.point)
        }
    }
}
