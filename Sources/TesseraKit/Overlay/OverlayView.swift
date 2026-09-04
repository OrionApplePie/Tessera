import AppKit
import SwiftUI

/// The overlay's fixed geometry, in one place: the thumbnail has to be told its
/// width explicitly, and the window has to know how many tiles fit across a screen.
/// The overlay's geometry, in one place and in one unit: everything is a fraction
/// of the tile, so a bigger tile makes a bigger overlay rather than a bigger tile
/// in the same layout.
///
/// The tile is not a constant any more because a 27-inch display and a laptop
/// screen do not want the same one: on the big screen the same 190 points read as
/// a contact sheet of stamps, and on the laptop anything larger does not fit.
struct TileMetrics: Equatable, Sendable {
  /// What every other measurement here is derived from.
  let width: CGFloat

  /// What the overlay has always looked like, and what it still looks like when it
  /// is sized to its contents rather than to the screen.
  static let base = TileMetrics(width: 190)

  /// Below this a thumbnail says nothing. The upper end is only reached by an
  /// overlay filling a large screen with few Spaces on it — two displays holding
  /// one Space each, say, where the map is two tiles and the room is the screen.
  static let range: ClosedRange<CGFloat> = 150...560

  init(width: CGFloat) {
    self.width = min(max(width, Self.range.lowerBound), Self.range.upperBound)
  }

  private var scale: CGFloat { width / Self.base.width }

  var padding: CGFloat { (4 * scale).rounded() }
  var spacing: CGFloat { (6 * scale).rounded() }
  var surfacePadding: CGFloat { (10 * scale).rounded() }
  /// Room inside a group's frame, so its tiles do not touch the line drawn round
  /// them.
  var groupPadding: CGFloat { (3 * scale).rounded() }
  /// The group's corner. Between the tile's and the panel's, so the three read as
  /// nested rather than repeated.
  var groupCornerRadius: CGFloat { (6 * scale).rounded() }
  /// What is left of the tile once its label and its own padding are taken out.
  ///
  /// The picture of the window is the tile's reason to exist, so it gets the room
  /// rather than a share of it: a fixed height left a third of every tile empty.
  var thumbnailHeight: CGFloat { width - padding * 2 - labelHeight - labelGap }
  /// Between the picture and the two lines under it.
  var labelGap: CGFloat { (4 * scale).rounded() }
  /// The tile's own corner. Smaller than the panel's, so a tile reads as sitting
  /// inside it rather than repeating it.
  var tileCornerRadius: CGFloat { (4 * scale).rounded() }
  /// The panel's corner, in the register macOS uses for a floating surface of this
  /// size.
  var surfaceCornerRadius: CGFloat { (10 * scale).rounded() }
  /// The height of the two lines of text under a thumbnail.
  var labelHeight: CGFloat { (30 * scale).rounded() }
  /// The line under the map that says what is being typed. Always there, so that
  /// the map does not move when someone starts typing at it.
  var searchHeight: CGFloat { (20 * scale).rounded() }

  /// How far each card of a deck peeks out from the one in front of it, and how
  /// many cards deep that goes before the rest hide behind the last.
  var deckStep: CGSize { CGSize(width: (10 * scale).rounded(), height: 0) }
  var deckDepth: Int { 4 }

  var contentWidth: CGFloat { width - padding * 2 }

  /// The width a row of `count` tiles takes, gaps included.
  func width(forColumns count: Int) -> CGFloat {
    let columns = CGFloat(max(count, 1))

    return columns * width + (columns - 1) * spacing
  }

  /// The room one Space takes, the same for every Space on the map.
  ///
  /// Sized for the deepest deck rather than for the cards actually in it: a group
  /// as wide as its own contents made every row a different shape, and a Space
  /// gaining a window pushed its neighbours along.
  func deckSize(for style: OverlayDeckStyle) -> CGSize {
    guard style == .fan else {
      return CGSize(width: width, height: width)
    }

    return CGSize(
      width: width + deckStep.width * CGFloat(deckDepth),
      height: width + deckStep.height * CGFloat(deckDepth)
    )
  }

