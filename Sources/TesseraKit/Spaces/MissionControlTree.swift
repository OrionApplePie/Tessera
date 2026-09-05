import AppKit
import ApplicationServices
import CoreGraphics

/// The Spaces bars of Mission Control, read out of the Dock's Accessibility tree.
///
/// Mission Control is drawn by the Dock, and while it is open the Dock publishes it
/// as an ordinary Accessibility tree: one bar per display, that display's Spaces
/// inside it as buttons, and beside them the button that adds a desktop. Measured
/// on macOS 15.7.5 with two displays:
///
///     AXGroup                                       ← one bar, one display
///       AXList
///         AXButton  "Desktop 1"  [AXPress]
///         AXButton  "Telegram"   [AXPress, AXRemoveDesktop]
///       AXButton    ""           [AXPress]          ← adds a desktop here
///
/// This is the whole reason Spaces can be created and closed at all. The window
/// server's own calls for it are shut: `SLSSpaceCreate` and `SLSSpaceDestroy` exist
/// in SkyLight but, like `SLSMoveWindowsToManagedSpace` and
/// `SLSSetWindowListWorkspace` before them, they answer only a privileged
/// connection, which is why yabai asks for System Integrity Protection to be turned
/// down before it will do any of this. Mission Control's own buttons need no such
/// thing — only the Accessibility permission the switcher already asks for.
///
/// Nothing here is matched on a label. Every title and description in this tree is
/// localised — the bar is "Панель Spaces" on a Russian system — so the shape of the
/// tree identifies things instead: a bar holds its Spaces one level deeper than the
/// button that adds one, and the adding button is the one with no title.
///
/// The bars exist only while Mission Control is open. With it closed the Dock's
/// tree is 29 elements of dock tiles and nothing else, which is what makes the
/// short flash of Mission Control unavoidable rather than untidy.
enum MissionControlTree {
  /// The Dock's own name for the action that closes a Space. Not in any header:
  /// read off the buttons themselves, which list it beside `AXPress`.
  static let removeAction = "AXRemoveDesktop"

  /// One display's row of Spaces.
  struct Bar {
    /// The display it is drawn on, when that could be worked out.
    let displayID: CGDirectDisplayID?
    /// That display's Spaces, in the order Mission Control shows them — the same
    /// order `SpaceQuery` numbers them in, because both read the one list the
    /// window server keeps per display. So an index into this is a `spaceIndex`.
    let spaces: [AXUIElement]
    /// The button that adds a desktop to this display, when there is one.
    let add: AXUIElement?
  }

  /// Every bar the Dock is showing, in the order the tree lists them.
  static func bars(ofDock dock: pid_t, displays: [CGDirectDisplayID: CGRect]) -> [Bar] {
    var found: [Bar] = []
    var seen = 0

    collect(
      AXUIElementCreateApplication(dock), displays: displays, depth: 0, seen: &seen, into: &found)

    return found
  }

  /// Walks the tree, keeping the groups shaped like a bar.
  ///
  /// Bounded on both depth and count: this runs while Mission Control is on screen
  /// and a runaway walk would be felt.
  private static func collect(
    _ element: AXUIElement,
    displays: [CGDirectDisplayID: CGRect],
    depth: Int,
    seen: inout Int,
    into found: inout [Bar]
  ) {
    guard depth < 12, seen < 4000 else {
      return
    }

    seen += 1

    if let bar = bar(from: element, displays: displays) {
      found.append(bar)
      return
    }

    for child in children(of: element) {
      collect(child, displays: displays, depth: depth + 1, seen: &seen, into: &found)
    }
  }

