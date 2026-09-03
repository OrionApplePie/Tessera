import AppKit
import SwiftUI

/// The overlay's fixed geometry, in one place: the thumbnail has to be told its
/// width explicitly, and the window has to know how many tiles fit across a screen.
enum TileMetrics {
  static let width: CGFloat = 190
  static let padding: CGFloat = 12
  static let spacing: CGFloat = 14
  static let surfacePadding: CGFloat = 20
  /// Room inside a group's frame, so its tiles do not touch the line drawn round
  /// them.
  static let groupPadding: CGFloat = 8
  /// The group's corner. Between the tile's and the panel's, so the three read as
  /// nested rather than repeated.
  static let groupCornerRadius: CGFloat = 12
  /// How far each card of a deck peeks out from the one in front of it, and how
  /// many cards deep that goes before the rest hide behind the last. Enough of a
  /// corner to count them at a glance, little enough that a Space of six windows
  /// still reads as one block.
  static let deckStep = CGSize(width: 20, height: 15)
  static let deckDepth = 4

  /// The room a deck of `count` windows takes.
  static func deckSize(forCards count: Int) -> CGSize {
    let steps = CGFloat(min(max(count, 1) - 1, deckDepth))

    return CGSize(
      width: width + deckStep.width * steps,
      height: width + deckStep.height * steps
    )
  }

  /// The width a row of `count` tiles takes, gaps included.
  static func width(forColumns count: Int) -> CGFloat {
    let columns = CGFloat(max(count, 1))
    return columns * width + (columns - 1) * spacing
  }
  static let thumbnailHeight: CGFloat = 100
  /// The tile's own corner. Smaller than the panel's, so a tile reads as sitting
  /// inside it rather than repeating it.
  static let tileCornerRadius: CGFloat = 8
  /// The panel's corner, in the register macOS uses for a floating surface of this
  /// size — eight points read as barely rounded at all.
  static let surfaceCornerRadius: CGFloat = 18

  static var contentWidth: CGFloat {
    width - padding * 2
  }

  /// How many tiles fit across a screen this wide, counting the gaps between them
  /// and the surface around them. Never fewer than one: a single tile too wide for
  /// the screen is still the only thing to draw.
  static func columnsFitting(availableWidth: CGFloat) -> Int {
    let usable = availableWidth - surfacePadding * 2 + spacing
    return max(1, Int(usable / (width + spacing)))
  }
}

/// Which tile the keyboard is on. Owned by `OverlayWindowController`, which moves
/// it in response to the arrow keys.
@MainActor
final class OverlaySelection: ObservableObject {
  @Published var index = 0
}

struct OverlayView: View {
  @ObservedObject var windowCoordinator: WindowCoordinator
  @ObservedObject var selection: OverlaySelection
  let background: OverlayColor
  let columns: Int
  let dimsStaleThumbnails: Bool
  let onSelect: (CGWindowID) -> Void
  let onFocusSpace: (WindowSectionID) -> Void
  let onMove: (CGWindowID, CGWindowID) -> Void
  let onClose: () -> Void

  private var gridColumns: [GridItem] {
    let count = OverlayGrid.columnCount(
      forSectionSizes: windowCoordinator.sections.map(\.tiles.count),
      maximum: columns
    )
    return Array(
      repeating: GridItem(.fixed(TileMetrics.width), spacing: TileMetrics.spacing),
      count: count)
  }

  /// Sections paired with the flat index their first tile has, which is what the
  /// number keys and the arrow-key highlight address.
  private var layout: [SectionLayout] {
    var offset = 0

    return windowCoordinator.sections.map { section in
      defer { offset += section.targets.count }
      return SectionLayout(section: section, offset: offset)
    }
  }

  /// A refresh can shrink the list under a highlight that was already placed.
  private var selectedIndex: Int {
    min(selection.index, max(0, windowCoordinator.targets.count - 1))
  }

