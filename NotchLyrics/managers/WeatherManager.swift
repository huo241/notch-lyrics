//
//  WeatherManager.swift
//  Notch Lyrics
//
//  Weather data for the notch weather tab.
//
//  Data source: Open-Meteo (https://open-meteo.com) — free, no API key, no
//  account. The same source is used in production by other notch apps, so the
//  request shape is well trodden. Air quality comes from Open-Meteo's separate
//  air-quality endpoint, IP-based location from ipwho.is (ipinfo.io as fallback),
//  and reverse geocoding for a readable place name from BigDataCloud.
//
//  Location strategy: IP lookup by default (zero prompts), with a manual city
//  list as the fallback. Automatic IP location can land on a carrier exit node
//  rather than the actual town — verified on this machine, where it reports
//  Nanjing — so the manual picker is not optional.
//

import Combine
import Defaults
import Foundation

// MARK: - Models

/// A place the user can pin. Built-in entries (and anything picked from the
/// city search) carry the coordinates; Open-Meteo models resolve to a grid cell
/// several kilometres wide, so finer precision is noise.
struct WeatherPlace: Codable, Hashable, Identifiable {
    let name: String
    let latitude: Double
    let longitude: Double
    /// Region line ("浙江省 · 中国") for search results and the settings list.
    /// Optional so places saved before this field existed still decode.
    var detail: String?

    var id: String { String(format: "%.4f,%.4f", latitude, longitude) }

    /// What to show under a search result.
    var subtitle: String { detail ?? "" }
}

/// One row in the city search: a place plus a stable identity for SwiftUI.
struct CitySearchResult: Identifiable, Hashable {
    let id: String
    let place: WeatherPlace
}

struct HourPoint: Identifiable {
    let id = UUID()
    let date: Date
    let temperature: Double
    let code: Int
    let isDay: Bool
    let precipitationProbability: Int
}

struct DayPoint: Identifiable {
    let id = UUID()
    let date: Date
    let code: Int
    let high: Double
    let low: Double
    let precipitationProbability: Int
    let uvIndexMax: Double
    let sunrise: Date?
    let sunset: Date?
}

struct WeatherSnapshot {
    let placeName: String
    let temperature: Double
    let apparentTemperature: Double
    let humidity: Int
    let windSpeed: Double
    let code: Int
    let isDay: Bool
    let high: Double
    let low: Double
    let aqi: Int?
    let hourly: [HourPoint]
    let daily: [DayPoint]
    let fetchedAt: Date

    /// Today's sun times, straight off the daily array.
    var sunrise: Date? { daily.first?.sunrise }
    var sunset: Date? { daily.first?.sunset }

    /// Midnight of the day the snapshot was taken — used to expire the cache
    /// when the date rolls over even if the user keeps the tab open.
    var fetchedDay: Date { Calendar.current.startOfDay(for: fetchedAt) }
}

// MARK: - WMO weather codes

/// Open-Meteo reports conditions as WMO codes. Both the glyph and the Chinese
/// label live here so the view layer never has to switch on raw integers.
enum WeatherCode {
    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.max.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57: return "cloud.sleet.fill"
        case 61, 63, 65: return "cloud.rain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75, 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.rain.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        }
    }

    static func label(_ code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1: return "晴间多云"
        case 2: return "局部多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51: return "小毛毛雨"
        case 53: return "毛毛雨"
        case 55: return "大毛毛雨"
        case 56, 57: return "冻毛毛雨"
        case 61: return "小雨"
        case 63: return "中雨"
        case 65: return "大雨"
        case 66, 67: return "冻雨"
        case 71: return "小雪"
        case 73: return "中雪"
        case 75: return "大雪"
        case 77: return "米雪"
        case 80: return "小阵雨"
        case 81: return "阵雨"
        case 82: return "强阵雨"
        case 85: return "小阵雪"
        case 86: return "大阵雪"
        case 95: return "雷阵雨"
        case 96, 99: return "雷阵雨伴冰雹"
        default: return "未知"
        }
    }

    /// Background tint family for the animated backdrop. Coarser than the raw
    /// code on purpose: nearby codes share a sky.
    enum Sky { case clear, partly, overcast, rain, snow, storm, night }

    static func sky(_ code: Int, isDay: Bool) -> Sky {
        if !isDay { return .night }
        switch code {
        case 0, 1: return .clear
        case 2: return .partly
        case 3, 45, 48: return .overcast
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: return .rain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .storm
        default: return .partly
        }
    }
}

