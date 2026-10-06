//
//  AppleScriptHelper.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

class AppleScriptHelper {
    /// Every script runs here, one at a time.
    ///
    /// `NSAppleScript` is not thread-safe, and the previous implementation spun
    /// up a fresh detached task per call. With several scripts in flight against
    /// Music.app at once they interfered: some calls threw, others returned the
    /// *previous* call's result. That is what made the favourite toggle look
    /// broken — the write landed in Music, but the read-back reported a stale
    /// value, so the UI flipped back and the next tap inverted the wrong way.
    private static let queue = DispatchQueue(label: "app.boringnotch.applescript", qos: .userInitiated)

    @discardableResult
    class func execute(_ scriptText: String) async throws -> NSAppleEventDescriptor? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let script = NSAppleScript(source: scriptText)
                var error: NSDictionary?
                if let descriptor = script?.executeAndReturnError(&error) {
                    continuation.resume(returning: descriptor)
                } else if let error = error {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: error as? [String: Any]))
                } else {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                }
            }
        }
    }

    class func executeVoid(_ scriptText: String) async throws {
        _ = try await execute(scriptText)
    }
}