  var body: some View {
    VStack(spacing: 0) {
      if windowCoordinator.tiles.isEmpty {
        EmptyOverlayContent()
      } else {
        GroupFlow(spacing: TileMetrics.spacing) {
          ForEach(layout) { entry in
            WindowGroup(
              title: entry.section.title,
              isCurrent: entry.section.isCurrent,
              isFullscreen: entry.section.isFullscreen,
              isEmpty: entry.section.tiles.isEmpty,
              isSelected: entry.section.tiles.isEmpty && entry.offset == selectedIndex,
              onFocus: { onFocusSpace(entry.section.id) },
              desktop: entry.section.tiles.isEmpty
                ? windowCoordinator.desktopImage(
                  for: entry.section.id.displayID,
                  fitting: CGSize(width: TileMetrics.width, height: TileMetrics.width))
                : nil,
              content: {
                WindowDeck(
                  tiles: entry.section.tiles,
                  offset: entry.offset,
                  selectedIndex: selectedIndex,
                  base: entry.section.tiles.count > 1 ? Color(background.opaque) : nil,
                  dimsStaleThumbnails: dimsStaleThumbnails,
                  onMove: onMove,
                  onSelect: onSelect
                )
              }
            )
          }
        }
      }
    }
    .frame(width: TileMetrics.width(forColumns: columns), alignment: .leading)
    .padding(TileMetrics.surfacePadding)
    .background(
      RoundedRectangle(cornerRadius: TileMetrics.surfaceCornerRadius, style: .continuous)
        .fill(Color(background))
    )
    .overlay(
      RoundedRectangle(cornerRadius: TileMetrics.surfaceCornerRadius, style: .continuous)
        .stroke(Color.white.opacity(0.12), lineWidth: 1)
    )
    .onExitCommand(perform: onClose)
  }
}

/// Places the groups left to right and starts a new row when the next one does not
/// fit. Side by side is what makes them read as places on a map rather than as
/// paragraphs in a list, which is what a stack of them read as.
private struct GroupFlow: Layout {
  let spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let limit = proposal.width ?? .infinity
    var total = CGSize.zero
    var rowWidth: CGFloat = 0
    var rowHeight: CGFloat = 0

    for view in subviews {
      let size = view.sizeThatFits(.unspecified)

      if rowWidth > 0, rowWidth + spacing + size.width > limit {
        total.width = max(total.width, rowWidth)
        total.height += rowHeight + spacing
        rowWidth = 0
        rowHeight = 0
      }

      rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
      rowHeight = max(rowHeight, size.height)
    }

    total.width = max(total.width, rowWidth)
    total.height += rowHeight

    return total
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0

    for view in subviews {
      let size = view.sizeThatFits(.unspecified)

      if x > bounds.minX, x + size.width > bounds.maxX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }

      view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}

/// The windows of one group — a display, a Space, or both — drawn as one thing.
///
/// A heading alone left the eye to work out where one group ended and the next
/// began, which is a poor way to show something as separate as a Space. The frame
/// says it outright, and the heading sits inside it rather than floating above.
private struct WindowGroup<Content: View>: View {
  let title: String
  var isCurrent: Bool = false
  var isFullscreen: Bool = false
  var isEmpty: Bool = false
  /// An empty Space carries the highlight itself: there is no tile in it to carry.
  var isSelected: Bool = false
  var onFocus: () -> Void = {}
  var desktop: CGImage?
  @ViewBuilder let content: Content

  var body: some View {
    if title.isEmpty {
      // Nothing to tell apart: one display, one Space, no frame worth drawing.
      content
    } else {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 5) {
          if isFullscreen {
            // The Space of a fullscreen window: one window, and no room for another.
            Image(systemName: "arrow.up.left.and.arrow.down.right")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(Color.white.opacity(0.5))
          }

          SectionHeading(title: title)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)

        if isEmpty {
          // A Space with nothing on it is still a place, and it is drawn as what it
          // is: the desktop, dimmed, in the room one window would take. A Space you
          // are not on cannot be captured, so this is its wallpaper rather than a
          // picture of it.
          RoundedRectangle(cornerRadius: TileMetrics.tileCornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.03))
            .frame(width: TileMetrics.width, height: TileMetrics.width)
            .overlay {
              if let desktop {
                Image(decorative: desktop, scale: 1, orientation: .up)
                  .resizable()
                  .scaledToFill()
                  .opacity(0.55)
                  .clipShape(
                    RoundedRectangle(
                      cornerRadius: TileMetrics.tileCornerRadius, style: .continuous))
              }
            }
            .overlay(
              RoundedRectangle(cornerRadius: TileMetrics.tileCornerRadius, style: .continuous)
                .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onFocus)
        } else {
          content
        }
      }
      .padding(TileMetrics.groupPadding)
      .background(
        RoundedRectangle(cornerRadius: TileMetrics.groupCornerRadius, style: .continuous)
          .fill(Color.white.opacity(isCurrent ? 0.12 : 0.04))
      )
      .overlay(
        RoundedRectangle(cornerRadius: TileMetrics.groupCornerRadius, style: .continuous)
          .stroke(Color.white.opacity(isCurrent ? 0.38 : 0.10), lineWidth: isCurrent ? 1.5 : 1)
      )
    }
  }
}