  /// How many tiles fit across a screen this wide, counting the gaps between them
  /// and the surface around them. Never fewer than one: a single tile too wide for
  /// the screen is still the only thing to draw.
  func columnsFitting(availableWidth: CGFloat) -> Int {
    let usable = availableWidth - surfacePadding * 2 + spacing

    return max(1, Int(usable / (width + spacing)))
  }

  /// The tile that fills a screen this wide with `columns` Spaces across.
  ///
  /// This is what "fill the screen" means in practice: the map keeps its shape and
  /// the tiles grow into the room, rather than the same small tiles floating in a
  /// large empty panel.
  static func filling(
    width available: CGFloat,
    columns: Int,
    style: OverlayDeckStyle
  ) -> TileMetrics {
    let count = CGFloat(max(columns, 1))
    // Solved for the tile: the row is `count` decks with gaps between them, inside
    // the surface's own padding, and every part of that scales with the tile.
    let perTile = base.deckSize(for: style).width + base.spacing + base.groupPadding * 2
    let fixed = base.surfacePadding * 2
    let scale = (available - fixed) / (count * perTile - base.spacing)

    return TileMetrics(width: (base.width * scale).rounded())
  }
}

/// The colour the overlay marks a choice with.
///
/// Warm rather than the system accent: the accent is already spoken for — it fills
/// the tile of the window you are in — and a second blue mark beside it was two
/// marks in one colour saying different things.
enum OverlayPalette {
  static let highlight = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
}

/// Which tile the keyboard is on. Owned by `OverlayWindowController`, which moves
/// it in response to the arrow keys.
@MainActor
/// Whether this view is being built to be measured rather than to be looked at.
///
/// Choosing a tile size means building the map a dozen times over and asking each
/// one how big it is. The pictures make no difference to that answer — every
/// thumbnail sits in a frame the tile has already fixed — but they cost most of the
/// time it takes, so a view built for the tape measure leaves them out. Measured:
/// half a second of building layouts became a fifth of it.
private struct MeasuringKey: nonisolated EnvironmentKey {
  nonisolated static let defaultValue = false
}

extension EnvironmentValues {
  nonisolated var isMeasuringOverlay: Bool {
    get { self[MeasuringKey.self] }
    set { self[MeasuringKey.self] = newValue }
  }
}

final class OverlaySelection: ObservableObject {
  @Published var index = 0
  /// What has been typed at the map so far. Shown on the panel, because a search
  /// nobody can see is a switcher that has started behaving oddly.
  @Published var query = ""
}

