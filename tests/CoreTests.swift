// CoreTests.swift
// Created: 2026-11-25 22:30
//
// Unit tests for CM2320Core.swift. XCTest is not part of the Command Line
// Tools, so this is a small self-contained test runner.
// Build and run: ./scripts/test.sh
// Arguments: [path to ppd/CM2320MfpClaude.ppd] [path for a sample PDF to write]

import CoreGraphics
import Foundation

var failures = 0
var checks = 0

/// Records one check and prints failures.
/// - Parameters:
///   - condition: The checked condition.
///   - message: Description shown when the check fails.
///   - line: Source line of the check.
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

/// Checks two equatable values for equality.
/// - Parameters:
///   - a: Actual value.
///   - b: Expected value.
///   - message: Description of the check.
///   - line: Source line of the check.
func checkEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, line: Int = #line) {
    check(a == b, "\(message): got \(a), expected \(b)", line: line)
}

// MARK: - Helpers

let a4 = CGSize(width: 595, height: 842)

/// Makes a test PDF: page i is filled with grey level `grays[i]` and has a
/// black band (80 pt) along the top edge, to detect orientation.
/// - Parameters:
///   - grays: Fill grey level (0 = black, 1 = white) for each page.
///   - size: Page size.
///   - band: Draw the top band.
/// - Returns: The PDF document.
func makePDF(grays: [CGFloat], size: CGSize = a4, band: Bool = true) -> CGPDFDocument {
    let data = NSMutableData()
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    let context = CGContext(consumer: consumer, mediaBox: nil, nil)!
    for g in grays {
        var box = CGRect(origin: .zero, size: size)
        context.beginPage(mediaBox: &box)
        context.setFillColor(gray: g, alpha: 1)
        context.fill(box)
        if band {
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: size.height - 80, width: size.width, height: 80))
        }
        context.endPage()
    }
    context.closePDF()
    return CGPDFDocument(CGDataProvider(data: data as CFData)!)!
}

/// Renders a PDF page to an 8-bit grey bitmap at 1/4 scale.
/// - Parameter page: The page.
/// - Returns: A function giving the grey value (0-255) at a relative position
///   (0...1, origin bottom-left), and the page size.
func rasterize(_ page: CGPDFPage) -> (sample: (CGFloat, CGFloat) -> Int, size: CGSize) {
    let box = page.getBoxRect(.mediaBox)
    let w = Int(box.width / 4), h = Int(box.height / 4)
    let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    context.scaleBy(x: 0.25, y: 0.25)
    context.drawPDFPage(page)
    // Copy the pixels: the bitmap memory is freed together with the context.
    let buffer = Array(UnsafeBufferPointer(start: context.data!.bindMemory(to: UInt8.self, capacity: w * h),
                                           count: w * h))
    let sample: (CGFloat, CGFloat) -> Int = { rx, ry in
        let x = min(w - 1, max(0, Int(rx * CGFloat(w))))
        let yFromBottom = min(h - 1, max(0, Int(ry * CGFloat(h))))
        // Bitmap memory row 0 is the top row.
        return Int(buffer[(h - 1 - yFromBottom) * w + x])
    }
    return (sample, box.size)
}

/// Renders a document and reopens the result.
/// - Parameters:
///   - document: Input PDF.
///   - settings: Filter settings.
/// - Returns: The output PDF document.
func render(_ document: CGPDFDocument, _ settings: FilterSettings) -> CGPDFDocument {
    let data = try! renderDocument(document, settings: settings)
    return CGPDFDocument(CGDataProvider(data: data as CFData)!)!
}

/// True when two grey samples are within 12 levels of each other.
/// - Parameters:
///   - a: First grey value.
///   - b: Second grey value.
/// - Returns: Whether they are approximately equal.
func near(_ a: Int, _ b: Int) -> Bool { abs(a - b) <= 12 }

// MARK: - Tests