extension Color {
  init(_ color: OverlayColor) {
    self.init(
      .sRGB,
      red: color.red,
      green: color.green,
      blue: color.blue,
      opacity: color.alpha
    )
  }
}

/// The windows of one Space, laid out as a deck of cards rather than as a row of
/// tiles: each one peeks out from behind the one in front of it, so a Space of
/// several windows says so in the room of about one, and the map stays readable
/// when there are a dozen Spaces on it.
///
/// The highlighted card is drawn on top of the rest, which is what makes stepping
/// through a Space read as dealing through a deck: the windows stay where they
/// are and the chosen one comes to the front.
private struct WindowDeck: View {
  let tiles: [WindowTileModel]
  /// The flat index of the first card, which is what the highlight and the number
  /// keys address.
  let offset: Int
  let selectedIndex: Int
  /// What a card is painted on when it has another one behind it. The tiles are
  /// translucent by design and the panel is too, so stacked without a backing they
  /// showed each other's titles through their own.
  let base: Color?
  let dimsStaleThumbnails: Bool
  let onMove: (CGWindowID, CGWindowID) -> Void
  let onSelect: (CGWindowID) -> Void

  var body: some View {
    let size = TileMetrics.deckSize(forCards: tiles.count)

    return ZStack(alignment: .topLeading) {
      ForEach(Array(tiles.enumerated()), id: \.element.id) { item in
        card(at: item.offset, tile: item.element)
      }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
  }

  private func card(at position: Int, tile: WindowTileModel) -> some View {
    let isSelected = offset + position == selectedIndex
    // Past the last step the cards sit on the one before them: they are hidden
    // either way, and a deck that kept growing would be no more compact than a row.
    let step = CGFloat(min(position, TileMetrics.deckDepth))

    return WindowTileButton(
      tile: tile,
      shortcutIndex: offset + position,
      isSelected: isSelected,
      base: base,
      dimsStaleThumbnails: dimsStaleThumbnails,
      onMove: onMove
    ) {
      onSelect(tile.id)
    }
    .shadow(
      color: .black.opacity(isSelected ? 0.5 : 0.3),
      radius: isSelected ? 14 : 6,
      y: isSelected ? 6 : 2
    )
    .offset(x: TileMetrics.deckStep.width * step, y: TileMetrics.deckStep.height * step)
    .zIndex(isSelected ? Double(tiles.count) : Double(position))
  }
}

private struct SectionLayout: Identifiable {
  let section: WindowTileSection
  let offset: Int

  var id: WindowSectionID {
    section.id
  }
}

private struct SectionHeading: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.system(size: 10, weight: .semibold))
      .tracking(0.8)
      .textCase(.uppercase)
      .foregroundStyle(Color.white.opacity(0.4))
      .lineLimit(1)
      .padding(.leading, 2)
  }
}

private struct WindowTileButton: View {
  let tile: WindowTileModel
  let shortcutIndex: Int
  let isSelected: Bool
  /// Painted under the tile's own translucent fill when the tile sits in a deck.
  var base: Color?
  let dimsStaleThumbnails: Bool
  let onMove: (CGWindowID, CGWindowID) -> Void
  let onSelect: () -> Void

  var body: some View {
    tileContent
  }

  /// Deliberately not a `Button`.
  ///
  /// A button joins the keyboard focus chain, and with Full Keyboard Access on
  /// that gives the overlay a second, invisible cursor: Tab moves it, and a
  /// focused button answers Return and Space itself — activating a window other
  /// than the highlighted one. Hiding the focus ring only hid the evidence. A
  /// plain view with a tap gesture leaves the panel's key handling as the single
  /// path, which is what a switcher needs.
  private var tileContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      WindowThumbnailContent(tile: tile, dimsStale: dimsStaleThumbnails)

      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(tile.displayAppName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tile.isActive ? Self.textOnAccent : Color.white)
            .lineLimit(1)

          Spacer(minLength: 0)

