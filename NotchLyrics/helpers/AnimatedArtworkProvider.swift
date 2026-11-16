//
//  AnimatedArtworkProvider.swift
//  Notch Lyrics
//
//  动态封面:Apple Music 目录里部分专辑自带的动画封面(HLS)。
//
//  链路三步,任何一步失败都返回 nil,由调用方退回静态封面:
//
//    1. AppleScript 侧的 `database id` 对上 Apple Music 目录。本地导入的曲目
//       也带这个值,但它对不上目录,查询会落空,同样走兜底;
//    2. 网页播放器 bundle 里烤着一把 developer token(kid = WebPlayKid,约
//       两个月一换),按过期时间缓存,过期才重新拉一次 bundle;
//    3. 目录 `editorialVideo.motionSquareVideo1x1` 给出 1:1 的 HLS 地址与
//       静帧海报。
//
//  查询结果(含"这张专辑没有动画资源"的负结果)按 catalog ID 缓存,所以没有
//  动画资源的专辑一次会话里只请求一次。
//

import Defaults
import Foundation

@MainActor
final class AnimatedArtworkProvider {
    static let shared = AnimatedArtworkProvider()
    private init() {}

    struct AnimatedCover: Equatable {
        let videoURL: URL
        /// 动画的静帧,加载期间可以先顶上;目录没给就是 nil。
        let posterURL: URL?
    }

    /// 会话内缓存。负结果也记:没有动画资源的专辑不该被反复请求。
    private var memoryCache: [String: AnimatedCover?] = [:]
    private var tokenTask: Task<String?, Never>?

    func animatedCover(catalogID: String, title: String, artist: String, album: String) async -> AnimatedCover? {
        // 缓存键用目录 ID(Apple Music 源下每个曲目稳定);本地文件的曲库 ID
        // 同样稳定,只是它在目录里查不到,由下面的搜索兜底。
        //
        // 元数据没到齐就先不缓存负结果:播放器会分批推送 ID 和标题,若用空
        // 专辑名搜一次就记住"没动画",这首歌就永远不会有动画了。
        let metadataReady = !album.isEmpty
        if metadataReady, let cached = memoryCache[catalogID] { return cached }
        let cover = await lookup(
            catalogID: catalogID, title: title, artist: artist, album: album)
        if metadataReady { memoryCache[catalogID] = cover }
        return cover
    }

    // MARK: - Catalog

    private func lookup(
        catalogID: String, title: String, artist: String, album: String
    ) async -> AnimatedCover? {
        guard let token = await developerToken() else { return nil }
        let storefront = Locale.autoupdatingCurrent.region?.identifier.lowercased() ?? "us"

        // ① 目录 ID 直查。Apple Music 串流曲目一次就中。
        if let attributes = await albumAttributes(
            id: catalogID, storefront: storefront, token: token) {
            // ID 有效但这张专辑没带动画 —— 静图是权威的,不猜另一张专辑的动画。
            return animatedCover(from: attributes)
        }

        // ② 目录 ID 落空(本地导入的文件):按「专辑 + 歌手」搜目录,打分挑
        //    最像的。动画配错专辑比没有动画更糟,所以分数不过线宁可直接放弃。
        return await search(
            album: album, artist: artist, storefront: storefront, token: token)
    }

