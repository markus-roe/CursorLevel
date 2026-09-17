import AppKit
import CoreGraphics

struct DisplayFrame: Equatable {
    var x: CGFloat
    var y: CGFloat
    var w: CGFloat
    var h: CGFloat
    var inches: CGFloat

    var minX: CGFloat { x }
    var minY: CGFloat { y }
    var maxX: CGFloat { x + w }
    var maxY: CGFloat { y + h }

    func contains(_ point: CGPoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    func clampY(_ value: CGFloat) -> CGFloat {
        min(max(value, minY), maxY - 1)
    }
}

struct ConnectedScreen {
    let id: CGDirectDisplayID
    let name: String
    let cocoa: CGRect
    let isBuiltin: Bool
    let measuredInches: CGFloat?
}

struct ResolvedLayout {
    var left: DisplayFrame
    var right: DisplayFrame
    var leftName: String
    var rightName: String
    /// False when a panel reported no usable physical size and Config had to fill in.
    var measured: Bool
    /// Taken from the display arrangement where it is unambiguous, Config otherwise.
    var alignmentBottom: Bool
}

enum DisplayResolver {
    static func allScreens() -> [ConnectedScreen] {
        NSScreen.screens.compactMap { screen in
            guard
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else {
                return nil
            }
            let id = CGDirectDisplayID(number.uint32Value)
            return ConnectedScreen(
                id: id,
                name: screen.localizedName,
                cocoa: screen.frame,
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                measuredInches: measuredDiagonal(id)
            )
        }
    }

    /// The panel reports its physical size over EDID. Virtual screens and a few
    /// cheap monitors report nothing or nonsense, so implausible values are dropped
    /// and the Config diagonal is used instead.
    static func measuredDiagonal(_ id: CGDirectDisplayID) -> CGFloat? {
        let millimetres = CGDisplayScreenSize(id)
        guard millimetres.width > 1, millimetres.height > 1 else {
            return nil
        }
        let inches = hypot(millimetres.width, millimetres.height) / 25.4
        guard inches > 10, inches < 90 else {
            return nil
        }
        return inches
    }

    static func resolve(_ config: AppConfig) -> ResolvedLayout? {
        let screens = allScreens()
        let namedLeft = findNamed(screens, spec: config.left, config: config)
        let namedRight = findNamed(screens, spec: config.right, config: config)
        var candidates = sizedExternals(screens, config: config)

        if candidates.count < 2 {
            candidates = topRowExternals(screens, config: config)
        }

        var left = namedLeft ?? pickCandidate(candidates, excluding: namedRight, preferRight: false)
        var right = namedRight ?? pickCandidate(candidates, excluding: left, preferRight: true)

        if let leftScreen = left, let rightScreen = right, leftScreen.id == rightScreen.id {
            left = pickCandidate(candidates, excluding: nil, preferRight: false)
            right = pickCandidate(candidates, excluding: left, preferRight: true)
        }

        guard let leftScreen = left, let rightScreen = right else {
            return nil
        }

        if leftScreen.isBuiltin || rightScreen.isBuiltin || isLaptop(leftScreen, config: config) || isLaptop(rightScreen, config: config) {
            return nil
        }

        return ResolvedLayout(
            left: frame(leftScreen, fallbackInches: config.left.diagonalInches),
            right: frame(rightScreen, fallbackInches: config.right.diagonalInches),
            leftName: leftScreen.name,
            rightName: rightScreen.name,
            measured: leftScreen.measuredInches != nil && rightScreen.measuredInches != nil,
            alignmentBottom: detectAlignmentBottom(leftScreen, rightScreen, config: config)
        )
    }

    /// Which edge the two displays share, taken from the arrangement the user
    /// already dragged in System Settings. Screens of equal pixel height line up on
    /// both edges at once and say nothing, so those fall back to Config.
    private static func detectAlignmentBottom(
        _ a: ConnectedScreen,
        _ b: ConnectedScreen,
        config: AppConfig
    ) -> Bool {
        guard abs(a.cocoa.height - b.cocoa.height) > 1 else {
            return config.alignmentBottom
        }
        let bottomGap = abs(a.cocoa.minY - b.cocoa.minY)
        let topGap = abs(a.cocoa.maxY - b.cocoa.maxY)
        guard abs(bottomGap - topGap) > 1 else {
            return config.alignmentBottom
        }
        return bottomGap < topGap
    }

    private static func frame(_ screen: ConnectedScreen, fallbackInches: CGFloat) -> DisplayFrame {
        DisplayFrame(
            x: screen.cocoa.origin.x,
            y: screen.cocoa.origin.y,
            w: screen.cocoa.width,
            h: screen.cocoa.height,
            inches: screen.measuredInches ?? fallbackInches
        )
    }

    private static func isLaptop(_ screen: ConnectedScreen, config: AppConfig) -> Bool {
        if screen.isBuiltin {
            return true
        }
        return config.laptopNamePatterns.contains { pattern in
            screen.name.localizedCaseInsensitiveContains(pattern)
        }
    }

    private static func resolutionMatches(_ screen: ConnectedScreen, spec: DisplaySpec, config: AppConfig) -> Bool {
        abs(screen.cocoa.width - spec.width) <= config.resolutionTolerance
            && abs(screen.cocoa.height - spec.height) <= config.resolutionTolerance
    }

    private static func nameMatches(_ screen: ConnectedScreen, spec: DisplaySpec) -> Bool {
        let query = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return true
        }
        return screen.name.localizedCaseInsensitiveContains(query)
    }

    private static func findNamed(_ screens: [ConnectedScreen], spec: DisplaySpec, config: AppConfig) -> ConnectedScreen? {
        let query = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return nil
        }
        return screens.first { screen in
            !isLaptop(screen, config: config)
                && resolutionMatches(screen, spec: spec, config: config)
                && nameMatches(screen, spec: spec)
        }
    }

    private static func sizedExternals(_ screens: [ConnectedScreen], config: AppConfig) -> [ConnectedScreen] {
        topRow(
            screens.filter { screen in
                !isLaptop(screen, config: config)
                    && (resolutionMatches(screen, spec: config.left, config: config)
                        || resolutionMatches(screen, spec: config.right, config: config))
            }
        )
    }

    private static func topRowExternals(_ screens: [ConnectedScreen], config: AppConfig) -> [ConnectedScreen] {
        topRow(screens.filter { !isLaptop($0, config: config) })
    }

    private static func topRow(_ screens: [ConnectedScreen]) -> [ConnectedScreen] {
        var matches = screens
        matches.sort { a, b in
            if abs(a.cocoa.maxY - b.cocoa.maxY) > 80 {
                return a.cocoa.maxY > b.cocoa.maxY
            }
            return a.cocoa.origin.x < b.cocoa.origin.x
        }
        guard matches.count > 2 else {
            return matches
        }
        let top = matches[0].cocoa.maxY
        return matches
            .filter { abs($0.cocoa.maxY - top) <= 80 }
            .sorted { $0.cocoa.origin.x < $1.cocoa.origin.x }
    }

    private static func pickCandidate(
        _ candidates: [ConnectedScreen],
        excluding: ConnectedScreen?,
        preferRight: Bool
    ) -> ConnectedScreen? {
        var chosen: ConnectedScreen?
        for screen in candidates where excluding == nil || screen.id != excluding?.id {
            if let current = chosen {
                if preferRight, screen.cocoa.origin.x > current.cocoa.origin.x {
                    chosen = screen
                } else if !preferRight, screen.cocoa.origin.x < current.cocoa.origin.x {
                    chosen = screen
                }
            } else {
                chosen = screen
            }
        }
        return chosen
    }
}
