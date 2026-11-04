//
//  StatsView.swift
//  Notch Lyrics
//
//  The stats tab: four ring gauges — CPU, GPU, memory, disk — laid out in the
//  same 640×190 strip as every other tab.
//
//  Layout contract — same as WeatherView: the open notch is a fixed 640×190
//  slab shared by every tab, and this view must live inside that box. The
//  header is the real notch height (32pt on a notched MacBook), so the row gets
//  190 − 32 − 4 = 154pt. The parent also insets the tab content, so the usable
//  width is ~566pt, not 640 — measure it, do not assume it.
//
//  The shape of the panel follows the ring-gauge convention: a circle whose
//  fill is the fraction, the number set inside it, and the name plus a second
//  reading to its right. That is what makes four metrics legible in a strip
//  this short — a row of cards with a big number and a bar underneath spent
//  half its height on empty space, and the curve pushed CPU to twice the width
//  of everything else.
//
//  The rings answer "what now". The strip underneath answers "what is moving":
//  a 60-second trace of network throughput across the full width — download as
//  the filled body, upload as the thinner line above it — plus a footer with the
//  current rates and GPU memory. Those readings have no cell in the ring row,
//  but the sampler already pays to collect them. They sit below rather than
//  beside the rings because the four gauges already use the whole width, and a
//  fifth column would squeeze the labels that are the only thing telling the
//  four apart.
//
//  There are deliberately no card backgrounds. The slab is already black, the
//  rings already separate the four readings, and a box around each one only
//  added four rounded rectangles competing with the slab's own corners.
//
//  Sampling cost is paid on appearance, not on construction: `start()` opens
//  the clock in `.onAppear` and `stop()` closes it in `.onDisappear`, so a tab
//  nobody is looking at costs nothing. A stats panel that shows up in its own
//  CPU reading is the one failure mode worth designing against.
//
//  The default is colourless, and that is a decision rather than an omission:
//  a red ring next to "GPU 100%" would imply the machine is in trouble when
//  `Device Utilization` only means "had work in flight". White on black, sized
//  to be read at a glance. `StatsPalette` carries the alternatives and the
//  reasoning for each, and the choice is a setting — see StatsSettings.
//

import Foundation
import SwiftUI

/// What drives the colour of the four rings.
///
/// This is a setting rather than a decision because both answers are defensible
/// and they fail differently. `.mono` never lies; `.trafficLight` is livelier
/// and photographs better, but it turns red on an ordinary compile. The user is
/// the only one who knows whether this panel is something they glance at or
/// something they screenshot.
///
/// The four cases read as a set because each answers the same question — what
/// is the colour a function of?
enum StatsPalette: String, CaseIterable, Identifiable {
    /// White rings, always.
    case mono
    /// Green / amber / red by utilisation.
    case trafficLight
    /// White rings, temperature line coloured.
    case temperature
    /// White until something is genuinely wrong.
    case alerts

    /// Shared by the tab and its settings page. `@AppStorage` on both sides
    /// rather than a `Defaults` key plus a manager: the notch has to pick up a
    /// change while the settings window is still open, and this gets there
    /// without an object in between.
    static let storageKey = "statsPalette"

    var id: String { rawValue }

    /// Short enough for a segmented control.
    ///
    /// Note the key: `L("None")` already exists in the catalogue for the
    /// keyboard-shortcut row, where it means "no shortcut" and translates to
    /// 无操作. Reusing it here put "无操作" under a ring setting — always give a
    /// new meaning a new key.
    var label: String {
        switch self {
        case .mono: return L("Monochrome")
        case .trafficLight: return L("Load")
        case .temperature: return L("Heat")
        case .alerts: return L("Alerts")
        }
    }
}