  /// A bar, if this element is one: a group holding a container of buttons — the
  /// Spaces — and, beside it, a button with no title, which is the one that adds a
  /// desktop.
  ///
  /// The container is an `AXList` rather than an `AXGroup`, and insisting on a
  /// group found no bars at all — the first version of this looked for one, having
  /// been written from a walk that flattened the tree and never recorded what the
  /// Spaces were held in.
  ///
  /// The last part is what makes it a bar rather than any group of buttons.
  /// Measured: the group of window thumbnails above the bar has the same shape,
  /// and matching on shape alone took it for the Spaces of a display and then
  /// found no button to add a desktop with. So a bar has to show one of the two
  /// things only a bar has: the button that adds a desktop, or a Space that can be
  /// closed.
  private static func bar(
    from element: AXUIElement,
    displays: [CGDirectDisplayID: CGRect]
  ) -> Bar? {
    guard string(kAXRoleAttribute, of: element) == kAXGroupRole else {
      return nil
    }

    let parts = children(of: element)
    let spaces = parts.lazy.map(buttons(inside:)).first { !$0.isEmpty } ?? []

    guard !spaces.isEmpty else {
      return nil
    }

    let add = parts.last { button in
      string(kAXRoleAttribute, of: button) == kAXButtonRole
        && (string(kAXTitleAttribute, of: button) ?? "").isEmpty
    }
    let closable = spaces.contains { actions(of: $0).contains(removeAction) }

    guard add != nil || closable else {
      return nil
    }

    return Bar(
      displayID: frame(of: element).flatMap { display(forBarAt: $0, among: displays) },
      spaces: spaces,
      add: add
    )
  }

  /// The buttons a container holds, or nothing when it is not a container of them.
  private static func buttons(inside element: AXUIElement) -> [AXUIElement] {
    let role = string(kAXRoleAttribute, of: element)

    guard role == kAXListRole || role == kAXGroupRole else {
      return []
    }

    return children(of: element).filter { string(kAXRoleAttribute, of: $0) == kAXButtonRole }
  }

  /// Which display a bar belongs to: the one its middle falls on.
  ///
  /// By geometry rather than by the order the bars come in, because that order is
  /// the Dock's business and this has to agree with the display ids the rest of the
  /// switcher uses. Accessibility measures from the top left of the main display,
  /// which is what `CGDisplayBounds` does too, so the two need no conversion.
  static func display(
    forBarAt frame: CGRect,
    among displays: [CGDirectDisplayID: CGRect]
  ) -> CGDirectDisplayID? {
    let middle = CGPoint(x: frame.midX, y: frame.midY)

    return
      displays
      .filter { $0.value.contains(middle) }
      .min { $0.key < $1.key }?
      .key
  }

  /// Every display's bounds, by id, in the coordinates Accessibility reports.
  static func displayBounds() -> [CGDirectDisplayID: CGRect] {
    var count: UInt32 = 0

    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
      return [:]
    }

    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))

    guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
      return [:]
    }

    return ids.reduce(into: [:]) { bounds, id in
      bounds[id] = CGDisplayBounds(id)
    }
  }

  // MARK: - Reading one element

  static func children(of element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?

    guard
      AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
    else {
      return []
    }

    return value as? [AXUIElement] ?? []
  }

  static func string(_ attribute: String, of element: AXUIElement) -> String? {
    var value: CFTypeRef?

    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
      return nil
    }

    return value as? String
  }

  /// Where an element is drawn, in screen coordinates.
  static func frame(of element: AXUIElement) -> CGRect? {
    var value: CFTypeRef?

    guard
      AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &value) == .success,
      let raw = value,
      CFGetTypeID(raw) == AXValueGetTypeID()
    else {
      return nil
    }

    // The cast is checked by the type id above; `AXValue` has no safe spelling.
    let box = unsafeDowncast(raw, to: AXValue.self)
    var frame = CGRect.zero

    guard AXValueGetValue(box, .cgRect, &frame) else {
      return nil
    }

    return frame
  }

  /// What an element can be asked to do. Used to tell a Space that may be closed
  /// from the last one on a display, which macOS refuses to remove.
  static func actions(of element: AXUIElement) -> [String] {
    var names: CFArray?

    guard AXUIElementCopyActionNames(element, &names) == .success else {
      return []
    }

    return names as? [String] ?? []
  }
}
