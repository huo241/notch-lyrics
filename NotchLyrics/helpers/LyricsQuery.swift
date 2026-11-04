//
//  LyricsQuery.swift
//  Notch Lyrics
//

import Foundation

/// Turns the noisy metadata a media player reports into the spellings LRCLIB
/// actually stores, and decides whether a returned record really is the track
/// that is playing.
///
/// Players hand over strings like `Song (Live)`, `Song - Remastered 2011` or
/// `A feat. B`, while LRCLIB keeps one canonical spelling per record and
/// `GET /api/get` matches that spelling exactly. Widening the query before
/// giving up is what turns "no lyrics" into a hit.
///
/// `GET /api/search` is looser, but it returns anything whose metadata merely
/// contains the query, so its results are ranked here rather than trusted in
/// whatever order LRCLIB happens to return them.
///
/// Everything is a pure function over a `String` and a decoded JSON record,
/// so the ranking can be exercised without a network or a running app.
enum LyricsQuery {

    /// Below this, a record is treated as "not this song" and the caller should
    /// show nothing rather than the wrong words.
    static let minimumScore: Double = 0.6

    /// The title has to clear this on its own, before artist and duration are
    /// allowed to contribute anything.
    ///
    /// A veto rather than a weight, because a weight cannot veto: the title is
    /// worth 0.5 of the total, so with a perfect artist and duration even a
    /// title score of 0.2 still lands on 0.6 — exactly the threshold. That is
    /// how `Mesmer` used to come back with `Mesmerizer`'s lyrics. Measured:
    /// capping the title at the old 0.5 floor still gave 0.8.
    static let minimumTitleScore: Double = 0.7

    /// Bracketed trails that describe a *release* rather than the song, and so
    /// are unlikely to appear in LRCLIB's canonical title.
    ///
    /// These are only ever used to build *extra* candidates — the untouched
    /// metadata always stays first — so an over-eager match costs one wasted
    /// request, never a wrong answer.
    private static let qualifiers = [
        "live", "remaster", "remastered", "version", "mix", "edit", "mono",
        "stereo", "deluxe", "edition", "acoustic", "instrumental", "demo",
        "session", "take", "feat", "ft.", "with", "from", "ost", "theme",
        "现场", "演唱会", "伴奏", "纯音乐", "翻唱", "重置", "重制", "版",
        "电影", "电视剧", "主题曲", "插曲", "片尾曲", "片头曲",
    ]

    private static let brackets: [Character: Character] = [
        "(": ")", "（": "）", "[": "]", "【": "】", "「": "」",
    ]

    // MARK: - Candidates

    /// Every `(title, artist)` spelling worth asking LRCLIB about, most
    /// faithful first. The first entry is always the untouched metadata, so a
    /// clean library still costs exactly one request.
    static func candidates(title: String, artist: String) -> [(title: String, artist: String)] {
        let titles = titleVariants(title)
        let artists = artistVariants(artist)
        guard !titles.isEmpty, !artists.isEmpty else { return [] }

        var out: [(title: String, artist: String)] = []
        var seen = Set<String>()
        for candidateTitle in titles {
            for candidateArtist in artists {
                // Deduplicated on the exact spelling, not the normalised one:
                // `Song (Live)` and `Song` normalise alike but are distinct
                // lookups, and `/api/get` needs the one LRCLIB actually stored.
                let key = candidateTitle.lowercased() + "\u{1}" + candidateArtist.lowercased()
                guard seen.insert(key).inserted else { continue }
                out.append((candidateTitle, candidateArtist))
            }
        }
        return out
    }

