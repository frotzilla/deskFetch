import WidgetKit
import SwiftUI
import AppKit


struct FastfetchEntry: TimelineEntry {
    let date: Date
    let text: String
}

struct FastfetchProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastfetchEntry {
        FastfetchEntry(date: Date(), text: "Loading fastfetch...")
    }

    func getSnapshot(in context: Context, completion: @escaping (FastfetchEntry) -> Void) {
        completion(currentEntry(for: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastfetchEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry(for: context.family)], policy: .never))
    }

    private func currentEntry(for family: WidgetFamily) -> FastfetchEntry {
        let variant = (family == .systemSmall || family == .systemMedium) ? "compact" : "full"
        if let text = LocalFastfetchClient.fetchSync(variant: variant) {
            return FastfetchEntry(date: Date(), text: text)
        }
        return FastfetchEntry(
            date: Date(),
            text: "deskFetch isn't running.\nLaunch it once to start updates."
        )
    }
}

struct FastfetchWidgetView: View {
    var entry: FastfetchProvider.Entry
    @Environment(\.widgetFamily) private var family

    private var padding: CGFloat {
        family == .systemSmall ? 6 : 8
    }

    var body: some View {
        let lines = visibleLines(of: entry.text)
        let renderable = renderableText(entry.text)

        GeometryReader { geo in
            let fontSize = bestFitFontSize(lines: lines, availableSize: geo.size, allowWrapping: true)

            // Let SwiftUI's own layout engine center the content based on its
            // real rendered size via equal spacers, rather than computing an
            // offset ourselves from a measurement that can drift out of sync
            // with actual rendering.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(ansiToAttributedString(renderable, fontSize: fontSize))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(padding)
        .containerBackground(for: .widget) {
            Color.black.opacity(0.55)
        }
    }
}

struct DeskFetchInfoWidget: Widget {
    let kind: String = "DeskFetchInfo"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FastfetchProvider()) { entry in
            FastfetchWidgetView(entry: entry)
        }
        .configurationDisplayName("deskFetch")
        .description("System info from fastfetch, kept up to date by the deskFetch menu bar app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct FastfetchLogoProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastfetchEntry {
        FastfetchEntry(date: Date(), text: "")
    }

