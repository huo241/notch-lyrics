//
//  QuickNoteView.swift
//  boringNotch
//
//  Created by Zhuanz on 2026-10-08.
//

import AppKit
import Combine
import Defaults
import SwiftUI

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
        case ready
    }

    private struct Flash {
        let message: String
        let isError: Bool
    }

    private enum FormatKind {
        case bold, italic, underline, strikethrough
    }

    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var draft = QuickNoteDraftStore.shared

    @Default(.quickNoteFolderID) private var folderID
    @Default(.quickNoteFolderLabel) private var folderLabel

    @State private var phase: Phase = .checking
    @State private var isSaving = false
    @State private var flash: Flash?
    @State private var flashTask: Task<Void, Never>?

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
            case .ready:
                composer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 2)
        .task { await prepare() }
        // Raising the capability here rather than on first click is deliberate:
        // a window whose `canBecomeKey` is false never delivers the click that
        // would ask for focus, so waiting for that click deadlocks. Nothing is
        // actually stolen until the user clicks, because becoming the key window
        // still requires the click.
        .onAppear { coordinator.quickNoteWantsFocus = true }
        .onDisappear { releaseKeyboard() }
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
                Button("打开系统设置") { openAutomationSettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("重试") { Task { await fetchFolders() } }
                    .controlSize(.small)
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

            Button("重试") { Task { await fetchFolders() } }
                .controlSize(.small)
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

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 10))
                Text(folderLabel.isEmpty ? "备忘录" : folderLabel)
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
                Button("保存") { save() }
                    .controlSize(.small)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSave)
            }
            .foregroundStyle(.white.opacity(0.55))

            formatBar

            editor
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

    /// A chip with its own background: plain text next to the folder label
    /// read as part of the label and was effectively invisible.
    private var changeFolderChip: some View {
        Button {
            Task { await fetchFolders() }
        } label: {
            Text("更改")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.75))
        .help("选择其他文件夹")
    }

    private func formatButton(_ icon: String, _ name: String, _ kind: FormatKind) -> some View {
        Button {
            applyFormatting(kind)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.75))
        .help(name)
    }

    private var editor: some View {
        RichTextEditor(store: draft) { focused in
            // Path 4: the editor losing focus is itself a hand-back.
            coordinator.quickNoteWantsFocus = focused
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
                    .padding(.top, 9)
                    .padding(.leading, 12)
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
        guard let textView = draft.textView else { return }
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
                toggleValueAttribute(.obliqueness, value: 0.3, in: storage, range: range)
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
                if isOn(attrs[.obliqueness]) {
                    attrs.removeValue(forKey: .obliqueness)
                } else {
                    attrs[.obliqueness] = 0.3
                }
            case .underline:
                if isOn(attrs[.underlineStyle]) {
                    attrs.removeValue(forKey: .underlineStyle)
                } else {
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
            case .strikethrough:
                if isOn(attrs[.strikethroughStyle]) {
                    attrs.removeValue(forKey: .strikethroughStyle)
                } else {
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            textView.typingAttributes = attrs
        }
    }

    /// Toggles a valued text attribute over a range, judged by its first
    /// character — good enough for the formats this toolbar offers.
    private func toggleValueAttribute(
        _ key: NSAttributedString.Key,
        value: Any,
        in storage: NSTextStorage,
        range: NSRange
    ) {
        if isOn(storage.attribute(key, at: range.location, effectiveRange: nil)) {
            storage.removeAttribute(key, range: range)
        } else {
            storage.addAttribute(key, value: value, range: range)
        }
    }

    /// Obliqueness arrives as an `NSNumber` float, underline styles as ints —
    /// both must read as "on" without the bridge silently dropping floats.
    private func isOn(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber: return number.doubleValue != 0
        case let int as Int: return int != 0
        default: return false
        }
    }

    // MARK: - Data

    private var canSave: Bool {
        !isSaving && !draft.attributedText.string
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func prepare() async {
        // Already configured — trust the stored folder and show the editor
        // straight away. Re-listing folders would spend an AppleScript round
        // trip to learn something already known.
        if !folderID.isEmpty {
            phase = .ready
            return
        }
        await fetchFolders()
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
        let plain = draft.attributedText.string
        let html = NoteHTML.make(from: draft.attributedText)
        let target = folderID
        guard canSave, !target.isEmpty else { return }

        isSaving = true
        flash = nil

        Task { @MainActor in
            do {
                try await NotesService.shared.createNote(
                    title: NotesService.title(from: plain),
                    html: html,
                    in: target
                )
                draft.attributedText = NSAttributedString(string: "")
                releaseKeyboard()
                showFlash("已保存", isError: false)
            } catch {
                // The draft is deliberately left untouched: the user may have
                // written a long note and a failed write must not destroy it.
                let message = (error as? NotesError)?.errorDescription
                    ?? error.localizedDescription
                showFlash(message, isError: true)
            }
            isSaving = false
        }
    }

    // MARK: - Focus hand-back

    /// Hands the keyboard back to whatever had it. Called from all exit
    /// paths; any one missed leaves the user unable to type elsewhere.
    private func releaseKeyboard() {
        coordinator.quickNoteWantsFocus = false
        draft.textView?.window?.makeFirstResponder(nil)
    }

    /// Asks for the keyboard. Raising the flag first is required: `makeKey()`
    /// only works on a window that reports it can become key.
    private func requestKeyboard() {
        coordinator.quickNoteWantsFocus = true
        DispatchQueue.main.async {
            let notch = NSApp.windows.first { $0 is BoringNotchSkyLightWindow }
            let window = notch ?? NSApp.keyWindow
            window?.makeKey()
            if let textView = draft.textView {
                window?.makeFirstResponder(textView)
            }
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
        let textView = NSTextView()
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
        guard !textView.attributedString().isEqual(to: store.attributedText) else { return }
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
            store.attributedText = textView.attributedString()
        }

        // AppKit's NSTextView reports editing begin/end through NSTextDelegate
        // (`textDidBeginEditing`), not the UIKit-style `textViewDidBeginEditing`
        // — misspelling those compiles but is never called.
        func textDidBeginEditing(_ notification: Notification) {
            onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
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
            if isOn(attrs[.obliqueness]) { piece = "<i>\(piece)</i>" }
            if isOn(attrs[.underlineStyle]) { piece = "<u>\(piece)</u>" }
            if isOn(attrs[.strikethroughStyle]) { piece = "<s>\(piece)</s>" }
            out += piece
        }
        return out
    }

    private static func isOn(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber: return number.doubleValue != 0
        case let int as Int: return int != 0
        default: return false
        }
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

    /// The live editor while the quick-note tab exists. The notch tears its
    /// content down constantly, so this is a weak back-reference rather than
    /// something the store owns; formatting actions go through it.
    weak var textView: NSTextView?

    private init() {}
}