/// Tests CUPS option string parsing.
func testParseOptions() {
    let o = parseCupsOptions("CMBooklet=LeftBinding job-sheets=none title='My Doc' x=\"a b\" esc=a\\ b collate nocolor CMBooklet=RightBinding")
    checkEqual(o["CMBooklet"], "RightBinding", "later option overrides")
    checkEqual(o["title"], "My Doc", "single quotes")
    checkEqual(o["x"], "a b", "double quotes")
    checkEqual(o["esc"], "a b", "backslash escape")
    checkEqual(o["collate"], "true", "bare name is true")
    checkEqual(o["color"], "false", "noname is false")
    checkEqual(parseCupsOptions("").count, 0, "empty string")
    checkEqual(parseCupsOptions("q='it\\'s'")["q"], "it's", "escape inside quotes")
    checkEqual(parseCupsOptions("no")["no"], "true", "bare 'no' is a name")
}

/// Tests PPD defaults and paper dimension reading.
func testPPDReading(ppdPath: String?) {
    let snippet = "*DefaultDuplex: None\n*DefaultPageSize: A4\n*PaperDimension A4/A4: \"595 842\"\n*PaperDimension DoublePostcardRotated/Double: \"419.5 567\"\n*PaperDimension Bad/Bad: \"1\"\n"
    let d = ppdDefaults(snippet)
    checkEqual(d["Duplex"], "None", "default duplex")
    checkEqual(d["PageSize"], "A4", "default page size")
    let dims = ppdPaperDimensions(snippet)
    checkEqual(dims["A4"], a4, "A4 dimension")
    checkEqual(dims["DoublePostcardRotated"], CGSize(width: 419.5, height: 567), "fractional dimension")
    check(dims["Bad"] == nil, "malformed dimension ignored")

    if let path = ppdPath, let text = try? String(contentsOfFile: path, encoding: .isoLatin1) {
        let realDefaults = ppdDefaults(text)
        checkEqual(realDefaults["CMBooklet"], "Off", "real PPD booklet default")
        checkEqual(realDefaults["InputSlot"], "Auto", "real PPD input slot default")
        checkEqual(ppdPaperDimensions(text).count, 21, "real PPD has 21 sizes")
    } else {
        check(false, "real PPD not found at \(ppdPath ?? "nil")")
    }
}

/// Tests small helpers: watermark text, booleans, units, sizes.
func testHelpers() {
    let expected = ["Draft": "DRAFT", "Confidential": "CONFIDENTIAL", "Copy": "COPY",
                    "Sample": "SAMPLE", "Internal": "INTERNAL", "DoNotCopy": "DO NOT COPY"]
    for (choice, text) in expected { checkEqual(watermarkText(forChoice: choice), text, "watermark \(choice)") }
    check(watermarkText(forChoice: "Off") == nil, "watermark Off")
    for v in ["True", "yes", "ON", "1"] { check(isTrue(v), "isTrue \(v)") }
    for v in ["False", "no", "0", ""] { check(!isTrue(v), "isTrue \(v) is false") }
    check(!isTrue(nil), "isTrue nil")
    checkEqual(toPoints(25.4, unit: "mm"), 72.0, "mm to points")
    checkEqual(toPoints(2.54, unit: "cm"), 72.0, "cm to points")
    checkEqual(toPoints(1, unit: "in"), 72.0, "in to points")
    checkEqual(toPoints(10, unit: "pt"), 10.0, "pt")
    check(toPoints(1, unit: "ft") == nil, "unknown unit")

    let dims = ["A4": a4, "Letter": CGSize(width: 612, height: 792)]
    checkEqual(resolvePageSize("A4", dimensions: dims), a4, "exact name")
    checkEqual(resolvePageSize("letter", dimensions: dims), CGSize(width: 612, height: 792), "case-insensitive")
    checkEqual(resolvePageSize("Custom.300x400", dimensions: dims), CGSize(width: 300, height: 400), "custom points")
    let customMM = resolvePageSize("Custom.210x297mm", dimensions: dims)!
    check(abs(customMM.width - 595.28) < 0.1 && abs(customMM.height - 841.89) < 0.1, "custom mm")
    let ipp = resolvePageSize("iso_a5_148x210mm", dimensions: dims)!
    check(abs(ipp.width - 419.53) < 0.1, "IPP mm name")
    checkEqual(resolvePageSize("na_letter_8.5x11in", dimensions: dims), CGSize(width: 612, height: 792), "IPP inch name")
    check(resolvePageSize("Unknown", dimensions: dims) == nil, "unknown size")
    check(parseSizeSpec("10x", defaultUnit: "") == nil, "bad spec")
    check(parseSizeSpec("0x10", defaultUnit: "") == nil, "zero size")
    check(parseSizeSpec("10x10", defaultUnit: nil) == nil, "unit required")
}

