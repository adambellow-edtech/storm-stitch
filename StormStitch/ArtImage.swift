import UIKit

/// Loads a bundled picture by name: PNG first, then JPG (used for full-screen paintings to keep the app small).
func artImage(_ name: String) -> UIImage? {
    if let png = UIImage(named: name) { return png }
    return UIImage(named: name + ".jpg")
}
