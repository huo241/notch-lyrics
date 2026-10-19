//
//  NeteaseLyricsProvider.swift
//  Notch Lyrics
//

import Foundation

/// 网易云音乐歌词源。
///
/// LRCLIB 的中文曲库明显偏薄（大量国语流行歌只有别名或干脆没有记录），
/// 而这正是本 App 主要用户的收听范围，所以中文歌优先走网易云。
///
/// 用的是网页端公开接口，不需要登录、不需要加密签名，只需带上 `Referer`：
///   · 搜索 `/api/search/get/web?s=…&type=1`
///   · 歌词 `/api/song/lyric?os=pc&id=…&lv=-1&kv=-1&tv=-1`
///
/// 搜索结果是按相关度排的，但里面混着翻唱、DJ 版和同名歌，所以候选要按
/// 标题/歌手/时长重新打分（复用 `LyricsQuery.score`），只有过线的才去拉歌词。
enum NeteaseLyricsProvider {

    // MARK: - Model

    struct Track {
        let id: Int
        let title: String
        let artist: String
        /// Seconds. 网易云返回的是毫秒。
        let duration: Double
    }

    // MARK: - Networking

    private static let userAgent = """
        Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 \
        (KHTML, like Gecko) Version/17.0 Safari/605.1.15
        """

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// 网易云对同一 IP 有明显的频率限制，超过就往回丢 `{"code":405,"msg":"操作频繁"}`
    /// （HTTP 状态仍是 200，只能从 body 里认）。连续切歌时很容易撞上，所以：
    /// 请求之间留最小间隔，撞上之后整体冷却一段时间，期间直接走别的源，
    /// 而不是每首歌都去撞一次墙。
    private actor Gate {
        static let shared = Gate()

        private var cooldownUntil: Date?
        private var lastRequest = Date.distantPast

        /// false 表示正在冷却，本次不要发请求。
        func acquire() async -> Bool {
            if let until = cooldownUntil, Date() < until { return false }
            let gap = Date().timeIntervalSince(lastRequest)
            if gap < 0.25 {
                try? await Task.sleep(for: .milliseconds(Int((0.25 - gap) * 1000)))
            }
            lastRequest = Date()
            return true
        }

        func penalize(seconds: TimeInterval) {
            cooldownUntil = Date().addingTimeInterval(seconds)
            LyricsDebug.log("netease: rate limited, cooling down \(Int(seconds))s")
        }
    }