/// Tests settings resolution from options and defaults.
func testResolveSettings() {
    let dims = ["A4": a4, "A5": CGSize(width: 420, height: 595)]
    let defaults = ["CMBooklet": "Off", "Duplex": "DuplexTumble", "PageSize": "A4"]

    var s = resolveSettings(options: [:], defaults: defaults, dimensions: dims)
    check(!s.needsProcessing, "defaults need no processing")
    checkEqual(s.userDuplex, "DuplexTumble", "duplex from PPD default")
    checkEqual(s.sheetSize, a4, "sheet from default page size")

    s = resolveSettings(options: ["CMBooklet": "LeftBinding", "CMLetterhead": "True", "PageSize": "A5"],
                        defaults: defaults, dimensions: dims)
    checkEqual(s.booklet, .left, "left booklet")
    check(!s.letterhead, "letterhead off when booklet is on")
    checkEqual(s.sheetSize, CGSize(width: 420, height: 595), "sheet from job PageSize")
    check(s.needsProcessing, "booklet needs processing")

    s = resolveSettings(options: ["CMBooklet": "RightBinding", "media": "iso_a5_148x210mm,tray-2"],
                        defaults: [:], dimensions: dims)
    checkEqual(s.booklet, .right, "right booklet")
    check(abs((s.sheetSize?.width ?? 0) - 419.5) < 0.2, "sheet from media")

    s = resolveSettings(options: ["CMLetterhead": "True", "sides": "two-sided-long-edge"], defaults: [:], dimensions: [:])
    check(s.letterhead, "letterhead on")
    checkEqual(s.userDuplex, "DuplexNoTumble", "sides long edge")
    checkEqual(resolveSettings(options: ["sides": "two-sided-short-edge"], defaults: [:], dimensions: [:]).userDuplex,
               "DuplexTumble", "sides short edge")
    checkEqual(resolveSettings(options: ["sides": "one-sided"], defaults: defaults, dimensions: [:]).userDuplex,
               "None", "sides one-sided")
    checkEqual(resolveSettings(options: ["Duplex": "None"], defaults: defaults, dimensions: [:]).userDuplex,
               "None", "Duplex option wins")
    checkEqual(resolveSettings(options: [:], defaults: [:], dimensions: [:]).userDuplex, "None", "no duplex info")

    s = resolveSettings(options: ["CMWmText": "Draft", "CMWmPages": "First", "CMWmIntensity": "Dark"],
                        defaults: [:], dimensions: [:])
    checkEqual(s.watermark, "DRAFT", "watermark text")
    check(s.watermarkFirstPageOnly, "first page only")
    checkEqual(s.watermarkAlpha, 0.35, "dark")
    checkEqual(resolveSettings(options: ["CMWmIntensity": "Light"], defaults: [:], dimensions: [:]).watermarkAlpha,
               0.12, "light")
    checkEqual(resolveSettings(options: [:], defaults: [:], dimensions: [:]).watermarkAlpha, 0.2, "medium")
    s = resolveSettings(options: ["CMWmText": "Draft", "CMWmCustomText": "My Text"], defaults: [:], dimensions: [:])
    checkEqual(s.watermark, "My Text", "custom watermark text wins")
    check(resolveSettings(options: ["CMRotate180": "True"], defaults: [:], dimensions: [:]).rotate180, "rotate")
    check(resolveSettings(options: ["PageSize": "Nope"], defaults: [:], dimensions: dims).sheetSize == nil, "unknown size")
}

