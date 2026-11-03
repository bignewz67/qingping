//
//  SettingsView.swift
//  清屏
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var store: StatsStore
    @EnvironmentObject private var prefs: PrefsStore

    @State private var showClearAlert = false

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                protectionSection
                dataSection
                aboutSection
            }
            .navigationTitle("设置")
        }
    }

    // MARK: 状态

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((store.hasLiveData ? Color.qpTeal : Color.qpAmber).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: store.hasLiveData ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundColor(store.hasLiveData ? .qpTeal : .qpAmber)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.statusText)
                        .font(.subheadline.weight(.semibold))
                    Text(store.hasLiveData
                         ? "注入端已生效，目标 App 启动时自动加载"
                         : "仅注入环境可启用真实拦截，当前展示演示数据")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: 拦截设置

    private var protectionSection: some View {
        Section {
            Toggle(isOn: $prefs.enabled) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("启用清屏防护")
                        Text("关闭后所有 App 都不再处理")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                }
            }

            Picker(selection: $prefs.skipMode) {
                ForEach(SkipMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Label("跳过方式", systemImage: "forward.end")
            }

            Text(prefs.skipMode.detail)
                .font(.caption2)
                .foregroundColor(.secondary)

            Toggle(isOn: $prefs.touchGuard) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("防误触")
                        Text("开屏期间吞掉广告区域的点击，避免跳转 App Store")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "hand.raised")
                }
            }

            NavigationLink {
                IgnoreListView()
            } label: {
                Label("忽略名单", systemImage: "nosign")
            }
        } header: {
            Text("拦截设置")
        } footer: {
            Text("设置写入 com.qingping.prefs，注入端 5 秒内读取。关闭立即生效；从关闭改为开启需要重新打开目标 App。")
        }
    }

    // MARK: 数据

    private var dataSection: some View {
        Section("数据") {
            Button {
                store.refresh()
            } label: {
                Label("刷新统计", systemImage: "arrow.clockwise")
            }

            ShareLink(item: store.exportCSV()) {
                Label("导出 CSV", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                showClearAlert = true
            } label: {
                Label("清空统计", systemImage: "trash")
            }
        }
        .alert("清空所有统计？", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { store.clearAll() }
        } message: {
            Text("只删除本机的拦截计数与事件记录，不影响防护开关。")
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        Section("关于") {
            NavigationLink {
                LimitsView()
            } label: {
                Label("iOS 限制与权限说明", systemImage: "info.circle")
            }

            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("适用系统")
                Spacer()
                Text("iOS 16.0 – 16.7")
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 忽略名单

struct IgnoreListView: View {

    @EnvironmentObject private var store: StatsStore
    @EnvironmentObject private var prefs: PrefsStore

    var body: some View {
        List {
            Section {
                if store.snapshot.sortedApps.isEmpty {
                    Text("还没有出现过拦截记录的应用")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(store.snapshot.sortedApps) { app in
                        Toggle(isOn: Binding(
                            get: { prefs.isIgnored(app.bundleID) },
                            set: { prefs.setIgnored(app.bundleID, $0) }
                        )) {
                            HStack(spacing: 10) {
                                AppMonogram(name: app.name, bundleID: app.bundleID, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name)
                                        .font(.subheadline)
                                    Text(app.bundleID)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("打开开关表示不处理该应用：既不跳过开屏，也不统计。")
            }
        }
        .navigationTitle("忽略名单")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 限制说明

struct LimitsView: View {

    private struct Limit: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: String
        let state: String
        let detail: String
    }

    private let limits: [Limit] = [
        Limit(icon: "checkmark.seal.fill", color: .qpTeal,
              title: "自动跳过开屏广告", state: "可实现（越狱 / TrollStore）",
              detail: "注入到目标 App 进程内，识别开屏广告控制器并模拟点击「跳过」，或直接移除广告视图。越狱直接用 deb；不越狱则用 TrollStore + TrollFools 把 QingPing.dylib 注入目标 App。"),
        Limit(icon: "checkmark.seal.fill", color: .qpTeal,
              title: "拦截误触跳转", state: "可实现（越狱 / TrollStore）",
              detail: "Hook UIApplication 的 openURL 与 App Store 落地页，在开屏广告展示期间拦截 itms-apps、第三方 scheme 等跳转，并吞掉广告区域的点击。"),
        Limit(icon: "checkmark.seal.fill", color: .qpTeal,
              title: "按 App 统计", state: "可实现（越狱 / TrollStore）",
              detail: "以宿主 App 的 Bundle ID 为键计数，同时写入共享偏好域和各 App 容器副本，清屏带平台权限读取汇总。非注入环境下无法得知其它 App 内部发生了什么。"),
        Limit(icon: "xmark.seal.fill", color: .qpAmber,
              title: "App Store 版本实现同样功能", state: "系统禁止",
              detail: "iOS 没有 Android 的「无障碍服务」，第三方 App 不能读取其它 App 的界面、不能模拟点击、不能常驻后台。审核指南 2.5.1 也禁止使用非公开 API 干预其它 App。"),
        Limit(icon: "xmark.seal.fill", color: .qpAmber,
              title: "开机自启 / 常驻后台", state: "系统不允许",
              detail: "普通 App 没有开机启动项，进入后台后会被挂起并最终被系统回收。清屏采用的是「进程内注入」，目标 App 一启动就生效，所以不需要常驻，也不怕清后台——越狱和 TrollStore 两条路线都是这个原理。"),
        Limit(icon: "exclamationmark.triangle.fill", color: .qpBlue,
              title: "DNS / 本地 VPN 拦截（非越狱折中）", state: "有限可用",
              detail: "用 NEPacketTunnelProvider 做域名级广告拦截，可以减少部分广告素材加载，但拦不住已缓存的开屏、无法按 App 归因、需要手动开启 VPN、不能开机自启，还可能让宿主 App 白屏。"),
        Limit(icon: "exclamationmark.triangle.fill", color: .qpBlue,
              title: "监管设备 + 内容过滤", state: "需企业资质",
              detail: "NEFilterDataProvider 能拿到 App 归因，但需要 Apple 特批的 Content Filter 权限，且通常只对受监管（supervised）设备开放，不适合消费级产品。"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(limits) { limit in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: limit.icon)
                            .foregroundColor(limit.color)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(limit.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 6)
                                Text(limit.state)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(limit.color)
                            }
                            Text(limit.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("能力清单")
            } footer: {
                Text("结论：开屏广告拦截、误触拦截、按 App 统计这三项，在 iOS 上只有「代码注入」一条路——越狱全局注入，或用 TrollStore + TrollFools 逐个 App 注入。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("限制说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}
