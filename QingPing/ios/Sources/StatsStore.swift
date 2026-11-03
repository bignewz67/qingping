//
//  StatsStore.swift
//  清屏
//
//  数据通道（按优先级）：
//   1. 具名剪贴板 com.qingping.stats —— 注入端写入，沙盒拦不住，TrollStore 环境可用
//   2. 共享偏好域 / 各 App 容器文件 —— 仅越狱或拿到平台权限时可用
//
//  因为剪贴板同一时刻只保留「最后写入的那个 App」的数据，清屏本地会做一份缓存，
//  按 Bundle ID 取最大值合并，历史数据不会丢。
//

import Foundation
import UIKit

// MARK: - 环境探测

enum TweaksBridge {
    static let statsPath = "/var/mobile/Library/Preferences/com.qingping.stats.plist"
    static let containersPath = "/var/mobile/Containers/Data/Application"
    static let pasteboardName = UIPasteboard.Name("com.qingping.stats")

    static func containerStatsFiles() -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: containersPath) else {
            return []
        }
        return names.compactMap { name in
            let path = "\(containersPath)/\(name)/Library/Application Support/QingPing/stats.json"
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
    }

    static var canReadContainers: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: containersPath)) != nil
    }

    /// 注入端通过具名剪贴板投递的统计
    static func readPasteboardRoot() -> [String: Any]? {
        guard let board = UIPasteboard(name: pasteboardName, create: false) else { return nil }
        guard let text = board.string, !text.isEmpty else { return nil }
        guard let data = text.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    static func clearPasteboard() {
        guard let board = UIPasteboard(name: pasteboardName, create: false) else { return }
        board.string = ""
    }
}

// MARK: - Store

final class StatsStore: ObservableObject {

    @Published private(set) var snapshot: StatsSnapshot = .empty
    @Published private(set) var lastRefresh: Date = .distantPast
    @Published private(set) var hasLiveData: Bool = false
    /// 最近一次同步来源，给设置页显示
    @Published private(set) var lastSource: String = "无"

    static let statsDomain = "com.qingping.stats"
    private let cacheKey = "qingping.stats.cache"

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var statusText: String {
        if hasLiveData { return "防护运行中" }
        return "等待首次同步"
    }

    // MARK: 读取