/// Tests booklet and letterhead page order.
func testSequencing() {
    checkEqual(bookletSides(pageCount: 8, mode: .left), [
        BookletSide(left: 7, right: 0), BookletSide(left: 1, right: 6),
        BookletSide(left: 5, right: 2), BookletSide(left: 3, right: 4),
    ], "8 pages, left binding")
    checkEqual(bookletSides(pageCount: 4, mode: .right), [
        BookletSide(left: 0, right: 3), BookletSide(left: 2, right: 1),
    ], "4 pages, right binding")
    checkEqual(bookletSides(pageCount: 1, mode: .left), [
        BookletSide(left: nil, right: 0), BookletSide(left: nil, right: nil),
    ], "1 page padded to 4")
    checkEqual(bookletSides(pageCount: 5, mode: .left).count, 4, "5 pages -> 2 sheets")
    check(bookletSides(pageCount: 4, mode: .off).isEmpty, "off")
    check(bookletSides(pageCount: 0, mode: .left).isEmpty, "no pages")
    checkEqual(letterheadSequence(pageCount: 2, userDuplex: "None"), [0, nil, 1, nil], "letterhead simplex")
    checkEqual(letterheadSequence(pageCount: 2, userDuplex: "DuplexNoTumble"), [0, 1], "letterhead duplex job")
}

/// Tests rendering: pass-through geometry, rotate 180, letterhead, watermark.
func testRenderSimple() {
    let doc = makePDF(grays: [1.0, 1.0])
    var s = FilterSettings()

    s.rotate180 = true
    let rotated = render(doc, s)
    checkEqual(rotated.numberOfPages, 2, "rotate keeps page count")
    let r = rasterize(rotated.page(at: 1)!)
    checkEqual(r.size, a4, "rotate keeps page size")
    check(r.sample(0.5, 0.03) < 40, "band is at the bottom after rotation")
    check(r.sample(0.5, 0.97) > 215, "top is white after rotation")

    s = FilterSettings()
    s.letterhead = true
    s.userDuplex = "None"
    let lh = render(doc, s)
    checkEqual(lh.numberOfPages, 4, "letterhead adds blank backs")
    check(rasterize(lh.page(at: 1)!).sample(0.5, 0.97) < 40, "page 1 has content")
    check(rasterize(lh.page(at: 2)!).sample(0.5, 0.97) > 215, "page 2 is blank")
    checkEqual(lh.page(at: 2)!.getBoxRect(.mediaBox).size, a4, "blank page has same size")
    s.userDuplex = "DuplexTumble"
    checkEqual(render(doc, s).numberOfPages, 2, "letterhead with duplex job adds nothing")

    s = FilterSettings()
    s.watermark = "DRAFT"
    s.watermarkAlpha = 0.35
    s.watermarkFirstPageOnly = true
    let wm = render(makePDF(grays: [1.0, 1.0], band: false), s)
    let centre1 = rasterize(wm.page(at: 1)!).sample(0.5, 0.5)
    let centre2 = rasterize(wm.page(at: 2)!).sample(0.5, 0.5)
    // Sample several points along the diagonal to hit a glyph.
    let p1 = rasterize(wm.page(at: 1)!)
    let darkest = [0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65].map { p1.sample(CGFloat($0), CGFloat($0)) }.min()!
    check(darkest < 235, "watermark visible on page 1 (darkest \(darkest), centre \(centre1))")
    check(centre2 > 245, "no watermark on page 2")
}

