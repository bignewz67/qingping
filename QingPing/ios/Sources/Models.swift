//
//  Models.swift
//  清屏
//

import Foundation

// MARK: - 拦截类型

enum InterceptKind: String, CaseIterable, Identifiable, Codable {
    case splash
    case misclick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .splash:   return "开屏跳过"
        case .misclick: return "误触拦截"
        }
    }

    var shortTitle: String {
        switch self {
        case .splash:   return "开屏"
        case .misclick: return "误触"
        }
    }

    var symbol: String {
        switch self {
        case .splash:   return "forward.end.fill"
        case .misclick: return "hand.raised.fill"
        }
    }

    static func from(_ raw: String) -> InterceptKind {
        InterceptKind(rawValue: raw) ?? .splash
    }
}

// MARK: - 跳过方式

enum SkipMode: Int, CaseIterable, Identifiable {
    case tapButton = 0
    case forceClose = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .tapButton:  return "模拟点「跳过」"
        case .forceClose: return "直接关闭广告"
        }
    }

    var detail: String {
        switch self {
        case .tapButton:  return "优先模拟点击广告自带的「跳过」按钮，最接近真实操作，兼容性最好。"
        case .forceClose: return "找不到跳过按钮时，直接把广告视图从界面上移除。更彻底，但个别 App 可能白屏。"
        }
    }
}

// MARK: - 统计模型

struct AppStats: Identifiable, Hashable {
    let bundleID: String
    var name: String
    var splash: Int
    var misclick: Int
    var lastSeen: Date?

    var id: String { bundleID }
    var total: Int { splash + misclick }
    var initial: String { String(name.prefix(1)) }
}

struct InterceptEvent: Identifiable, Hashable {
    let id: String
    let bundleID: String
    let appName: String
    let kind: InterceptKind
    let detail: String
    let date: Date
}

struct DayPoint: Identifiable, Hashable {
    let id: String
    let date: Date
    let count: Int
}

// MARK: - 快照

struct StatsSnapshot {
    var apps: [AppStats] = []
    var events: [InterceptEvent] = []
    var daily: [DayPoint] = []
    var isDemo: Bool = false
    var updatedAt: Date = Date()

    static let empty = StatsSnapshot()

    var totalCount: Int { apps.reduce(0) { $0 + $1.total } }
    var splashCount: Int { apps.reduce(0) { $0 + $1.splash } }
    var misclickCount: Int { apps.reduce(0) { $0 + $1.misclick } }
    var appCount: Int { apps.count }
    var weeklyCount: Int { daily.reduce(0) { $0 + $1.count } }

    var todayCount: Int {
        let calendar = Calendar.current
        return daily.first(where: { calendar.isDateInToday($0.date) })?.count ?? 0
    }

    var avgPerDay: Int {
        let active = daily.filter { $0.count > 0 }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0) { $0 + $1.count } / active.count
    }

    var sortedApps: [AppStats] {
        apps.sorted { lhs, rhs in
            if lhs.total != rhs.total { return lhs.total > rhs.total }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    var recentEvents: [InterceptEvent] {
        events.sorted { $0.date > $1.date }
    }

    func events(for bundleID: String) -> [InterceptEvent] {
        recentEvents.filter { $0.bundleID == bundleID }
    }

    func app(for bundleID: String) -> AppStats? {
        apps.first { $0.bundleID == bundleID }
    }
}
