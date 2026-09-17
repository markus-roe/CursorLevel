import ApplicationServices
import CoreGraphics
import Foundation

struct LayoutSnapshot {
    var left: DisplayFrame
    var right: DisplayFrame
    var alignmentBottom: Bool
    var borderInset: CGFloat
    var primaryHeight: CGFloat
}

struct CorrectorStats {
    var tapInstalled = false
    var tapKind = "none"
    var eventCount: UInt64 = 0
    var remapCount: UInt64 = 0
    var lastRole = "—"
    var lastPoint = CGPoint.zero
}

final class MouseCorrector: @unchecked Sendable {
    static let shared = MouseCorrector()

    private let lock = NSLock()
    private var snapshot: LayoutSnapshot?
    private var enabled = true
    private var stats = CorrectorStats()

    private var lastY: CGFloat = 0
    private var hasLast = false
    private var lastRole: Role = .other

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activity: NSObjectProtocol?

    private enum Role: String {
        case left
        case right
        case other
    }

    private init() {}

    func setEnabled(_ value: Bool) {
        lock.lock()
        enabled = value
        lock.unlock()
    }

    func updateLayout(_ layout: ResolvedLayout?, config: AppConfig) {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        lock.lock()
        if let layout {
            snapshot = LayoutSnapshot(
                left: layout.left,
                right: layout.right,
                alignmentBottom: layout.alignmentBottom,
                borderInset: config.borderInset,
                primaryHeight: primaryHeight
            )
        } else {
            snapshot = nil
        }
        lock.unlock()
    }

    func copyStats() -> CorrectorStats {
        lock.lock()
        defer { lock.unlock() }
        return stats
    }

    func start() {
        stop()

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "CursorLevel pointer correction"
        )

        let mask =
            (CGEventMask(1) << CGEventType.mouseMoved.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDragged.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseDragged.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseDragged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: MouseCorrector.tapCallback,
            userInfo: refcon
        )

        guard let tap else {
            NSLog("[cursorlevel] Event tap could not be created.")
            lock.lock()
            stats.tapInstalled = false
            stats.tapKind = "failed"
            lock.unlock()
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        CGEventSource(stateID: .hidSystemState)?.localEventsSuppressionInterval = 0

        lock.lock()
        stats.tapInstalled = true
        stats.tapKind = "session"
        stats.eventCount = 0
        stats.remapCount = 0
        lock.unlock()
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        lock.lock()
        stats.tapInstalled = false
        lock.unlock()
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let corrector = Unmanaged<MouseCorrector>.fromOpaque(refcon).takeUnretainedValue()
        return corrector.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let currentEnabled = enabled
        let layout = snapshot
        stats.eventCount += 1
        lock.unlock()

        let point = event.unflippedLocation
        let role = role(for: point, layout: layout)

        lock.lock()
        stats.lastRole = role.rawValue
        stats.lastPoint = point
        lock.unlock()

        guard currentEnabled, let layout else {
            remember(point, role)
            return Unmanaged.passUnretained(event)
        }

        if (lastRole == .left && role == .right) || (lastRole == .right && role == .left) {
            handleCrossing(from: lastRole, to: role, point: point, event: event, layout: layout)
            return Unmanaged.passUnretained(event)
        }

        remember(point, role)
        return Unmanaged.passUnretained(event)
    }

    private func handleCrossing(
        from: Role,
        to: Role,
        point: CGPoint,
        event: CGEvent,
        layout: LayoutSnapshot
    ) {
        let src = from == .left ? layout.left : layout.right
        let dst = to == .left ? layout.left : layout.right
        let sourceY = sourceY(for: point, source: src)
        let mappedY = mapY(sourceY, from: src, to: dst, alignmentBottom: layout.alignmentBottom)
        let minY = dst.y
        let maxY = dst.y + dst.h - 1

        if mappedY < minY - 0.5 || mappedY > maxY + 0.5 {
            // Keep the cursor on the source display, but do not freeze Y.
            var stay = point
            stay.x = from == .right ? src.x + layout.borderInset : src.x + src.w - layout.borderInset
            stay.y = src.clampY(point.y)
            apply(stay, role: from, event: event, layout: layout)
            return
        }

        var next = point
        next.y = min(max(mappedY, minY), maxY)
        apply(next, role: to, event: event, layout: layout)
    }

    private func apply(
        _ point: CGPoint,
        role: Role,
        event: CGEvent,
        layout: LayoutSnapshot
    ) {
        let quartz = CGPoint(x: point.x, y: layout.primaryHeight - point.y)
        event.location = quartz
        remember(point, role)
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        CGWarpMouseCursorPosition(quartz)
        CGAssociateMouseAndMouseCursorPosition(1)
        lock.lock()
        stats.remapCount += 1
        lock.unlock()
    }

    private func remember(_ point: CGPoint, _ role: Role) {
        lastY = point.y
        hasLast = true
        lastRole = role
    }

    private func role(for point: CGPoint, layout: LayoutSnapshot?) -> Role {
        guard let layout else {
            return .other
        }
        let inLeft = layout.left.contains(point)
        let inRight = layout.right.contains(point)
        if inLeft && inRight {
            return (lastRole == .left || lastRole == .right) ? lastRole : .right
        }
        if inLeft {
            return .left
        }
        if inRight {
            return .right
        }
        return .other
    }

    private func sourceY(for point: CGPoint, source: DisplayFrame) -> CGFloat {
        if hasLast, point.y >= source.y, point.y < source.y + source.h {
            return point.y
        }
        if hasLast {
            return lastY
        }
        return point.y
    }

    private func mapY(
        _ sourceY: CGFloat,
        from src: DisplayFrame,
        to dst: DisplayFrame,
        alignmentBottom: Bool
    ) -> CGFloat {
        let sourceDistance = alignmentBottom
            ? sourceY - src.y
            : (src.y + src.h) - sourceY
        let destinationDistance = sourceDistance * (src.inches / dst.inches) * (dst.h / src.h)
        return alignmentBottom
            ? dst.y + destinationDistance
            : (dst.y + dst.h) - destinationDistance
    }
}