/// Tests booklet imposition geometry by pixel colour.
func testRenderBooklet() {
    // Four pages with distinct grey levels: 0.2, 0.4, 0.6, 0.8 -> 51, 102, 153, 204.
    let doc = makePDF(grays: [0.2, 0.4, 0.6, 0.8], band: true)
    var s = FilterSettings()
    s.booklet = .left
    s.sheetSize = a4
    let out = render(doc, s)
    checkEqual(out.numberOfPages, 2, "4 pages -> 1 sheet, 2 sides")
    let front = rasterize(out.page(at: 1)!)
    let back = rasterize(out.page(at: 2)!)
    checkEqual(front.size, a4, "output side is portrait sheet")
    // Spread left half -> bottom half of the portrait sheet, right half -> top.
    check(near(front.sample(0.6, 0.25), 204), "front bottom = page 4 (got \(front.sample(0.6, 0.25)))")
    check(near(front.sample(0.6, 0.75), 51), "front top = page 1 (got \(front.sample(0.6, 0.75)))")
    check(near(back.sample(0.6, 0.25), 102), "back bottom = page 2 (got \(back.sample(0.6, 0.25)))")
    check(near(back.sample(0.6, 0.75), 153), "back top = page 3 (got \(back.sample(0.6, 0.75)))")
    // Page top (black band) is turned to the left edge of the sheet.
    check(front.sample(0.03, 0.75) < 40, "page top is at the left edge (got \(front.sample(0.03, 0.75)))")
    check(!(front.sample(0.97, 0.75) < 40), "right edge is not the band")

    s.booklet = .right
    let right = rasterize(render(doc, s).page(at: 1)!)
    check(near(right.sample(0.6, 0.25), 51), "right binding: front bottom = page 1")

    // Sheet size taken from the first page when unknown; landscape sheet is turned portrait.
    s.sheetSize = CGSize(width: 842, height: 595)
    checkEqual(render(doc, s).page(at: 1)!.getBoxRect(.mediaBox).size, a4, "landscape sheet normalised")
    s.sheetSize = nil
    checkEqual(render(doc, s).page(at: 1)!.getBoxRect(.mediaBox).size, a4, "sheet from first page")
}

/// Tests the empty-document error.
func testEmptyDocument() {
    let data = NSMutableData()
    let context = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: nil, nil)!
    context.closePDF()
    // CoreGraphics may write one blank page when a PDF is closed without pages.
    if let doc = CGPDFDocument(CGDataProvider(data: data as CFData)!), doc.numberOfPages > 0 {
        checkEqual((try? renderDocument(doc, settings: FilterSettings()))?.isEmpty, false, "blank-page PDF renders")
    } else if let doc = CGPDFDocument(CGDataProvider(data: data as CFData)!) {
        do {
            _ = try renderDocument(doc, settings: FilterSettings())
            check(false, "empty document should throw")
        } catch {
            checkEqual(error as? RenderError, .emptyDocument, "empty document error")
        }
    } else {
        check(true, "empty PDF not readable (also acceptable)")
    }
}

// MARK: - Main

/// Entry point of the test runner (compiled with -parse-as-library).
@main
struct CoreTestRunner {
    /// Runs all tests, optionally writes the sample PDF, and exits 0 or 1.
    static func main() {
        let args = CommandLine.arguments
        let tests: [(String, () -> Void)] = [
            ("parseOptions", testParseOptions),
            ("ppdReading", { testPPDReading(ppdPath: args.count > 1 ? args[1] : nil) }),
            ("helpers", testHelpers),
            ("resolveSettings", testResolveSettings),
            ("sequencing", testSequencing),
            ("renderSimple", testRenderSimple),
            ("renderBooklet", testRenderBooklet),
            ("emptyDocument", testEmptyDocument),
        ]
        for (name, test) in tests {
            print("- \(name)")
            fflush(stdout)
            test()
        }

        if args.count > 2 {
            // Write a 6-page sample PDF for the integration tests of the filter binary.
            let sample = makePDF(grays: [0.9, 0.8, 0.7, 0.6, 0.5, 0.4])
            let data = try! renderDocument(sample, settings: FilterSettings())
            try! data.write(to: URL(fileURLWithPath: args[2]))
        }

        print("\(checks - failures)/\(checks) checks passed")
        exit(failures == 0 ? 0 : 1)
    }
}
