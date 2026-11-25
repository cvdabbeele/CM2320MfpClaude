// CM2320Core.swift
// Created: 2026-11-25 22:25
//
// Core logic of the CM2320MfpClaude CUPS pre-filter: option parsing, PPD
// reading, page sequencing (booklet, letterhead) and PDF rendering (booklet
// imposition, rotate 180, watermark). No I/O with CUPS here, so it can be
// unit tested. License: MIT.

import CoreGraphics
import CoreText
import Foundation

// MARK: - CUPS option parsing

/// Parses a CUPS option string (argv[5] of a filter) into a dictionary.
///
/// Supports `name=value`, quoted values (`name='a b'`, `name="a b"`),
/// backslash escapes, bare `name` (meaning `true`) and `noname` for a
/// name given without value and starting with "no" (meaning `false` for
/// `name`). Later options override earlier ones.
/// - Parameter text: The raw option string.
/// - Returns: Option names mapped to their values.
public func parseCupsOptions(_ text: String) -> [String: String] {
    var result: [String: String] = [:]
    var chars = Array(text)
    chars.append(" ")
    var i = 0
    while i < chars.count {
        while i < chars.count && chars[i].isWhitespace { i += 1 }
        if i >= chars.count { break }
        var name = ""
        while i < chars.count && !chars[i].isWhitespace && chars[i] != "=" {
            name.append(chars[i]); i += 1
        }
        if i < chars.count && chars[i] == "=" {
            i += 1
            var value = ""
            var quote: Character? = nil
            while i < chars.count {
                let c = chars[i]
                if let q = quote {
                    if c == q { quote = nil; i += 1; continue }
                    if c == "\\" && i + 1 < chars.count { value.append(chars[i + 1]); i += 2; continue }
                    value.append(c); i += 1
                } else {
                    if c.isWhitespace { break }
                    if c == "'" || c == "\"" { quote = c; i += 1; continue }
                    if c == "\\" && i + 1 < chars.count { value.append(chars[i + 1]); i += 2; continue }
                    value.append(c); i += 1
                }
            }
            if !name.isEmpty { result[name] = value }
        } else if !name.isEmpty {
            if name.hasPrefix("no") && name.count > 2 {
                result[String(name.dropFirst(2))] = "false"
            } else {
                result[name] = "true"
            }
        }
    }
    return result
}

// MARK: - PPD reading

/// Reads all `*DefaultKeyword: Choice` lines of a PPD file.
/// - Parameter ppdText: Full text of the PPD file.
/// - Returns: Option keywords mapped to their default choice.
public func ppdDefaults(_ ppdText: String) -> [String: String] {
    var result: [String: String] = [:]
    for rawLine in ppdText.split(whereSeparator: \.isNewline) {
        let line = String(rawLine)
        guard line.hasPrefix("*Default"), let colon = line.firstIndex(of: ":") else { continue }
        let key = String(line[line.index(line.startIndex, offsetBy: 8)..<colon])
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if !key.isEmpty { result[key] = value }
    }
    return result
}

/// Reads all `*PaperDimension Name/Text: "w h"` lines of a PPD file.
/// - Parameter ppdText: Full text of the PPD file.
/// - Returns: Page size names mapped to their size in points.
public func ppdPaperDimensions(_ ppdText: String) -> [String: CGSize] {
    var result: [String: CGSize] = [:]
    for rawLine in ppdText.split(whereSeparator: \.isNewline) {
        let line = String(rawLine)
        guard line.hasPrefix("*PaperDimension "), let quote1 = line.firstIndex(of: "\"") else { continue }
        let afterKeyword = line.dropFirst("*PaperDimension ".count)
        let name = String(afterKeyword.prefix { $0 != "/" && $0 != ":" })
        let numbers = line[line.index(after: quote1)...]
            .replacingOccurrences(of: "\"", with: "")
            .split(separator: " ")
            .compactMap { Double($0) }
        if numbers.count == 2 && !name.isEmpty {
            result[name] = CGSize(width: numbers[0], height: numbers[1])
        }
    }
    return result
}

// MARK: - Settings

/// Booklet binding side.
public enum BookletMode: Equatable {
    case off, left, right
}

/// Everything the pre-filter needs to know about one job.
public struct FilterSettings: Equatable {
    /// Booklet imposition mode.
    public var booklet: BookletMode = .off
    /// Letterhead mode: insert blank backs so simplex pages use the duplex path.
    public var letterhead: Bool = false
    /// Rotate every output page by 180 degrees.
    public var rotate180: Bool = false
    /// Watermark text, or nil for no watermark.
    public var watermark: String? = nil
    /// Watermark only on the first logical page.
    public var watermarkFirstPageOnly: Bool = false
    /// Watermark opacity (0...1).
    public var watermarkAlpha: CGFloat = 0.2
    /// Duplex mode chosen by the user ("None", "DuplexNoTumble", "DuplexTumble").
    public var userDuplex: String = "None"
    /// Sheet size for booklet imposition, if known.
    public var sheetSize: CGSize? = nil