    /// The most reduced spelling, used to seed the keyword search.
    static func cleaned(title: String, artist: String) -> (title: String, artist: String) {
        let trimmedTitle = titleVariants(title).last ?? title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtist = artistVariants(artist).last ?? artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmedTitle, trimmedArtist)
    }

    private static func titleVariants(_ raw: String) -> [String] {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return [] }

        var out = [base]
        let trailing = dropTrailingQualifier(base)
        if trailing != base { out.append(trailing) }
        let stripped = dropQualifierGroups(trailing)
        if !out.contains(stripped) { out.append(stripped) }
        let dashed = dropDashQualifier(stripped)
        if !out.contains(dashed) { out.append(dashed) }
        return out.filter { !$0.isEmpty }
    }

    private static func artistVariants(_ raw: String) -> [String] {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return [] }

        var out = [base]
        let stripped = dropQualifierGroups(base)
        if stripped != base, !stripped.isEmpty { out.append(stripped) }
        let primary = primaryArtist(stripped.isEmpty ? base : stripped)
        if !primary.isEmpty, !out.contains(primary) { out.append(primary) }
        return out
    }

    // MARK: - String surgery

    /// Removes a trailing bracketed group when it describes the release, e.g.
    /// `Song (Live)` → `Song`. Groups that are part of the title itself are
    /// left alone, because their content is not a qualifier.
    private static func dropTrailingQualifier(_ string: String) -> String {
        guard let closer = string.last,
              let opener = brackets.first(where: { $0.value == closer })?.key,
              let start = matchingOpen(of: opener, closer: closer, in: string) else { return string }

        let inner = String(string[string.index(after: start)..<string.index(before: string.endIndex)])
        guard containsQualifier(inner) else { return string }
        return String(string[string.startIndex..<start]).trimmingCharacters(in: .whitespaces)
    }

    /// Index of the bracket that opens the group closing at the end of `string`.
    private static func matchingOpen(of opener: Character, closer: Character, in string: String) -> String.Index? {
        var depth = 0
        var index = string.endIndex
        while index > string.startIndex {
            index = string.index(before: index)
            let character = string[index]
            if character == closer {
                depth += 1
            } else if character == opener {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    /// Removes every bracketed group whose content marks a release variant.
    private static func dropQualifierGroups(_ string: String) -> String {
        var result = ""
        var group = ""
        var depth = 0

        for character in string {
            guard depth > 0 else {
                if brackets[character] != nil {
                    depth = 1
                    group = String(character)
                } else {
                    result.append(character)
                }
                continue
            }

            group.append(character)
            if brackets[character] != nil {
                depth += 1
            } else if brackets.values.contains(character) {
                depth -= 1
                if depth == 0 {
                    if !containsQualifier(group) { result.append(group) }
                    group = ""
                }
            }
        }
        if depth == 0 { result.append(group) }

        return result
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// `Song - Remastered 2011` → `Song`.
    private static func dropDashQualifier(_ string: String) -> String {
        guard let dash = string.range(of: " - ", options: .backwards),
              containsQualifier(String(string[dash.upperBound...])) else { return string }
        return String(string[string.startIndex..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// `A feat. B` → `A`. LRCLIB files a collaboration under whichever artist
    /// the uploader picked, so the leading name is the better bet.
    private static func primaryArtist(_ string: String) -> String {
        let separators = [", ", " & ", "、", " / ", " feat. ", " ft. ", " featuring ", " with "]
        var cut = string.endIndex
        for separator in separators {
            if let range = string.range(of: separator, options: .caseInsensitive), range.lowerBound < cut {
                cut = range.lowerBound
            }
        }
        return String(string[string.startIndex..<cut]).trimmingCharacters(in: .whitespaces)
    }

    private static func containsQualifier(_ group: String) -> Bool {
        let lowered = group.lowercased()
        return qualifiers.contains { lowered.contains($0) }
    }

    // MARK: - Match quality

    /// Lowercased, diacritic- and punctuation-free form used for comparison.
    /// Release qualifiers are dropped first, so `Song (Live)` and `Song` meet.
    ///
    /// Dash qualifiers go too: `titleVariants` already strips
    /// `Song - Remastered 2011` before asking LRCLIB, so the scorer has to
    /// reduce the record's spelling the same way — otherwise a record stored
    /// with the dash suffix scores as a near miss against its own title.
    static func normalize(_ string: String) -> String {
        dropDashQualifier(dropQualifierGroups(string))
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    /// How much a record looks like the track that is playing.
    ///
    /// - Parameters:
    ///   - title: the player's raw title, not a cleaned one.
    ///   - artist: the player's raw artist.
    ///   - duration: the player's duration in seconds, or `0` when unknown.
    ///
    /// Title dominates, because a wrong song is far worse than a wrong take of
    /// the right one. When the player cannot report a duration, the weights
    /// are redistributed instead of silently scoring the record down.
    static func score(record: [String: Any], title: String, artist: String, duration: Double) -> Double {
        let recordTitle = (record["trackName"] as? String) ?? ""
        let recordArtist = (record["artistName"] as? String) ?? ""

        let titleScore = titleSimilarity(title, recordTitle)
        // A record about a different song is never acceptable, however well
        // the rest of the metadata lines up. This is a veto, not a weight:
        // see `minimumTitleScore`.
        guard titleScore >= Self.minimumTitleScore else { return 0 }
        let artistScore = similarity(normalize(artist), normalize(recordArtist))

        guard duration >= 1, let recordDuration = number(record["duration"]), recordDuration >= 1 else {
            return 0.65 * titleScore + 0.35 * artistScore
        }

        let difference = abs(duration - recordDuration)
        let durationScore: Double
        switch difference {
        case ..<2.5: durationScore = 1
        case ..<6: durationScore = 0.75
        case ..<12: durationScore = 0.45
        case ..<31: durationScore = 0.15
        default: durationScore = 0
        }

        return 0.5 * titleScore + 0.25 * artistScore + 0.25 * durationScore
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    /// 标题之间的相似度。
    ///
    /// 标题比歌手苛刻得多，因为「包含」在这里是个陷阱：`Mesmerizer` 只是把
    /// `Mesmer` 用作了前缀，字符相似度（Dice 0.73）看着很高，其实是两首歌。
    /// 所以包含关系只在短的那个是长的里面**连续的一串完整的词**时才算数；只是某个
    /// 单词里的一段字母，就把分数压到 `minimumTitleScore` 以下。
    private static func titleSimilarity(_ raw: String, _ otherRaw: String) -> Double {
        let lhs = normalize(raw)
        let rhs = normalize(otherRaw)
        if lhs.isEmpty || rhs.isEmpty { return 0 }
        if lhs == rhs { return 1 }

        let shorter: String
        let longer: String
        let longerRaw: String
        if lhs.contains(rhs) {
            shorter = rhs; longer = lhs; longerRaw = raw
        } else if rhs.contains(lhs) {
            shorter = lhs; longer = rhs; longerRaw = otherRaw
        } else {
            return dice(lhs, rhs)
        }

        guard shorter.count >= 2, isWordRun(shorter, in: longerRaw) else {
            // 只是词里的一段字母。0.45 不是为了「再低一点」——`score` 里标题
            // 要自己过 0.7，这里压下去是为了排序：片段命中必须排在真正的
            // 模糊命中之后，否则最像的那条会被它挤掉。
            return min(dice(lhs, rhs), 0.45)
        }
        // 几乎一样长（≥80%）且是整词包含：同一首歌的不同写法，给高分。
        // 已知边界：`Halo` 与 `Halo 2` 也会走这条，因为两个标题长度只差一个
        // 字符。真机上「同名词 + 数字后缀」几乎只出现在续作上，代价可以接受。
        return Double(shorter.count) >= Double(longer.count) * 0.8 ? 0.85 : dice(lhs, rhs)
    }

    /// 短的那个（已归一化）是不是长的那个原始写法里**连续的一串词**。
    ///
    /// 按词而不是按整串比，是因为两边都可能带空格：`Shape of You` 是
    /// `Shape of You - Radio Edit` 里连续三个词，只比整串会漏掉。
    private static func isWordRun(_ normalized: String, in raw: String) -> Bool {
        let words = raw.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map(normalize)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return false }

        for start in words.indices {
            var joined = ""
            for end in start..<words.count {
                joined += words[end]
                if joined == normalized { return true }
                if joined.count >= normalized.count { break }
            }
        }
        return false
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs.isEmpty || rhs.isEmpty { return 0 }
        if lhs == rhs { return 1 }
        if lhs.count >= 2, rhs.count >= 2, lhs.contains(rhs) || rhs.contains(lhs) { return 0.85 }
        return dice(lhs, rhs)
    }

    /// Sørensen–Dice over character bigrams. Works for CJK, where there are no
    /// word boundaries to split on.
    private static func dice(_ lhs: String, _ rhs: String) -> Double {
        let left = bigrams(lhs)
        let right = bigrams(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return 2 * Double(left.intersection(right).count) / Double(left.count + right.count)
    }

    /// Character bigrams. Works for CJK, where there are no word boundaries to
    /// split on.
    private static func bigrams(_ string: String) -> Set<String> {
        let characters = Array(string)
        guard characters.count > 1 else { return Set([string]) }

        var out = Set<String>()
        for index in 0..<(characters.count - 1) {
            out.insert(String(characters[index...index + 1]))
        }
        return out
    }
}
