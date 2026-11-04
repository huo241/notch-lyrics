//
//  LyricsNetwork.swift
//  Notch Lyrics
//
//  LRCLIB 的地址与出网方式。
//
//  官方域名在国内经常「连得上、但收不到响应」（TCP 握手成功，之后一直不返回），
//  表现就是每次查询都把预算耗在超时里。这里给出两条出路：
//
//    · 自定义端点：指向一个可达的镜像，官方域名不可用时照样查得到；
//    · 代理：默认沿用系统代理（沙盒里的 URLSession 本来就会用），也能手动指定，
//      给那些系统没配代理、但自己知道该走哪里的人。
//

import CFNetwork
import Defaults
import Foundation

enum LyricsNetwork {

    /// 官方端点。设置留空、或填了非法地址时用它。
    static let official = URL(string: "https://lrclib.net")!

    // MARK: - Endpoint

    /// 用户配置的端点，校验不过就回落到官方域名。
    ///
    /// 只接受带 http/https 的绝对地址：一个打错的端点比官方域名更糟——它会让每一次
    /// 查询都静默失败，而用户以为自己在用一个更快的镜像。
    static var base: URL {
        let raw = Defaults[.lyricsEndpoint].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return official }
        return url
    }

    /// 拼一个请求地址。
    ///
    /// `query` 已经百分号编码过，所以这里用字符串拼接而不是 `URLComponents`：后者会把
    /// `%` 再编码一遍，`%20` 就变成了 `%2520`。
    static func url(path: String, query: String) -> URL? {
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        return URL(string: "\(root)/\(path)?\(query)")
    }

    // MARK: - Session

    private static let lock = NSLock()
    private static var cached: (key: String, session: URLSession)?

    /// 歌词网络层共用的会话，代理设置变了就重建。
    ///
    /// 单次请求的超时是逐请求设置的（必须卡在整轮预算之内），所以这里只关心代理。
    static func session() -> URLSession {
        let key = proxyKey
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.key == key { return cached.session }

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = proxyDictionary()
        let session = URLSession(configuration: config)
        cached = (key, session)
        return session
    }

    // MARK: - Proxy

    private static var proxyKey: String {
        manualProxy() == nil ? "system" : "manual:\(Defaults[.lyricsProxy])"
    }

    /// 手动代理优先，否则交给系统。
    private static func proxyDictionary() -> [AnyHashable: Any]? {
        manualProxy() ?? systemProxy()
    }

    /// `host:port`（端口可省）。留空返回 nil，表示不覆盖系统设置。
    private static func manualProxy() -> [AnyHashable: Any]? {
        let raw = Defaults[.lyricsProxy].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ":")
        guard let host = parts.first, !host.isEmpty, parts.count <= 2 else { return nil }
        let port = parts.count == 2 ? Int(parts[1]) : nil

        var dictionary: [AnyHashable: Any] = [
            "HTTPEnable": 1, "HTTPProxy": String(host),
            "HTTPSEnable": 1, "HTTPSProxy": String(host),
        ]
        if let port {
            dictionary["HTTPPort"] = port
            dictionary["HTTPSPort"] = port
        }
        return dictionary
    }

    /// 系统代理。没配代理时返回 nil —— 让 URLSession 走默认（直连），而不是塞一个
    /// 空字典进去把它变成「无代理」。
    private static func systemProxy() -> [AnyHashable: Any]? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue()
                as? [String: Any] else { return nil }
        let enabled = ["HTTPEnable", "HTTPSEnable", "SOCKSEnable"]
            .contains { (settings[$0] as? Int) == 1 }
        return enabled ? settings : nil
    }
}
