//
//  ObsidianService.swift
//  Notch Lyrics
//
//  Created by Zhuanz on 2026-10-10.
//

import AppKit
import Defaults
import Foundation

enum ObsidianError: Error, LocalizedError {
    /// No folder has been chosen yet, or the choice was cleared.
    case notConfigured
    /// The bookmark no longer resolves — the folder was moved, renamed or
    /// deleted. macOS reports only "stale"; it cannot say which happened.
    case folderUnavailable
    /// The sandbox refused the access the bookmark was supposed to carry.
    case accessDenied
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "还没有选择 Obsidian 文件夹"
        case .folderUnavailable:
            return "找不到之前选的文件夹，请重新选择"
        case .accessDenied:
            return "没有写入这个文件夹的权限，请重新选择"
        case .writeFailed(let message):
            return message
        }
    }
}

/// Writes quick notes into an Obsidian vault as Markdown files.
///
/// A vault is nothing but a folder of `.md` files, so there is no API and no
/// automation here — this is plain file I/O. The only real obstacle is the
/// sandbox: the chosen folder sits outside the app's container, so permission
/// has to come from the user picking it in a panel. That grant is remembered as
/// a **security-scoped bookmark**, which is what lets it survive a relaunch.
///
/// Note what this route does *not* need: no new entitlement. `files.user-selected
/// .read-write` plus app-scoped bookmarks are already declared for the shelf,
/// so adding Obsidian support costs the user nothing — unlike the Notes route,
/// whose Apple Events exception changed the code signature and reset every
/// privacy permission the app held.
///
/// The folder is chosen, never assumed: a vault root is a curated place, and
/// dropping notes into it unasked would be rude. If the user wants an `Inbox`
/// or a `速记` subfolder, they make it in the panel — the app does not invent
/// directories on anyone's behalf.
final class ObsidianService: Sendable {
    static let shared = ObsidianService()
    private init() {}

    /// Longest file-name stem, before the `.md`. Obsidian shows names in a
    /// narrow sidebar, where a whole first line is unreadable.
    private static let maxStemLength = 40

    // MARK: - Choosing the folder

    /// Shows the folder picker and remembers the choice.
    ///
    /// Returns the label to display, or `nil` if the user cancelled.
    ///
    /// The body runs as main-actor work, which `NSOpenPanel` requires. It is
    /// this way round — `assumeIsolated` rather than marking the whole method
    /// `@MainActor` — because the only caller is a SwiftUI button action, which
    /// is already on the main thread; annotating would push `@MainActor` up
    /// through the view for no benefit. As an accessory app (no Dock icon) we
    /// also have to come forward explicitly, or the panel opens behind whatever
    /// the user is actually looking at.
    func chooseFolder() -> String? {
        MainActor.assumeIsolated {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            // Lets the user create the `Inbox` they want in place, rather than
            // having us create one for them.
            panel.canCreateDirectories = true
            panel.prompt = "选择"
            panel.message = "选择存放速记的文件夹（vault 根目录，或其中的某个文件夹）"

            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            return remember(url)
        }
    }

    /// Persists access to `url`. Returns the label to show for it, or `nil` if
    /// the bookmark could not be made.
    @discardableResult
    func remember(_ url: URL) -> String? {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }

        Defaults[.quickNoteVaultBookmark] = bookmark
        let label = url.lastPathComponent
        Defaults[.quickNoteVaultLabel] = label
        return label
    }

    var isConfigured: Bool { !Defaults[.quickNoteVaultBookmark].isEmpty }

    var label: String { Defaults[.quickNoteVaultLabel] }

    /// Drops the grant. Used when the folder turns out to be gone, so the UI
    /// falls back to asking again instead of failing on every save.
    func forget() {
        Defaults[.quickNoteVaultBookmark] = Data()
        Defaults[.quickNoteVaultLabel] = ""
    }

    // MARK: - Writing

    /// Writes `body` as a new `.md` file and returns where it landed.
    ///
    /// Always a new file: the design chose not to append, so a stray Return can
    /// never overwrite an earlier note.
    func write(body: String) throws -> URL {
        let bookmark = Defaults[.quickNoteVaultBookmark]
        guard !bookmark.isEmpty else { throw ObsidianError.notConfigured }

        var isStale = false
        guard let folder = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            forget()
            throw ObsidianError.folderUnavailable
        }
        guard !isStale else {
            // Practically always means the folder moved. Nothing can repair a
            // stale bookmark but a fresh choice, so clear it now and let the UI
            // ask — otherwise every future save fails the same way.
            forget()
            throw ObsidianError.folderUnavailable
        }

        // Claiming the scope is what turns the bookmark into actual rights.
        // Without it, every write fails with a bare "operation not permitted".
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard scoped else { throw ObsidianError.accessDenied }

        let fileURL = Self.uniqueURL(in: folder, stem: Self.fileName(from: body))
        do {
            try body.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw ObsidianError.writeFailed(error.localizedDescription)
        }
        return fileURL
    }

    // MARK: - Naming

    /// Derives the file name from the note's first line, the way Obsidian names
    /// a new note — so the entry in the file list reads as what the user typed,
    /// not as a timestamp.
    static func fileName(from body: String) -> String {
        let firstLine = body
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        var stem = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)

        // Replaced rather than dropped, so "A/B" does not quietly become "AB".
        // `/` separates path components, `:` is rewritten by Finder, and the
        // rest are illegal on one volume or another.
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        stem = stem.components(separatedBy: illegal).joined(separator: "-")
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)

        if stem.count > maxStemLength {
            stem = String(stem.prefix(maxStemLength))
        }
        // A leading dot would hide the file from Obsidian's file list.
        while stem.hasPrefix(".") { stem.removeFirst() }
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? timestamp() : stem
    }

    /// Fallback name for a note with no usable first line.
    static func timestamp(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return formatter.string(from: date)
    }

    /// A URL nothing occupies yet, so a second note opening with the same words
    /// never overwrites the first.
    private static func uniqueURL(in folder: URL, stem: String) -> URL {
        var candidate = folder.appendingPathComponent(stem).appendingPathExtension("md")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder
                .appendingPathComponent("\(stem)-\(index)")
                .appendingPathExtension("md")
            index += 1
        }
        return candidate
    }
}

/// Renders the draft as Markdown for the vault.
///
/// The same four formats the toolbar offers, mapped to what Markdown can say:
/// bold, italic and strikethrough have syntax of their own, whereas underline
/// does not — so it keeps the `<u>` tag, which Obsidian renders as HTML.
/// Font size and colour are dropped, exactly as they are on the Notes route.
///
/// The text itself is passed through unescaped. That is deliberate: it means
/// typing `# 标题` or `- 一条` produces a real heading or list in the vault,
/// which is what someone writing into Obsidian is likely to want.
enum NoteMarkdown {
    static func make(from text: NSAttributedString) -> String {
        guard text.length > 0 else { return "" }

        var out = ""
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            guard range.length > 0 else { return }
            var piece = text.attributedSubstring(from: range).string
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) { piece = "**\(piece)**" }
                if traits.contains(.italic) { piece = "*\(piece)*" }
            }
            // Italic applied to Chinese text is a skew, not a font trait.
            if attributeIsOn(attrs[.obliqueness]) { piece = "*\(piece)*" }
            if attributeIsOn(attrs[.strikethroughStyle]) { piece = "~~\(piece)~~" }
            if attributeIsOn(attrs[.underlineStyle]) { piece = "<u>\(piece)</u>" }
            out += piece
        }
        return out
    }
}
