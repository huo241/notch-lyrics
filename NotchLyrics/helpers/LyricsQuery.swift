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
    static func normalize(_ string: String) -> String {
        dropQualifierGroups(string)
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

        let titleScore = similarity(normalize(title), normalize(recordTitle))
        // A record about a different song is never acceptable, however well
        // the rest of the metadata lines up.
        guard titleScore >= 0.5 else { return 0 }
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

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs.isEmpty || rhs.isEmpty { return 0 }
        if lhs == rhs { return 1 }
        if lhs.count >= 2, rhs.count >= 2, lhs.contains(rhs) || rhs.contains(lhs) { return 0.85 }

        let left = bigrams(lhs)
        let right = bigrams(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return 2 * Double(left.intersection(right).count) / Double(left.count + right.count)
    }

    /// Character bigrams — the usual Sørensen–Dice coefficient. Works for CJK
    /// where there are no word boundaries to split on.
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