          if let shortcut = shortcutLabel {
            Text(shortcut)
              .font(.system(size: 11, weight: .medium, design: .rounded))
              .foregroundStyle(
                tile.isActive
                  ? Self.textOnAccent.opacity(0.7) : Color.white.opacity(0.5))
          }
        }

        Text(tile.displayTitle)
          .font(.system(size: 11))
          .foregroundStyle(
            tile.isActive ? Self.textOnAccent.opacity(0.8) : Color.white.opacity(0.62)
          )
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(height: 34, alignment: .top)
    }
    .padding(TileMetrics.padding)
    .frame(width: TileMetrics.width, height: TileMetrics.width)
    .background(tileBackground)
    .overlay(tileBorder)
    .contentShape(
      RoundedRectangle(cornerRadius: TileMetrics.tileCornerRadius, style: .continuous)
    )
    .onTapGesture(perform: onSelect)
    // Dragging arranges the thumbnails and nothing else: the window stays where it
    // is. The identifier travels as text because that is what a drop can carry
    // without a type of its own.
    .draggable(String(tile.id))
    .dropDestination(for: String.self) { items, _ in
      guard let text = items.first, let dragged = CGWindowID(text) else {
        return false
      }

      onMove(dragged, tile.id)
      return true
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
  }

  /// The system accent, so the frontmost window is marked the way macOS marks a
  /// selection everywhere else, and in whatever colour the user chose.
  private static let accent = Color(nsColor: .controlAccentColor)
  /// What AppKit puts on top of an accent fill, which is not always white.
  private static let textOnAccent = Color(nsColor: .alternateSelectedControlTextColor)

  /// Only the first nine tiles get a number key.
  private var shortcutLabel: String? {
    shortcutIndex < 9 ? String(shortcutIndex + 1) : nil
  }

  private var tileBackground: some View {
    RoundedRectangle(cornerRadius: TileMetrics.tileCornerRadius, style: .continuous)
      .fill(base ?? .clear)
      .overlay(
        RoundedRectangle(cornerRadius: TileMetrics.tileCornerRadius, style: .continuous)
          .fill(backgroundOpacity)
      )
  }

  private var backgroundOpacity: Color {
    if tile.isActive {
      return Self.accent
    }

    return Color.white.opacity(isSelected ? 0.22 : 0.1)
  }

  /// Two marks that must not be confused: the accent fill says which window is
  /// frontmost, the ring says which one Return will activate. The ring is white
  /// rather than another accent, so it reads on the accent fill as well as on an
  /// ordinary tile.
  private var tileBorder: some View {
    RoundedRectangle(cornerRadius: TileMetrics.tileCornerRadius, style: .continuous)
      .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
  }

  private var borderColor: Color {
    if isSelected {
      return Color.white.opacity(0.95)
    }

    return tile.isActive ? Self.accent : Color.white.opacity(0.16)
  }
}

private struct WindowThumbnailContent: View {
  let tile: WindowTileModel
  let dimsStale: Bool

  var body: some View {
    ZStack {
      if let thumbnail = tile.thumbnail {
        Image(decorative: thumbnail, scale: 1, orientation: .up)
          .resizable()
          .interpolation(.high)
          .antialiased(true)
          .scaledToFill()
          .opacity(dimsStale && tile.isThumbnailStale ? 0.72 : 1)
      } else {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.white.opacity(0.06))
          .overlay {
            VStack(spacing: 6) {
              if let icon = tile.icon {
                Image(nsImage: icon)
                  .resizable()
                  .interpolation(.high)
                  .frame(width: 38, height: 38)
              }

              if tile.isMinimized {
                Text("Minimized")
                  .font(.system(size: 10, weight: .medium))
                  .foregroundStyle(Color.white.opacity(0.42))
              }
            }
            .padding(6)
          }
      }
    }
    // Both dimensions, not just the height: `scaledToFill` on a window that is
    // much wider than it is tall makes the image wider than the tile, and a frame
    // that leaves the width free grows to match it and spills over the neighbours.
    .frame(width: TileMetrics.contentWidth, height: TileMetrics.thumbnailHeight)
    .clipped()
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(Color.white.opacity(0.14), lineWidth: 1)
    )
  }
}

private struct EmptyOverlayContent: View {
  var body: some View {
    VStack(spacing: 6) {
      Text("No switchable windows")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.72))

      Text("Tessera needs Screen Recording permission to see open windows.")
        .font(.system(size: 12))
        .foregroundStyle(Color.white.opacity(0.45))
    }
    .frame(width: 420, height: 120)
  }
}
