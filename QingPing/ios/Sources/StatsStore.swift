//
//  StatsStore.swift
//  清屏
//
//  数据来源：注入端写入的 com.qingping.stats 偏好域（cfprefsd 中介）。
//  非越狱环境读不到任何数据，会自动切换到演示数据，保证界面可预览。
//

import Foundation
import Combine

// MARK: - 环境探测

enum TweaksBridge {
    static let statsPath = "/var/mobile/Library/Preferences/com.qingping.stats.plist"
    static let containersPath = "/var/mobile/Containers/Data/Application"

    /// 各注入过的 App 在自己沙盒里留下的统计副本（TrollStore 路线主要靠它）
    static func containerStatsFiles() -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: containersPath) else {
            return []
        }
        return names.compactMap { name in
            let path = "\(containersPath)/\(name)/Library/Application Support/QingPing/stats.json"
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
    }

    /// 是否检测到注入端。仅做提示用，判断失败不影响读数据。
    static var tweakInstalled: Bool {
        if FileManager.default.fileExists(atPath: statsPath) { return true }
        return !containerStatsFiles().isEmpty
    }

    /// 能不能列目录（不能 = 缺平台权限，沙盒挡住了）
    static var canReadContainers: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: containersPath)) != nil
    }

    /// 共享偏好域里有没有数据（注入端走 cfprefsd 写的那份）
    static var prefsDomainHasData: Bool {
        guard let defaults = UserDefaults(suiteName: "com.qingping.stats") else { return false }
        defaults.synchronize()
        let root = defaults.dictionary(forKey: "root")
        return !(root?.isEmpty ?? true)
    }
}

// MARK: - Store

final class StatsStore: ObservableObject {

    @Published private(set) var snapshot: StatsSnapshot = .empty
    @Published private(set) var lastRefresh: Date = .distantPast
    @Published private(set) var hasLiveData: Bool = false

    static let statsDomain = "com.qingping.stats"

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var statusText: String {
        if hasLiveData { return "防护运行中" }
        if TweaksBridge.tweakInstalled { return "等待拦截数据" }
        return "未检测到注入"
    }

    var statusColorName: String {
        hasLiveData ? "green" : "orange"
    }

    // MARK: 读取

    /// 优先读各 App 容器里的副本（TrollStore / 平台权限路线最稳），
    /// 没有再退回共享偏好域（越狱路线）。
    private func loadBestRoot() -> [String: Any]? {
        if let merged = loadContainers() { return merged }
        return loadRoot()
    }

    private func loadContainers() -> [String: Any]? {
        let files = TweaksBridge.containerStatsFiles()
        guard !files.isEmpty else { return nil }

        var apps: [String: Any] = [:]
        var daily: [String: Any] = [:]
        var recent: [[String: Any]] = []

        for path in files {
            guard let data = FileManager.default.contents(atPath: path),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dict = object as? [String: Any] else { continue }

            if let rawApps = dict["apps"] as? [String: Any] {
                for (bundleID, value) in rawApps {
                    apps[bundleID] = value
                }
            }
            if let rawDaily = dict["daily"] as? [String: Any] {
                for (day, value) in rawDaily {
                    let current = daily[day] as? Int ?? 0
                    daily[day] = current + intValue(value)
                }
            }
            if let rawRecent = dict["recent"] as? [[String: Any]] {
                recent.append(contentsOf: rawRecent)
            }
        }

        guard !apps.isEmpty else { return nil }
        return [
            "apps": apps,
            "daily": daily,
            "recent": recent,
            "updatedAt": Date().timeIntervalSince1970,
        ]
    }

    func refresh() {
        lastRefresh = Date()

        guard let root = loadBestRoot(), !root.isEmpty else {
            snapshot = DemoData.snapshot()
            hasLiveData = false
            return
        }

        var apps: [AppStats] = []
        if let rawApps = root["apps"] as? [String: Any] {
            for (bundleID, value) in rawApps {
                guard let info = value as? [String: Any] else { continue }
                let name = (info["name"] as? String) ?? bundleID
                let splash = intValue(info["splash"])
                let misclick = intValue(info["misclick"])
                let loaded = doubleValue(info["loadedAt"]).map { Date(timeIntervalSince1970: $0) }
                guard splash + misclick > 0 || loaded != nil else { continue }
                let last = doubleValue(info["last"]).map { Date(timeIntervalSince1970: $0) }
                apps.append(AppStats(bundleID: bundleID,
                                     name: name,
                                     splash: splash,
                                     misclick: misclick,
                                     lastSeen: last,
                                     loadedAt: loaded))
            }
        }

        var dailyRaw: [String: Int] = [:]
        if let rawDaily = root["daily"] as? [String: Any] {
            for (key, value) in rawDaily {
                dailyRaw[key] = intValue(value)
            }
        }

        var daily: [DayPoint] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = dayFormatter.string(from: date)
            daily.append(DayPoint(id: key, date: date, count: dailyRaw[key] ?? 0))
        }

