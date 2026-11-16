//
//  StatsView.swift
//  Notch Lyrics
//
//  The stats tab: four readings — CPU, GPU, memory, disk — each drawn as a
//  ring, in the same 640×190 strip as every other tab.
//
//  Layout contract — same as WeatherView: the open notch is a fixed 640×190
//  slab shared by every tab, and this view must live inside that box. The
//  header is the real notch height (32pt on a notched MacBook), so the row gets
//  190 − 32 − 4 = 154pt. The parent also insets the tab content, so the usable
//  width is ~566pt, not 640 — measure it, do not assume it.
//
//  The design. This strip is a monitor, not a dashboard wall. One ring per
//  metric with the percentage written in its centre, so the reading is legible
//  at a glance; one fixed hue per metric names the reading the way a colour key
//  does. Four readings in one row, nothing competing with them for attention.
//
//    - A ring is the most glanceable form a 0–100% value takes. The old
//      bar-under-a-number layout made you read a number and then find its bar;
//      the ring collapses both into one shape. That is the fix for "not
//      intuitive".
//
//    - The four hues are a key, not decoration. Each value is a constant
//      (coral / violet / sky / mint), never sampled from the wallpaper, and
//      none of them ever means "alarm" — colour indexes the metric, nothing
//      else.
//
//    - Each reading sits in a capsule with a soft drop shadow, so the four
//      tiles read as separate surfaces rather than one continuous slab. The
//      slab behind them is the existing notch surface; no extra sheen is added.
//
//    - Red means exactly one thing — this reading is in trouble — and appears in
//      exactly one place. The disk ring and its number turn red only when space
//      is genuinely low. A hot part turns only its detail line red: temperature
//      is a footnote to the utilisation number, so recolouring the ring would
//      conflate "busy" with "alarmed". The GPU at 100% never turns red — its
//      `Device Utilization %` is in-flight work, not a load alarm.
//
//  The second row is a single network readout: current down/up rates, spelled
//  out with their label and arrows. There is no history graph — an area under a
//  curve read as decoration rather than as a speed. VRAM belongs on the GPU
//  tile, not here, so this card means exactly one thing.
//
//  Sampling cost is paid on appearance, not on construction: `start()` opens
//  the clock in `.onAppear` and `stop()` closes it in `.onDisappear`, so a tab
//  nobody is looking at costs nothing. A stats panel that shows up in its own
//  CPU reading is the one failure mode worth designing against.
//

