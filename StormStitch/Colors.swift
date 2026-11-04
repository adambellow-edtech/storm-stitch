import UIKit

extension UIColor {
    /// Builds a color from a 0xRRGGBB value, matching the hex codes on the art direction board.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

/// Palette from the art direction board.
enum Palette {
    static let paper = UIColor(hex: 0xFBF6EA)
    static let ink = UIColor(hex: 0x1E1B2E)
    static let stormGray = UIColor(hex: 0xA3A5B1)
    static let stormDark = UIColor(hex: 0x4A4D5C)
    static let stitchGold = UIColor(hex: 0xFFC93C)
    static let goldDark = UIColor(hex: 0xC98F00)
    static let bramble = UIColor(hex: 0x5DBB63)
    static let heart = UIColor(hex: 0xFF5C7A)
}

func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}