        var events: [InterceptEvent] = []
        if let rawRecent = root["recent"] as? [[String: Any]] {
            for (index, item) in rawRecent.enumerated() {
                let bundleID = (item["bid"] as? String) ?? ""
                guard !bundleID.isEmpty else { continue }
                let name = (item["name"] as? String) ?? bundleID
                let kind = InterceptKind.from((item["kind"] as? String) ?? "splash")
                let detail = (item["detail"] as? String) ?? ""
                let timestamp = doubleValue(item["ts"]) ?? 0
                events.append(InterceptEvent(id: "\(bundleID)-\(timestamp)-\(index)",
                                             bundleID: bundleID,
                                             appName: name,
                                             kind: kind,
                                             detail: detail,
                                             date: Date(timeIntervalSince1970: timestamp)))
            }
        }

        let updated = doubleValue(root["updatedAt"]).map { Date(timeIntervalSince1970: $0) } ?? Date()

        snapshot = StatsSnapshot(apps: apps,
                                 events: events,
                                 daily: daily,
                                 isDemo: false,
                                 updatedAt: updated)
        hasLiveData = !apps.isEmpty || !events.isEmpty
    }

    private func loadRoot() -> [String: Any]? {
        if let defaults = UserDefaults(suiteName: Self.statsDomain) {
            defaults.synchronize()
            if let root = defaults.dictionary(forKey: "root"), !root.isEmpty {
                return root
            }
        }

        // 兜底：直接读偏好文件（越狱环境下该目录可读）
        if let data = FileManager.default.contents(atPath: TweaksBridge.statsPath),
           let object = try? PropertyListSerialization.propertyList(from: data,
                                                                    options: [],
                                                                    format: nil),
           let plist = object as? [String: Any],
           let root = plist["root"] as? [String: Any] {
            return root
        }
        return nil
    }

    // MARK: 操作

    func clearAll() {
        guard let defaults = UserDefaults(suiteName: Self.statsDomain) else { return }
        let empty: [String: Any] = [
            "version": 1,
            "apps": [String: Any](),
            "daily": [String: Any](),
            "recent": [Any](),
            "totals": ["splash": 0, "misclick": 0],
            "updatedAt": Date().timeIntervalSince1970,
        ]
        defaults.set(empty, forKey: "root")
        defaults.synchronize()

        // 各 App 容器里的副本也一并清掉（没有平台权限时删不掉，忽略即可）
        for path in TweaksBridge.containerStatsFiles() {
            try? FileManager.default.removeItem(atPath: path)
        }

        refresh()
    }

    func exportCSV() -> String {
        var lines = ["应用名称,BundleID,开屏跳过,误触拦截,合计,最近拦截时间"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for app in snapshot.sortedApps {
            let last = app.lastSeen.map { formatter.string(from: $0) } ?? ""
            let name = app.name.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\"\(name)\",\(app.bundleID),\(app.splash),\(app.misclick),\(app.total),\(last)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: 工具

    private func intValue(_ any: Any?) -> Int {
        if let value = any as? Int { return value }
        if let value = any as? NSNumber { return value.intValue }
        if let value = any as? String { return Int(value) ?? 0 }
        return 0
    }

    private func doubleValue(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? NSNumber { return value.doubleValue }
        if let value = any as? String { return Double(value) }
        return nil
    }
}

// MARK: - 演示数据

enum DemoData {

    static func snapshot() -> StatsSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let seeds: [(String, String, Int, Int, Int)] = [
            // name, bundleID, splash, misclick, 最近发生于多少分钟前
            ("微信",    "com.tencent.xin",              14, 4, 6),
            ("抖音",    "com.ss.iphone.ugc.Aweme",      11, 7, 21),
            ("淘宝",    "com.taobao.taobao",             9, 9, 48),
            ("小红书",  "com.xingin.xhs",                8, 5, 120),
            ("微博",    "com.sina.weibo",                7, 3, 240),
            ("哔哩哔哩", "tv.danmaku.bili",              5, 2, 400),
            ("知乎",    "com.zhihu.ios",                 4, 2, 700),
            ("高德地图", "com.autonavi.amap",            2, 1, 1500),
        ]

        var apps: [AppStats] = []
        var events: [InterceptEvent] = []

        for (name, bundleID, splash, misclick, minutesAgo) in seeds {
            let last = Date().addingTimeInterval(-Double(minutesAgo) * 60)
            apps.append(AppStats(bundleID: bundleID,
                                 name: name,
                                 splash: splash,
                                 misclick: misclick,
                                 lastSeen: last))

            if splash > 0 {
                events.append(InterceptEvent(id: "\(bundleID)-s",
                                             bundleID: bundleID,
                                             appName: name,
                                             kind: .splash,
                                             detail: "SplashAdView",
                                             date: last))
            }
            if misclick > 0 {
                events.append(InterceptEvent(id: "\(bundleID)-m",
                                             bundleID: bundleID,
                                             appName: name,
                                             kind: .misclick,
                                             detail: "itms-apps://apps.apple.com",
                                             date: last.addingTimeInterval(-90)))
            }
        }

        // 与上面 8 个 App 的累计数（93）保持一致
        let dayCounts = [8, 12, 9, 15, 11, 17, 21]
        var daily: [DayPoint] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        for (index, offset) in stride(from: 6, through: 0, by: -1).enumerated() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let count = index < dayCounts.count ? dayCounts[index] : 0
            daily.append(DayPoint(id: formatter.string(from: date), date: date, count: count))
        }

        return StatsSnapshot(apps: apps,
                             events: events,
                             daily: daily,
                             isDemo: true,
                             updatedAt: Date())
    }
}
