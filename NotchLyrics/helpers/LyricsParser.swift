//
//  LyricsParser.swift
//  Notch Lyrics
//
//  Created by Zhuanz on 2026-10-06.
//

import Foundation

/// Parses LRC-formatted lyrics into time-ordered lines.
///
/// Deliberately free of app dependencies so it can be exercised on its own.
enum LyricsParser {
    private static let timeTagRegex = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
    private static let offsetRegex = try! NSRegularExpression(
        pattern: #"\[offset:\s*([+-]?\d+)\s*\]"#, options: [.caseInsensitive])
    /// `<mm:ss.xx>` word-level tags, which carry no usable line timing.
    private static let wordTagRegex = try! NSRegularExpression(
        pattern: #"<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>"#)

    /// - Returns: lines sorted by time. Handles the variants found in the wild:
    ///   several tags sharing one line, 1–3 fractional digits (or none), and the
    ///   standard `[offset:±ms]` header.
    static func parse(_ lrc: String) -> [(time: Double, text: String)] {
        guard !lrc.isEmpty else { return [] }

        var offsetSeconds: Double = 0
        let fullRange = NSRange(lrc.startIndex..., in: lrc)
        if let offsetMatch = offsetRegex.firstMatch(in: lrc, range: fullRange),
           let range = Range(offsetMatch.range(at: 1), in: lrc),
           let milliseconds = Double(lrc[range]) {
            offsetSeconds = milliseconds / 1000
        }

        var result: [(Double, String)] = []
        for rawLine in lrc.split(separator: "\n") {
            let line = String(rawLine)
            let lineRange = NSRange(line.startIndex..., in: line)
            let matches = timeTagRegex.matches(in: line, range: lineRange)
            guard !matches.isEmpty else { continue }

            // Text follows the final time tag on the line.
            let last = matches[matches.count - 1]
            let textStart = last.range.location + last.range.length
            guard let textBoundary = Range(
                NSRange(location: textStart, length: lineRange.length - textStart), in: line
            ) else { continue }

            var text = String(line[textBoundary])
            text = wordTagRegex.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            text = text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for match in matches {
                guard let minRange = Range(match.range(at: 1), in: line),
                      let secRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minRange]),
                      let seconds = Double(line[secRange]) else { continue }

                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound,
                   let fracRange = Range(match.range(at: 3), in: line) {
                    let digits = line[fracRange]
                    // "5" is 5/10s, "55" is 55/100s, "555" is 555/1000s.
                    if let value = Double(digits) {
                        fraction = value / pow(10, Double(digits.count))
                    }
                }

                let time = minutes * 60 + seconds + fraction - offsetSeconds
                result.append((max(0, time), text))
            }
        }

        return result
            .sorted { $0.0 < $1.0 }
            .map { (time: $0.0, text: $0.1) }
    }

    /// Index of the line to highlight for `elapsed`, or nil when there is none.
    static func currentIndex(in lines: [(time: Double, text: String)], at elapsed: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        // Binary search for the last line whose time is <= elapsed.
        var low = 0
        var high = lines.count - 1
        var idx = 0
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= elapsed {
                idx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return idx
    }
}
