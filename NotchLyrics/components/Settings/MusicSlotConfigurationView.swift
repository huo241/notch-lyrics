//
//  MusicSlotConfigurationView.swift
//  Notch Lyrics
//
//  Created by Alexander on 2025-11-17.
////

import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct MusicSlotConfigurationView: View {
    @Default(.musicControlSlots) private var musicControlSlots
    @ObservedObject private var musicManager = MusicManager.shared
    @State private var draggedSlot: MusicControlButton?
    @State private var hoveredSlotIndex: Int?
    @State private var hoveredPaletteControl: MusicControlButton?
    @State private var dropTargetIndex: Int?

    // Must track the runtime slot count so every configurable slot (including
    // the trailing share slot) is shown and editable here.
    private let fixedSlotCount: Int = MusicControlButton.maxSlotCount

    private let tileSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: NLSpace.s4) {
            previewBlock

            NLDivider()

            paletteBlock

            NLDivider()

            footerBlock
        }
        .padding(.horizontal, NLSpace.s4)
        .padding(.vertical, NLSpace.s4)
        .onAppear {
            ensureSlotCapacity(fixedSlotCount)
        }
    }

    // MARK: - Layout preview

    private var previewBlock: some View {
        VStack(alignment: .leading, spacing: NLSpace.s3) {
            HStack(alignment: .firstTextBaseline, spacing: NLSpace.s3) {
                Text(L("Layout Preview"))
                    .font(NLFont.title)
                    .foregroundStyle(NLColor.textPrimary)
                Text(L("Drag items in the preview to reorder or drop from the palette"))
                    .font(NLFont.caption)
                    .foregroundStyle(NLColor.textTertiary)
                Spacer(minLength: 0)
            }

            HStack(spacing: NLSpace.s3) {
                HStack(spacing: NLSpace.s2) {
                    ForEach(0..<fixedSlotCount, id: \.self) { index in
                        slotTile(at: index)
                    }
                }

                clearTile
            }
        }
    }

    @ViewBuilder
    private func slotTile(at index: Int) -> some View {
        let slot = slotValue(at: index)
        let isHovered = hoveredSlotIndex == index
        let isDropTarget = dropTargetIndex == index

        Group {
            if slot == .none {
                // Empty slot: accepts a drop, but cannot be dragged out
                tileSurface(hovered: isHovered || isDropTarget, dashed: true) {
                    EmptyView()
                }
                .onDrop(of: [UTType.plainText.identifier], isTargeted: targetBinding(index)) {
                    providers in
                    let handled = handleDrop(providers, toIndex: index)
                    DispatchQueue.main.async { draggedSlot = nil }
                    return handled
                }
            } else {
                tileSurface(hovered: isHovered || isDropTarget, dashed: false) {
                    Image(systemName: slot.iconName)
                        .font(.system(size: slot.prefersLargeScale ? 17 : 15, weight: .regular))
                        .foregroundStyle(previewIconColor(for: slot))
                }
                .onDrag {
                    DispatchQueue.main.async { draggedSlot = slot }
                    return NSItemProvider(object: NSString(string: "slot:\(index)"))
                }
                .onDrop(of: [UTType.plainText.identifier], isTargeted: targetBinding(index)) {
                    providers in
                    let handled = handleDrop(providers, toIndex: index)
                    DispatchQueue.main.async { draggedSlot = nil }
                    return handled
                }
                .help(slot.label)
            }
        }
        .onHover { inside in
            if inside {
                hoveredSlotIndex = index
            } else if hoveredSlotIndex == index {
                hoveredSlotIndex = nil
            }
        }
    }

    private var clearTile: some View {
        let isTargeted = dropTargetIndex == -1
        let isHovered = hoveredSlotIndex == -1

        return tileSurface(hovered: isHovered || isTargeted, dashed: false) {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(
                    isTargeted || isHovered ? NLColor.destructive : NLColor.textSecondary)
        }
        .onDrop(of: [UTType.plainText.identifier], isTargeted: targetBinding(-1)) { providers in
            return handleDropOnTrash(providers)
        }
        .onHover { inside in
            if inside {
                hoveredSlotIndex = -1
            } else if hoveredSlotIndex == -1 {
                hoveredSlotIndex = nil
            }
        }
        .help(L("Drag a control here to clear this slot"))
    }

    /// Shared surface for the slot tiles: canvas fill, 1px border-strong
    /// stroke, radius 6. On hover the stroke moves to text-tertiary and a
    /// fill-hover layer goes underneath. No shadow.
    private func tileSurface<Content: View>(
        hovered: Bool,
        dashed: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                .fill(hovered ? NLColor.hoverFill : NLColor.canvas)

            RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous)
                .strokeBorder(
                    hovered ? NLColor.textTertiary : NLColor.borderStrong,
                    style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : [])
                )

            content()
        }
        .frame(width: tileSize, height: tileSize)
        .clipShape(RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: NLRadius.control, style: .continuous))
        .animation(.easeOut(duration: NLMotion.hover), value: hovered)
    }

    // MARK: - Palette

    private var paletteBlock: some View {
        VStack(alignment: .leading, spacing: NLSpace.s3) {
            Text(L("Drag a control onto a slot"))
                .font(NLFont.caption)
                .foregroundStyle(NLColor.textSecondary)

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 64, maximum: 84), spacing: NLSpace.s3, alignment: .top)
                ],
                alignment: .leading,
                spacing: NLSpace.s3
            ) {
                ForEach(MusicControlButton.pickerOptions, id: \.self) { control in
                    paletteTile(control)
                }
            }
        }
    }

    private func paletteTile(_ control: MusicControlButton) -> some View {
        let isHovered = hoveredPaletteControl == control

        return VStack(spacing: NLSpace.s1) {
            tileSurface(hovered: isHovered, dashed: false) {
                Image(systemName: control.iconName)
                    .font(.system(size: control.prefersLargeScale ? 17 : 15, weight: .regular))
                    .foregroundStyle(NLColor.textPrimary)
            }
            .onDrag {
                return NSItemProvider(object: NSString(string: "control:\(control.rawValue)"))
            }
            .onTapGesture {
                addOrReplace(control)
            }
            .focusable()
            .onKeyPress(.return) {
                addOrReplace(control)
                return .handled
            }
            .onKeyPress(.space) {
                addOrReplace(control)
                return .handled
            }

            Text(control.label)
                .font(NLFont.caption)
                .foregroundStyle(NLColor.textSecondary)
                .frame(width: 64)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .onHover { inside in
            if inside {
                hoveredPaletteControl = control
            } else if hoveredPaletteControl == control {
                hoveredPaletteControl = nil
            }
        }
    }

    // MARK: - Restore defaults

    private var footerBlock: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button(L("Reset to Defaults")) {
                withAnimation {
                    musicControlSlots = MusicControlButton.defaultLayout
                }
            }
            .buttonStyle(NLButtonStyle(variant: .secondary))
        }
    }

    // MARK: - Visuals

    private func previewIconColor(for slot: MusicControlButton) -> Color {
        switch slot {
        case .shuffle:
            return musicManager.isShuffled ? NLColor.accent : NLColor.textPrimary
        case .repeatMode:
            return musicManager.repeatMode != .off ? NLColor.accent : NLColor.textPrimary
        case .favorite:
            return musicManager.isFavoriteTrack ? NLColor.accent : NLColor.textPrimary
        default:
            return NLColor.textPrimary
        }
    }

    // MARK: - Data

    private func targetBinding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { dropTargetIndex == index },
            set: { newValue in
                if newValue {
                    dropTargetIndex = index
                } else if dropTargetIndex == index {
                    dropTargetIndex = nil
                }
            }
        )
    }

    private func ensureSlotCapacity(_ target: Int) {
        guard target > musicControlSlots.count else { return }
        let missing = target - musicControlSlots.count
        musicControlSlots.append(contentsOf: Array(repeating: .none, count: missing))
    }

    private func slotValue(at index: Int) -> MusicControlButton {
        guard musicControlSlots.indices.contains(index) else { return .none }
        return musicControlSlots[index]
    }

    /// Tapping a color takes the first empty slot, or replaces the first tile when none is free.
    private func addOrReplace(_ control: MusicControlButton) {
        if let idx = musicControlSlots.firstIndex(of: .none) {
            updateSlot(control, at: idx)
        } else {
            withAnimation { updateSlot(control, at: 0) }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], toIndex: Int) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { item, error in
                    // item may be an NSString (which conforms to NSItemProviderReading) or other reading type
                    if let nsstring = item as? NSString {
                        let raw = nsstring as String
                        DispatchQueue.main.async {
                            processDropString(raw, toIndex: toIndex)
                        }
                    } else if let str = item as? String {
                        DispatchQueue.main.async {
                            processDropString(str, toIndex: toIndex)
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func handleDropOnTrash(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { item, error in
                    if let nsstring = item as? NSString {
                        let raw = nsstring as String
                        DispatchQueue.main.async {
                            clearSlot(fromRaw: raw)
                        }
                    } else if let str = item as? String {
                        DispatchQueue.main.async {
                            clearSlot(fromRaw: str)
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func clearSlot(fromRaw raw: String) {
        guard raw.hasPrefix("slot:") else { return }
        let from = Int(raw.replacingOccurrences(of: "slot:", with: "")) ?? -1
        guard from >= 0 && from < fixedSlotCount else { return }
        var slots = musicControlSlots
        if from < slots.count {
            slots[from] = .none
            musicControlSlots = slots
        }
    }

    private func processDropString(_ raw: String, toIndex: Int) {
        if raw.hasPrefix("slot:") {
            let from = Int(raw.replacingOccurrences(of: "slot:", with: "")) ?? -1
            guard from >= 0 && from < fixedSlotCount else { return }
            var slots = musicControlSlots
            if from < slots.count && toIndex < slots.count {
                slots.swapAt(from, toIndex)
                musicControlSlots = slots
            }
        } else if raw.hasPrefix("control:") {
            let val = raw.replacingOccurrences(of: "control:", with: "")
            if let control = MusicControlButton(rawValue: val) {
                // If this control already exists in another slot, clear that original slot
                var slots = musicControlSlots
                if let existing = slots.firstIndex(of: control), existing != toIndex {
                    slots[existing] = .none
                    musicControlSlots = slots
                }

                updateSlot(control, at: toIndex)
            }
        }
    }

    private func updateSlot(_ value: MusicControlButton, at index: Int) {
        var slots = musicControlSlots
        if index >= slots.count {
            slots.append(contentsOf: Array(repeating: .none, count: index - slots.count + 1))
        }
        slots[index] = value
        musicControlSlots = slots
    }
}
