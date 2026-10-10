//
//  QuickNoteView.swift
//  Notch Lyrics
//
//  Created by Zhuanz on 2026-10-08.
//

import AppKit
import Combine
import Defaults
import SwiftUI

/// True for any "on" attribute value — obliqueness arrives as an `NSNumber`
/// float, underline styles as plain ints; both must read as on.
func attributeIsOn(_ value: Any?) -> Bool {
    switch value {
    case let number as NSNumber: return number.doubleValue != 0
    case let int as Int: return int != 0
    default: return false
    }
}

/// The formats the toolbar can toggle, as a set so the active-state highlight
/// can travel in a single published value.
struct QuickNoteFormats: OptionSet {
    let rawValue: Int
    static let bold = QuickNoteFormats(rawValue: 1 << 0)
    static let italic = QuickNoteFormats(rawValue: 1 << 1)
    static let underline = QuickNoteFormats(rawValue: 1 << 2)
    static let strikethrough = QuickNoteFormats(rawValue: 1 << 3)
}

/// Type a note straight into the notch; it lands in Apple Notes as a new note.
///
/// The notch is a **non-activating panel** — it deliberately never takes the
/// keyboard, which is what stops it from stealing focus while it hovers into
/// view. That guarantee has to be lifted for text entry and then put back, so
/// this view treats focus as something borrowed rather than owned.
///
/// The capability is raised while the quick-note tab is on screen and lowered on
/// every exit path (tab switch, notch collapse, Esc, save, app deactivation).
/// `onDisappear` is load-bearing, not tidiness: miss it and the user's keyboard
/// stays trapped in the notch.
///
/// Editing uses an `NSTextView` rather than SwiftUI's `TextEditor` because the
/// formatting toolbar needs the selected range, which `TextEditor` does not
/// expose. The draft (text *and* its formatting) lives in
/// `QuickNoteDraftStore` rather than `@State`: the notch is torn down
/// constantly and a draft must outlive that.
struct QuickNoteView: View {
    private enum Phase {
        case checking
        case notAuthorized
        case failed(String)
        case pickFolder([NoteFolder])
        case chooseVault
        case ready
    }

    private struct Flash {
        let message: String
        let isError: Bool
    }

    private enum FormatKind {
        case bold, italic, underline, strikethrough

        var formats: QuickNoteFormats {
            switch self {
            case .bold: return .bold
            case .italic: return .italic
            case .underline: return .underline
            case .strikethrough: return .strikethrough
            }
        }
    }

    @ObservedObject private var coordinator = NotchViewCoordinator.shared
    @ObservedObject private var draft = QuickNoteDraftStore.shared

    @Default(.quickNoteFolderID) private var folderID
    @Default(.quickNoteFolderLabel) private var folderLabel
    @Default(.quickNoteTarget) private var targetRaw
    @Default(.quickNoteVaultLabel) private var vaultLabel

    @State private var phase: Phase = .checking
    @State private var isSaving = false
    @State private var flash: Flash?
    @State private var flashTask: Task<Void, Never>?
    @State private var keyBridge = QuickNoteKeyBridge()