    func refresh() {
        lastRefresh = Date()

        var cache = loadCache()
        var source = "本地缓存"
        var incoming: [String: Any]?

        if let fromPasteboard = TweaksBridge.readPasteboardRoot() {
            incoming = fromPasteboard
            source = "剪贴板"
        } else if let fromFile = loadBestRoot() {
            incoming = fromFile
            source = "文件"
        }

        if let incoming {
            merge(incoming, into: &cache)
            saveCache(cache)
            lastSource = source
        }

        let apps = cache["apps"] as? [String: Any] ?? [:]
        guard !apps.isEmpty else {
            snapshot = DemoData.snapshot()
            hasLiveData = false
            lastSource = "无"
            return
        }

        snapshot = makeSnapshot(fromCache: cache)
        hasLiveData = true
    }

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
                for (bundleID, value) in rawApps { apps[bundleID] = value }
            }
            if let rawDaily = dict["daily"] as? [String: Any] {
                for (day, value) in rawDaily {
                    daily[day] = max(intValue(daily[day]), intValue(value))
                }
            }
            if let rawRecent = dict["recent"] as? [[String: Any]] {
                recent.append(contentsOf: rawRecent)
            }
        }

        guard !apps.isEmpty else { return nil }
        return ["apps": apps, "daily": daily, "recent": recent]
    }

    private func loadRoot() -> [String: Any]? {
        if let defaults = UserDefaults(suiteName: Self.statsDomain) {
            defaults.synchronize()
            if let root = defaults.dictionary(forKey: "root"), !root.isEmpty {
                return root
            }
        }

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

    // MARK: 缓存合并

    private func loadCache() -> [String: Any] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private func saveCache(_ cache: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: cache) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    private func merge(_ incoming: [String: Any], into cache: inout [String: Any]) {
        var apps = cache["apps"] as? [String: Any] ?? [:]

        if let incomingApps = incoming["apps"] as? [String: Any] {
            for (bundleID, value) in incomingApps {
                guard let newApp = value as? [String: Any] else { continue }
                var app = apps[bundleID] as? [String: Any] ?? [:]

                if let name = newApp["name"] as? String, !name.isEmpty {
                    app["name"] = name
                }
                app["splash"] = max(intValue(app["splash"]), intValue(newApp["splash"]))
                app["misclick"] = max(intValue(app["misclick"]), intValue(newApp["misclick"]))
                app["last"] = max(doubleValue(app["last"]) ?? 0, doubleValue(newApp["last"]) ?? 0)
                app["loadedAt"] = max(doubleValue(app["loadedAt"]) ?? 0,
                                      doubleValue(newApp["loadedAt"]) ?? 0)

                var daily = app["daily"] as? [String: Any] ?? [:]
                if let newDaily = newApp["daily"] as? [String: Any] {
                    for (day, val) in newDaily {
                        daily[day] = max(intValue(daily[day]), intValue(val))
                    }
                }
                app["daily"] = daily

                apps[bundleID] = app
            }
        }
        cache["apps"] = apps

        var recent = cache["recent"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        for item in recent { seen.insert(eventKey(item)) }
        if let newRecent = incoming["recent"] as? [[String: Any]] {
            for item in newRecent {
                let key = eventKey(item)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                recent.append(item)
            }
        }
        recent.sort { (doubleValue($0["ts"]) ?? 0) > (doubleValue($1["ts"]) ?? 0) }
        if recent.count > 120 { recent = Array(recent.prefix(120)) }
        cache["recent"] = recent
        cache["updatedAt"] = Date().timeIntervalSince1970
    }

    private func eventKey(_ item: [String: Any]) -> String {
        let bid = (item["bid"] as? String) ?? ""
        let ts = doubleValue(item["ts"]) ?? 0
        let kind = (item["kind"] as? String) ?? ""
        return "\(bid)|\(Int(ts))|\(kind)"
    }

    // MARK: 生成快照

    private func makeSnapshot(fromCache cache: [String: Any]) -> StatsSnapshot {
        let rawApps = cache["apps"] as? [String: Any] ?? [:]
        var apps: [AppStats] = []
        var dailySum: [String: Int] = [:]

        for (bundleID, value) in rawApps {
            guard let info = value as? [String: Any] else { continue }
            let splash = intValue(info["splash"])
            let misclick = intValue(info["misclick"])
            let loaded = doubleValue(info["loadedAt"]).map { Date(timeIntervalSince1970: $0) }
            guard splash + misclick > 0 || loaded != nil else { continue }

            let last = doubleValue(info["last"]).map { Date(timeIntervalSince1970: $0) }
            apps.append(AppStats(bundleID: bundleID,
                                 name: (info["name"] as? String) ?? bundleID,
                                 splash: splash,
                                 misclick: misclick,
                                 lastSeen: last,
                                 loadedAt: loaded))

            if let daily = info["daily"] as? [String: Any] {
                for (day, val) in daily {
                    dailySum[day] = (dailySum[day] ?? 0) + intValue(val)
                }
            }
        }

        var daily: [DayPoint] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = dayFormatter.string(from: date)
            daily.append(DayPoint(id: key, date: date, count: dailySum[key] ?? 0))
        }

        var events: [InterceptEvent] = []
        if let rawRecent = cache["recent"] as? [[String: Any]] {
            for (index, item) in rawRecent.enumerated() {
                let bundleID = (item["bid"] as? String) ?? ""
                guard !bundleID.isEmpty else { continue }
                let timestamp = doubleValue(item["ts"]) ?? 0
                events.append(InterceptEvent(id: "\(bundleID)-\(timestamp)-\(index)",
                                             bundleID: bundleID,
                                             appName: (item["name"] as? String) ?? bundleID,
                                             kind: InterceptKind.from((item["kind"] as? String) ?? "splash"),
                                             detail: (item["detail"] as? String) ?? "",
                                             date: Date(timeIntervalSince1970: timestamp)))
            }
        }

        let updated = doubleValue(cache["updatedAt"]).map { Date(timeIntervalSince1970: $0) } ?? Date()

        return StatsSnapshot(apps: apps,
                             events: events,
                             daily: daily,
                             isDemo: false,
                             updatedAt: updated)
    }

    // MARK: 操作

    func clearAll() {
        UserDefaults.standard.removeObject(forKey: cacheKey)

        if let defaults = UserDefaults(suiteName: Self.statsDomain) {
            defaults.set([String: Any](), forKey: "root")
            defaults.synchronize()
        }
        for path in TweaksBridge.containerStatsFiles() {
            try? FileManager.default.removeItem(atPath: path)
        }
        TweaksBridge.clearPasteboard()

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
