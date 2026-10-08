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
/// Text lives in `QuickNoteDraftStore` rather than `@State` for the same
/// reason the focus handling is explicit: the notch is torn down constantly,
/// and a draft must outlive that.
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

    @ObservedObject private var coordinator = BoringViewCoordinator.shared
    @ObservedObject private var draft = QuickNoteDraftStore.shared

    @Default(.quickNoteFolderID) private var folderID
    @Default(.quickNoteFolderLabel) private var folderLabel

    @State private var phase: Phase = .checking
    @State private var isSaving = false
    @State private var flash: Flash?
    @State private var flashTask: Task<Void, Never>?
    @FocusState private var editorFocused: Bool

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
        .onChange(of: editorFocused) { _, focused in
            // Path 4: the editor losing focus is itself a hand-back.
            coordinator.quickNoteWantsFocus = focused
        }
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
                Button("更改") { Task { await fetchFolders() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))

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

            editor
        }
    }

    private var editor: some View {
        TextEditor(text: $draft.text)
            .focused($editorFocused)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(alignment: .topLeading) {
                if draft.text.isEmpty {
                    Text("随手记点什么…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 7)
                        .padding(.leading, 10)
                        .allowsHitTesting(false)
                }
            }
            // An explicit re-request covers the case where the window lost key
            // status without the editor noticing.
            .simultaneousGesture(TapGesture().onEnded { requestKeyboard() })
    }

    // MARK: - Data

    private var canSave: Bool {
        !isSaving && !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        let body = draft.text
        let target = folderID
        guard canSave, !target.isEmpty else { return }

        isSaving = true
        flash = nil

        Task { @MainActor in
            do {
                try await NotesService.shared.createNote(
                    title: NotesService.title(from: body),
                    body: body,
                    in: target
                )
                draft.text = ""
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

    /// Hands the keyboard back to whatever had it. Called from all five exit
    /// paths; any one missed leaves the user unable to type elsewhere.
    private func releaseKeyboard() {
        coordinator.quickNoteWantsFocus = false
        editorFocused = false
    }

    /// Asks for the keyboard. Raising the flag first is required: `makeKey()`
    /// only works on a window that reports it can become key.
    private func requestKeyboard() {
        coordinator.quickNoteWantsFocus = true
        DispatchQueue.main.async {
            let notch = NSApp.windows.first { $0 is BoringNotchSkyLightWindow }
            (notch ?? NSApp.keyWindow)?.makeKey()
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

/// Holds the unsaved draft for as long as the app runs.
///
/// It lives outside the view on purpose. `ContentView` only instantiates
/// `QuickNoteView` while the notch is expanded — it renders the tab content
/// inside `if vm.notchState == .open` — and the notch collapses on hover-out
/// (roughly 100 ms after the pointer leaves), on Esc, and on a swipe gesture.
/// A draft kept in `@State` is therefore destroyed the first time the pointer
/// wanders off mid-sentence.
///
/// Deliberately in-memory rather than written to `Defaults`: a draft that
/// silently reappears days later is more surprising than an empty editor.
/// Restarting the app still clears it.
@MainActor
final class QuickNoteDraftStore: ObservableObject {
    static let shared = QuickNoteDraftStore()

    @Published var text: String = ""

    private init() {}
}