    var body: some View {
        Group {
            switch phase {
            case .checking:
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
            case .notAuthorized:
                permissionPrompt
            case .failed(let message):
                failurePrompt(message)
            case .pickFolder(let folders):
                folderPicker(folders)
            case .chooseVault:
                vaultPicker
            case .ready:
                composer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The other tabs (weather, shelf) keep their content off the slab
        // edge; 2 pt read as glued to the border.
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .task { await prepare() }
        // Raising the capability here rather than on first click is deliberate:
        // a window whose `canBecomeKey` is false never delivers the click that
        // would ask for focus, so waiting for that click deadlocks. Nothing is
        // actually stolen until the user clicks, because becoming the key window
        // still requires the click.
        .onAppear {
            QuickNoteSelfTest.log("QuickNoteView body appeared, folderID=\(folderID.isEmpty ? "EMPTY" : "set")")
            coordinator.quickNoteWantsFocus = true
            keyBridge.install()
        }
        .onDisappear {
            QuickNoteSelfTest.log("QuickNoteView onDisappear")
            releaseKeyboard()
            keyBridge.remove()
        }
        .onExitCommand { releaseKeyboard() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            // Path 5: another app came forward — it gets the keyboard.
            releaseKeyboard()
        }
    }

    // MARK: - States

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 11))
                Text("需要访问「备忘录」的权限")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)

            Text("在「系统设置 › 隐私与安全性 › 自动化」里允许 Notch Lyrics 控制备忘录，然后回到这里。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                chipButton("打开系统设置", prominent: true) { openAutomationSettings() }
                chipButton("重试") { Task { await fetchFolders() } }
                // The refusal is answered rather than repeated: this is the
                // "ask once, and if they say no, use Obsidian" path. Without
                // it the tab is a dead end for anyone who declines.
                chipButton("改用 Obsidian") { switchTo(.obsidian) }
            }
        }
    }

    private func failurePrompt(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                Text(message)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white.opacity(0.85))

            chipButton("重试") { Task { await fetchFolders() } }
        }
    }

    private func folderPicker(_ folders: [NoteFolder]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("选择备忘录文件夹")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(folders) { folder in
                        Button {
                            folderID = folder.id
                            folderLabel = folder.displayName
                            phase = .ready
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder").font(.system(size: 10))
                                Text(folder.displayName)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.85))
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                }
            }
        }
    }

    /// Where the Obsidian route starts: pick the folder, or back out to Notes.
    private var vaultPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.plus").font(.system(size: 11))
                Text("选择 Obsidian 文件夹")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)

            Text("速记会存成 .md 文件写进你选的文件夹。vault 根目录或其中任意文件夹都可以，需要新建文件夹也可以在这里建。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                chipButton("选择文件夹…", prominent: true) { chooseVault() }
                chipButton("改用备忘录") { switchTo(.notes) }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                targetSwitch

                Divider()
                    .frame(height: 10)
                    .overlay { Color.white.opacity(0.15) }

                Image(systemName: target.icon).font(.system(size: 10))
                Text(destinationLabel)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                changeFolderChip

                Spacer(minLength: 4)

                if let flash {
                    Text(flash.message)
                        .font(.system(size: 10))
                        .foregroundStyle(flash.isError ? Color.orange : Color.green)
                        .lineLimit(1)
                }
                if isSaving {
                    ProgressView().controlSize(.mini)
                }
                // A plain chip rather than a bordered system button: the
                // default style renders a light bezel that clashes with the
                // notch's dark, self-drawn controls.
                chipButton("保存", prominent: canSave) { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSave)
            }
            .foregroundStyle(.white.opacity(0.55))

            formatBar

            editor
        }
        // Focus immediately, then once more shortly after as a belt-and-braces
        // pass: the first keystroke must not race the focus request. Re-focus
        // is idempotent when the editor already holds the keyboard.
        .onAppear {
            requestKeyboard()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                requestKeyboard()
            }
            runSelfTest()
        }
    }

    // MARK: - Self test sequence

    /// Types into the real editor, applies italic through the real code path,
    /// dumps the storage attributes, exports the rendered glyphs as PDF, then
    /// injects a synthetic keyDown into this process to probe first-key loss.
    private func runSelfTest() {
        guard QuickNoteSelfTest.enabled else { return }
        QuickNoteSelfTest.log("composer appeared")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let tv = draft.textView else {
                QuickNoteSelfTest.log("FAIL: draft.textView is nil")
                return
            }
            QuickNoteSelfTest.log("editor identity=\(ObjectIdentifier(tv).hashValue)")
            guard let window = tv.window else {
                QuickNoteSelfTest.log("FAIL: textView.window is nil")
                return
            }
            QuickNoteSelfTest.log(
                "window=\(window.title) isKeyWindow=\(window.isKeyWindow) "
                + "firstResponderIsTextView=\(window.firstResponder === tv) "
                + "quickNoteWantsFocus=\(coordinator.quickNoteWantsFocus)"
            )

            tv.insertText("哇哇哇", replacementRange: NSRange(location: 0, length: 0))

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                tv.setSelectedRange(NSRange(location: 0, length: tv.textStorage?.length ?? 0))
                applyFormatting(.italic)
                let storage = tv.textStorage
                QuickNoteSelfTest.log("storage=\(storage?.string ?? "?")")
                if let storage {
                    storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, range, _ in
                        QuickNoteSelfTest.log(
                            "range=\(range) obliqueness=\(String(describing: attrs[.obliqueness])) "
                            + "font=\(String(describing: attrs[.font]))"
                        )
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let pdf = tv.dataWithPDF(inside: tv.bounds)
                    try? pdf.write(to: URL(fileURLWithPath: "/tmp/quicknote_selftest.pdf"))
                    QuickNoteSelfTest.log("glyph PDF written to /tmp/quicknote_selftest.pdf")

                    // Probe first-keystroke delivery with a synthetic keyDown
                    // ('x', virtualKey 7) posted straight into this process —
                    // the same event the bridge should route into the editor.
                    let pid = ProcessInfo.processInfo.processIdentifier
                    if let down = CGEvent(keyboardEventSource: nil, virtualKey: 7, keyDown: true) {
                        down.postToPid(pid)
                        QuickNoteSelfTest.log("synthetic keyDown posted to pid \(pid)")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        QuickNoteSelfTest.log("after synthetic key storage=\(tv.textStorage?.string ?? "?")")
                        QuickNoteSelfTest.log("done")
                        QuickNoteSelfTest.restoreStashedFolder()
                        exit(0)
                    }
                }
            }
        }
    }

    private var formatBar: some View {
        HStack(spacing: 3) {
            formatButton("bold", "粗体", .bold)
            formatButton("italic", "斜体", .italic)
            formatButton("underline", "下划线", .underline)
            formatButton("strikethrough", "删除线", .strikethrough)
            Spacer()
        }
    }

    /// The two destinations, side by side.
    ///
    /// Two chips rather than a popup menu: the notch panel is a non-activating
    /// panel, and a menu needs an active app before it will open at all.
    private var targetSwitch: some View {
        HStack(spacing: 3) {
            ForEach(QuickNoteTarget.allCases) { option in
                let active = option == target
                Button {
                    switchTo(option)
                } label: {
                    Text(option.label)
                        .font(.system(size: 10, weight: active ? .semibold : .regular))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                Color.white.opacity(active ? 0.22 : 0.07)
                            )
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(active ? 0.95 : 0.5))
            }
        }
    }

    /// What the header states as the destination — the Notes folder for one
    /// route, the chosen vault folder for the other.
    private var destinationLabel: String {
        switch target {
        case .notes:
            return folderLabel.isEmpty ? "备忘录" : folderLabel
        case .obsidian:
            return vaultLabel.isEmpty ? "未选择文件夹" : vaultLabel
        }
    }

    /// A chip with its own background: plain text next to the destination label
    /// read as part of the label and was effectively invisible.
    private var changeFolderChip: some View {
        chipButton("更改", small: true) { pickDestination() }
            .help(target == .notes ? "选择其他备忘录文件夹" : "选择其他文件夹")
    }

    /// Both routes re-pick their destination; they differ only in which picker
    /// opens.
    private func pickDestination() {
        if target == .notes {
            Task { await fetchFolders() }
        } else {
            chooseVault()
        }
    }

    /// Points the tab at a destination and lands in whatever state that
    /// destination needs — the editor if it is already set up, its picker if
    /// not. Switching target never clears the other one's configuration, so
    /// going back and forth costs nothing.
    private func switchTo(_ newTarget: QuickNoteTarget) {
        guard newTarget != target else { return }
        QuickNoteSelfTest.log("switchTo: \(newTarget.rawValue)")
        targetRaw = newTarget.rawValue
        Task { await prepare() }
    }

    /// Opens the folder picker for the Obsidian route.
    private func chooseVault() {
        guard let label = ObsidianService.shared.chooseFolder() else { return }
        QuickNoteSelfTest.log("chooseVault: \(label)")
        showFlash("已指向 \(label)", isError: false)
        phase = .ready
    }

    /// The one button style used across the quick-note UI. Every action in
    /// this tab draws as a dark capsule so nothing pops out of the notch the
    /// way a bordered system button does.
    private func chipButton(
        _ title: String,
        small: Bool = false,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(.system(size: small ? 10 : 11, weight: .medium))
                .padding(.horizontal, small ? 7 : 9)
                .padding(.vertical, small ? 2 : 4)
                .background(
                    Capsule().fill(
                        prominent ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.14)
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(prominent ? 1 : 0.8))
    }

    private func formatButton(_ icon: String, _ name: String, _ kind: FormatKind) -> some View {
        let active = draft.activeFormats.contains(kind.formats)
        return Button {
            applyFormatting(kind)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? Color.accentColor : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.white : Color.white.opacity(0.75))
        .help(name)
    }

    private var editor: some View {
        RichTextEditor(store: draft) { focused in
            // Path 4: the editor losing focus is itself a hand-back.
            coordinator.quickNoteWantsFocus = focused
            coordinator.quickNoteIsEditing = focused
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(alignment: .topLeading) {
            if draft.attributedText.length == 0 {
                Text("随手记点什么…")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                    // Matches the editor's textContainerInset (6, 5) so the
                    // placeholder sits exactly where the first typed glyph
                    // will land instead of floating off grid.
                    .padding(.top, 5)
                    .padding(.leading, 6)
                    .allowsHitTesting(false)
            }
        }
        // An explicit re-request covers the case where the window lost key
        // status without the editor noticing.
        .simultaneousGesture(TapGesture().onEnded { requestKeyboard() })
    }

    // MARK: - Formatting

    /// Applies a format to the selection, or — with an empty selection — to
    /// what gets typed next.
    ///
    /// Bold and italic toggle the font's symbolic traits per run, because the
    /// selection usually mixes fonts. Underline and strikethrough are boolean
    /// attributes and can be toggled for the range in one step. The store is
    /// updated explicitly: programmatic `NSTextStorage` edits do not fire the
    /// delegate's `textDidChange`.
    private func applyFormatting(_ kind: FormatKind) {
        guard let textView = activeEditor else { return }
        let range = textView.selectedRange()

        if range.length > 0, let storage = textView.textStorage {
            storage.beginEditing()
            switch kind {
            case .bold:
                storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
                    let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 12)
                    var traits = font.fontDescriptor.symbolicTraits
                    traits.formSymmetricDifference(.bold)
                    let toggled = NSFont(
                        descriptor: font.fontDescriptor.withSymbolicTraits(traits),
                        size: font.pointSize
                    ) ?? font
                    storage.addAttribute(.font, value: toggled, range: subRange)
                }
            case .italic:
                // Chinese system fonts have no italic face, so the symbolic
                // trait renders as upright text. A skew always shows.
                toggleValueAttribute(.obliqueness, value: Self.obliqueSkew, in: storage, range: range)
            case .underline:
                toggleValueAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    in: storage,
                    range: range
                )
            case .strikethrough:
                toggleValueAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    in: storage,
                    range: range
                )
            }
            storage.endEditing()
            draft.attributedText = textView.attributedString()
        } else {
            var attrs = textView.typingAttributes
            switch kind {
            case .bold:
                let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 12)
                var traits = font.fontDescriptor.symbolicTraits
                traits.formSymmetricDifference(.bold)
                attrs[.font] = NSFont(
                    descriptor: font.fontDescriptor.withSymbolicTraits(traits),
                    size: font.pointSize
                ) ?? font
            case .italic:
                if attributeIsOn(attrs[.obliqueness]) {
                    attrs.removeValue(forKey: .obliqueness)
                } else {
                    attrs[.obliqueness] = Self.obliqueSkew
                }
            case .underline:
                if attributeIsOn(attrs[.underlineStyle]) {
                    attrs.removeValue(forKey: .underlineStyle)
                } else {
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
            case .strikethrough:
                if attributeIsOn(attrs[.strikethroughStyle]) {
                    attrs.removeValue(forKey: .strikethroughStyle)
                } else {
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            textView.typingAttributes = attrs
        }

        // Programmatic edits don't move the selection, so nothing else would
        // refresh the toolbar's active-state highlight.
        draft.refreshActiveFormats()
    }

    /// Radians of skew for italic. 0.2 rad ≈ 12°, the slant of a normal
    /// italic face. (Earlier rounds used much larger values only because
    /// TextKit 2 was dropping the attribute entirely — see the editor setup.)
    private static let obliqueSkew: Double = 0.2

    /// The editor formatting must act on: the one actually holding the
    /// keyboard when that can be identified, otherwise the registered one.
    /// Two editor instances are alive while the notch is open (visual +
    /// gesture layer); setting typing attributes on the one that is *not*
    /// receiving keystrokes makes the format silently invisible — exactly
    /// the "clicked italic, typed, nothing happened" report.
    private var activeEditor: NSTextView? {
        if let textView = draft.textView,
           textView.window?.firstResponder === textView {
            return textView
        }
        return draft.textView
    }

    /// Toggles a valued text attribute over a range, judged by its first
    /// character — good enough for the formats this toolbar offers.
    private func toggleValueAttribute(
        _ key: NSAttributedString.Key,
        value: Any,
        in storage: NSTextStorage,
        range: NSRange
    ) {
        if attributeIsOn(storage.attribute(key, at: range.location, effectiveRange: nil)) {
            storage.removeAttribute(key, range: range)
        } else {
            storage.addAttribute(key, value: value, range: range)
        }
    }

    // MARK: - Data

    /// The destination the tab is currently pointed at.
    ///
    /// Falls back to Notes rather than failing: the stored value is a raw
    /// string, and a typo or a downgrade should not leave the tab with no
    /// destination at all.
    private var target: QuickNoteTarget {
        QuickNoteTarget(rawValue: targetRaw) ?? .notes
    }

    private var canSave: Bool {
        guard !isSaving else { return false }
        guard !draft.attributedText.string
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // Save would silently no-op with no destination, so the button must be
        // off in that case rather than clickable-and-dead.
        switch target {
        case .notes:
            return !folderID.isEmpty
        case .obsidian:
            return ObsidianService.shared.isConfigured
        }
    }

    private func prepare() async {
        switch target {
        case .obsidian:
            // A vault folder is ordinary file I/O — there is nothing to ask the
            // system, so the only open question is whether one has been chosen.
            QuickNoteSelfTest.log(
                "prepare: target=obsidian vault=\(vaultLabel.isEmpty ? "EMPTY" : vaultLabel)"
            )
            phase = ObsidianService.shared.isConfigured ? .ready : .chooseVault
        case .notes:
            // Already configured — trust the stored folder and show the editor
            // straight away. Re-listing folders would spend an AppleScript round
            // trip to learn something already known.
            QuickNoteSelfTest.log(
                "prepare: target=notes folderID=\(folderID.isEmpty ? "EMPTY" : "set(\(folderID))")"
            )
            if !folderID.isEmpty {
                phase = .ready
                return
            }
            await fetchFolders()
        }
    }

    private func fetchFolders() async {
        phase = .checking
        do {
            phase = .pickFolder(try await NotesService.shared.listFolders())
        } catch let error as NotesError {
            switch error {
            case .notAuthorized:
                phase = .notAuthorized
            case .noFolders:
                phase = .failed("备忘录里没有可写入的文件夹")
            case .scriptFailed(let message):
                phase = .failed(message)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func save() {
        guard canSave else { return }

        // Both routes read the draft before the write begins: on success the
        // editor is cleared, and a failure must leave the text intact.
        let markdown = NoteMarkdown.make(from: draft.attributedText)
        let html = NoteHTML.make(from: draft.attributedText)
        let notesFolder = folderID
        let destination = target

        isSaving = true
        flash = nil

        Task { @MainActor in
            do {
                switch destination {
                case .notes:
                    // No `name` is sent: Notes derives the list title from the
                    // first body line. Passing one as well rendered the first
                    // line twice — once as the title row, once as the body.
                    try await NotesService.shared.createNote(
                        title: "",
                        html: html,
                        in: notesFolder
                    )
                case .obsidian:
                    // A file this small is written synchronously; handing it to
                    // another executor would buy nothing and cost a hop.
                    _ = try ObsidianService.shared.write(body: markdown)
                }
                draft.attributedText = NSAttributedString(string: "")
                releaseKeyboard()
                showFlash("已保存", isError: false)
            } catch {
                if let obsidian = error as? ObsidianError {
                    switch obsidian {
                    case .folderUnavailable, .notConfigured:
                        // The grant is gone and the service has already cleared
                        // it, so go straight to picking a new folder instead of
                        // leaving a dead Save button with no way forward.
                        phase = .chooseVault
                    default:
                        break
                    }
                }
                // The draft is deliberately left untouched: the user may have
                // written a long note and a failed write must not destroy it.
                showFlash(Self.message(for: error), isError: true)
            }
            isSaving = false
        }
    }

    /// One message for every error family — the UI shows the same thing for
    /// all of them, so there is no reason to branch any higher up.
    private static func message(for error: Error) -> String {
        if let notes = error as? NotesError, let text = notes.errorDescription {
            return text
        }
        if let obsidian = error as? ObsidianError, let text = obsidian.errorDescription {
            return text
        }
        return error.localizedDescription
    }

    // MARK: - Focus hand-back

    /// Hands the keyboard back to whatever had it. Called from all exit
    /// paths; any one missed leaves the user unable to type elsewhere.
    private func releaseKeyboard() {
        coordinator.quickNoteWantsFocus = false
        coordinator.quickNoteIsEditing = false
        draft.textView?.window?.makeFirstResponder(nil)
    }

    /// Asks for the keyboard. Raising the flag first is required: `makeKey()`
    /// only works on a window that reports it can become key.
    ///
    /// The window is taken from the editor itself rather than searched for:
    /// there is one notch window per attached display, and grabbing "the first
    /// one" can pick a window this editor does not live in — then
    /// `makeFirstResponder` silently does nothing and the first keystroke
    /// falls on the floor.
    private func requestKeyboard() {
        coordinator.quickNoteWantsFocus = true
        DispatchQueue.main.async {
            guard let textView = self.draft.textView else {
                QuickNoteSelfTest.log("requestKeyboard: no textView")
                return
            }
            guard let window = textView.window ?? NSApp.keyWindow else {
                QuickNoteSelfTest.log("requestKeyboard: no window")
                return
            }
            QuickNoteSelfTest.log(
                "requestKeyboard: makeKey=\(!window.isKeyWindow) "
                + "makeFirstResp=\(window.firstResponder !== textView) "
                + "appActive=\(NSApp.isActive)"
            )
            if !window.isKeyWindow {
                // See the bridge: key status alone is not enough — the app
                // must be active for the IME to attach to this editor, or the
                // first keystroke goes missing.
                NSApp.activate(ignoringOtherApps: true)
                window.makeKey()
            }
            window.makeFirstResponder(textView)
        }
    }

    // MARK: - Helpers

    private func showFlash(_ message: String, isError: Bool) {
        flashTask?.cancel()
        flash = Flash(message: message, isError: isError)
        flashTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(isError ? 4 : 1.8))
            guard !Task.isCancelled else { return }
            flash = nil
        }
    }

    private func openAutomationSettings() {
        // The Automation pane has no documented URL scheme; this is the
        // conventional path and falls back to opening Privacy & Security.
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }
}

// MARK: - Rich text editor

/// `NSTextView` in a scroll view, wired to the draft store.
///
/// SwiftUI's `TextEditor` cannot expose the selected range, which the
/// formatting toolbar needs, so the AppKit control it wraps anyway is used
/// directly. `updateNSView` compares content before writing: the usual flow is
/// store changed *because* this text view edited, and re-setting the storage
/// would wipe the selection mid-keystroke.
private struct RichTextEditor: NSViewRepresentable {
    @ObservedObject var store: QuickNoteDraftStore
    var onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, onFocusChange: onFocusChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 is load-bearing here: TextKit 2 silently ignores
        // `.obliqueness` (verified empirically — the italic renders upright),
        // and Chinese fonts have no italic face, so the skew attribute is the
        // only way italic can be visible at all. Building the view around an
        // explicit NSLayoutManager pins this text view to TextKit 1. (Merely
        // READING `textView.layoutManager` also triggers the fallback, but an
        // explicit stack is the documented, non-deprecated way.)
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.font = .systemFont(ofSize: 12)
        textView.textColor = .white
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 6, height: 5)
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay

        store.textView = textView
        context.coordinator.textView = textView
        textView.textStorage?.setAttributedString(store.attributedText)
        syncTypingAttributes(of: textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.onFocusChange = onFocusChange
        // An IME composition (marked text) exists only in the text view, never
        // in the store — so the two legitimately differ while the user is
        // typing Chinese. "Reconciling" that difference destroys the
        // composition mid-keystroke and the typed character vanishes, which
        // presented as the first letter of every note being swallowed. Never
        // write into a view that holds marked text.
        if textView.markedRange().location != NSNotFound { return }
        guard !textView.attributedString().isEqual(to: store.attributedText) else { return }
        QuickNoteSelfTest.log(
            "updateNSView: replacing storage (tv=\(ObjectIdentifier(textView).hashValue)) "
            + "newContent=\(store.attributedText.string)"
        )
        textView.textStorage?.setAttributedString(store.attributedText)
        syncTypingAttributes(of: textView)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let textView = scroll.documentView as? NSTextView,
           textView === coordinator.store.textView {
            coordinator.store.textView = nil
        }
        coordinator.textView = nil
    }

    /// New text should continue with the formatting of the text before it.
    private func syncTypingAttributes(of textView: NSTextView) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        textView.typingAttributes = storage.attributes(at: storage.length - 1, effectiveRange: nil)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let store: QuickNoteDraftStore
        var onFocusChange: (Bool) -> Void
        weak var textView: NSTextView?

        init(store: QuickNoteDraftStore, onFocusChange: @escaping (Bool) -> Void) {
            self.store = store
            self.onFocusChange = onFocusChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            QuickNoteSelfTest.log("textDidChange tv=\(ObjectIdentifier(textView).hashValue) text=\(textView.string.prefix(20))")
            store.textView = textView
            store.attributedText = textView.attributedString()
            store.refreshActiveFormats()
        }

        // Selection moves flip the toolbar's active-state highlight, and also
        // mark this instance as the one the user is working in — a click into
        // the editor always moves the selection, so this fires on every entry.
        func textViewDidChangeSelection(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                store.textView = textView
            }
            store.refreshActiveFormats()
        }

        // AppKit's NSTextView reports editing begin/end through NSTextDelegate
        // (`textDidBeginEditing`), not the UIKit-style `textViewDidBeginEditing`
        // — misspelling those compiles but is never called.
        func textDidBeginEditing(_ notification: Notification) {
            QuickNoteSelfTest.log("textDidBeginEditing")
            if let textView = notification.object as? NSTextView {
                store.textView = textView
            }
            onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            QuickNoteSelfTest.log("textDidEndEditing")
            onFocusChange(false)
        }
    }
}