// MARK: - Manager

@MainActor
final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// Where the current numbers came from, shown in the tab so the user can
    /// tell an IP guess from a hand-picked city.
    @Published private(set) var resolvedPlace: WeatherPlace?
    @Published private(set) var resolvedFromIP = false

    /// Stale-while-revalidate window. Five minutes keeps the tab honest without
    /// hammering a free public API that asks callers to be reasonable.
    private let cacheLifetime: TimeInterval = 300
    private var inFlight = false

    private init() {}

    // MARK: Places

    /// Built-in places. Coordinates are city-centre; weather models resolve to
    /// a grid cell several kilometres wide, so finer precision is noise.
    static let builtInPlaces: [WeatherPlace] = [
        WeatherPlace(name: "长兴", latitude: 31.0267, longitude: 119.9103),
        WeatherPlace(name: "湖州", latitude: 30.8703, longitude: 120.0933),
        WeatherPlace(name: "杭州", latitude: 30.2741, longitude: 120.1551),
        WeatherPlace(name: "上海", latitude: 31.2304, longitude: 121.4737),
        WeatherPlace(name: "南京", latitude: 32.0603, longitude: 118.7969),
        WeatherPlace(name: "苏州", latitude: 31.2989, longitude: 120.5853),
        WeatherPlace(name: "北京", latitude: 39.9042, longitude: 116.4074),
        WeatherPlace(name: "广州", latitude: 23.1291, longitude: 113.2644),
        WeatherPlace(name: "深圳", latitude: 22.5431, longitude: 114.0579),
        WeatherPlace(name: "成都", latitude: 30.5728, longitude: 104.0668),
        WeatherPlace(name: "西安", latitude: 34.3416, longitude: 108.9398),
        WeatherPlace(name: "武汉", latitude: 30.5928, longitude: 114.3055),
        WeatherPlace(name: "重庆", latitude: 29.5630, longitude: 106.5516),
        WeatherPlace(name: "厦门", latitude: 24.4798, longitude: 118.0894),
    ]

    /// The place the user pinned manually, if any.
    var manualPlace: WeatherPlace? {
        get {
            guard let data = Defaults[.weatherManualPlaceData],
                  let place = try? JSONDecoder().decode(WeatherPlace.self, from: data)
            else { return nil }
            return place
        }
        set {
            Defaults[.weatherManualPlaceData] = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    // MARK: City search

    /// Free-text city search, so the user is not limited to the built-in list.
    /// Backed by Photon (OpenStreetMap) — the one keyless geocoder that handles
    /// Chinese queries properly ("湖州" → 湖州市 / 浙江省 / 中国), which is what
    /// this app's users type. Results are biased towards the current location so
    /// that a bare "长兴" prefers the nearby county over a same-named village
    /// provinces away.
    func searchCities(_ query: String) async throws -> [CitySearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 1 else { return [] }

        var components = URLComponents(string: "https://photon.komoot.io/api/")!
        var items: [URLQueryItem] = [
            .init(name: "q", value: trimmed),
            .init(name: "limit", value: "10"),
        ]
        if let nearby = resolvedPlace {
            items.append(.init(name: "lat", value: String(nearby.latitude)))
            items.append(.init(name: "lon", value: String(nearby.longitude)))
        }
        components.queryItems = items

        let payload: PhotonPayload = try await get(components.url!)

        var seen = Set<String>()
        var results: [CitySearchResult] = []
        for feature in payload.features {
            guard feature.geometry.coordinates.count == 2 else { continue }
            let properties = feature.properties
            guard let name = properties.name, !name.isEmpty else { continue }
            guard Self.isSettlement(properties) else { continue }

            let longitude = feature.geometry.coordinates[0]
            let latitude = feature.geometry.coordinates[1]
            guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { continue }

            let detail = [properties.state, properties.country]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")

            // Photon answers with both the city node and its administrative
            // boundary; keeping the first of each name/region pair avoids a list
            // of duplicates.
            let key = "\(name)|\(detail)"
            guard seen.insert(key).inserted else { continue }

            results.append(CitySearchResult(
                id: key,
                place: WeatherPlace(name: name, latitude: latitude, longitude: longitude, detail: detail)
            ))
            if results.count == 6 { break }
        }
        return results
    }

    /// Photon indexes streets, companies and train stations too; only places a
    /// person would recognise as a location belong in the picker. Anything
    /// tagged as a place or an administrative boundary passes; for everything
    /// else the type must name a settlement.
    private static func isSettlement(_ properties: PhotonPayload.Feature.Properties) -> Bool {
        if properties.osm_key == "place" || properties.osm_key == "boundary" { return true }
        let kind = (properties.type ?? properties.osm_value ?? "").lowercased()
        let allowed: Set<String> = [
            "city", "town", "village", "hamlet", "locality", "suburb",
            "administrative", "county", "district", "state", "region",
            "municipality", "borough", "province",
        ]
        return allowed.contains(kind)
    }

    private struct PhotonPayload: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                let name: String?
                let state: String?
                let country: String?
                let osm_key: String?
                let osm_value: String?
                let type: String?
            }
            struct Geometry: Decodable {
                let coordinates: [Double]
            }
            let properties: Properties
            let geometry: Geometry
        }
        let features: [Feature]
    }

    // MARK: Refresh

    /// Entry point from the view. Cached data is served instantly; a refresh
    /// happens only when the cache is stale or `force` is set.
    func refresh(force: Bool = false) async {
        // Serves cache instantly and skips the network when it is still fresh;
        // `isStale` also trips when the date rolls over, since the "today"
        // cards would otherwise keep yesterday's numbers.
        if !force, let snapshot, !isStale(snapshot) { return }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        // Manual pick always wins over IP.
        if let place = manualPlace {
            resolvedPlace = place
            resolvedFromIP = false
            await load(place: place, resolvedFromIP: false)
            return
        }

        if let cached = cachedIPPlace() {
            resolvedPlace = cached
            resolvedFromIP = true
            await load(place: cached, resolvedFromIP: true)
            return
        }

        do {
            let place = try await locateByIP()
            storeIPPlace(place)
            resolvedPlace = place
            resolvedFromIP = true
            await load(place: place, resolvedFromIP: true)
        } catch {
            errorMessage = "定位失败：\(error.localizedDescription)"
            isLoading = false
        }
    }

    private func isStale(_ snapshot: WeatherSnapshot) -> Bool {
        Date().timeIntervalSince(snapshot.fetchedAt) > cacheLifetime
            || snapshot.fetchedDay != Calendar.current.startOfDay(for: Date())
    }

    /// Drops cached numbers so the next refresh re-fetches (used after the user
    /// changes city in settings).
    func invalidate() {
        snapshot = nil
        errorMessage = nil
    }

    // MARK: Network

    private func load(place: WeatherPlace, resolvedFromIP: Bool) async {
        isLoading = snapshot == nil
        errorMessage = nil

        do {
            async let forecast = fetchForecast(place)
            async let aqi = fetchAQI(place)
            let (base, air) = try await (forecast, aqi)
            // A hand-picked city already carries the name the user chose;
            // reverse geocoding is only needed to translate an IP guess into
            // readable local script.
            let name = resolvedFromIP ? await displayName(for: place) : place.name
            snapshot = base.with(placeName: name, aqi: air)
        } catch {
            // Keep whatever was on screen; a stale reading beats a blank tab.
            if snapshot == nil {
                errorMessage = "天气获取失败：\(error.localizedDescription)"
            }
        }
        isLoading = false
    }

    private struct ForecastPayload: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let relative_humidity_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let is_day: Int
            let wind_speed_10m: Double
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let is_day: [Int]
            let precipitation_probability: [Int]
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int]
            let uv_index_max: [Double]
            let sunrise: [String]
            let sunset: [String]
        }
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    private func fetchForecast(_ place: WeatherPlace) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,is_day,wind_speed_10m"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max,sunrise,sunset"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "7"),
        ]

        let payload: ForecastPayload = try await get(components.url!)

        // Only hours from now forward; the endpoint returns the whole day.
        let now = Date()
        var hours: [HourPoint] = []
        for index in payload.hourly.time.indices {
            guard let date = Self.parse(payload.hourly.time[index]), date >= now.addingTimeInterval(-1800) else { continue }
            hours.append(HourPoint(
                date: date,
                temperature: payload.hourly.temperature_2m[safe: index] ?? 0,
                code: payload.hourly.weather_code[safe: index] ?? 0,
                isDay: (payload.hourly.is_day[safe: index] ?? 1) == 1,
                precipitationProbability: payload.hourly.precipitation_probability[safe: index] ?? 0
            ))
            if hours.count == 24 { break }
        }

        var days: [DayPoint] = []
        for index in payload.daily.time.indices {
            guard let date = Self.parseDay(payload.daily.time[index]) else { continue }
            days.append(DayPoint(
                date: date,
                code: payload.daily.weather_code[safe: index] ?? 0,
                high: payload.daily.temperature_2m_max[safe: index] ?? 0,
                low: payload.daily.temperature_2m_min[safe: index] ?? 0,
                precipitationProbability: payload.daily.precipitation_probability_max[safe: index] ?? 0,
                uvIndexMax: payload.daily.uv_index_max[safe: index] ?? 0,
                sunrise: Self.parse(payload.daily.sunrise[safe: index]),
                sunset: Self.parse(payload.daily.sunset[safe: index])
            ))
        }

        return WeatherSnapshot(
            placeName: place.name,
            temperature: payload.current.temperature_2m,
            apparentTemperature: payload.current.apparent_temperature,
            humidity: Int(payload.current.relative_humidity_2m.rounded()),
            windSpeed: payload.current.wind_speed_10m,
            code: payload.current.weather_code,
            isDay: payload.current.is_day == 1,
            // High/low come from the daily array; if that model ever fails to
            // parse, fall back to the extremes of the hours ahead rather than
            // pinning both to the current temperature (which once rendered as
            // the nonsensical "H:26° L:26°").
            high: days.first?.high ?? hours.map(\.temperature).max() ?? payload.current.temperature_2m,
            low: days.first?.low ?? hours.map(\.temperature).min() ?? payload.current.temperature_2m,
            aqi: nil,
            hourly: hours,
            daily: days,
            fetchedAt: Date()
        )
    }

    private struct AQIPayload: Decodable {
        struct Current: Decodable { let us_aqi: Double? }
        let current: Current?
    }

    /// Air quality lives on its own endpoint. Failure is non-fatal — the tab
    /// simply omits the AQI tile.
    private func fetchAQI(_ place: WeatherPlace) async throws -> Int? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "us_aqi"),
            .init(name: "timezone", value: "auto"),
        ]
        do {
            let payload: AQIPayload = try await get(components.url!)
            return payload.current?.us_aqi.map { Int($0.rounded()) }
        } catch {
            return nil
        }
    }

    /// Reads the place name in Chinese. Open-Meteo returns the romanized name
    /// the user picked; BigDataCloud reverse geocoding gives the local script,
    /// which is what belongs on screen.
    private func displayName(for place: WeatherPlace) async -> String {
        var components = URLComponents(string: "https://api.bigdatacloud.net/data/reverse-geocode-client")!
        components.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "localityLanguage", value: "zh"),
        ]
        struct Payload: Decodable {
            let city: String?
            let locality: String?
            let principalSubdivision: String?
        }
        do {
            let payload: Payload = try await get(components.url!)
            let candidate = payload.city ?? payload.locality ?? payload.principalSubdivision
            if let candidate, !candidate.isEmpty { return candidate }
        } catch {
            // Fall through to the built-in label.
        }
        return place.name
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("NotchLyrics/2.7.5 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherError.badResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: IP location

    private struct IPWhoIs: Decodable {
        let success: Bool?
        let city: String?
        let latitude: Double?
        let longitude: Double?
    }

    private struct IPInfo: Decodable {
        let city: String?
        let loc: String?
    }

    private func locateByIP() async throws -> WeatherPlace {
        // Primary: ipwho.is — HTTPS, keyless, returns coordinates directly.
        if let place = try? await locateViaIPWhoIs() { return place }
        // Fallback: ipinfo.io — also HTTPS; encodes coordinates as "lat,lon".
        if let place = try? await locateViaIPInfo() { return place }
        throw WeatherError.locationUnavailable
    }

    private func locateViaIPWhoIs() async throws -> WeatherPlace {
        struct Wrapper: Decodable { let success: Bool?; let city: String?; let latitude: Double?; let longitude: Double? }
        let payload: Wrapper = try await get(URL(string: "https://ipwho.is/")!)
        guard payload.success != false,
              let lat = payload.latitude, let lon = payload.longitude
        else { throw WeatherError.locationUnavailable }
        return WeatherPlace(name: payload.city ?? "当前位置", latitude: lat, longitude: lon)
    }

    private func locateViaIPInfo() async throws -> WeatherPlace {
        let payload: IPInfo = try await get(URL(string: "https://ipinfo.io/json")!)
        guard let loc = payload.loc else { throw WeatherError.locationUnavailable }
        let parts = loc.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0]), let lon = Double(parts[1])
        else { throw WeatherError.locationUnavailable }
        return WeatherPlace(name: payload.city ?? "当前位置", latitude: lat, longitude: lon)
    }

    /// The IP answer is cached for a day: it rarely changes, and it gives the
    /// tab something to render instantly on launch.
    private func cachedIPPlace() -> WeatherPlace? {
        guard let data = Defaults[.weatherIPPlaceData],
              let cached = try? JSONDecoder().decode(CachedIPPlace.self, from: data),
              Date().timeIntervalSince(cached.storedAt) < 86_400
        else { return nil }
        return cached.place
    }

    private func storeIPPlace(_ place: WeatherPlace) {
        let cached = CachedIPPlace(place: place, storedAt: Date())
        Defaults[.weatherIPPlaceData] = try? JSONEncoder().encode(cached)
    }

    private struct CachedIPPlace: Codable {
        let place: WeatherPlace
        let storedAt: Date
    }

    // MARK: Helpers

    /// Open-Meteo returns local wall-clock strings without a zone suffix
    /// ("2026-10-08T22:00") because we asked for `timezone=auto`. A strict
    /// ISO8601DateFormatter rejects zone-less stamps — the whole hourly/daily
    /// model silently empties out if parsing fails — so parse with a plain
    /// DateFormatter in the machine's zone, which matches the auto timezone.
    private static let wallClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// The daily array carries bare dates ("2026-10-08"), not timestamps —
    /// parsing them with the wall-clock format silently fails, empties the
    /// whole week model, and the today card falls back to showing the current
    /// temperature as both the high and the low.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        return wallClockFormatter.date(from: value)
    }

    private static func parseDay(_ value: String?) -> Date? {
        guard let value else { return nil }
        return dayFormatter.date(from: value)
    }
}

enum WeatherError: LocalizedError {
    case badResponse
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .badResponse: return "天气服务暂时不可用"
        case .locationUnavailable: return "无法通过网络定位，请在设置里手动选择城市"
        }
    }
}

// MARK: - Snapshot helpers

extension WeatherSnapshot {
    func with(placeName: String, aqi: Int?) -> WeatherSnapshot {
        WeatherSnapshot(
            placeName: placeName,
            temperature: temperature,
            apparentTemperature: apparentTemperature,
            humidity: humidity,
            windSpeed: windSpeed,
            code: code,
            isDay: isDay,
            high: high,
            low: low,
            aqi: aqi,
            hourly: hourly,
            daily: daily,
            fetchedAt: fetchedAt
        )
    }

    /// The next `count` hours starting at the current hour, for the hourly strip.
    func upcomingHours(_ count: Int = 12) -> [HourPoint] {
        Array(hourly.prefix(count))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
