import SwiftUI
import UIKit

enum BundleImage {
    static func uiImage(named name: String) -> UIImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        return UIImage(named: name)
    }

    static func image(_ name: String, systemFallback: String = "app.fill") -> Image {
        if let uiImage = uiImage(named: name) {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: systemFallback)
    }
}