/// Thresholds shared by the alert colouring and the settings page, so the two
/// cannot drift apart. Edited with sliders in `StatsSettings`.
enum StatsTuning {
    static let hotTemperatureKey = "statsHotTemperature"
    static let lowDiskKey = "statsLowDiskGB"
    /// An M-series part starts pulling its clocks back around here.
    static let defaultHotTemperature: Double = 85
    /// The point where macOS itself starts complaining about the startup disk.
    static let defaultLowDiskGB: Double = 20
}

struct StatsView: View {
    @ObservedObject private var manager = StatsManager.shared

    @AppStorage(StatsPalette.storageKey) private var paletteRaw: String = StatsPalette.mono.rawValue
    @AppStorage(StatsTuning.hotTemperatureKey) private var hotTemperature: Double = StatsTuning.defaultHotTemperature
    @AppStorage(StatsTuning.lowDiskKey) private var lowDiskGB: Double = StatsTuning.defaultLowDiskGB

    /// Only the offscreen render harness sets this; in the app the palette
    /// comes from the setting above.
    var paletteOverride: StatsPalette?

    private var palette: StatsPalette {
        paletteOverride ?? StatsPalette(rawValue: paletteRaw) ?? .mono
    }

    var body: some View {
        // Spacing is fixed and each cell is only as wide as its own content, so
        // the row is a single block that `.frame(maxWidth: .infinity)` centres.
        //
        // The earlier version gave every cell an equal quarter of the width
        // (`maxWidth: .infinity` per cell). That kept the rings on an even
        // rhythm but left-aligned the content inside each quarter, and because
        // the last label ("可用 204 GB") is narrower than its quarter, all the
        // slack piled up on the right: measured 14.5pt of margin on the left
        // against 29.5pt on the right, i.e. the block sat 7.5pt off centre.
        // Equal *gaps* instead of equal *cells* centres the ink by construction.
        VStack(spacing: 7) {
            HStack(spacing: 26) {
                RingCell(
                    label: "CPU",
                    reading: percentText(manager.snapshot?.cpuUsage),
                    unit: "%",
                    detail: temperature(manager.snapshot?.cpuTemperature),
                    fraction: manager.snapshot?.cpuUsage ?? 0,
                    ringTint: ringTint(manager.snapshot?.cpuUsage ?? 0),
                    detailTint: detailTint(
                        manager.snapshot?.cpuUsage ?? 0,
                        celsius: manager.snapshot?.cpuTemperature,
                        alert: isHot(manager.snapshot?.cpuTemperature))
                )

                RingCell(
                    label: "GPU",
                    reading: percentText(manager.snapshot?.gpuUsage),
                    unit: "%",
                    detail: temperature(manager.snapshot?.gpuTemperature),
                    fraction: manager.snapshot?.gpuUsage ?? 0,
                    ringTint: ringTint(manager.snapshot?.gpuUsage ?? 0, escalates: false),
                    detailTint: detailTint(
                        manager.snapshot?.gpuUsage ?? 0,
                        celsius: manager.snapshot?.gpuTemperature,
                        alert: isHot(manager.snapshot?.gpuTemperature),
                        escalates: false)
                )

                RingCell(
                    label: L("Memory"),
                    reading: percentText(manager.snapshot?.memoryFraction),
                    unit: "%",
                    detail: memoryDetail,
                    fraction: manager.snapshot?.memoryFraction ?? 0,
                    ringTint: ringTint(manager.snapshot?.memoryFraction ?? 0),
                    detailTint: detailTint(manager.snapshot?.memoryFraction ?? 0)
                )

                RingCell(
                    label: L("Disk"),
                    reading: percentText(manager.snapshot?.diskFraction),
                    unit: "%",
                    detail: diskDetail,
                    fraction: manager.snapshot?.diskFraction ?? 0,
                    ringTint: ringTint(manager.snapshot?.diskFraction ?? 0),
                    detailTint: detailTint(
                        manager.snapshot?.diskFraction ?? 0,
                        alert: isDiskLow)
                )
            }
            .frame(maxWidth: .infinity)

            // The trace is drawn against a fixed 60-slot window, right-aligned,
            // so it rolls in from the right as samples arrive instead of
            // stretching a two-point line across the whole width.
            //
            // It carries its own caption: a chart sitting directly above the
            // network numbers has to say what it is, and the busiest moment in
            // the window is the number worth reading off it.
            //
            // The caption reports the *measured* peak, not the axis ceiling.
            // Those are deliberately different numbers: the axis sits on a
            // quantised ladder so it stops wobbling, which means a quiet minute
            // is drawn against a ceiling far above anything it reached. Printing
            // the ceiling under the word "Peak" made the panel claim 4 MB/s on a
            // minute that never passed 100 KB/s.
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L("Network") + " · 60s")
                    Spacer(minLength: 8)
                    Text("\(L("Peak")) \(rateText(networkPeak))")
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .accessibilityHidden(true)

                NetworkHistoryCurve(
                    download: manager.downloadHistory,
                    upload: manager.uploadHistory,
                    capacity: StatsManager.historyLength,
                    scaleMax: networkScale
                )
                .frame(height: 26)
                .accessibilityLabel(L("Network"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                NetworkReading(
                    down: manager.snapshot?.downBytesPerSecond ?? 0,
                    up: manager.snapshot?.upBytesPerSecond ?? 0
                )

                Spacer(minLength: 8)

                if let vram = vramText {
                    HStack(spacing: 4) {
                        Text(L("VRAM"))
                            .foregroundStyle(.white.opacity(0.45))
                        Text(vram)
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .onAppear { manager.start() }
        .onDisappear { manager.stop() }
    }

    private var memoryDetail: String {
        guard let snapshot = manager.snapshot, snapshot.memoryTotal > 0 else { return "—" }
        return "\(gigabytes(snapshot.memoryUsed)) / \(String(format: "%.0f", Double(snapshot.memoryTotal) / 1_073_741_824)) GB"
    }

    private var diskDetail: String {
        guard let available = diskAvailableGB else { return "—" }
        return "\(L("Available")) \(String(format: "%.0f", available)) GB"
    }

    private var vramText: String? {
        guard let bytes = manager.snapshot?.gpuMemory, bytes > 0 else { return nil }
        return "\(gigabytes(bytes)) GB"
    }

    private var diskAvailableGB: Double? {
        guard let snapshot = manager.snapshot, snapshot.diskTotal > snapshot.diskUsed else { return nil }
        return Double(snapshot.diskTotal - snapshot.diskUsed) / 1_073_741_824
    }

    /// The busiest single reading in the window, either direction. This is the
    /// number the caption prints; `networkScale` is only the axis it is drawn
    /// against.
    private var networkPeak: Double {
        (manager.downloadHistory + manager.uploadHistory).max() ?? 0
    }

    private var networkScale: Double {
        Self.networkScale(download: manager.downloadHistory, upload: manager.uploadHistory)
    }

    /// The y-axis ceiling: the smallest rung of a fixed ladder that covers the
    /// busiest reading in the window, floored at 64 KB/s. Quantising keeps the
    /// axis still — auto-scaling to the exact peak rescaled the whole trace on
    /// every sample and made it visibly wobble.
    static func networkScale(download: [Double], upload: [Double]) -> Double {
        let peak = (download + upload).max() ?? 0
        return networkScaleLadder.first { $0 >= peak }
            ?? networkScaleLadder[networkScaleLadder.count - 1]
    }

    private static let networkScaleLadder: [Double] = [
        64 * 1024, 256 * 1024, 1024 * 1024, 4 * 1024 * 1024,
        16 * 1024 * 1024, 64 * 1024 * 1024, 256 * 1024 * 1024,
    ]

    /// Both thresholds default to where an M-series part throttles and where
    /// macOS warns about the startup disk, but each is adjustable in settings.
    private func isHot(_ celsius: Double?) -> Bool {
        guard let celsius else { return false }
        return celsius >= hotTemperature
    }

    private var isDiskLow: Bool {
        guard let available = diskAvailableGB else { return false }
        return available < lowDiskGB
    }

    private func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    private func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return "—" }
        return String(format: "%.0f°C", celsius)
    }

    // MARK: - Colour

    /// `escalates` says whether a high number is actually bad. For the CPU a busy
    /// core is load; for the GPU the ring reads `Device Utilization`, which only
    /// means "had work in flight" — a video call pins it at 100% while the chip
    /// is idle — so it must never turn amber or red.
    private func ringTint(_ fraction: Double, escalates: Bool = true) -> Color {
        switch palette {
        case .mono, .temperature, .alerts: return .white.opacity(0.92)
        case .trafficLight:                return escalates ? Self.loadColor(fraction) : .white.opacity(0.92)
        }
    }

    private func detailTint(
        _ fraction: Double, celsius: Double? = nil, alert: Bool = false, escalates: Bool = true
    ) -> Color {
        switch palette {
        case .mono:
            return .white.opacity(0.5)
        case .trafficLight:
            return escalates ? Self.loadColor(fraction).opacity(0.8) : .white.opacity(0.5)
        case .alerts:
            return alert ? Self.alertColor : .white.opacity(0.5)
        case .temperature:
            // Only the two readings that have a ceiling can go hot. Memory and
            // disk have no such thing, so they stay neutral rather than being
            // assigned a colour that would mean nothing.
            guard let celsius else { return .white.opacity(0.5) }
            return Self.heatColor(celsius)
        }
    }

    /// One red for both ramps. If `.trafficLight` and `.alerts` disagreed about
    /// what red looks like, the same panel would mean two different things.
    private static let alertColor = Color(red: 0.96, green: 0.40, blue: 0.36)

    /// Load ramp. Not the system `.green` / `.yellow` / `.red`: those are tuned
    /// for light backgrounds and the yellow in particular disappears on black.
    /// These are picked to sit at the same perceived weight as the white they
    /// replace, so a coloured panel does not read as "louder" overall.
    private static func loadColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.60: return Color(red: 0.36, green: 0.86, blue: 0.52)
        case ..<0.85: return Color(red: 0.98, green: 0.76, blue: 0.28)
        default:      return alertColor
        }
    }