    /// Creates default settings (no processing).
    public init() {}

    /// True when the pre-filter has to change the document at all.
    public var needsProcessing: Bool {
        return booklet != .off || letterhead || rotate180 || watermark != nil
    }
}

/// Maps a `CMWmText` choice to the text that is printed.
/// - Parameter choice: The PPD choice keyword.
/// - Returns: The watermark text, or nil for "Off" or an unknown choice.
public func watermarkText(forChoice choice: String) -> String? {
    switch choice {
    case "Draft": return "DRAFT"
    case "Confidential": return "CONFIDENTIAL"
    case "Copy": return "COPY"
    case "Sample": return "SAMPLE"
    case "Internal": return "INTERNAL"
    case "DoNotCopy": return "DO NOT COPY"
    default: return nil
    }
}

/// Interprets a CUPS boolean option value.
/// - Parameter value: Option value such as "True", "yes", "on", "1".
/// - Returns: True for a true value, false otherwise (including nil).
public func isTrue(_ value: String?) -> Bool {
    guard let v = value?.lowercased() else { return false }
    return v == "true" || v == "yes" || v == "on" || v == "1"
}

/// Converts a length with unit suffix (pt, mm, cm, in) to points.
/// - Parameters:
///   - number: The numeric value.
///   - unit: Unit name; empty means points.
/// - Returns: The length in points, or nil for an unknown unit.
public func toPoints(_ number: Double, unit: String) -> Double? {
    switch unit.lowercased() {
    case "", "pt": return number
    case "mm": return number * 72.0 / 25.4
    case "cm": return number * 72.0 / 2.54
    case "in": return number * 72.0
    default: return nil
    }
}

/// Resolves a page size name (PPD name, `Custom.WxH`, or IPP self-describing
/// name such as `iso_a4_210x297mm`) to a size in points.
/// - Parameters:
///   - name: The size name from the job options.
///   - dimensions: PPD page sizes (name to size).
/// - Returns: The size in points, or nil when the name is not understood.
public func resolvePageSize(_ name: String, dimensions: [String: CGSize]) -> CGSize? {
    if let exact = dimensions[name] { return exact }
    if let match = dimensions.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame }) {
        return match.value
    }
    let lower = name.lowercased()
    if lower.hasPrefix("custom.") {
        let spec = String(lower.dropFirst("custom.".count))
        return parseSizeSpec(spec, defaultUnit: "")
    }
    // IPP self-describing name: class_name_WxHunit
    if let last = lower.split(separator: "_").last, let size = parseSizeSpec(String(last), defaultUnit: nil) {
        return size
    }
    return nil
}

/// Parses "WxH" with an optional unit suffix on the whole spec (for example
/// "210x297mm", "8.5x11in", "595x842").
/// - Parameters:
///   - spec: The size text.
///   - defaultUnit: Unit to use when the spec has none; nil means a unit is required.
/// - Returns: The size in points, or nil when the text is not a size.
public func parseSizeSpec(_ spec: String, defaultUnit: String?) -> CGSize? {
    let units = ["mm", "cm", "in", "pt"]
    var body = spec
    var unit = ""
    for u in units where spec.hasSuffix(u) {
        unit = u
        body = String(spec.dropLast(u.count))
        break
    }
    if unit.isEmpty {
        guard let d = defaultUnit else { return nil }
        unit = d
    }
    let parts = body.split(separator: "x")
    guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]),
          let wp = toPoints(w, unit: unit), let hp = toPoints(h, unit: unit), wp > 0, hp > 0 else { return nil }
    return CGSize(width: wp, height: hp)
}