    private func albumAttributes(
        id: String, storefront: String, token: String
    ) async -> [String: Any]? {
        var request = URLRequest(url: URL(string:
            "https://amp-api.music.apple.com/v1/catalog/\(storefront)/albums/\(id)?extend=editorialVideo")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]]
        else { return nil }
        return items.first?["attributes"] as? [String: Any]
    }

    /// 从目录的专辑属性里取 1:1 动画资源;没有就 nil。
    private func animatedCover(from attributes: [String: Any]) -> AnimatedCover? {
        guard let editorial = attributes["editorialVideo"] as? [String: Any],
              let square = editorial["motionSquareVideo1x1"] as? [String: Any],
              let videoString = square["video"] as? String,
              let videoURL = URL(string: videoString)
        else { return nil }

        // 静帧模板带 {w}x{h};按封面位给 600×600 足够。
        let posterURL = ((square["previewFrame"] as? [String: Any])?["url"] as? String)
            .flatMap { template in
                URL(string: template
                    .replacingOccurrences(of: "{w}", with: "600")
                    .replacingOccurrences(of: "{h}", with: "600"))
            }

        return AnimatedCover(videoURL: videoURL, posterURL: posterURL)
    }

    /// 按专辑 + 歌手搜目录,在**带动画资源**的结果里挑与元数据最像的一张。
    private func search(
        album: String, artist: String, storefront: String, token: String
    ) async -> AnimatedCover? {
        let term = "\(album) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty,
              let escaped = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string:
                "https://amp-api.music.apple.com/v1/catalog/\(storefront)/search"
                    + "?term=\(escaped)&types=albums&limit=6&extend=editorialVideo")
        else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("https://music.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [String: Any],
              let albums = (results["albums"] as? [String: Any])?["data"] as? [[String: Any]]
        else { return nil }

        var best: (score: Double, cover: AnimatedCover)?
        for albumResult in albums {
            guard let attributes = albumResult["attributes"] as? [String: Any],
                  let cover = animatedCover(from: attributes)
            else { continue }

            let record: [String: Any] = [
                "trackName": attributes["name"] ?? "",
                "artistName": attributes["artistName"] ?? "",
                "duration": 0,
            ]
            let score = LyricsQuery.score(
                record: record, title: album, artist: artist, duration: 0)
            guard score >= LyricsQuery.minimumScore else { continue }
            if best == nil || score > best!.score { best = (score, cover) }
        }
        return best?.cover
    }

    // MARK: - Developer token

    /// 过期前留一天余量,避免"刚好在今天过期"的临界态。
    private func developerToken() async -> String? {
        let cached = Defaults[.animatedArtworkDeveloperToken]
        if !cached.isEmpty,
           Defaults[.animatedArtworkDeveloperTokenExpiry] > Date().addingTimeInterval(86_400) {
            return cached
        }
        if let running = tokenTask { return await running.value }

        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            defer { self.tokenTask = nil }
            return await self.fetchDeveloperToken()
        }
        tokenTask = task
        return await task.value
    }

    private func fetchDeveloperToken() async -> String? {
        // 首页会重定向到本机店面;bundle 的文件名带 hash,得先从页面里取。
        guard let page = await fetchText(URL(string: "https://music.apple.com/")!),
              let bundleRange = page.range(of: #"/assets/index~[A-Za-z0-9_-]+\.js"#, options: .regularExpression),
              let bundle = await fetchText(URL(string: "https://music.apple.com\(page[bundleRange])")!)
        else { return nil }

        // bundle 里烤着多把 JWT;MusicKit 配置用的是 kid = WebPlayKid 那把。
        let pattern = try! NSRegularExpression(pattern: #"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#)
        let range = NSRange(bundle.startIndex..., in: bundle)
        let candidates = pattern.matches(in: bundle, range: range)
            .compactMap { Range($0.range, in: bundle) }.map { String(bundle[$0]) }

        for candidate in candidates {
            let parts = candidate.split(separator: ".").map(String.init)
            guard parts.count >= 2,
                  let headerData = Data(base64URLEncoded: parts[0]),
                  let payloadData = Data(base64URLEncoded: parts[1]),
                  let header = (try? JSONSerialization.jsonObject(with: headerData)) as? [String: Any],
                  header["kid"] as? String == "WebPlayKid",
                  let payload = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any],
                  let expiresAt = payload["exp"] as? Double
            else { continue }

            let expiry = Date(timeIntervalSince1970: expiresAt).addingTimeInterval(-86_400)
            Defaults[.animatedArtworkDeveloperToken] = candidate
            Defaults[.animatedArtworkDeveloperTokenExpiry] = expiry
            return candidate
        }
        return nil
    }

    private func fetchText(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue("https://music.apple.com/", forHTTPHeaderField: "Referer")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension Data {
    /// JWT 用的是 base64url,与标准 base64 差两个字符和补位。
    init?(base64URLEncoded string: String) {
        var value = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value += "=" }
        self.init(base64Encoded: value)
    }
}