    func getSnapshot(in context: Context, completion: @escaping (FastfetchEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastfetchEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> FastfetchEntry {
        if let text = LocalFastfetchClient.fetchSync(variant: "logo") {
            return FastfetchEntry(date: Date(), text: text)
        }
        return FastfetchEntry(date: Date(), text: "Launch\ndeskFetch")
    }
}

private func stripAnsi(_ line: Substring) -> String {
    var result = ""
    var inEscape = false
    for ch in line {
        if ch == "\u{1B}" { inEscape = true; continue }
        if inEscape {
            if ch == "m" { inEscape = false }
            continue
        }
        result.append(ch)
    }
    return result
}

/// Plain-text lines with ANSI codes removed, for measurement only.
/// Never render this — it has no color information.
private func visibleLines(of text: String) -> [String] {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(stripAnsi)
    // Drop trailing blank lines produced by a trailing newline in the source text.
    while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
        lines.removeLast()
    }
    return lines
}

/// The original text with its ANSI color codes intact, trimmed of trailing
/// blank lines so it matches what `visibleLines` measured. fastfetch's output
/// ends in a newline; rendering that raw adds an invisible trailing line that
/// pushes content up off centre.
private func renderableText(_ text: String) -> String {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    while let last = lines.last, stripAnsi(last).trimmingCharacters(in: .whitespaces).isEmpty {
        lines.removeLast()
    }
    return lines.joined(separator: "\n")
}

/// The height of one line as SwiftUI's Text actually lays it out.
///
/// SwiftUI quantizes line height to whole points and adds a small amount of
/// line spacing over the raw font metric. Calibrated by rendering text at 12
/// font sizes from 6pt to 14pt and measuring the real per-line advance: every
/// sample is satisfied by `ceil(raw * k)` for k in (1.0189, 1.0311], so 1.025
/// sits safely mid-window. TextKit's `boundingRect` is up to 1pt per line
/// short of this, which is what previously caused the last line to clip.
private func swiftUILineHeight(fontSize: CGFloat) -> CGFloat {
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    return ceil((font.ascender - font.descender + font.leading) * 1.025)
}

/// Width of a single character. Monospaced, and measurement here matches
/// SwiftUI's rendering essentially exactly (verified ratio ~1.000).
private func advanceWidth(fontSize: CGFloat) -> CGFloat {
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    return NSAttributedString(string: String(repeating: "M", count: 20), attributes: [.font: font])
        .size().width / 20.0
}

/// Greedy word wrap, matching how SwiftUI breaks lines: whole words move to
/// the next line, and a word longer than the line hard-breaks. Counting
/// characters instead of words undercounts rows and overflows the box.
private func wrappedRowCount(_ line: String, charsPerLine: Int) -> Int {
    guard charsPerLine > 0 else { return 1 }
    if line.isEmpty { return 1 }
    var rows = 1
    var used = 0
    for word in line.split(separator: " ", omittingEmptySubsequences: false) {
        let wordLen = word.count
        let needed = used == 0 ? wordLen : wordLen + 1
        if used + needed <= charsPerLine {
            used += needed
        } else if wordLen > charsPerLine {
            var remaining = wordLen
            if used > 0 { rows += 1; used = 0 }
            while remaining > charsPerLine { remaining -= charsPerLine; rows += 1 }
            used = remaining
        } else {
            rows += 1
            used = wordLen
        }
    }
    return rows
}

/// Raw (ascender - descender + leading) per point of font size. Linear in size.
private let rawLineHeightPerPoint: CGFloat = {
    let f = NSFont.monospacedSystemFont(ofSize: 100, weight: .regular)
    return (f.ascender - f.descender + f.leading) / 100
}()

/// Character advance per point of font size.
private let advancePerPoint: CGFloat = advanceWidth(fontSize: 100) / 100

/// Picks a font size by searching over *integer line heights* rather than
/// continuous font size.
///
/// SwiftUI quantizes line height to whole points, so a continuous search
/// always converges exactly onto a rounding boundary, where being wrong by a
/// hair costs a full point on every line (17 lines of logo = 17pt of
/// overflow). Instead, for each candidate line height we take the largest
/// font size sitting safely inside that bucket, so small metric differences
/// can't flip the rounding.
///
/// `minFontSize` is 5pt because below that the text is an illegible smudge
/// and the metrics stop being reliable anyway.
private func bestFitFontSize(
    lines: [String],
    availableSize: CGSize,
    allowWrapping: Bool,
    minFontSize: CGFloat = 5,
    maxFontSize: CGFloat = 60
) -> CGFloat {
    guard availableSize.width > 0, availableSize.height > 0, !lines.isEmpty else { return minFontSize }
    let maxCols = CGFloat(lines.map(\.count).max() ?? 1)

    let highestLine = Int(ceil(maxFontSize * rawLineHeightPerPoint * 1.025))
    for lineHeight in stride(from: highestLine, through: 3, by: -1) {
        var fontSize = (CGFloat(lineHeight) - 0.15) / (1.025 * rawLineHeightPerPoint)
        fontSize = min(fontSize, maxFontSize)
        if !allowWrapping {
            fontSize = min(fontSize, availableSize.width / (maxCols * advancePerPoint * 1.005))
        }
        guard fontSize >= minFontSize else { continue }

        // Slightly conservative advance, so we never sit exactly on the
        // boundary where one more character forces an extra wrapped row.
        let advance = advanceWidth(fontSize: fontSize) * 1.005
        let rows: Int
        if allowWrapping {
            let charsPerLine = max(Int(availableSize.width / advance), 1)
            rows = lines.reduce(0) { $0 + wrappedRowCount($1, charsPerLine: charsPerLine) }
        } else {
            rows = lines.count
        }

        if CGFloat(rows) * CGFloat(lineHeight) <= availableSize.height,
           allowWrapping || maxCols * advance <= availableSize.width {
            return fontSize
        }
    }
    return minFontSize
}

/// Renders the ASCII logo scaled to fit, with no padding or background of
/// its own. Shared verbatim between the standalone logo widget and the combo
/// widget's logo half, so both behave identically.
///
/// The art is laid out at a fixed reference size where the text metrics are
/// exact, then scaled geometrically to fit. That keeps the real fastfetch
/// art at any size and avoids SwiftUI's whole-point line-height rounding,
/// which otherwise makes a 17-row logo overflow by a full point per line.
struct LogoContentView: View {
    var text: String

    private let referenceFontSize: CGFloat = 14