struct OverlayView: View {
  let metrics: TileMetrics
  @ObservedObject var windowCoordinator: WindowCoordinator
  @ObservedObject var selection: OverlaySelection
  let background: OverlayColor
  let columns: Int
  let deck: OverlayDeckStyle
  let arrangement: OverlayLayout
  /// What typing does, which decides whether there is a line under the map at all.
  let search: OverlaySearch
  @Environment(\.isMeasuringOverlay) private var isMeasuring
  let rowAlignment: OverlayRowAlignment
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
      repeating: GridItem(.fixed(metrics.width), spacing: metrics.spacing),
      count: count)
  }

  /// The map itself: a row of Spaces per band, drawn in the order the displays
  /// stand in.
  private var map: some View {
    // Rows are centred rather than left-aligned: a band of seven Spaces splits into
    // four and three, and the three hanging off the left edge under a full row read
    // as a mistake. Centred, the two rows of a band look like each other, which is
    // what makes the map symmetrical.
    VStack(alignment: rowAlignment.horizontal, spacing: metrics.spacing) {

      ForEach(Array(rows.enumerated()), id: \.offset) { row in
        HStack(alignment: .top, spacing: metrics.spacing) {
          ForEach(row.element) { entry in
            group(for: entry)
          }
        }
      }

      if search == .fuzzy {
        searchLine
      }
    }
    // Pinned in the panel the same way its rows are pinned to each other: when the
    // panel is the screen and the map is narrower, all the room left over otherwise
    // went to one side and the whole thing sat lopsided.
    .frame(maxWidth: .infinity, alignment: rowAlignment.frame)
  }

  /// What is being typed, under the map.
  ///
  /// The room it takes is there whether anything has been typed or not: appearing
  /// and disappearing, it moved every tile by its own height on the first keystroke
  /// and back again on the last, which is a poor thing to do under the eyes of
  /// someone reading the map.
  private var searchLine: some View {
    HStack(spacing: 5) {
      if !selection.query.isEmpty {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 10, weight: .semibold))

        Text(selection.query)
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .lineLimit(1)
      }
    }
    .foregroundStyle(OverlayPalette.highlight)
    .padding(.horizontal, selection.query.isEmpty ? 0 : 8)
    .frame(height: metrics.searchHeight)
    .background(Capsule().fill(Color.white.opacity(selection.query.isEmpty ? 0 : 0.10)))
  }

  private func group(for entry: SectionLayout) -> some View {
    let range = entry.offset..<(entry.offset + entry.section.targets.count)

    return WindowGroup(
      metrics: metrics,
      title: entry.section.title,
      isCurrent: entry.section.isCurrent,
      isFullscreen: entry.section.isFullscreen,
      cards: deck == .stack ? entry.section.tiles.count : 1,
      isEmpty: entry.section.tiles.isEmpty,
      isSelected: entry.section.tiles.isEmpty && entry.offset == selectedIndex,
      holdsSelection: range.contains(selectedIndex),
      onFocus: { onFocusSpace(entry.section.id) },
      desktop: entry.section.tiles.isEmpty && !isMeasuring
        ? windowCoordinator.desktopImage(
          for: entry.section.id.displayID,
          fitting: metrics.deckSize(for: deck))
        : nil,
      content: {
        WindowDeck(
          metrics: metrics,
          tiles: entry.section.tiles,
          offset: entry.offset,
          selectedIndex: selectedIndex,
          style: deck,
          base: entry.section.tiles.count > 1 ? Color(background.opaque) : nil,
          dimsStaleThumbnails: dimsStaleThumbnails,
          onMove: onMove,
          onSelect: onSelect
        )
      }
    )
    // Its own width and no more: the heading inside a group takes any width it is
    // offered, so in a row shorter than the widest one the groups grew to fill it.
    .fixedSize(horizontal: true, vertical: false)
  }

  /// The map's rows, built by the same rule the arrow keys move by, so that what
  /// the eye sees and what the keyboard walks are one thing.
  private var rows: [[SectionLayout]] {
    let entries = layout

    return OverlayGrid.spaceRows(
      ofDisplays: entries.map(\.section.id.displayID),
      perRow: columns,
      banded: arrangement.isBanded
    )
    .map { row in row.compactMap { entries[safe: $0] } }
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
        map
      }
    }
    .padding(metrics.surfacePadding)
    .background(
      RoundedRectangle(cornerRadius: metrics.surfaceCornerRadius, style: .continuous)
        .fill(Color(background))
    )
    .overlay(
      RoundedRectangle(cornerRadius: metrics.surfaceCornerRadius, style: .continuous)
        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
    )
    .onExitCommand(perform: onClose)
  }
}

/// The windows of one group — a display, a Space, or both — drawn as one thing.
///
/// A heading alone left the eye to work out where one group ended and the next
/// began, which is a poor way to show something as separate as a Space. The frame
/// says it outright, and the heading sits inside it rather than floating above.
private struct WindowGroup<Content: View>: View {
  let metrics: TileMetrics
  let title: String
  var isCurrent: Bool = false
  var isFullscreen: Bool = false
  /// How many windows the deck holds, when the deck is drawn as one card and the
  /// others are behind it. One means there is nothing to count.
  var cards: Int = 1
  var isEmpty: Bool = false
  /// An empty Space carries the highlight itself: there is no tile in it to carry.
  var isSelected: Bool = false
  /// The Space the highlight is in, which is not the Space you are on: one says
  /// where the keyboard is, the other where you are.
  var holdsSelection: Bool = false
  var onFocus: () -> Void = {}
  var desktop: CGImage?
  @ViewBuilder let content: Content

