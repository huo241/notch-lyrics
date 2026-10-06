//
//  AppleScriptBoolean.swift
//  boringNotch
//
//  Created by Zhuanz on 2026-10-06.
//

import Foundation

/// Reads booleans returned from AppleScript reliably.
///
/// `NSAppleEventDescriptor.booleanValue` only works for descriptors whose type
/// is `'bool'`. Values bridged from Cocoa — `favorited of current track` in
/// Music, for instance — come back as `'true'` / `'fals'` (0x74727565 /
/// 0x66616C73) instead, for which `booleanValue` always reports `false`
/// regardless of the actual value. That silently broke the favourite toggle:
/// the write reached Music but the state read back was always `false`.
enum AppleScriptBoolean {
    private static let typeTrue: DescType = 0x74727565  // 'true'
    private static let typeFalse: DescType = 0x66616C73 // 'fals'
    private static let typeBool: DescType = 0x626F6F6C  // 'bool'

    static func isTrue(_ descriptor: NSAppleEventDescriptor) -> Bool {
        switch descriptor.descriptorType {
        case typeTrue, typeBool:
            return true
        case typeFalse:
            return false
        default:
            // Fall back to the textual form (`stringValue` yields "true"/"false"
            // for these descriptors) before trusting `booleanValue`, which is
            // not meaningful for non-'bool' types.
            if let text = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                if text == "true" { return true }
                if text == "false" { return false }
            }
            return descriptor.booleanValue
        }
    }
}