// MARK: - HTML rendering

/// Renders the draft as the HTML Notes stores in `body`.
///
/// Only the four supported formats are carried over; font size and colour are
/// dropped on purpose. Runs are wrapped rather than merged, so adjacent
/// same-format runs yield repeated tags — valid HTML that Notes renders fine.
private enum NoteHTML {
    static func make(from text: NSAttributedString) -> String {
        guard text.length > 0 else { return "" }

        var out = ""
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            guard range.length > 0 else { return }
            var piece = NotesService.escapeForNotesHTML(
                text.attributedSubstring(from: range).string
            )
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) { piece = "<b>\(piece)</b>" }
                if traits.contains(.italic) { piece = "<i>\(piece)</i>" }
            }
            // Italic applied to Chinese text is a skew, not a font trait.
            if attributeIsOn(attrs[.obliqueness]) { piece = "<i>\(piece)</i>" }
            if attributeIsOn(attrs[.underlineStyle]) { piece = "<u>\(piece)</u>" }
            if attributeIsOn(attrs[.strikethroughStyle]) { piece = "<s>\(piece)</s>" }
            out += piece
        }
        return out
    }
}

// MARK: - Draft store

/// Holds the unsaved draft — text *and* its formatting — for as long as the
/// app runs.
///
/// It lives outside the view on purpose. `ContentView` only instantiates
/// `QuickNoteView` while the notch is expanded — it renders the tab content
/// inside `if vm.notchState == .open` — and the notch collapses on hover-out
/// (roughly 100 ms after the pointer leaves), on Esc, and on a swipe gesture.
/// A draft kept in `@State` is therefore destroyed the first time the pointer
/// wanders off mid-sentence. The formatting has to live here too, or a
/// collapse would silently strip every bold and underline the user applied.
///
/// Deliberately in-memory rather than written to `Defaults`: a draft that
/// silently reappears days later is more surprising than an empty editor.
/// Restarting the app still clears it.
@MainActor
final class QuickNoteDraftStore: ObservableObject {
    static let shared = QuickNoteDraftStore()

