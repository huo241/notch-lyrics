//
//  LyricsDebug.swift
//  Notch Lyrics
//

import Foundation

/// Append-only diagnostic log for the lyrics pipeline. Debug builds only.
///
/// The lookup fails silently in production: a throttled edge node, a metadata
/// variant nobody predicted, a request the OS proxy swallowed — all of them
/// look identical to the user ("no lyrics"), and none of them can be told
/// apart by guessing. One short line per stage lands in
/// `~/Library/Application Support/NotchLyrics/lyrics-debug.log`, so a single
/// repro pinpoints the broken stage.
enum LyricsDebug {

    private static let queue = DispatchQueue(label: "blog.snappy.notchlyrics.lyricsdebug")
    private static let maxBytes = 512 * 1024
    private static let keepBytes = 256 * 1024

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static var logURL: URL? = {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true) else { return nil }
        let directory = support.appendingPathComponent("NotchLyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("lyrics-debug.log")
    }()

    /// Writes one line. Never throws, never blocks the caller meaningfully,
    /// and compiles down to nothing in Release builds.
    static func log(_ message: String) {
        #if DEBUG
        guard let url = logURL else { return }
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: url)
            }
            trimIfNeeded()
        }
        #endif
    }

    /// Keeps the log bounded; a few hundred kilobytes of recent lines is
    /// plenty for diagnosis and keeps the file openable in any editor.
    private static func trimIfNeeded() {
        #if DEBUG
        guard let url = logURL,
              let data = try? Data(contentsOf: url),
              data.count > maxBytes else { return }
        let slice = data.suffix(keepBytes)
        guard let newline = slice.firstIndex(of: 0x0A) else { return }
        try? Data(slice[slice.index(after: newline)...]).write(to: url)
        #endif
    }
}