/// Builds the filter settings from the job options and the PPD.
/// Job options win over PPD defaults.
/// - Parameters:
///   - options: Parsed job options (argv[5]).
///   - defaults: PPD default choices.
///   - dimensions: PPD page sizes.
/// - Returns: The settings for this job.
public func resolveSettings(options: [String: String],
                            defaults: [String: String],
                            dimensions: [String: CGSize]) -> FilterSettings {
    func value(_ key: String) -> String? { options[key] ?? defaults[key] }
    var s = FilterSettings()

    switch value("CMBooklet") ?? "Off" {
    case "LeftBinding": s.booklet = .left
    case "RightBinding": s.booklet = .right
    default: s.booklet = .off
    }
    s.letterhead = isTrue(value("CMLetterhead")) && s.booklet == .off
    s.rotate180 = isTrue(value("CMRotate180"))

    if let custom = options["CMWmCustomText"], !custom.isEmpty {
        s.watermark = custom
    } else {
        s.watermark = watermarkText(forChoice: value("CMWmText") ?? "Off")
    }
    s.watermarkFirstPageOnly = (value("CMWmPages") ?? "All") == "First"
    switch value("CMWmIntensity") ?? "Medium" {
    case "Light": s.watermarkAlpha = 0.12
    case "Dark": s.watermarkAlpha = 0.35
    default: s.watermarkAlpha = 0.2
    }

    if let d = options["Duplex"] {
        s.userDuplex = d
    } else if let sides = options["sides"] {
        switch sides {
        case "two-sided-long-edge": s.userDuplex = "DuplexNoTumble"
        case "two-sided-short-edge": s.userDuplex = "DuplexTumble"
        default: s.userDuplex = "None"
        }
    } else {
        s.userDuplex = defaults["Duplex"] ?? "None"
    }

    let sizeNames = [options["PageSize"], options["PageRegion"],
                     options["media"]?.split(separator: ",").first.map(String.init),
                     defaults["PageSize"]].compactMap { $0 }
    for n in sizeNames {
        if let size = resolvePageSize(n, dimensions: dimensions) { s.sheetSize = size; break }
    }
    return s
}

// MARK: - Page sequencing

/// One side of a booklet sheet: the logical pages on the left and right half
/// of the spread (0-based page index, nil for a blank half).
public struct BookletSide: Equatable {
    /// Page on the left half of the spread.
    public let left: Int?
    /// Page on the right half of the spread.
    public let right: Int?
}

/// Computes the booklet page order.
///
/// The page count is padded to a multiple of 4 with blank pages. Sheet `i`
/// has front `[n-2i, 2i+1]` and back `[2i+2, n-2i-1]` (1-based, left
/// binding). Right binding swaps left and right on every side.
/// - Parameters:
///   - pageCount: Number of logical pages in the document.
///   - mode: Binding side (`.off` returns an empty list).
/// - Returns: Output sides in print order (front, back, front, back, ...).
public func bookletSides(pageCount: Int, mode: BookletMode) -> [BookletSide] {
    guard mode != .off, pageCount > 0 else { return [] }
    let padded = ((pageCount + 3) / 4) * 4
    func page(_ oneBased: Int) -> Int? { oneBased <= pageCount ? oneBased - 1 : nil }
    var sides: [BookletSide] = []
    for i in 0..<(padded / 4) {
        let front = (page(padded - 2 * i), page(2 * i + 1))
        let back = (page(2 * i + 2), page(padded - 2 * i - 1))
        if mode == .left {
            sides.append(BookletSide(left: front.0, right: front.1))
            sides.append(BookletSide(left: back.0, right: back.1))
        } else {
            sides.append(BookletSide(left: front.1, right: front.0))
            sides.append(BookletSide(left: back.1, right: back.0))
        }
    }
    return sides
}

/// Computes the letterhead page order: every page followed by a blank back,
/// but only for jobs the user prints single-sided.
/// - Parameters:
///   - pageCount: Number of logical pages.
///   - userDuplex: The duplex mode the user chose.
/// - Returns: Output pages (0-based index, nil for blank).
public func letterheadSequence(pageCount: Int, userDuplex: String) -> [Int?] {
    if userDuplex != "None" { return (0..<pageCount).map { Optional($0) } }
    var out: [Int?] = []
    for p in 0..<pageCount { out.append(p); out.append(nil) }
    return out
}

// MARK: - Rendering

/// Size of a PDF page as it is shown (crop box, with /Rotate applied).
/// - Parameter page: The PDF page.
/// - Returns: Displayed width and height in points.
public func displaySize(of page: CGPDFPage) -> CGSize {
    let box = page.getBoxRect(.cropBox)
    let rotation = ((page.rotationAngle % 360) + 360) % 360
    return (rotation == 90 || rotation == 270)
        ? CGSize(width: box.height, height: box.width)
        : box.size
}

/// Draws a diagonal watermark centred in `rect`.
/// - Parameters:
///   - text: The watermark text.
///   - rect: The area of the logical page (in the current user space).
///   - alpha: Opacity of the grey text.
///   - context: The PDF context to draw into.
public func drawWatermark(_ text: String, in rect: CGRect, alpha: CGFloat, context: CGContext) {
    let diagonal = hypot(rect.width, rect.height)
    let angle = atan2(rect.height, rect.width)
    let probeFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 100, nil)
    let probeWidth = textWidth(text, font: probeFont)
    guard probeWidth > 0 else { return }
    let fontSize = min(100 * (diagonal * 0.7) / probeWidth, rect.height * 0.25 * 2)
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
    let color = CGColor(gray: 0.4, alpha: alpha)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.saveGState()
    context.translateBy(x: rect.midX, y: rect.midY)
    context.rotate(by: angle)
    context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
    CTLineDraw(line, context)
    context.restoreGState()
}

