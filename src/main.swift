// main.swift
// Created: 2026-11-25 22:27
//
// cm2320claude-prefilter: CUPS pre-filter of the CM2320MfpClaude driver.
// Usage (by CUPS): cm2320claude-prefilter job-id user title copies options [file]
// Reads a PDF (file or stdin), applies booklet / letterhead / rotate 180 /
// watermark as set in the job options or PPD defaults, and writes PDF to
// stdout. When nothing has to change, or the PDF cannot be read, the input
// is passed through unchanged so the job still prints. License: MIT.

import CoreGraphics
import Foundation

/// Writes one CUPS log line to stderr ("INFO:", "WARNING:", "ERROR:").
/// - Parameters:
///   - level: CUPS log level prefix without colon.
///   - message: The message.
func log(_ level: String, _ message: String) {
    FileHandle.standardError.write("\(level): CM2320MfpClaude: \(message)\n".data(using: .utf8)!)
}

/// Reads the whole input document from the file argument or stdin.
/// - Parameter arguments: The filter's argv.
/// - Returns: The document bytes, or nil when the file cannot be read.
func readInput(_ arguments: [String]) -> Data? {
    if arguments.count >= 7 {
        return FileManager.default.contents(atPath: arguments[6])
    }
    return FileHandle.standardInput.readDataToEndOfFile()
}

/// Reads the PPD named by the PPD environment variable, if any.
/// - Returns: The PPD text, or an empty string.
func readPPD() -> String {
    guard let path = ProcessInfo.processInfo.environment["PPD"],
          let data = FileManager.default.contents(atPath: path) else { return "" }
    return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
}

/// Runs the filter and returns the process exit code.
/// - Parameter arguments: The filter's argv.
/// - Returns: 0 on success, 1 on a usage or input error.
func runFilter(_ arguments: [String]) -> Int32 {
    guard arguments.count == 6 || arguments.count == 7 else {
        FileHandle.standardError.write("Usage: cm2320claude-prefilter job-id user title copies options [file]\n".data(using: .utf8)!)
        return 1
    }
    guard let input = readInput(arguments) else {
        log("ERROR", "cannot read input file \(arguments[6])")
        return 1
    }
    let ppd = readPPD()
    let settings = resolveSettings(options: parseCupsOptions(arguments[5]),
                                   defaults: ppdDefaults(ppd),
                                   dimensions: ppdPaperDimensions(ppd))
    guard settings.needsProcessing else {
        FileHandle.standardOutput.write(input)
        return 0
    }
    guard let provider = CGDataProvider(data: input as CFData),
          let document = CGPDFDocument(provider) else {
        log("WARNING", "input is not a readable PDF; passing it through unchanged")
        FileHandle.standardOutput.write(input)
        return 0
    }
    do {
        let output = try renderDocument(document, settings: settings)
        log("INFO", "booklet=\(settings.booklet) letterhead=\(settings.letterhead) rotate180=\(settings.rotate180) watermark=\(settings.watermark ?? "none") pages=\(document.numberOfPages)")
        FileHandle.standardOutput.write(output)
        return 0
    } catch {
        log("WARNING", "processing failed (\(error)); passing input through unchanged")
        FileHandle.standardOutput.write(input)
        return 0
    }
}

exit(runFilter(CommandLine.arguments))
