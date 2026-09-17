import CoreGraphics

struct DisplaySpec {
    var name: String
    var diagonalInches: CGFloat
    var width: CGFloat
    var height: CGFloat
}

struct AppConfig {
    /// `diagonalInches` is only a fallback. The real size comes from the panel over
    /// EDID; these values are used when a display reports nothing usable.
    var left = DisplaySpec(name: "", diagonalInches: 27, width: 2560, height: 1440)
    var right = DisplaySpec(name: "", diagonalInches: 31.5, width: 2560, height: 1440)
    /// Only consulted when the arrangement is ambiguous, which is the case whenever
    /// both displays have the same pixel height.
    var alignmentBottom = true
    var laptopNamePatterns = ["Color LCD", "Built-in", "MacBook", "Liquid Retina"]
    var resolutionTolerance: CGFloat = 64
    var borderInset: CGFloat = 2
}
