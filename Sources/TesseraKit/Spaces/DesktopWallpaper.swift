import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// The picture on a display's desktop, for the Spaces that have nothing on them.
///
/// A Space you are not on cannot be captured — there is no surface to capture — so
/// an empty desktop is drawn from its wallpaper instead. It is the same picture the
/// Space would show, which is enough to say "a desktop, and nothing on it".
///
/// The file is decoded once per display at thumbnail size and kept: wallpapers are
/// large, the overlay redraws often, and the picture only changes when someone
/// changes it.
@MainActor
final class DesktopWallpaper {
  private var images: [CGDirectDisplayID: CGImage] = [:]
  private var sources: [CGDirectDisplayID: URL] = [:]

  func image(for displayID: CGDirectDisplayID, fitting size: CGSize) -> CGImage? {
    guard let screen = DisplayInfo.screen(for: displayID),
      let url = NSWorkspace.shared.desktopImageURL(for: screen)
    else {
      return nil
    }

    if sources[displayID] == url, let cached = images[displayID] {
      return cached
    }

    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }

    let pixels = Int(max(size.width, size.height) * (screen.backingScaleFactor))
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(pixels, 1),
    ]

    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else {
      return nil
    }

    sources[displayID] = url
    images[displayID] = image

    return image
  }
}
