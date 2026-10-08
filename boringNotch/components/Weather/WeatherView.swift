//
//  WeatherView.swift
//  Notch Lyrics
//
//  The weather tab: a live sky backdrop, current conditions, the hours ahead,
//  a temperature curve and the week.
//
//  Layout notes: the open notch is a wide, short strip (640×190), so the
//  Apple-Weather card stack — which relies on vertical scrolling on a phone —
//  becomes three columns here: conditions on the left, then the hours and the
//  curve stacked on the right, with the week one tap away. The visual language
//  (sky gradient that follows the weather and the hour, frosted cards,
//  multicolour SF Symbols, a spline temperature curve with a "now" marker)
//  follows Apple Weather.
//
//  The animated MeshGradient backdrop, the frosted-card treatment and the
//  spline curve are adapted from lruiz5/weather-app (MIT licensed) — see
//  ACKNOWLEDGEMENTS in the README for the full attribution.
//

import Defaults
import SwiftUI

// MARK: - Page

struct WeatherView: View {
    @ObservedObject private var manager = WeatherManager.shared
    @Default(.weatherAnimatedBackground) private var animated
    @Default(.weatherShowWeek) private var showWeek

    @State private var mode: Mode = .today
    @State private var isRefreshing = false

    private enum Mode: String, CaseIterable {
        case today = "今天"
        case week = "一周"
    }