    /// 网易云对没有 Referer 的请求一律返回空 JSON，这一步不能省。
    private static func request(_ url: URL) async -> Data? {
        guard await Gate.shared.acquire() else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                LyricsDebug.log("netease: not an HTTP response")
                return nil
            }
            // 限流藏在 body 里，状态码还是 200。
            if let text = String(data: data.prefix(300), encoding: .utf8),
               text.contains("\"code\":405") || text.contains("操作频繁") {
                await Gate.shared.penalize(seconds: 120)
                return nil
            }
            guard http.statusCode == 200 else {
                LyricsDebug.log("netease HTTP \(http.statusCode) \(url.path)")
                return nil
            }
            return data
        } catch {
            LyricsDebug.log("netease network: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Lookup

    /// 返回可直接应用的歌词，找不到时返回 nil（调用方继续试别的源）。
    @MainActor
    static func lookup(title: String, artist: String, duration: Double) async -> LyricsPayload? {
        // 关键：不能用「有返回就停」作为收敛条件。带 `(Live)`、`feat.` 这类噪声的
        // 查询往往能搜到一堆东西，但全都对不上；只有搜出真正过线的候选才值得停。
        var tracks: [Track] = []
        var ranked: [(track: Track, score: Double)] = []
        for query in searchQueries(title: title, artist: artist) {
            tracks += await search(query)
            ranked = rank(tracks, title: title, artist: artist, duration: duration)
            if !ranked.isEmpty { break }
        }

        guard !tracks.isEmpty else {
            LyricsDebug.log("netease: no search results")
            return nil
        }

        LyricsDebug.log("netease: \(tracks.count) results, \(ranked.count) above threshold")
        guard !ranked.isEmpty else { return nil }

        // 前几名都试一遍：正版可能被「uncollected」（无版权）挡住，而紧随其后的
        // 翻唱/现场版往往有完整时间轴，总比没有强。
        for item in ranked.prefix(3) {
            LyricsDebug.log(
                "netease try id=\(item.track.id) score=\(String(format: "%.2f", item.score)) "
                    + "← \"\(item.track.title)\" | \"\(item.track.artist)\"")
            if let payload = await lyric(for: item.track) {
                LyricsDebug.log("netease hit id=\(item.track.id) kind=\(payload.kind)")
                return payload
            }
        }
        return nil
    }

    /// 按「像不像在播的这首」重新排序，复用的是 LRCLIB 那套打分：
    /// 标题权重最高，时长差异是第二信号。
    private static func rank(
        _ tracks: [Track], title: String, artist: String, duration: Double
    ) -> [(track: Track, score: Double)] {
        tracks
            .compactMap { track -> (track: Track, score: Double)? in
                // 打分本身有个洞：`lhs.contains(rhs)` 直接给 0.85，
                // 于是「不存在的歌名xyz」会被《不存在的》这种短前缀曲名蹭到 0.61。
                // 归一化后长度差太多的，直接判为不是同一首。
                guard titleCompatible(title, track.title) else { return nil }

                let record: [String: Any] = [
                    "trackName": track.title,
                    "artistName": track.artist,
                    "duration": track.duration,
                ]
                let score = LyricsQuery.score(
                    record: record, title: title, artist: artist, duration: duration)
                return score >= LyricsQuery.minimumScore ? (track, score) : nil
            }
            .sorted { $0.score > $1.score }
    }

    private static func titleCompatible(_ playing: String, _ candidate: String) -> Bool {
        let left = LyricsQuery.normalize(playing)
        let right = LyricsQuery.normalize(candidate)
        guard !left.isEmpty, !right.isEmpty else { return false }
        let shorter = min(left.count, right.count)
        let longer = max(left.count, right.count)
        return Double(shorter) >= Double(longer) * 0.6
    }

    private static func searchQueries(title: String, artist: String) -> [String] {
        let cleaned = LyricsQuery.cleaned(title: title, artist: artist)
        var queries: [String] = []
        if !artist.isEmpty { queries.append("\(title) \(artist)") }
        if !cleaned.artist.isEmpty { queries.append("\(cleaned.title) \(cleaned.artist)") }
        queries.append(title)
        if cleaned.title != title { queries.append(cleaned.title) }

        var seen = Set<String>()
        return queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func search(_ keyword: String) async -> [Track] {
        // 用 `/api/search/get`，不要用它旁边那个 `/api/search/get/web`：
        // 后者被限得很死，几十次请求之后整条路径直接回 `操作频繁`，
        // 而同样的查询走前者一直正常。
        var components = URLComponents(string: "https://music.163.com/api/search/get")
        components?.queryItems = [
            URLQueryItem(name: "s", value: keyword),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "offset", value: "0"),
        ]
        guard let url = components?.url, let data = await request(url) else { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]]
        else {
            LyricsDebug.log("netease search: unparsable reply for \"\(keyword)\"")
            return []
        }

        return songs.compactMap { song in
            guard let id = song["id"] as? Int, let name = song["name"] as? String else { return nil }
            let artists = (song["artists"] as? [[String: Any]] ?? [])
                .compactMap { $0["name"] as? String }
                .joined(separator: " / ")
            let milliseconds = (song["duration"] as? NSNumber)?.doubleValue ?? 0
            return Track(id: id, title: name, artist: artists, duration: milliseconds / 1000)
        }
    }

    private static func lyric(for track: Track) async -> LyricsPayload? {
        var components = URLComponents(string: "https://music.163.com/api/song/lyric")
        components?.queryItems = [
            URLQueryItem(name: "os", value: "pc"),
            URLQueryItem(name: "id", value: String(track.id)),
            URLQueryItem(name: "lv", value: "-1"),
            URLQueryItem(name: "kv", value: "-1"),
            URLQueryItem(name: "tv", value: "-1"),
        ]
        guard let url = components?.url, let data = await request(url) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let raw = ((root["lrc"] as? [String: Any])?["lyric"] as? String) ?? ""
        let cleaned = stripCredits(raw)
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            LyricsDebug.log("netease: empty lyric for id=\(track.id) uncollected=\(root["uncollected"] ?? "?")")
            return nil
        }
        if isInstrumentalMarker(trimmed) {
            return LyricsPayload(kind: .instrumental, plain: "", synced: [])
        }

        let lines = LyricsParser.parse(cleaned)
        if lines.count >= 2 {
            return LyricsPayload(
                kind: .synced,
                plain: lines.map(\.text).joined(separator: "\n"),
                synced: lines)
        }
        // 少数条目只有纯文本（没有时间标签），仍然比空白强。
        return LyricsPayload(kind: .plain, plain: trimmed, synced: [])
    }

    // MARK: - Cleanup

    /// 网易云的 LRC 开头总挂着「作词 : X / 人声录音 : Y / 母带 : Z」这类制作信息。
    /// 它们只占开头几十秒，滚动时会一闪而过，读起来像歌词的一部分。
    ///
    /// 光靠关键词列表漏得多（「人声录音室」「人声编辑」都在意料之外），所以改成
    /// 句式判断：开头 30 秒内、形如「短名词 + 冒号 + 内容」的行，且冒号前的部分
    /// 命中制作相关字眼，才算制作信息。歌词正文里偶然出现的冒号不会命中字眼。
    private static let creditKeywords = [
        "作词", "作曲", "编曲", "制作", "混音", "母带", "录音", "人声", "和声",
        "吉他", "贝斯", "鼓", "键盘", "弦乐", "出品", "监制", "统筹", "发行",
        "营销", "策划", "企划", "演唱", "原唱", "翻唱", "工程师", "助理",
        "工作室", "后期", "版权", "宣发", "艺统", "配唱", "编配", "音乐制作",
        "词", "曲", "op", "sp",
    ]

    private static let timeTagRegex = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)

    private static func stripCredits(_ lrc: String) -> String {
        lrc
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { rawLine in
                let line = String(rawLine)
                guard let time = firstTime(in: line), time < 30 else { return true }
                return !looksLikeCredit(textAfterLastTimeTag(line))
            }
            .joined(separator: "\n")
    }

    private static func looksLikeCredit(_ text: String) -> Bool {
        guard let colon = text.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return false }
        let head = text[text.startIndex..<colon].trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty, head.count <= 14 else { return false }
        guard !head.contains(where: { "，。！？、；".contains($0) }) else { return false }
        let lowered = head.lowercased()
        return creditKeywords.contains { lowered.contains($0) }
    }

    private static func textAfterLastTimeTag(_ line: String) -> String {
        let range = NSRange(line.startIndex..., in: line)
        guard let last = timeTagRegex.matches(in: line, range: range).last,
              let boundary = Range(
                NSRange(location: last.range.location + last.range.length,
                        length: range.length - last.range.location - last.range.length),
                in: line)
        else { return "" }
        return String(line[boundary]).trimmingCharacters(in: .whitespaces)
    }

    private static func firstTime(in line: String) -> Double? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = timeTagRegex.firstMatch(in: line, range: range),
              let minuteRange = Range(match.range(at: 1), in: line),
              let secondRange = Range(match.range(at: 2), in: line),
              let minutes = Double(line[minuteRange]),
              let seconds = Double(line[secondRange])
        else { return nil }
        return minutes * 60 + seconds
    }

    private static func isInstrumentalMarker(_ text: String) -> Bool {
        guard text.count <= 40 else { return false }
        let lowered = text.lowercased()
        return lowered.contains("纯音乐")
            || lowered.contains("instrumental")
            || lowered.contains("此歌曲为没有填词的纯音乐")
    }
}