  var body: some View {
    if title.isEmpty {
      // Nothing to tell apart: one display, one Space, no frame worth drawing.
      content
    } else {
      VStack(alignment: .leading, spacing: metrics.labelGap) {
        HStack(spacing: 5) {
          if isFullscreen {
            // The Space of a fullscreen window: one window, and no room for another.
            Image(systemName: "arrow.up.left.and.arrow.down.right")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(Color.white.opacity(0.5))
          }

          SectionHeading(title: title)
            .lineLimit(1)

          if cards > 1 {
            Spacer(minLength: 6)

            // The card on top hides the rest, so the count is what says they are
            // there at all.
            HStack(spacing: 3) {
              Image(systemName: "square.stack")
                .font(.system(size: 9, weight: .semibold))
              Text("\(cards)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color.white.opacity(0.62))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)

        if isEmpty {
          // A Space with nothing on it is still a place, and it is drawn as what it
          // is: the desktop, dimmed, in the room one window would take. A Space you
          // are not on cannot be captured, so this is its wallpaper rather than a
          // picture of it.
          RoundedRectangle(cornerRadius: metrics.tileCornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.03))
            .frame(width: metrics.width, height: metrics.width)
            .overlay {
              if let desktop {
                Image(decorative: desktop, scale: 1, orientation: .up)
                  .resizable()
                  .scaledToFill()
                  .opacity(0.55)
                  .clipShape(
                    RoundedRectangle(
                      cornerRadius: metrics.tileCornerRadius, style: .continuous))
              }
            }
            .overlay(
              RoundedRectangle(cornerRadius: metrics.tileCornerRadius, style: .continuous)
                .stroke(OverlayPalette.highlight, lineWidth: isSelected ? 1.5 : 0)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onFocus)
        } else {
          content
        }
      }
      .padding(metrics.groupPadding)
      .background(
        RoundedRectangle(cornerRadius: metrics.groupCornerRadius, style: .continuous)
          .fill(
            holdsSelection
              ? OverlayPalette.highlight.opacity(0.10)
              : Color.white.opacity(isCurrent ? 0.09 : 0.035)
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: metrics.groupCornerRadius, style: .continuous)
          .stroke(
            holdsSelection
              ? OverlayPalette.highlight.opacity(0.85)
              : Color.white.opacity(isCurrent ? 0.28 : 0.08),
            lineWidth: holdsSelection ? 1.25 : (isCurrent ? 0.75 : 0.5)
          )
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
  let metrics: TileMetrics
  let tiles: [WindowTileModel]
  /// The flat index of the first card, which is what the highlight and the number
  /// keys address.
  let offset: Int
  let selectedIndex: Int
  let style: OverlayDeckStyle
  /// What a card is painted on when it has another one behind it. The tiles are
  /// translucent by design and the panel is too, so stacked without a backing they
  /// showed each other's titles through their own.
  let base: Color?
  let dimsStaleThumbnails: Bool
  let onMove: (CGWindowID, CGWindowID) -> Void
  let onSelect: (CGWindowID) -> Void

  var body: some View {
    switch style {
    case .fan:
      fanned
    case .stack:
      stacked
    }
  }

  /// Every card visible, each behind the one in front of it by a strip.
  private var fanned: some View {
    let size = metrics.deckSize(for: .fan)

    return ZStack(alignment: .topLeading) {
      ForEach(Array(tiles.enumerated()), id: \.element.id) { item in
        card(at: item.offset, tile: item.element)
          // Past the last step the cards sit on the one before them: they are
          // hidden either way, and a deck that kept growing would be no more
          // compact than a row.
          .offset(
            x: metrics.deckStep.width * CGFloat(min(item.offset, metrics.deckDepth)),
            y: metrics.deckStep.height * CGFloat(min(item.offset, metrics.deckDepth))
          )
      }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
  }

  /// One card, and the group stays one window wide however many it holds. Stepping
  /// through the Space turns the card over instead of moving the stack: with the
  /// cards squarely on top of each other there is nothing else to see move, and a
  /// swap with no motion at all reads as a redraw rather than as a step.
  private var stacked: some View {
    ZStack {
      if let front {
        card(at: front.position, tile: front.tile)
          .id(front.tile.id)
          .transition(
            .asymmetric(
              insertion: .modifier(active: CardTurn(degrees: -84), identity: CardTurn(degrees: 0)),
              removal: .modifier(active: CardTurn(degrees: 84), identity: CardTurn(degrees: 0))
            )
          )
      }
    }
    .frame(
      width: metrics.deckSize(for: .stack).width,
      height: metrics.deckSize(for: .stack).height
    )
    .animation(.easeInOut(duration: 0.2), value: selectedIndex)
  }

  /// The card on top: the highlighted one while the highlight is in this Space, and
  /// the first otherwise.
  private var front: (position: Int, tile: WindowTileModel)? {
    let here = selectedIndex - offset

    if tiles.indices.contains(here) {
      return (here, tiles[here])
    }

    return tiles.first.map { (0, $0) }
  }

  private func card(at position: Int, tile: WindowTileModel) -> some View {
    let isSelected = offset + position == selectedIndex

    return WindowTileButton(
      metrics: metrics,
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
      color: .black.opacity(isSelected ? 0.38 : 0.22),
      radius: isSelected ? 10 : 5,
      y: isSelected ? 4 : 2
    )
    .zIndex(isSelected ? Double(tiles.count) : Double(position))
  }
}

/// A card mid-turn: rotated about its own vertical axis and gone by the time it is
/// edge-on, so two cards never show through each other.
private struct CardTurn: ViewModifier {
  let degrees: Double

  func body(content: Content) -> some View {
    content
      .rotation3DEffect(.degrees(degrees), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
      .opacity(degrees == 0 ? 1 : 0)
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
      .font(.system(size: 9.5, weight: .medium))
      .tracking(1.1)
      .textCase(.uppercase)
      .foregroundStyle(Color.white.opacity(0.34))
      .lineLimit(1)
      .padding(.leading, 2)
  }
}

private struct WindowTileButton: View {
  let metrics: TileMetrics
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
    VStack(alignment: .leading, spacing: metrics.labelGap) {
      WindowThumbnailContent(metrics: metrics, tile: tile, dimsStale: dimsStaleThumbnails)

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
      .frame(height: metrics.labelHeight, alignment: .top)
    }
    .padding(metrics.padding)
    .frame(width: metrics.width, height: metrics.width)
    .background(tileBackground)
    .overlay(tileBorder)
    .contentShape(
      RoundedRectangle(cornerRadius: metrics.tileCornerRadius, style: .continuous)
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
    RoundedRectangle(cornerRadius: metrics.tileCornerRadius, style: .continuous)
      .fill(base ?? .clear)
      .overlay(
        RoundedRectangle(cornerRadius: metrics.tileCornerRadius, style: .continuous)
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
  /// frontmost, the ring says which one Return will activate.
  private var tileBorder: some View {
    RoundedRectangle(cornerRadius: metrics.tileCornerRadius, style: .continuous)
      .stroke(borderColor, lineWidth: isSelected ? 1.5 : 0.5)
  }

  private var borderColor: Color {
    if isSelected {
      return OverlayPalette.highlight
    }

    return tile.isActive ? Self.accent : Color.white.opacity(0.12)
  }
}

private struct WindowThumbnailContent: View {
  let metrics: TileMetrics
  let tile: WindowTileModel
  let dimsStale: Bool
  @Environment(\.isMeasuringOverlay) private var isMeasuring

  var body: some View {
    ZStack {
      if let thumbnail = tile.thumbnail, !isMeasuring {
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
              if let icon = tile.icon, !isMeasuring {
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
    .frame(width: metrics.contentWidth, height: metrics.thumbnailHeight)
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