    @Published var attributedText: NSAttributedString = NSAttributedString(string: "")

    /// Which toolbar formats are currently "on", for the button highlight.
    /// Derived from the selection (or the typing attributes when the selection
    /// is empty); recomputed via `refreshActiveFormats` after every edit,
    /// selection move, and programmatic format toggle.
    @Published var activeFormats: QuickNoteFormats = []

    /// The live editor. `ContentView` renders the notch content **twice** —
    /// once as the visual layer and once as the gesture layer — so two editor
    /// instances exist at any time. Whoever the user is actually typing in
    /// re-registers itself here (see the coordinator's delegate callbacks), so
    /// formatting and focus always land on the visible one rather than on
    /// whichever happened to be created last.
    weak var textView: NSTextView?

    /// Recomputes the active formats from the editor's current state.
    ///
    /// Judged by the first character of the selection — or the typing
    /// attributes for an empty selection — matching how `applyFormatting`
    /// decides what to toggle.
    func refreshActiveFormats() {
        guard let textView else {
            activeFormats = []
            return
        }

        let range = textView.selectedRange()
        let attrs: [NSAttributedString.Key: Any]
        if range.length > 0,
           let storage = textView.textStorage,
           storage.length > 0,
           range.location < storage.length {
            attrs = storage.attributes(at: range.location, effectiveRange: nil)
        } else {
            // Empty selection or empty editor — the typing attributes carry
            // the pending format, and must not read as "nothing is on" or
            // the toolbar's highlight would drop the moment it's toggled.
            attrs = textView.typingAttributes
        }

        var result: QuickNoteFormats = []
        if let font = attrs[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.bold) { result.insert(.bold) }
            if traits.contains(.italic) { result.insert(.italic) }
        }
        // Italic on Chinese text is a skew, not a font trait.
        if attributeIsOn(attrs[.obliqueness]) { result.insert(.italic) }
        if attributeIsOn(attrs[.underlineStyle]) { result.insert(.underline) }
        if attributeIsOn(attrs[.strikethroughStyle]) { result.insert(.strikethrough) }
        activeFormats = result
    }

    private init() {}
}

