//
//  NotchHomeView.swift
//  Notch Lyrics
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import AppKit
import AVFoundation
import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

/// 媒体页:左边一整块封面,右边标题、进度、控制 —— 布局保持原样,只在外面
/// 套一层 Liquid Glass 底板。
struct MusicPlayerView: View {
    @EnvironmentObject var vm: NotchViewModel
    let albumArtNamespace: Namespace.ID

    /// 面板可用高度约 149,卡片给 142 留一圈边,玻璃才不会贴着面板边读成
    /// 一块板子。里面扣掉上下 8 的留白,右栏拿到 126 —— 正好装得下
    /// 标题行(43)+ 进度(36)+ 控制行(30)。高度取自 `openPaneCardHeight`,
    /// 右栏歌词卡读的是同一个数,两张卡才对得齐。
    var body: some View {
        NotchGlassCard {
            HStack(spacing: 0) {
                AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace)
                    .padding(.all, 5)
                MusicControlsView()
                    .drawingGroup()
                    .compositingGroup()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(width: musicPaneWidth, height: openPaneCardHeight, alignment: .center)
        }
        .frame(width: musicPaneWidth, height: openPaneCardHeight)
    }
}

/// 媒体页的玻璃底板 —— 用的是统计页那套卡片配方。
///
/// 统计页的 tile(见 `StatRingCell` / `networkCard`)只做两件事:6% 白填充
/// 加 8% 白描边。它在全黑面板上读起来是"一片薄玻璃浮在底下",而不是一块
/// 实心灰板 —— 关键恰恰在于**几乎不填**,厚度只由那 1pt 描边交代。
///
/// 之前的版本给到 13% 提亮 + 0.34 亮边,还想叠 `.glassEffect`。方向是反的:
/// 提亮越重,越像贴上去的塑料板;玻璃感来自"底下还能看见"和"边缘有一道线"。
/// 所以这里不叠 Liquid Glass,直接复用 `NLNotch.cellFill` / `cellStroke`,
/// 保证媒体页和统计页是同一套表面语言,而不是两个各自为政的白。
struct NotchGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 14
    @ViewBuilder var content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        content()
            .background(
                shape
                    .fill(NLNotch.cellFill)
                    .overlay(shape.stroke(NLNotch.cellStroke, lineWidth: 1))
            )
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: NotchViewModel
    let albumArtNamespace: Namespace.ID
    @Default(.animatedArtwork) private var animatedArtworkEnabled
    @State private var animatedPlayer: AVQueuePlayer?
    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            albumArtButton
        }
        // 换歌即重查;目录 ID 不变时 Provider 的会话缓存直接命中。ID 和标题
        // 都进 key:播放器分批推送元数据,标题到齐后要用完整信息再查一次。
        .task(id: "\(musicManager.catalogID ?? "")|\(musicManager.songTitle)|\(musicManager.album)") {
            await refreshAnimatedCover()
        }
        .onAppear {
            // 收起时整个视图被拆掉,期间播放状态的变化收不到,展开时按现状补。
            setAnimatedPlaying(musicManager.isPlaying)
        }
        .onChange(of: musicManager.isPlaying) { _, playing in
            setAnimatedPlaying(playing)
        }
        .onDisappear {
            setAnimatedPlaying(false)
        }
    }

    /// 动态封面:目录里有动画资源时用 HLS 循环播放替掉静图,否则维持现状。
    /// 查询是异步的,期间静图照常显示 —— 迟到或落空都不产生可见的空窗。
    private func refreshAnimatedCover() async {
        let requestedID = musicManager.catalogID
        animatedPlayer?.pause()
        animatedPlayer = nil

        guard animatedArtworkEnabled,
              musicManager.isPlaying,
              vm.notchState == .open,
              let requestedID
        else { return }

        guard let cover = await AnimatedArtworkProvider.shared.animatedCover(
            catalogID: requestedID,
            title: musicManager.songTitle,
            artist: musicManager.artistName,
            album: musicManager.album),
              musicManager.catalogID == requestedID,
              musicManager.isPlaying
        else { return }

        let item = AVPlayerItem(url: cover.videoURL)
        let player = AVQueuePlayer(items: [item])
        player.isMuted = true
        player.actionAtItemEnd = .none
        animatedPlayer = player

        if let observer = loopObserver { NotificationCenter.default.removeObserver(observer) }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak player] _ in
            MainActor.assumeIsolated {
                player?.seek(to: .zero)
                player?.play()
            }
        }
        setAnimatedPlaying(true)
    }

    /// 暂停/收起就停,省的既费电又抢主线程;恢复播放时从当前帧继续。
    private func setAnimatedPlaying(_ playing: Bool) {
        guard animatedArtworkEnabled else { return }
        if playing {
            animatedPlayer?.play()
        } else {
            animatedPlayer?.pause()
        }
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment:.bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
            
            albumArtDarkOverlay
        }
    }

    /// 暂停时压暗封面。原来是外扩 50pt 的模糊黑雾,现在封面底下是玻璃卡而
    /// 不是纯黑面板,那层雾会溢出到卡面上,所以裁进封面形状里再压。
    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
    }
                

    private var albumArtImage: some View {
        ZStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(1, contentMode: .fit)

            // 动画层铺在静图上,加载完成前看到的是静图;裁剪与静图同心。
            if animatedArtworkEnabled, let player = animatedPlayer, musicManager.isPlaying {
                AnimatedArtworkVideoLayer(player: player)
                    .transition(.opacity)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
        .clipped()
        .clipShape(
            RoundedRectangle(
                cornerRadius: Defaults[.cornerRadiusScaling]
                    ? MusicPlayerImageSizes.cornerRadiusInset.opened
                    : MusicPlayerImageSizes.cornerRadiusInset.closed)
        )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

/// 静音、铺满、无控件的 HLS 播放层。AVPlayerLayer 的尺寸跟住容器,不参与
/// 布局 —— 封面的圆角与裁剪仍由外层的 `albumArtImage` 决定。
private struct AnimatedArtworkVideoLayer: NSViewRepresentable {
    let player: AVQueuePlayer

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.postsFrameChangedNotifications = true

        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspectFill
        layer.player = player
        container.layer?.addSublayer(layer)

        context.coordinator.frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: container, queue: .main
        ) { _ in
            // 关闭隐式动画,否则拖动窗口时视频层会拖着边走。
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = container.bounds
            CATransaction.commit()
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.syncLayerFrame(of: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let observer = coordinator.frameObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    final class Coordinator {
        var frameObserver: NSObjectProtocol?
        /// 首次布局先于任何 frame 通知发生,所以挂载与更新时都要同步一次。
        func syncLayerFrame(of container: NSView) {
            guard let layer = container.layer?.sublayers?.first as? AVPlayerLayer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = container.bounds
            CATransaction.commit()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
        @EnvironmentObject var vm: NotchViewModel
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit
    @Default(.keepMusicOpen) private var keepMusicOpen

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            slotToolbar
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    songInfo(width: geo.size.width - 36)
                    Spacer(minLength: 0)
                    keepLyricsPin
                        .padding(.top, 1)
                }
                musicSlider
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
        .padding(.trailing, 4)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            MarqueeText(
                $musicManager.songTitle,
                font: NLNotch.playerTitle,
                nsFont: .title3,
                textColor: NLNotch.playerTitleInk,
                frameWidth: width)
            MarqueeText(
                $musicManager.artistName,
                font: NLNotch.playerArtist,
                nsFont: .callout,
                // Keep the tint switch meaningful without sacrificing legibility:
                // blend the cover hue toward white only as far as 4.5:1 requires.
                textColor: Defaults[.playerColorTinting]
                    ? Color(nsColor: musicManager.avgColor).slabLegibleInk()
                    : NLNotch.playerArtistInk,
                frameWidth: width
            )
        }
    }

    /// A pin toggle that turns "keep lyrics on screen" on/off without leaving
    /// the music view. Mirrors the `keepMusicOpen` setting so the pin and the
    /// Settings switch stay in sync.
    ///
    /// The two states must read unmistakably different on the dark notch:
    /// pinned = solid white pin (filled glyph + white color), unpinned =
    /// outline pin in gray. The previous accent-color tint was too subtle and
    /// users read the pinned state as "did nothing".
    private var keepLyricsPin: some View {
        GlyphButton(
            icon: keepMusicOpen ? "pin.fill" : "pin",
            size: 11,
            color: keepMusicOpen ? .white : .white.opacity(0.5),
            box: 22
        ) {
            Defaults[.keepMusicOpen] = !Defaults[.keepMusicOpen]
        }
        .opacity(musicManager.hasActiveTrack ? 1 : 0.3)
        .disabled(!musicManager.hasActiveTrack)
        .help(L("Keep lyrics visible"))
    }

    private var musicSlider: some View {
        // The interval must not depend on `playbackRate`. Passing `nil` when the
        // rate was 0 stopped the timeline entirely, so the progress bar and
        // lyrics froze with no way to notice that state had changed — which is
        // exactly what happened after a track change, when MediaRemote briefly
        // reports rate 0. Refreshing unconditionally lets the data layer decide
        // whether the position should advance. During the ~0.3 s layout
        // animation the tick slows down so the animation owns the main thread;
        // at rest it returns to 0.1 s and progress accuracy is unchanged.
        TimelineView(.animation(minimumInterval: vm.isExpansionAnimating ? 0.5 : 0.1)) { timeline in
            NowPlayingProgress(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: sliderColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var sliderColor: Color {
        switch Defaults[.sliderColor] {
        case .albumArt:
            return Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.8)
        case .accent:
            return .effectiveAccent
        default:
            return .white
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        // 空槽位在这一行里不再有意义:整行是等分宽度,一个空槽只会把右边留出
        // 一段空白、让按钮整体偏左。原来的实现用空槽把按钮往中间挤,那是
        // 「按钮定宽、整行居中」的老布局。
        //
        // 心形槽在当前播放器没有写入通道时(网易云、Spotify)整个消失 —— 一颗
        // 按了没反应的死心形,不如不出现。
        return slotConfig
            .filter { $0 != .none && (musicManager.canFavoriteTrack || $0 != .favorite) }
            .prefix(sanitizedLimit)
            .map { $0 }
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        // 尺寸分三档:走带键 15、辅助键 14、播放键 20(它必须在视觉上重一档)。
        switch slot {
        case .shuffle:
            GlyphButton(icon: "shuffle", size: 14, color: musicManager.isShuffled ? NLNotch.musicPink : glyph) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            GlyphButton(icon: "backward.fill", size: 15, color: glyph) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            GlyphButton(
                icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
                size: 20,
                color: .white,
                box: 30,
                weight: .semibold
            ) {
                MusicManager.shared.togglePlay()
            }
        case .next:
            GlyphButton(icon: "forward.fill", size: 15, color: glyph) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            GlyphButton(icon: repeatIcon, size: 14, color: repeatIconColor) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            GlyphButton(
                icon: musicManager.isFavoriteTrack ? "heart.fill" : "heart",
                size: 14,
                color: musicManager.isFavoriteTrack ? NLNotch.musicPink : glyph
            ) {
                MusicManager.shared.toggleFavoriteTrack()
            }
        case .share:
            GlyphButton(icon: "square.and.arrow.up", size: 14, color: glyph) {
                Task { await QuickShareService.shared.shareNowPlaying() }
            }
            .disabled(!musicManager.hasActiveTrack)
            .opacity(musicManager.hasActiveTrack ? 1 : 0.35)
        case .goBackward:
            GlyphButton(icon: "gobackward.15", size: 14, color: glyph) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            GlyphButton(icon: "goforward.15", size: 14, color: glyph) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(height: 1)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return glyph
        case .all, .one:
            return NLNotch.musicPink
        }
    }

    /// 非激活态的字形色。比纯白低一档,播放键才好"跳"出来。
    private var glyph: Color { .white.opacity(0.82) }
}

/// 可调尺寸的小图标按钮。
///
/// 现成的 `HoverButton` 把尺寸钉死在 30/40 与 `.body`/`.largeTitle` 上:大号
/// 那颗字形 34pt,进到玻璃卡里会把整行撑高、也会把卡片撑到贴住面板底边。
/// 这里单独做一只尺寸可控的,顺便把 hover 底从胶囊换成圆。
struct GlyphButton: View {
    var icon: String
    var size: CGFloat = 14
    var color: Color = .white.opacity(0.85)
    var box: CGFloat = 26
    var weight: Font.Weight = .medium
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
                .frame(width: box, height: box)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovering in
            withAnimation(.smooth(duration: 0.2)) { hovering = isHovering }
        }
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(NLNotch.controlGlyph)
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }
    
    
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        // simplified: use a straightforward opacity transition
        .transition(.opacity)
    }

    /// Lyrics claim the right-hand pane whenever the feature is on and a track
    /// is loaded; the calendar falls back into that space otherwise.
    /// Keyed on `hasActiveTrack` rather than `isPlayerIdle` so that pausing does
    /// not make the lyrics disappear.
    private var isShowingLyrics: Bool {
        Defaults[.enableLyrics] && musicManager.hasActiveTrack
    }

    private var mainContent: some View {
        // The ZStack is intentional: its `.top` alignment pins the row when the
        // parent offers more height than the content needs.
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: openNotchPaneSpacing) {
                MusicPlayerView(albumArtNamespace: albumArtNamespace)
                    .frame(width: musicPaneWidth)

                secondaryPane
            }
            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        }
    }

    /// Right-hand pane: lyrics, else the calendar.
    ///
    /// The card is drawn unconditionally — with neither lyrics nor events it is
    /// simply an empty sheet of glass. Two reasons. It keeps the two panes on
    /// one surface language instead of a card next to a bare patch of panel;
    /// and an empty 186 pt hole on the right made the music card read as
    /// shoved off to the left. `Color.clear` is the empty content, not a
    /// placeholder string: there is nothing to explain.
    private var secondaryPane: some View {
        NotchGlassCard {
            Group {
                if isShowingLyrics {
                    ScrollingLyricsView(width: secondaryPaneWidth - 12)
                } else if Defaults[.showCalendar] {
                    CalendarView()
                        .onHover { isHovering in
                            vm.isHoveringCalendar = isHovering
                        }
                        .environmentObject(vm)
                } else {
                    Color.clear
                }
            }
            // 横向只让 6:日历自带 120 的固定高、宽度却要装下月份和滚轮,
            // 比媒体卡少让 3 pt 也换得回来,不至于把月份挤断。
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(width: secondaryPaneWidth, height: openPaneCardHeight)
        }
        .frame(width: secondaryPaneWidth, height: openPaneCardHeight)
        .transition(.opacity)
    }
}

/// 进度行:左已播、右剩余(带负号),两端夹住一条细轨 —— 和锁屏正在播放
/// 组件一致。两侧给固定宽度,数字翻位时轨道不会左右跳。
struct NowPlayingProgress: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: Color
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(timeString(from: sliderValue))
                .lineLimit(1)
                .frame(width: 30, alignment: .leading)

            CustomSlider(
                value: $sliderValue,
                range: 0...max(duration, 0),
                color: color,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 12, alignment: .center)

            // "-15:53" 是六个字符,10pt 等宽下 34 放不下会折行,给到 40;
            // 超过一小时的曲目会变成八字符,允许它轻微缩一点而不是截断。
            Text("-" + timeString(from: max(0, duration - sliderValue)))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 40, alignment: .trailing)
        }
        .font(NLNotch.playerTime)
        .monospacedDigit()
        .foregroundStyle(NLNotch.inkSoft)
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(NLNotch.trackFill)
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}
