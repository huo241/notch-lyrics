//
//  FileShareView.swift
//  Notch Lyrics
//
//  Created by Alexander on 2025-09-24.
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct FileShareView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @StateObject private var quickShare = QuickShareService.shared
    @Default(.quickShareProvider) var quickShareProvider: String

    @State private var hostView: NSView?
    @State private var interactionNonce: UUID = .init()
    @State private var isProcessing = false
    
    private var selectedProvider: QuickShareProvider {
        quickShare.availableProviders.first(where: { $0.id == quickShareProvider }) ?? QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true)
    }

    var body: some View {
        dropArea
            .background(ZoneReporter(view: $hostView) { rect in
                // Feed the window-level drop handler so it can tell "drop on the
                // share square" apart from "drop on the shelf".
                NotchViewCoordinator.shared.airDropZoneRect = rect
            })
            .onTapGesture {
                Task {
                    await handleClick()
                }
            }
    }

    private var dropArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            vm.dropZoneTargeting
                                ? Color.accentColor.opacity(0.9)
                                : Color.white.opacity(0.1),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
                        )
                )
                .shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 2)

            // Content
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(
                            vm.dropZoneTargeting ? 0.11 : 0.09
                        ))
                        .frame(width: 55, height: 55)
                    Image(systemName: "square.and.arrow.up")
                    Group {
                        if let imgData = selectedProvider.imageData, let nsImg = NSImage(data: imgData) {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .frame(width: 34, height: 34)
                        .foregroundStyle(
                            vm.dropZoneTargeting ? Color.accentColor : Color.gray
                        )
                        .scaleEffect(
                            vm.dropZoneTargeting ? 1.06 : 1.0
                        )
                        .animation(.spring(response: 0.36, dampingFraction: 0.7), value: vm.dropZoneTargeting)
                }

                Text(selectedProvider.id)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))

            }
            .padding(18)
            
            // Loading overlay
            if isProcessing || quickShare.isPickerOpen {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func handleClick() async {
        await quickShare.showFilePicker(for: selectedProvider, from: hostView)
    }
}

// MARK: - Host NSView for share-sheet anchoring + drop-zone frame reporting

/// Backing `NSView` for the share square. It exists for two reasons:
///   1. it anchors `NSSharingServicePicker`, and
///   2. it reports its own frame in window coordinates, which the window-level
///      drag destination uses to decide whether a drop landed on this square.
private struct ZoneReporter: NSViewRepresentable {
    @Binding var view: NSView?
    var onFrame: (CGRect) -> Void

    func makeNSView(context: Context) -> ZoneFrameView {
        let v = ZoneFrameView()
        v.onFrame = onFrame
        NotchViewCoordinator.shared.airDropZoneView = v
        DispatchQueue.main.async { self.view = v }
        return v
    }

    func updateNSView(_ nsView: ZoneFrameView, context: Context) {
        nsView.onFrame = onFrame
        NotchViewCoordinator.shared.airDropZoneView = nsView
        DispatchQueue.main.async { self.view = nsView }
        nsView.reportNow()
    }
}

final class ZoneFrameView: NSView {
    var onFrame: ((CGRect) -> Void)?

    private let ringLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupRing()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupRing()
    }

    private func setupRing() {
        wantsLayer = true
        ringLayer.borderColor = NSColor.controlAccentColor.cgColor
        ringLayer.borderWidth = 3
        ringLayer.cornerRadius = 12
        ringLayer.opacity = 0
        layer?.addSublayer(ringLayer)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.frame = bounds
        CATransaction.commit()
    }

    /// Drawn with Core Animation instead of a SwiftUI state change: republishing
    /// view state mid-drag rebuilds the SwiftUI tree and cancels the session.
    func setHighlighted(_ on: Bool) {
        let target: Float = on ? 1 : 0
        guard ringLayer.opacity != target else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.opacity = target
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            // Left the hierarchy (e.g. the notch collapsed): drop the stale
            // frame so an old rect can never be mistaken for a live drop zone.
            onFrame?(.zero)
        } else {
            reportNow()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportNow()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        reportNow()
    }

    /// `convert(_:to: nil)` gives window base coordinates — the same space as
    /// `NSDraggingInfo.draggingLocation`.
    func reportNow() {
        guard window != nil else { return }
        let rect = convert(bounds, to: nil)
        guard rect.width > 1, rect.height > 1 else { return }
        onFrame?(rect)
    }
}