// MARK: - Keystroke bridge

/// Delivers the first keystroke, deterministically.
///
/// The notch window only accepts keys while `quickNoteWantsFocus` is raised,
/// and every focus request before this bridge was asynchronous — a key that
/// landed inside that gap was dropped on the floor. Local event monitors run
/// **before** the app routes the event into the responder chain, so this
/// bridge closes the gap synchronously: before a printable key is dispatched,
/// the editor's window is made key and the registered editor becomes first
/// responder. The event then continues its normal route straight into the
/// editor — nothing is swallowed or re-injected, so IME composition and undo
/// keep working.
// MARK: - Self test (launch with -quicknote-selftest)

/// Automated probe for the two long-standing quick-note bugs. Only active
/// when the app is launched with `-quicknote-selftest`; writes a report to
/// stderr, a glyph PDF of the editor to /tmp, and exits. The bootstrap that
/// opens the notch lives in the app delegate (it owns the view models).
@MainActor
enum QuickNoteSelfTest {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-quicknote-selftest")

    /// The real folder choice, stashed by the app bootstrap before the test
    /// seeds its fake one and restored right before the process exits — the
    /// test used to overwrite the user's actual setting permanently.
    static var stashedFolderID: String?
    static var stashedFolderLabel: String?

    static func restoreStashedFolder() {
        let defaults = UserDefaults.standard
        if let id = stashedFolderID {
            defaults.set(id, forKey: "quickNoteFolderID")
        } else {
            defaults.removeObject(forKey: "quickNoteFolderID")
        }
        if let label = stashedFolderLabel {
            defaults.set(label, forKey: "quickNoteFolderLabel")
        } else {
            defaults.removeObject(forKey: "quickNoteFolderLabel")
        }
    }