    var body: some View {
        ZStack {
            WeatherBackdrop(code: manager.snapshot?.code, isDay: manager.snapshot?.isDay ?? true, animated: animated)

            content
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task {
            await manager.refresh()
        }
        .onChange(of: showWeek) { _, isOn in
            // Turning the week view off while it is the active mode would leave
            // the toolbar with no selected segment.
            if !isOn, mode == .week { mode = .today }
        }
        .onReceive(NotificationCenter.default.publisher(for: .weatherShouldRefresh)) { _ in
            Task { await manager.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = manager.snapshot {
            HStack(spacing: 12) {
                WeatherNowPane(snapshot: snapshot)
                    .frame(width: 208)

                VStack(spacing: 8) {
                    toolbar(snapshot: snapshot)

                    Group {
                        switch mode {
                        case .today:
                            VStack(spacing: 8) {
                                WeatherHourlyStrip(hours: snapshot.upcomingHours(10))
                                    .frame(maxHeight: .infinity)
                                WeatherCurvePane(hours: Array(snapshot.upcomingHours(10)))
                                    .frame(height: 60)
                            }
                        case .week:
                            WeatherWeekPane(days: snapshot.daily)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if manager.isLoading {
            WeatherLoadingPane()
        } else {
            WeatherEmptyPane(message: manager.errorMessage) {
                Task { await manager.refresh(force: true) }
            }
        }
    }

    /// Mode switch on the left, freshness and a manual refresh on the right.
    private func toolbar(snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 6) {
            ForEach(Mode.allCases.filter { $0 != .week || showWeek }, id: \.self) { candidate in
                Button {
                    withAnimation(.smooth(duration: 0.22)) { mode = candidate }
                } label: {
                    Text(candidate.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(mode == candidate ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(.white.opacity(mode == candidate ? 0.22 : 0.08))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Text(Self.updatedLabel(snapshot.fetchedAt))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
                .monospacedDigit()

            Button {
                Task {
                    isRefreshing = true
                    await manager.refresh(force: true)
                    isRefreshing = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .help("立即刷新")
        }
        .frame(height: 18)
    }

    private static func updatedLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return "更新于 \(formatter.string(from: date))"
    }
}

/// Broadcast when settings change the location, so an already-open tab reloads.
extension Notification.Name {
    static let weatherShouldRefresh = Notification.Name("weatherShouldRefresh")
}

// MARK: - Backdrop

/// The sky behind the tab. Two implementations: an animated `MeshGradient` on
/// macOS 15+, and a layered `LinearGradient` below that (the project still
/// supports Sonoma, where `MeshGradient` does not exist).
struct WeatherBackdrop: View {
    let code: Int?
    let isDay: Bool
    let animated: Bool

    @State private var phase: Float = 0

    var body: some View {
        let sky = code.map { WeatherCode.sky($0, isDay: isDay) } ?? .partly
        let (top, mid, bottom) = Palette.colors(for: sky)

        Group {
            if #available(macOS 15.0, *) {
                if animated {
                    TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
                        MeshGradient(
                            width: 3,
                            height: 3,
                            points: meshPoints,
                            colors: [top, top.opacity(0.95), top,
                                     mid, mid.opacity(0.92), mid,
                                     bottom, bottom.opacity(0.95), bottom]
                        )
                        .onChange(of: timeline.date) { _, _ in
                            phase += 0.006
                            if phase > .pi * 2 { phase -= .pi * 2 }
                        }
                    }
                } else {
                    MeshGradient(
                        width: 3,
                        height: 3,
                        points: [
                            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
                            SIMD2(0, 0.5), SIMD2(0.5, 0.5), SIMD2(1, 0.5),
                            SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
                        ],
                        colors: [top, top.opacity(0.95), top,
                                 mid, mid.opacity(0.92), mid,
                                 bottom, bottom.opacity(0.95), bottom]
                    )
                }
            } else {
                LinearGradient(colors: [top, mid, bottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        // A dark scrim keeps white text legible over a bright midday sky.
        .overlay(
            LinearGradient(colors: [.black.opacity(0.18), .black.opacity(0.34)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    /// Three interior control points drift gently; the edges stay pinned so the
    /// gradient never reveals a seam at the clip bounds.
    private var meshPoints: [SIMD2<Float>] {
        let t = phase
        let drift: Float = 0.035
        return [
            SIMD2(0, 0),
            SIMD2(0.5 + sin(t * 0.7) * drift, 0),
            SIMD2(1, 0),
            SIMD2(0, 0.5 + cos(t * 0.5) * drift),
            SIMD2(0.5 + sin(t) * drift, 0.5 + cos(t * 0.8) * drift),
            SIMD2(1, 0.5 + sin(t * 0.6) * drift),
            SIMD2(0, 1),
            SIMD2(0.5 + cos(t * 0.9) * drift, 1),
            SIMD2(1, 1),
        ]
    }
}

/// Sky palettes, one per weather family, day and night variants.
enum Palette {
    static func colors(for sky: WeatherCode.Sky) -> (Color, Color, Color) {
        switch sky {
        case .clear:
            return (rgb(0.25, 0.52, 0.88), rgb(0.42, 0.70, 0.94), rgb(0.62, 0.85, 0.97))
        case .partly:
            return (rgb(0.28, 0.45, 0.70), rgb(0.44, 0.60, 0.80), rgb(0.60, 0.73, 0.88))
        case .overcast:
            return (rgb(0.33, 0.38, 0.46), rgb(0.45, 0.51, 0.59), rgb(0.58, 0.64, 0.71))
        case .rain:
            return (rgb(0.19, 0.26, 0.35), rgb(0.28, 0.36, 0.46), rgb(0.38, 0.47, 0.58))
        case .snow:
            return (rgb(0.42, 0.56, 0.74), rgb(0.58, 0.71, 0.86), rgb(0.74, 0.84, 0.93))
        case .storm:
            return (rgb(0.13, 0.14, 0.20), rgb(0.20, 0.21, 0.29), rgb(0.29, 0.30, 0.39))
        case .night:
            return (rgb(0.06, 0.10, 0.20), rgb(0.10, 0.15, 0.28), rgb(0.16, 0.22, 0.37))
        }
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }
}

// MARK: - Current conditions

struct WeatherNowPane: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(snapshot.placeName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                if WeatherManager.shared.resolvedFromIP {
                    Image(systemName: "location.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.45))
                        .help("由网络定位推断")
                }
            }

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: WeatherCode.symbol(snapshot.code, isDay: snapshot.isDay))
                    .font(.system(size: 34))
                    .symbolRenderingMode(.multicolor)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 2)

                Text("\(Int(snapshot.temperature.rounded()))°")
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .padding(.top, 2)

            Text(WeatherCode.label(snapshot.code))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))

            HStack(spacing: 4) {
                Text("H:\(Int(snapshot.high.rounded()))°")
                Text("L:\(Int(snapshot.low.rounded()))°")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.65))

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                WeatherStatChip(icon: "thermometer.medium", text: "\(Int(snapshot.apparentTemperature.rounded()))°")
                WeatherStatChip(icon: "humidity.fill", text: "\(snapshot.humidity)%")
                WeatherStatChip(icon: "wind", text: String(format: "%.0f", snapshot.windSpeed))
                if let aqi = snapshot.aqi {
                    WeatherStatChip(icon: "aqi.medium", text: "\(aqi)")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

/// One small stat under the temperature: an icon plus a value. The wind value
/// is km/h, matching Open-Meteo's default unit.
struct WeatherStatChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .monospacedDigit()
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.white.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Hourly strip

struct WeatherHourlyStrip: View {
    let hours: [HourPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WeatherSectionHeader(title: "逐小时", icon: "clock")

            HStack(spacing: 0) {
                ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                    VStack(spacing: 3) {
                        Text(index == 0 ? "现在" : Self.hourLabel(hour.date))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(index == 0 ? 0.95 : 0.7))

                        Image(systemName: WeatherCode.symbol(hour.code, isDay: hour.isDay))
                            .font(.system(size: 15))
                            .symbolRenderingMode(.multicolor)
                            .frame(height: 18)

                        Text(hour.precipitationProbability > 0 ? "\(hour.precipitationProbability)%" : " ")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color(red: 0.45, green: 0.82, blue: 1.0))
                            .monospacedDigit()

                        Text("\(Int(hour.temperature.rounded()))°")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    static func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "H时"
        return formatter.string(from: date)
    }
}

// MARK: - Temperature curve

/// The spline temperature curve: gradient fill under the line, dots at each
/// hour, a dashed "now" marker, and precipitation bars along the bottom.
struct WeatherCurvePane: View {
    let hours: [HourPoint]

    private let sideInset: CGFloat = 14
    private let topInset: CGFloat = 12
    private let bottomInset: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let points = chartPoints(in: geometry.size)

            ZStack(alignment: .topLeading) {
                // Filled area under the curve.
                splinePath(points: points, closedTo: geometry.size.height - bottomInset)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.04)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                // The curve itself.
                splinePath(points: points, closedTo: nil)
                    .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // Hour dots, plus a label on the first and last point so the
                // range is readable without crowding every value in.
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    Circle()
                        .fill(.white)
                        .frame(width: 4, height: 4)
                        .position(point)

                    if index == 0 || index == points.count - 1 {
                        Text("\(Int(hours[index].temperature.rounded()))°")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .position(x: point.x, y: max(point.y - 12, 8))
                            .monospacedDigit()
                    }
                }

                // Precipitation bars, pinned to the baseline.
                precipitationBars(in: geometry.size, points: points)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.white.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard hours.count > 1 else { return [] }
        let temperatures = hours.map(\.temperature)
        let minimum = temperatures.min() ?? 0
        let maximum = temperatures.max() ?? 1
        // Pad the range so the curve never touches the frame edges.
        let padding = max((maximum - minimum) * 0.2, 1.5)
        let low = minimum - padding
        let high = maximum + padding
        let span = max(high - low, 0.001)

        let usableWidth = max(size.width - sideInset * 2, 1)
        let usableHeight = max(size.height - topInset - bottomInset, 1)

        return hours.enumerated().map { index, hour in
            let x = sideInset + usableWidth * CGFloat(index) / CGFloat(hours.count - 1)
            let normalized = (hour.temperature - low) / span
            let y = topInset + usableHeight * CGFloat(1 - normalized)
            return CGPoint(x: x, y: y)
        }
    }

    /// Catmull-Rom style smoothing expressed as cubic segments. `closedTo`
    /// appends a baseline and closes the path, which is how the area fill is
    /// built from the same curve.
    private func splinePath(points: [CGPoint], closedTo baseline: CGFloat?) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        if points.count == 2 {
            path.addLine(to: points[1])
        } else {
            for index in 0..<(points.count - 1) {
                let p0 = index > 0 ? points[index - 1] : points[index]
                let p1 = points[index]
                let p2 = points[index + 1]
                let p3 = index + 2 < points.count ? points[index + 2] : p2

                let control1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6,
                    y: p1.y + (p2.y - p0.y) / 6
                )
                let control2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6,
                    y: p2.y - (p3.y - p1.y) / 6
                )
                path.addCurve(to: p2, control1: control1, control2: control2)
            }
        }

        if let baseline, let last = points.last, let firstPoint = points.first {
            path.addLine(to: CGPoint(x: last.x, y: baseline))
            path.addLine(to: CGPoint(x: firstPoint.x, y: baseline))
            path.closeSubpath()
        }
        return path
    }

    private func precipitationBars(in size: CGSize, points: [CGPoint]) -> some View {
        let baseline = size.height - 4
        let maxHeight: CGFloat = 12
        return ForEach(Array(points.enumerated()), id: \.offset) { index, point in
            let probability = hours[index].precipitationProbability
            if probability > 0 {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(red: 0.45, green: 0.82, blue: 1.0).opacity(0.65))
                    .frame(width: 3, height: max(2, maxHeight * CGFloat(probability) / 100))
                    .position(x: point.x, y: baseline - maxHeight / 2 + (maxHeight - max(2, maxHeight * CGFloat(probability) / 100)) / 2)
            }
        }
    }
}

// MARK: - Week

struct WeatherWeekPane: View {
    let days: [DayPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            WeatherSectionHeader(title: "未来一周", icon: "calendar")

            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 8) {
                    Text(index == 0 ? "今天" : Self.weekdayLabel(day.date))
                        .font(.system(size: 11, weight: index == 0 ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(index == 0 ? 0.95 : 0.8))
                        .frame(width: 40, alignment: .leading)

                    Image(systemName: WeatherCode.symbol(day.code, isDay: true))
                        .font(.system(size: 12))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 18)

                    Text(day.precipitationProbability > 0 ? "\(day.precipitationProbability)%" : "")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(red: 0.45, green: 0.82, blue: 1.0))
                        .frame(width: 26, alignment: .leading)
                        .monospacedDigit()

                    Spacer(minLength: 4)

                    // A mini range bar: how the day's span sits inside the
                    // week's span, which makes the shape of the week readable
                    // at a glance.
                    Capsule()
                        .fill(.white.opacity(0.18))
                        .frame(width: 54, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: [
                                    Color(red: 0.45, green: 0.82, blue: 1.0),
                                    Color(red: 1.0, green: 0.83, blue: 0.4),
                                ], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, 54 * spanFraction(for: day)), height: 4)
                                .offset(x: 54 * startFraction(for: day))
                        }

                    Text("\(Int(day.low.rounded()))°")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 24, alignment: .trailing)
                        .monospacedDigit()
                    Text("\(Int(day.high.rounded()))°")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, alignment: .trailing)
                        .monospacedDigit()
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var weekLow: Double { days.map(\.low).min() ?? 0 }
    private var weekHigh: Double { days.map(\.high).max() ?? 1 }

    private func startFraction(for day: DayPoint) -> Double {
        let span = max(weekHigh - weekLow, 0.001)
        return (day.low - weekLow) / span
    }

    private func spanFraction(for day: DayPoint) -> Double {
        let span = max(weekHigh - weekLow, 0.001)
        return max((day.high - day.low) / span, 0.12)
    }

    static func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - Shared bits

struct WeatherSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
        }
        .foregroundStyle(.white.opacity(0.6))
    }
}

// MARK: - States

struct WeatherLoadingPane: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
            Text("正在获取天气…")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WeatherEmptyPane: View {
    let message: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.55))
            Text(message ?? "暂无天气数据")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("重试")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.16))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    WeatherView()
        .frame(width: 640, height: 190)
        .background(.black)
}
