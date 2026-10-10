//
//  LyricsView.swift
//  Notch Lyrics
//
//  Created by Zhuanz on 2026-10-06.
//

import SwiftUI

/// Lyrics pane shown on the right-hand side of the open notch.
///
/// Presents time-synced lyrics as a scrolling window with the current line
/// highlighted. When only unsynced text is available it degrades to a static,
/// scrollable block rather than pretending to follow playback.
struct ScrollingLyricsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    let width: CGFloat

    /// Number of lines in the scrolling window (current line plus two either side).
    private let windowSize = 5
    private let lineHeight: CGFloat = 23

    var body: some View {
        Group {
            switch musicManager.lyricsKind {
            case .synced:
                syncedLyricsBody
            case .plain:
                staticLyricsBody
            case .instrumental:
                placeholder("纯音乐")
            case .none:
                placeholder(musicManager.isFetchingLyrics ? "加载中…" : "未找到歌词")
            }
        }
        .frame(width: width)
    }

    // MARK: - Synced

    private var syncedLyricsBody: some View {
        // 0.1s keeps line changes within ~100ms of the beat; the previous 0.25s
        // was noticeable on lyrics.
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            let elapsed = currentElapsed(at: timeline.date)
            let current = musicManager.currentLyricIndex(at: elapsed) ?? 0
            let lines = musicManager.syncedLyrics

            GeometryReader { geometry in
                let centerY = geometry.size.height / 2
                ZStack(alignment: .top) {
                    ForEach(lines.indices, id: \.self) { index in
                        let distance = index - current
                        if abs(distance) < windowSize {
                            Text(lines[index].text)
                                .font(font(forDistance: distance))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: width, alignment: .center)
                                .position(x: width / 2, y: centerY + CGFloat(distance) * lineHeight)
                                .opacity(opacity(forDistance: distance))
                                .scaleEffect(scale(forDistance: distance))
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: current)
                .mask(edgeFadeMask)
            }
        }
    }

    /// Fades lines out towards the top and bottom of the pane.
    private var edgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.18),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func opacity(forDistance distance: Int) -> Double {
        switch abs(distance) {
        case 0: return 1
        case 1: return 0.45
        default: return 0.22
        }
    }

    private func scale(forDistance distance: Int) -> CGFloat {
        abs(distance) == 0 ? 1 : 0.92
    }

    private func font(forDistance distance: Int) -> Font {
        abs(distance) == 0
            ? .system(size: 13, weight: .semibold)
            : .system(size: 12, weight: .regular)
    }

    // MARK: - Plain fallback

    private var staticLyricsBody: some View {
        let lines = musicManager.currentLyrics
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        return VStack(alignment: .leading, spacing: 4) {
            Text("无时间轴")
                .font(.system(size: 9))
                .foregroundStyle(.gray.opacity(0.6))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(lines.indices, id: \.self) { index in
                        if !lines[index].isEmpty {
                            Text(lines[index])
                                .font(.system(size: 11))
                                .foregroundStyle(.gray)
                                .frame(width: width, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }

    // MARK: - Helpers

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.gray.opacity(0.7))
                .frame(width: width, alignment: .center)
            Spacer(minLength: 0)
        }
        .frame(width: width)
    }

    /// Projects the playback position forward from the last reported timestamp.
    private func currentElapsed(at date: Date) -> Double {
        guard musicManager.isPlaying else { return musicManager.elapsedTime }
        let delta = date.timeIntervalSince(musicManager.timestampDate)
        // Same reasoning as MusicManager.estimatedPlaybackPosition: a rate of 0
        // here means MediaRemote stopped reporting it, not that playback halted,
        // and multiplying by it would freeze the lyrics.
        let rate = musicManager.playbackRate > 0 ? musicManager.playbackRate : 1
        let progressed = musicManager.elapsedTime + (delta * rate)
        guard musicManager.songDuration > 0 else { return max(0, progressed) }
        return min(max(progressed, 0), musicManager.songDuration)
    }
}