import Foundation
import SwiftUI

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

    @AppStorage(StatsTuning.hotTemperatureKey) private var hotTemperature: Double = StatsTuning.defaultHotTemperature
    @AppStorage(StatsTuning.lowDiskKey) private var lowDiskGB: Double = StatsTuning.defaultLowDiskGB

    var body: some View {
        VStack(spacing: 8) {
            ringsRow
                .frame(maxWidth: .infinity)

            // Network — one unambiguously-labelled readout. The old 60-second
            // area graph read as decoration: a user could not tell the shape
            // meant "this is your network speed". So the reading names itself —
            // lead with the word 网络 and print the two directions with their
            // arrows. VRAM is GPU memory, not network; it now lives on the GPU
            // tile (see `gpuDetail`), so this card means exactly one thing.
            networkCard
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .onAppear { manager.start() }
        .onDisappear { manager.stop() }
    }

    // MARK: - Metric data

    /// One value object per ring. `accent` is the metric's fixed index colour;
    /// `ringAlert` turns the ring and its number red when the reading is truly
    /// in trouble (disk low); `detailAlert` turns only the footnote line red
    /// (a part is hot).
    private var metrics: [StatMetric] {
        let snapshot = manager.snapshot
        let cpu = snapshot?.cpuUsage ?? 0
        let gpu = snapshot?.gpuUsage ?? 0
        let memory = snapshot?.memoryFraction ?? 0
        let disk = snapshot?.diskFraction ?? 0
        let cpuTemp = snapshot?.cpuTemperature
        let gpuTemp = snapshot?.gpuTemperature

        return [
            StatMetric(
                id: "cpu", label: "CPU", reading: percentText(snapshot?.cpuUsage),
                detail: temperature(cpuTemp), fraction: cpu,
                accent: NLNotch.statCpu, ringAlert: false, detailAlert: isHot(cpuTemp)),
            StatMetric(
                id: "gpu", label: "GPU", reading: percentText(snapshot?.gpuUsage),
                detail: gpuDetail, fraction: gpu,
                accent: NLNotch.statGpu, ringAlert: false, detailAlert: isHot(gpuTemp)),
            StatMetric(
                id: "memory", label: L("Memory"), reading: percentText(snapshot?.memoryFraction),
                detail: memoryDetail, fraction: memory,
                accent: NLNotch.statMemory, ringAlert: false, detailAlert: false),
            StatMetric(
                id: "disk", label: L("Disk"), reading: percentText(snapshot?.diskFraction),
                detail: diskDetail, fraction: disk,
                accent: NLNotch.statDisk, ringAlert: isDiskLow, detailAlert: false),
        ]
    }

    @ViewBuilder
    private var ringsRow: some View {
        HStack(spacing: 10) {
            ForEach(metrics) { metric in
                StatRingCell(metric: metric)
            }
        }
    }

    /// The network card: one thing, named by its own label. The word 网络 leads,
    /// then the two directions are spelled out with their arrows and live rates.
    /// No graph — a filled area under a curve was the part that read as
    /// "what is this", so it is gone, and the reading now says what it is.
    private var networkCard: some View {
        HStack(spacing: 14) {
            Text(L("Network"))
                .font(NLNotch.captionMedium)
                .foregroundStyle(NLNotch.dim)
                .lineLimit(1)

            Spacer(minLength: 6)

            NetworkReading(
                down: manager.snapshot?.downBytesPerSecond ?? 0,
                up: manager.snapshot?.upBytesPerSecond ?? 0,
                downTint: NLNotch.netDown,
                upTint: NLNotch.netUp
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NLNotch.cellFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(NLNotch.cellStroke, lineWidth: 1)
                )
        )
    }

    private var memoryDetail: String {
        guard let snapshot = manager.snapshot, snapshot.memoryTotal > 0 else { return "—" }
        return "\(gigabytes(snapshot.memoryUsed)) / \(String(format: "%.0f", Double(snapshot.memoryTotal) / 1_073_741_824)) GB"
    }

    /// GPU footnote: temperature plus the memory the accelerator has allocated.
    /// VRAM used to sit in the network footer, which was exactly the kind of
    /// mismatch that made that card read as "what is this even measuring" — it
    /// is GPU memory, so it belongs here, next to the GPU percentage.
    private var gpuDetail: String {
        let temp = temperature(manager.snapshot?.gpuTemperature)
        guard let vram = vramText else { return temp }
        return temp == "—" ? vram : "\(temp) · \(vram)"
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

    /// The one red on the strip. It means exactly one thing — this reading is in
    /// trouble — so there is only ever a single definition of it. The GPU at
    /// 100% does NOT get it: `Device Utilization` only means the chip had work
    /// in flight, and recolouring it would invent an alarm that is not there.
    /// `fileprivate` so the cell type in this file can read it too.
    fileprivate static let alertColor = Color(red: 0.96, green: 0.40, blue: 0.36)
}

// MARK: - Metric model

/// Everything one ring needs to draw its reading.
private struct StatMetric: Identifiable {
    let id: String
    let label: String
    let reading: String
    let detail: String
    /// 0...1 against a fixed 0–100% scale — every metric here is a percentage,
    /// so the ring never has to guess its own range.
    let fraction: Double
    /// The metric's fixed index colour (coral / violet / sky / mint).
    let accent: Color
    /// Turns the ring and its number red: the disk is genuinely low.
    let ringAlert: Bool
    /// Turns only the detail line red: a part is genuinely hot.
    let detailAlert: Bool
}

// MARK: - Ring cell

/// One reading in a capsule with a soft shadow, so the tile reads as its own
/// surface. The ring carries the magnitude at a glance; the centred percentage
/// is the value; the label and detail defer to it.
private struct StatRingCell: View {
    let metric: StatMetric

    private var ringColor: Color {
        metric.ringAlert ? StatsView.alertColor : metric.accent
    }

    private var numberColor: Color {
        metric.ringAlert ? StatsView.alertColor : NLNotch.inkStrong
    }

    private var detailColor: Color {
        metric.detailAlert ? StatsView.alertColor : NLNotch.detail
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                StatRing(fraction: metric.fraction, color: ringColor)
                    .frame(width: 48, height: 48)

                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(metric.reading)
                        .font(NLNotch.ringNumber)
                        .monospacedDigit()
                    Text("%")
                        .font(NLNotch.metricUnit)
                        .foregroundStyle(
                            metric.ringAlert ? StatsView.alertColor.opacity(0.8) : NLNotch.dim)
                }
                .foregroundStyle(numberColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            Text(metric.label)
                .font(NLNotch.ringLabel)
                .foregroundStyle(NLNotch.ink)
                .lineLimit(1)

            Text(metric.detail)
                .font(NLNotch.metricDetail)
                .monospacedDigit()
                .foregroundStyle(detailColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NLNotch.cellFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NLNotch.cellStroke, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

/// A thin progress ring. The track is the accent at low alpha; the arc is the
/// accent at full, starting at 12 o'clock and rounding its cap. Fixed 0–100%
/// range, so it never has to discover its own maximum.
private struct StatRing: View {
    let fraction: Double
    let color: Color
    let lineWidth: CGFloat = 4.5

    var body: some View {
        Circle()
            .stroke(color.opacity(0.16), lineWidth: lineWidth)
            .overlay(
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            )
    }
}

// MARK: - Footer readings

/// Download / upload, in the same 9pt weight as the metric details. The arrows
/// carry the meaning; a "Network" caption would be one word wider than the two
/// numbers it names.
private struct NetworkReading: View {
    let down: Double
    let up: Double
    var downTint: Color = NLNotch.netDownSoft
    var upTint: Color = NLNotch.netUpSoft

    var body: some View {
        HStack(spacing: 16) {
            metric(symbol: "arrow.down", value: down, tint: downTint)
            metric(symbol: "arrow.up", value: up, tint: upTint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Network"))
    }

    private func metric(symbol: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(rateText(value))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
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