    /// Heat ramp. 85°C is roughly where an M-series part starts pulling its
    /// clocks back, so that is where red begins — not at some round number.
    private static func heatColor(_ celsius: Double) -> Color {
        switch celsius {
        case ..<70: return .white.opacity(0.5)
        case ..<85: return Color(red: 0.98, green: 0.76, blue: 0.28)
        default:    return alertColor
        }
    }
}

// MARK: - Ring

/// One gauge: the fraction as a ring, the number inside it, and two lines of
/// text beside it. The second line is the interesting part — the ring already
/// says "67%", so repeating the percentage there would waste the only place
/// left for something the ring cannot show (temperature, GB, capacity).
private struct RingCell: View {
    let label: String
    let reading: String
    var unit: String?
    let detail: String
    let fraction: Double
    let ringTint: Color
    let detailTint: Color

    private let diameter: CGFloat = 66
    private let lineWidth: CGFloat = 7

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                // The track takes the ring's own hue at low alpha rather than a
                // flat grey, so a red ring does not sit on a grey ring.
                Circle()
                    .stroke(ringTint.opacity(0.16), lineWidth: lineWidth)

                Circle()
                    // A round cap on a zero-length trim still draws a dot, which
                    // reads as "present but idle" rather than "broken".
                    .trim(from: 0, to: min(max(fraction, 0.012), 1))
                    .stroke(
                        ringTint,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(reading)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    if let unit {
                        Text(unit)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
            }
            .frame(width: diameter, height: diameter)

            // Hug the content. There is deliberately no trailing spacer and no
            // per-cell `maxWidth`: both let a cell grow wider than its own
            // content, which is what pushed the row off centre (see the note in
            // `StatsView.body`).
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(detailTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Network history

/// A 60-second trace of network throughput. Download is the filled body;
/// upload is the thinner line above it. `scaleMax` is passed in from
/// `StatsView`, which picks it off a fixed ladder — so the axis only moves when
/// traffic crosses a rung, not on every sample.
///
/// No axes and no gridlines: the readings themselves live in the footer right
/// below, and the ceiling value is printed in the caption, so the strip shows a
/// magnitude as well as a silhouette.
private struct NetworkHistoryCurve: View {
    let download: [Double]
    let upload: [Double]
    let capacity: Int
    let scaleMax: Double

    private let downTint = Color.white.opacity(0.85)
    private let upTint = Color.white.opacity(0.4)

    var body: some View {
        GeometryReader { geo in
            let downPoints = points(download, in: geo.size)
            let upPoints = points(upload, in: geo.size)

            ZStack(alignment: .bottomLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                }
                .stroke(downTint.opacity(0.16), lineWidth: 1)

                if downPoints.count >= 2 {
                    fillPath(downPoints, height: geo.size.height)
                        .fill(
                            LinearGradient(
                                colors: [downTint.opacity(0.22), downTint.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    linePath(downPoints)
                        .stroke(
                            downTint,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                }

                if upPoints.count >= 2 {
                    linePath(upPoints)
                        .stroke(
                            upTint,
                            style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
                        )
                }
            }
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        Path { path in
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func fillPath(_ points: [CGPoint], height: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: points[0].x, y: height))
            for point in points { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: height))
            path.closeSubpath()
        }
    }

    private func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1, capacity > 1, size.width > 0, scaleMax > 0 else { return [] }
        let slots = max(capacity, values.count)
        let stepX = size.width / CGFloat(slots - 1)
        let offset = slots - values.count

        // Two points of headroom so a peak is not clipped by the stroke.
        let headroom: CGFloat = 2
        let usable = max(size.height - headroom, 1)

        return values.enumerated().map { index, value in
            let clamped = min(max(value, 0), scaleMax)
            return CGPoint(
                x: CGFloat(offset + index) * stepX,
                y: headroom + usable * (1 - CGFloat(clamped / scaleMax))
            )
        }
    }
}

// MARK: - Footer readings

/// Download / upload, in the same 9pt weight as the ring details. The arrows
/// carry the meaning; a "Network" caption would be one word wider than the two
/// numbers it names.
private struct NetworkReading: View {
    let down: Double
    let up: Double

    var body: some View {
        HStack(spacing: 8) {
            metric(symbol: "arrow.down", value: down, tint: .white.opacity(0.78))
            metric(symbol: "arrow.up", value: up, tint: .white.opacity(0.45))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Network"))
    }

    private func metric(symbol: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .bold))
            Text(rateText(value))
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .lineLimit(1)
    }
}

// MARK: - Helpers

/// The first sample has no baseline to subtract, so `cpuUsage` reads 0 for one
/// tick rather than unknown. Nothing to special-case there: it shows 0 for a
/// second and then behaves.
private func percentText(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(Int((min(max(value, 0), 1) * 100).rounded()))
}

/// Bytes per second as the unit a person would say out loud. Anything under a
/// kilobyte reads as 0 KB/s rather than flashing raw bytes.
private func rateText(_ bytesPerSecond: Double) -> String {
    let kilobytes = max(bytesPerSecond, 0) / 1024
    if kilobytes >= 1024 {
        return String(format: "%.1f MB/s", kilobytes / 1024)
    }
    return String(format: "%.0f KB/s", kilobytes)
}

private extension StatsSnapshot {
    var memoryFraction: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal)
    }

    var diskFraction: Double {
        guard diskTotal > 0 else { return 0 }
        return Double(diskUsed) / Double(diskTotal)
    }
}

#Preview {
    StatsView()
        .frame(width: 640, height: 190)
        .background(.black)
}
