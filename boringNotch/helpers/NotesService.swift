//
//  NotesService.swift
//  boringNotch
//
//  Created by Zhuanz on 2026-10-08.
//

import Foundation

/// A Notes folder a note can be filed into.
///
/// `id` is the folder's stable scripting identifier (`x-coredata://…/ICFolder/pN`).
/// The name alone does *not* identify a folder: several accounts can each hold
/// one called "Notes", and picking the wrong one silently files the note in the
/// wrong place. `account` is what makes those rows distinguishable in the UI.
struct NoteFolder: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let account: String

    /// Row title for the picker — see the note on `account` above.
    var displayName: String { "\(name) · \(account)" }
}

enum NotesError: Error, LocalizedError {
    /// macOS has not been told we may drive Notes, or the user declined.
    case notAuthorized
    /// Reached Notes fine, but it has no folder we could write into.
    case noFolders
    /// Anything else Notes reported.
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "没有访问「备忘录」的权限"
        case .noFolders:
            return "没有找到可写入的备忘录文件夹"
        case .scriptFailed(let message):
            return message
        }
    }
}

/// The only place that talks to Apple Notes.
///
/// Apple ships no public API for Notes (unlike EventKit for calendars), so
/// AppleScript is the sole route. Every call goes through `AppleScriptHelper`,
/// which serialises execution — `NSAppleScript` is not thread-safe, and letting
/// Notes and Music scripts overlap made calls return each other's results.
final class NotesService: Sendable {
    static let shared = NotesService()
    private init() {}

    // Folder names are free text, so the delimiters that carried structure out
    // of the script must be characters a person cannot type. The script emits
    // these via `ASCII character`, so no raw control characters appear in the
    // source it executes.
    private static let fieldSeparator = "\u{1F}"
    private static let recordSeparator = "\u{1E}"

    /// Notes' own "trash" folder. Writable in theory, never what the user means.
    private static let excludedFolderNames: Set<String> = [
        "Recently Deleted", "最近删除"
    ]

    // MARK: - Escaping

