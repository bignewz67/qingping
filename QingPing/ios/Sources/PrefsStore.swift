//
//  PrefsStore.swift
//  清屏
//
//  与注入端共享的配置（com.qingping.prefs），写入 root 键，
//  注入端用 CFPreferences 读取同一份数据。
//

import Foundation
import Combine

final class PrefsStore: ObservableObject {

    static let domain = "com.qingping.prefs"

    @Published var enabled: Bool { didSet { persist() } }
    @Published var skipMode: SkipMode { didSet { persist() } }
    @Published var touchGuard: Bool { didSet { persist() } }
    @Published var ignoreList: [String] { didSet { persist() } }
    @Published var cleanWidgets: Bool { didSet { persist() } }
    @Published var cleanFeed: Bool { didSet { persist() } }

    init() {
        let defaults = UserDefaults(suiteName: Self.domain)
        defaults?.synchronize()
        let root = defaults?.dictionary(forKey: "root") ?? [:]

        enabled = root["enabled"] as? Bool ?? true
        let rawMode = root["skipMode"] as? Int ?? 0
        skipMode = SkipMode(rawValue: rawMode) ?? .tapButton
        touchGuard = root["touchGuard"] as? Bool ?? true
        ignoreList = root["ignoreList"] as? [String] ?? []
        cleanWidgets = root["cleanWidgets"] as? Bool ?? false
        cleanFeed = root["cleanFeed"] as? Bool ?? false
    }

    func isIgnored(_ bundleID: String) -> Bool {
        ignoreList.contains(bundleID)
    }

    func setIgnored(_ bundleID: String, _ ignored: Bool) {
        if ignored {
            guard !ignoreList.contains(bundleID) else { return }
            ignoreList.append(bundleID)
        } else {
            ignoreList.removeAll { $0 == bundleID }
        }
    }

    private func persist() {
        guard let defaults = UserDefaults(suiteName: Self.domain) else { return }
        let root: [String: Any] = [
            "enabled": enabled,
            "skipMode": skipMode.rawValue,
            "touchGuard": touchGuard,
            "ignoreList": ignoreList,
            "cleanWidgets": cleanWidgets,
            "cleanFeed": cleanFeed,
        ]
        defaults.set(root, forKey: "root")
        defaults.synchronize()
    }
}
