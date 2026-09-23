import SwiftUI

private let basicColors: [Color] = [
    Color(red: 0.0, green: 0.0, blue: 0.0),
    Color(red: 0.80, green: 0.0, blue: 0.0),
    Color(red: 0.31, green: 0.60, blue: 0.02),
    Color(red: 0.77, green: 0.63, blue: 0.0),
    Color(red: 0.20, green: 0.40, blue: 0.64),
    Color(red: 0.46, green: 0.31, blue: 0.48),
    Color(red: 0.02, green: 0.60, blue: 0.60),
    Color(red: 0.83, green: 0.84, blue: 0.81),
    Color(red: 0.33, green: 0.34, blue: 0.33),
    Color(red: 0.94, green: 0.16, blue: 0.16),
    Color(red: 0.54, green: 0.89, blue: 0.20),
    Color(red: 0.99, green: 0.91, blue: 0.31),
    Color(red: 0.45, green: 0.62, blue: 0.81),
    Color(red: 0.68, green: 0.50, blue: 0.66),
    Color(red: 0.20, green: 0.89, blue: 0.89),
    Color(red: 0.93, green: 0.93, blue: 0.93),
]

private func color256(_ idx: Int) -> Color {
    if idx < 16 { return basicColors[idx] }
    if idx >= 232 {
        let v = Double(8 + (idx - 232) * 10) / 255.0
        return Color(red: v, green: v, blue: v)
    }
    let i = idx - 16
    let levels: [Double] = [0, 95, 135, 175, 215, 255]
    let r = levels[i / 36] / 255.0
    let g = levels[(i % 36) / 6] / 255.0
    let b = levels[i % 6] / 255.0
    return Color(red: r, green: g, blue: b)
}

func ansiToAttributedString(_ text: String, fontSize: CGFloat = 11) -> AttributedString {
    var result = AttributedString()
    var currentColor: Color?
    var bold = false

    // Accumulate consecutive characters that share the same style into a
    // single run instead of emitting one run per character. Fragmenting
    // AttributedString into hundreds of single-character runs makes
    // SwiftUI's real line-wrapping behave differently from how a plain
    // String of the same text would wrap, which throws off any size
    // estimate computed against a plain-string measurement.
    var pendingChars = ""
    var pendingColor: Color?
    var pendingBold = false

    func flushPending() {
        guard !pendingChars.isEmpty else { return }
        var run = AttributedString(pendingChars)
        if let pendingColor { run.foregroundColor = pendingColor }
        run.font = pendingBold
            ? .system(size: fontSize, weight: .bold, design: .monospaced)
            : .system(size: fontSize, design: .monospaced)
        result += run
        pendingChars = ""
    }

    var index = text.startIndex
    while index < text.endIndex {
        let char = text[index]
        if char == "\u{1B}" {
            let next = text.index(after: index)
            if next < text.endIndex, text[next] == "[" {
                flushPending()
                var scanIndex = text.index(after: next)
                var code = ""
                while scanIndex < text.endIndex, text[scanIndex] != "m" {
                    code.append(text[scanIndex])
                    scanIndex = text.index(after: scanIndex)
                }
                if scanIndex < text.endIndex {
                    let codes = code.split(separator: ";").compactMap { Int($0) }
                    let effectiveCodes = codes.isEmpty ? [0] : codes
                    var i = 0
                    while i < effectiveCodes.count {
                        let c = effectiveCodes[i]
                        switch c {
                        case 0: currentColor = nil; bold = false
                        case 1: bold = true
                        case 22: bold = false
                        case 39: currentColor = nil
                        case 30...37: currentColor = basicColors[c - 30]
                        case 90...97: currentColor = basicColors[8 + (c - 90)]
                        case 38:
                            if i + 2 < effectiveCodes.count, effectiveCodes[i + 1] == 5 {
                                currentColor = color256(effectiveCodes[i + 2])
                                i += 2
                            } else if i + 4 < effectiveCodes.count, effectiveCodes[i + 1] == 2 {
                                let r = Double(effectiveCodes[i + 2]) / 255.0
                                let g = Double(effectiveCodes[i + 3]) / 255.0
                                let b = Double(effectiveCodes[i + 4]) / 255.0
                                currentColor = Color(red: r, green: g, blue: b)
                                i += 4
                            }
                        default: break
                        }
                        i += 1
                    }
                    index = text.index(after: scanIndex)
                    continue
                }
            }
        }

        if !pendingChars.isEmpty, (pendingColor != currentColor || pendingBold != bold) {
            flushPending()
        }
        pendingColor = currentColor
        pendingBold = bold
        pendingChars.append(char)
        index = text.index(after: index)
    }
    flushPending()
    return result
}