    var body: some View {
        let lines = visibleLines(of: text)
        let renderable = renderableText(text)
        let natural = logoSize(lines: lines, fontSize: referenceFontSize)

        GeometryReader { geo in
            let scale = min(geo.size.width / max(natural.width, 1),
                            geo.size.height / max(natural.height, 1))
            Text(ansiToAttributedString(renderable, fontSize: referenceFontSize))
                .fixedSize(horizontal: true, vertical: true)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Natural size of an unwrapped block of monospaced lines.
private func logoSize(lines: [String], fontSize: CGFloat) -> CGSize {
    let advance = advanceWidth(fontSize: fontSize)
    let lineHeight = swiftUILineHeight(fontSize: fontSize)
    return CGSize(width: CGFloat(lines.map(\.count).max() ?? 1) * advance,
                  height: CGFloat(lines.count) * lineHeight)
}

struct FastfetchLogoWidgetView: View {
    var entry: FastfetchLogoProvider.Entry

    var body: some View {
        LogoContentView(text: entry.text)
            .padding(3)
            .containerBackground(for: .widget) {
                Color.black.opacity(0.55)
            }
    }
}

struct DeskFetchLogoWidget: Widget {
    let kind: String = "DeskFetchLogo"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FastfetchLogoProvider()) { entry in
            FastfetchLogoWidgetView(entry: entry)
        }
        .configurationDisplayName("deskFetch Logo")
        .description("Just the ASCII logo from fastfetch.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct FastfetchComboEntry: TimelineEntry {
    let date: Date
    let logoText: String
    let infoText: String
}

struct FastfetchComboProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastfetchComboEntry {
        FastfetchComboEntry(date: Date(), logoText: "", infoText: "Loading fastfetch...")
    }

    func getSnapshot(in context: Context, completion: @escaping (FastfetchComboEntry) -> Void) {
        completion(currentEntry(for: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastfetchComboEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry(for: context.family)], policy: .never))
    }

    private func currentEntry(for family: WidgetFamily) -> FastfetchComboEntry {
        // The bigger sizes have room for the full module list.
        let infoVariant = family == .systemMedium ? "compact" : "full"
        let logo = LocalFastfetchClient.fetchSync(variant: "logo")
        let info = LocalFastfetchClient.fetchSync(variant: infoVariant)
        guard let logo, let info else {
            return FastfetchComboEntry(
                date: Date(),
                logoText: "",
                infoText: "deskFetch isn't running.\nLaunch it once to start updates."
            )
        }
        return FastfetchComboEntry(date: Date(), logoText: logo, infoText: info)
    }
}

struct FastfetchComboWidgetView: View {
    var entry: FastfetchComboEntry

    var body: some View {
        let infoLines = visibleLines(of: entry.infoText)
        let renderableInfo = renderableText(entry.infoText)
        let logoLines = visibleLines(of: entry.logoText)
        let logoNatural = logoSize(lines: logoLines, fontSize: 14)

        GeometryReader { outer in
            // Give the logo exactly the width its art needs at the scale that
            // fits the height (capped at half the widget), so it sits at the
            // left edge like the standalone logo widget instead of floating
            // in the middle of a half-width column. The info side gets the
            // rest of the width.
            let logoScale = min((outer.size.width * 0.5) / max(logoNatural.width, 1),
                                outer.size.height / max(logoNatural.height, 1))
            let logoWidth = logoNatural.width * logoScale

            HStack(spacing: 10) {
                LogoContentView(text: entry.logoText)
                    .frame(width: logoWidth)

                GeometryReader { geo in
                    let fontSize = bestFitFontSize(lines: infoLines, availableSize: geo.size, allowWrapping: true)

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Text(ansiToAttributedString(renderableInfo, fontSize: fontSize))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Leading inset matches the standalone logo widget's left margin.
        .padding(.leading, 10)
        .padding([.top, .bottom, .trailing], 8)
        .containerBackground(for: .widget) {
            Color.black.opacity(0.55)
        }
    }
}

struct DeskFetchComboWidget: Widget {
    let kind: String = "DeskFetchCombo"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FastfetchComboProvider()) { entry in
            FastfetchComboWidgetView(entry: entry)
        }
        .configurationDisplayName("deskFetch Combo")
        .description("The classic layout: ASCII logo next to system info.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

@main
struct DeskFetchWidgetBundle: WidgetBundle {
    var body: some Widget {
        DeskFetchInfoWidget()
        DeskFetchLogoWidget()
        DeskFetchComboWidget()
    }
}

#Preview("Small", as: .systemSmall) {
    DeskFetchInfoWidget()
} timeline: {
    FastfetchEntry(date: .now, text: LocalFastfetchClient.fetchSync(variant: "compact") ?? "no data")
}

#Preview("Medium", as: .systemMedium) {
    DeskFetchInfoWidget()
} timeline: {
    FastfetchEntry(date: .now, text: LocalFastfetchClient.fetchSync(variant: "compact") ?? "no data")
}

#Preview("Large", as: .systemLarge) {
    DeskFetchInfoWidget()
} timeline: {
    FastfetchEntry(date: .now, text: LocalFastfetchClient.fetchSync(variant: "full") ?? "no data")
}

#Preview("Logo Small", as: .systemSmall) {
    DeskFetchLogoWidget()
} timeline: {
    FastfetchEntry(date: .now, text: LocalFastfetchClient.fetchSync(variant: "logo") ?? "no data")
}

#Preview("Logo Large", as: .systemLarge) {
    DeskFetchLogoWidget()
} timeline: {
    FastfetchEntry(date: .now, text: LocalFastfetchClient.fetchSync(variant: "logo") ?? "no data")
}

#Preview("Combo Medium", as: .systemMedium) {
    DeskFetchComboWidget()
} timeline: {
    FastfetchComboEntry(
        date: .now,
        logoText: LocalFastfetchClient.fetchSync(variant: "logo") ?? "",
        infoText: LocalFastfetchClient.fetchSync(variant: "compact") ?? "no data"
    )
}