    /// Escapes text for use inside an AppleScript string literal.
    ///
    /// Backslash is handled before the quote so the backslash the quote pass
    /// introduces is not escaped a second time. Newlines are left alone — they
    /// are legal inside an AppleScript string literal, and the caller decides
    /// whether they survive as newlines or become markup.
    static func escapeForAppleScript(_ value: String) -> String {
        var out = value.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "\"", with: "\\\"")
        return out
    }

    /// Escapes text for the note `body`, which Notes stores as **HTML**.
    ///
    /// The dictionary confirms this: `body` is documented as "the HTML content
    /// of the note". A note containing `<` or `&` is otherwise mangled by the
    /// parser, and a bare newline would collapse to a space. Only `&`, `<` and
    /// `>` need escaping in text content — quotes are harmless there.
    static func escapeForNotesHTML(_ value: String) -> String {
        // Ampersand first, or the entities introduced below get re-escaped.
        var out = value.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        // Normalise line endings before converting, so CRLF does not yield two
        // breaks where the user typed one.
        out = out.replacingOccurrences(of: "\r\n", with: "<br>")
        out = out.replacingOccurrences(of: "\n", with: "<br>")
        out = out.replacingOccurrences(of: "\r", with: "<br>")
        return out
    }

    /// Notes names a note after the first line of its body. We pass the title
    /// explicitly so it is predictable, truncating because the Notes list shows
    /// only a short prefix and an unbounded title makes it unreadable.
    static func title(from body: String, maxLength: Int = 60) -> String {
        let firstLine = body
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }

    // MARK: - Parsing

    /// Splits the packed script output back into folders.
    ///
    /// The field count is matched exactly rather than as a lower bound: the
    /// delimiters are control characters that cannot occur in a folder name, so
    /// any other shape means the script output is malformed and the record is
    /// better dropped than guessed at. Records with an empty id or name go too —
    /// a partially readable folder would only yield a row that fails on save.
    static func parseFolders(_ raw: String) -> [NoteFolder] {
        raw
            .split(separator: Character(recordSeparator), omittingEmptySubsequences: true)
            .compactMap { record in
                let fields = record.split(
                    separator: Character(fieldSeparator),
                    omittingEmptySubsequences: false
                )
                guard fields.count == 3 else { return nil }
                let id = String(fields[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let name = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                let account = String(fields[2]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, !name.isEmpty else { return nil }
                guard !excludedFolderNames.contains(name) else { return nil }
                return NoteFolder(id: id, name: name, account: account)
            }
    }

    // MARK: - Error classification

    /// The message AppleScript attached to the failure, if any.
    static func message(from error: Error) -> String {
        let userInfo = (error as NSError).userInfo
        for key in [
            "NSAppleScriptErrorMessage",
            "NSLocalizedDescription",
            "NSLocalizedFailureReason",
        ] {
            if let value = userInfo[key] as? String, !value.isEmpty { return value }
        }
        return error.localizedDescription
    }

    /// AppleScript's numeric error, pulled out of the userInfo the helper forwards.
    static func scriptErrorNumber(from error: Error) -> Int? {
        let userInfo = (error as NSError).userInfo
        if let number = userInfo["NSAppleScriptErrorNumber"] as? NSNumber {
            return number.intValue
        }
        return nil
    }

    /// Detects "macOS would not let us talk to Notes".
    ///
    /// Two different layers can refuse, and they report differently: the Apple
    /// Event layer returns -1743, the sandbox returns -10004 with a localised
    /// message. Matching on the number alone would miss whichever the user hits,
    /// so the text is checked as well.
    static func isNotAuthorized(_ error: Error) -> Bool {
        if let number = scriptErrorNumber(from: error), number == -1743 || number == -10004 {
            return true
        }
        let text = message(from: error).lowercased()
        return text.contains("not authorized")
            || text.contains("not permitted")
            || text.contains("权限")
    }

    // MARK: - Scripts

    private static let listFoldersScript = """
    tell application "Notes"
        set fs to ASCII character 31
        set rs to ASCII character 30
        set out to ""
        repeat with a in accounts
            try
                set accName to name of a
                repeat with f in folders of a
                    try
                        set out to out & (id of f) & fs & (name of f) & fs & accName & rs
                    end try
                end repeat
            end try
        end repeat
        return out
    end tell
    """

    /// Runs a script and normalises its result to a string.
    @discardableResult
    private func run(_ script: String) async throws -> String {
        do {
            let descriptor = try await AppleScriptHelper.execute(script)
            return descriptor?.stringValue ?? ""
        } catch {
            if Self.isNotAuthorized(error) { throw NotesError.notAuthorized }
            throw NotesError.scriptFailed(Self.message(from: error))
        }
    }

    // MARK: - Public API

    /// Every folder the user could save into, across all accounts.
    ///
    /// Accounts are walked explicitly rather than using the flat `folders`
    /// collection, because the account name is only reachable from the account
    /// object and it is required to tell same-named folders apart.
    func listFolders() async throws -> [NoteFolder] {
        let raw = try await run(Self.listFoldersScript)
        let folders = Self.parseFolders(raw)
        if folders.isEmpty { throw NotesError.noFolders }
        return folders
    }

    /// Builds the script that creates a note.
    ///
    /// Separated from the call so the exact source text can be asserted without
    /// driving Notes — the escaping rules are what break, not the AppleScript.
    static func createNoteScript(title: String, body: String, folderID: String) -> String {
        let safeFolderID = escapeForAppleScript(folderID)
        let safeBody = escapeForAppleScript(escapeForNotesHTML(body))

        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Leave `name` off entirely rather than sending an empty one: Notes
            // then derives the title from the body, which is what we want.
            return """
            tell application "Notes"
                set f to first folder whose id is "\(safeFolderID)"
                make new note at f with properties {body:"\(safeBody)"}
            end tell
            """
        }

        let safeTitle = escapeForAppleScript(title)
        return """
        tell application "Notes"
            set f to first folder whose id is "\(safeFolderID)"
            make new note at f with properties {name:"\(safeTitle)", body:"\(safeBody)"}
        end tell
        """
    }

    /// Creates a new note in the given folder. Always a new note — the design
    /// chose not to append, so a stray Enter can never overwrite earlier text.
    func createNote(title: String, body: String, in folderID: String) async throws {
        try await run(Self.createNoteScript(title: title, body: body, folderID: folderID))
    }
}