/// Measures the typographic width of a single line of text.
/// - Parameters:
///   - text: The text.
///   - font: The font.
/// - Returns: Width in points.
public func textWidth(_ text: String, font: CTFont) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

/// Draws one logical page scaled to fit and centred in `target`, plus the
/// watermark when requested.
/// - Parameters:
///   - page: The source page.
///   - target: Destination rectangle in the current user space.
///   - watermark: Watermark text or nil.
///   - alpha: Watermark opacity.
///   - context: The PDF context.
public func drawLogicalPage(_ page: CGPDFPage, in target: CGRect, watermark: String?,
                            alpha: CGFloat, context: CGContext) {
    let size = displaySize(of: page)
    let scale = min(target.width / size.width, target.height / size.height)
    let drawn = CGSize(width: size.width * scale, height: size.height * scale)
    let origin = CGPoint(x: target.midX - drawn.width / 2, y: target.midY - drawn.height / 2)

    context.saveGState()
    context.translateBy(x: origin.x, y: origin.y)
    context.scaleBy(x: scale, y: scale)
    // Map the page box (with its /Rotate) onto (0, 0, size).
    let transform = page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size),
                                             rotate: 0, preserveAspectRatio: true)
    context.saveGState()
    context.clip(to: CGRect(origin: .zero, size: size))
    context.concatenate(transform)
    context.drawPDFPage(page)
    context.restoreGState()
    if let text = watermark {
        drawWatermark(text, in: CGRect(origin: .zero, size: size), alpha: alpha, context: context)
    }
    context.restoreGState()
}

/// Errors of the renderer.
public enum RenderError: Error, Equatable {
    /// The PDF context could not be created.
    case cannotCreateContext
    /// The input document has no pages.
    case emptyDocument
}

/// Renders the processed document as PDF data.
/// - Parameters:
///   - document: The input PDF.
///   - settings: What to do.
/// - Returns: The output PDF.
/// - Throws: `RenderError` when the input is empty or no context can be made.
public func renderDocument(_ document: CGPDFDocument, settings: FilterSettings) throws -> Data {
    let pageCount = document.numberOfPages
    guard pageCount > 0 else { throw RenderError.emptyDocument }
    let pages: [CGPDFPage] = (1...pageCount).compactMap { document.page(at: $0) }

    let output = NSMutableData()
    guard let consumer = CGDataConsumer(data: output as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
        throw RenderError.cannotCreateContext
    }

    /// Returns the watermark for logical page `index`, honouring "first page only".
    func watermark(for index: Int) -> String? {
        guard let text = settings.watermark else { return nil }
        return (settings.watermarkFirstPageOnly && index != 0) ? nil : text
    }

    /// Starts a page of `size`, applying the 180 degree rotation when set.
    func beginPage(_ size: CGSize) {
        var box = CGRect(origin: .zero, size: size)
        context.beginPage(mediaBox: &box)
        if settings.rotate180 {
            context.translateBy(x: size.width, y: size.height)
            context.rotate(by: .pi)
        }
    }

    if settings.booklet != .off {
        let sheet = settings.sheetSize ?? displaySize(of: pages[0])
        // Sheet is portrait; the spread is landscape and drawn rotated 90 degrees.
        let portrait = CGSize(width: min(sheet.width, sheet.height), height: max(sheet.width, sheet.height))
        let spread = CGSize(width: portrait.height, height: portrait.width)
        for side in bookletSides(pageCount: pageCount, mode: settings.booklet) {
            beginPage(portrait)
            context.saveGState()
            context.concatenate(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: portrait.width, ty: 0))
            let halves = [(side.left, CGRect(x: 0, y: 0, width: spread.width / 2, height: spread.height)),
                          (side.right, CGRect(x: spread.width / 2, y: 0, width: spread.width / 2, height: spread.height))]
            for (index, rect) in halves {
                if let i = index {
                    drawLogicalPage(pages[i], in: rect, watermark: watermark(for: i),
                                    alpha: settings.watermarkAlpha, context: context)
                }
            }
            context.restoreGState()
            context.endPage()
        }
    } else {
        let sequence: [Int?] = settings.letterhead
            ? letterheadSequence(pageCount: pageCount, userDuplex: settings.userDuplex)
            : (0..<pageCount).map { Optional($0) }
        var lastSize = displaySize(of: pages[0])
        for entry in sequence {
            if let i = entry {
                let size = displaySize(of: pages[i])
                lastSize = size
                beginPage(size)
                drawLogicalPage(pages[i], in: CGRect(origin: .zero, size: size),
                                watermark: watermark(for: i), alpha: settings.watermarkAlpha, context: context)
            } else {
                beginPage(lastSize)
            }
            context.endPage()
        }
    }
    context.closePDF()
    return output as Data
}