    /// Always-on lightweight trace. Sandboxed apps cannot write to /tmp, so
    /// this lands in the app container's tmp directory instead —
    /// `~/Library/Containers/<bundle-id>/Data/tmp/notch_lyrics_debug.log`.
    private static let formatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    static func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) QN \(message)\n"
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("notch_lyrics_debug.log")
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

@MainActor
private final class QuickNoteKeyBridge {
    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        QuickNoteSelfTest.log("bridge: installing")
        let store = QuickNoteDraftStore.shared
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            QuickNoteSelfTest.log("bridge: keyDown seen keyCode=\(event.keyCode)")
            guard let textView = store.textView,
                  let window = textView.window else {
                QuickNoteSelfTest.log("bridge: no textView/window, passthrough")
                return event
            }

            // Printable, unmodified keys only. Esc must stay untouched so it
            // keeps reaching the notch's exit path, and modifier combos such
            // as Cmd+Return (save) keep their normal dispatch route.
            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.shift, .capsLock])
            let isPrintable = modifiers.isEmpty
                && event.keyCode != 53 // kVK_Escape
                && !(event.characters?.isEmpty ?? true)
                && event.characters!.unicodeScalars.contains { $0.value >= 0x20 }

            guard isPrintable else { return event }
            QuickNoteSelfTest.log(
                "bridge: printable key, windowKey=\(window.isKeyWindow) "
                + "firstRespIsTV=\(window.firstResponder === textView) "
                + "appActive=\(NSApp.isActive)"
            )
            if !window.isKeyWindow {
                // Activate the app as well: a non-activating panel can hold
                // key status while the app is inactive, but then the input
                // context never attaches cleanly and the FIRST keystroke is
                // swallowed by the IME handoff.
                NSApp.activate(ignoringOtherApps: true)
                NotchViewCoordinator.shared.quickNoteWantsFocus = true
                window.makeKey()
            }
            if window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
            return event
        }
    }

    func remove() {
        QuickNoteSelfTest.log("bridge: removing")
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
