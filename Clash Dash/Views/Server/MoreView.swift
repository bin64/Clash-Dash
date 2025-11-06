import SwiftUI

struct MoreView: View {
    let server: ClashServer
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = ServerDetailViewModel()
    @State private var showingConfigSubscription = false
    @State private var showingSwitchConfig = false
    @State private var showingCustomRules = false
    @State private var showingRestartService = false
    @State private var showingServiceLog = false
    @State private var showingWebView = false
    @State private var pluginName: String = "未知插件"
    @State private var pluginVersion: String = "未知版本"
    @State private var runningTime: String = "未知运行时长"
    @State private var kernelRunningTime: String = "未知运行时长"
    @State private var pluginRunningTime: String = "未知运行时长"

    // Surge 功能开关状态
    @State private var mitmEnabled: Bool = false
    @State private var rewriteEnabled: Bool = false
    @State private var captureEnabled: Bool = false
    
    private let logger = LogManager.shared
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知版本"
    private let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? 
            Color(.systemGray6) : 
            Color(.systemBackground)
    }
    
    private var versionDisplay: String {
        if server.source == .surge {
            guard let version = server.surgeVersion else { return "未知版本" }
            if let build = server.surgeBuild {
                return "\(version) (\(build))"
            }
            return version
        }
        guard let version = server.version else { return "未知版本" }
        return version
    }
    
    private var kernelType: String {
        if server.source == .surge {
            return "Surge"
        }
        guard let type = server.serverType else { return "未知内核" }
        switch type {
        case .meta: return "Mihomo (meta)"
        case .premium: return "Clash Premium"
        case .singbox: return "Sing-Box"
        case .unknown: return "未知内核"
        }
    }
    
    private func fetchPluginVersion() {
        Task {
            do {
                logger.info("开始获取插件版本信息")
                let pluginInfo = try await viewModel.getPluginVersion(server: server)
                let components = pluginInfo.split(separator: " ", maxSplits: 1)
                pluginName = String(components[0])
                pluginVersion = components.count > 1 ? String(components[1]) : "未知版本"
                logger.info("成功获取插件版本: \(pluginInfo)")

                if server.source == .openWRT {
                    logger.info("开始获取运行时长")
                    let (kernel, plugin) = try await viewModel.getRunningTime(server: server)
                    kernelRunningTime = kernel
                    pluginRunningTime = plugin
                    logger.info("成功获取运行时长: 内核(\(kernel)), 插件(\(plugin))")
                }
            } catch {
                logger.error("获取插件版本失败: \(error.localizedDescription)")
                pluginName = "未知插件"
                pluginVersion = "未知版本"
                kernelRunningTime = "未知运行时长"
                pluginRunningTime = "未知运行时长"
            }
        }
    }

    // 获取 Surge 功能状态
    private func fetchSurgeFeatures() {
        Task {
            do {
                logger.info("开始获取 Surge 功能状态")
                async let mitmStatus = getSurgeFeatureStatus(feature: "mitm")
                async let rewriteStatus = getSurgeFeatureStatus(feature: "rewrite")
                async let captureStatus = getSurgeFeatureStatus(feature: "capture")

                let (mitm, rewrite, capture) = try await (mitmStatus, rewriteStatus, captureStatus)

                mitmEnabled = mitm
                rewriteEnabled = rewrite
                captureEnabled = capture

                logger.info("成功获取 Surge 功能状态: MitM(\(mitm)), 复写(\(rewrite)), 抓包(\(capture))")
            } catch {
                logger.error("获取 Surge 功能状态失败: \(error.localizedDescription)")
            }
        }
    }

    // 获取单个 Surge 功能状态
    private func getSurgeFeatureStatus(feature: String) async throws -> Bool {
        let scheme = server.surgeUseSSL ? "https" : "http"
        let url = URL(string: "\(scheme)://\(server.url):\(server.port)/v1/features/\(feature)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(server.surgeKey, forHTTPHeaderField: "x-key")

        let (data, _) = try await URLSession.secure.data(for: request)
        let response = try JSONDecoder().decode([String: Bool].self, from: data)
        return response["enabled"] ?? false
    }

    // 切换 Surge 功能状态
    private func toggleSurgeFeature(feature: String, enabled: Bool) {
        Task {
            do {
                logger.info("切换 Surge 功能 \(feature) 状态为: \(enabled)")
                let scheme = server.surgeUseSSL ? "https" : "http"
                let url = URL(string: "\(scheme)://\(server.url):\(server.port)/v1/features/\(feature)")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(server.surgeKey, forHTTPHeaderField: "x-key")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body = ["enabled": enabled]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (_, response) = try await URLSession.secure.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    logger.info("成功切换 Surge 功能 \(feature) 状态")
                    // 重新获取状态以确认
                    fetchSurgeFeatures()
                } else {
                    logger.error("切换 Surge 功能 \(feature) 状态失败")
                }
            } catch {
                logger.error("切换 Surge 功能 \(feature) 状态失败: \(error.localizedDescription)")
            }
        }
    }
    
    var body: some View {
        List {
            // Surge 控制器不显示配置菜单
            if server.source != .surge {
                NavigationLink {
                    SettingsView(server: server)
                } label: {
                    HStack {
                        Image(systemName: "gearshape")
                            .foregroundColor(.blue)
                            .frame(width: 25)
                        Text("配置")
                    }
                }
            }
            
            NavigationLink {
                LogView(server: server)
            } label: {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.blue)
                        .frame(width: 25)
                    Text("日志")
                }
            }
            
            // Surge 控制器不显示解析菜单
            if server.source != .surge {
                // 添加域名查询工具
                NavigationLink {
                    DNSQueryView(server: server)
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.blue)
                            .frame(width: 25)
                        Text("解析")
                    }
                }
            }

            // Surge 功能开关
            if server.source == .surge {
                Section("Surge 功能控制") {
                    Toggle(isOn: $mitmEnabled) {
                        HStack {
                            Image(systemName: "person.badge.shield.checkmark")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("MitM")
                        }
                    }
                    .onChange(of: mitmEnabled) { newValue in
                        HapticManager.shared.impact(.light)
                        toggleSurgeFeature(feature: "mitm", enabled: newValue)
                    }

                    Toggle(isOn: $rewriteEnabled) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("复写")
                        }
                    }
                    .onChange(of: rewriteEnabled) { newValue in
                        HapticManager.shared.impact(.light)
                        toggleSurgeFeature(feature: "rewrite", enabled: newValue)
                    }

                    Toggle(isOn: $captureEnabled) {
                        HStack {
                            Image(systemName: "record.circle")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("抓包")
                        }
                    }
                    .onChange(of: captureEnabled) { newValue in
                        HapticManager.shared.impact(.light)
                        toggleSurgeFeature(feature: "capture", enabled: newValue)
                    }
                }
            }

            // OpenClash 功能组
            if server.luciPackage == .openClash && server.source == .openWRT {
                Section("OpenClash 插件控制") {
                    Button {
                        HapticManager.shared.impact(.light)
                        showingServiceLog = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.below.ecg")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("运行日志")
                        }
                    }
                    
                    Button {
                        HapticManager.shared.impact(.light)
                        showingConfigSubscription = true
                    } label: {
                        HStack {
                            Image(systemName: "cloud")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("订阅管理")
                        }
                    }
                    
                    Button {
                        HapticManager.shared.impact(.light)
                        showingSwitchConfig = true
                    } label: {
                        HStack {
                            Image(systemName: "filemenu.and.selection")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("配置管理")
                        }
                    }
                    
                    Button {
                        HapticManager.shared.impact(.light)
                        showingCustomRules = true
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("附加规则")
                        }
                    }
                    
                    Button {
                        HapticManager.shared.impact(.light)
                        showingRestartService = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("重启服务")
                        }
                    }

                    Button {
                        HapticManager.shared.impact(.light)
                        showingWebView = true
                    } label: {
                        HStack {
                            Image(systemName: "safari")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("网页访问")
                        }
                    }
                }
            }

            // MihomoTProxy 功能组
            if server.luciPackage == .mihomoTProxy && server.source == .openWRT {
                Section("Nikki 插件控制") {
                    Button {
                        HapticManager.shared.impact(.light)
                        showingServiceLog = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.below.ecg")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("运行日志")
                        }
                    }
                    
                    Button {
                        HapticManager.shared.impact(.light)
                        showingConfigSubscription = true
                    } label: {
                        HStack {
                            Image(systemName: "cloud")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("订阅管理")
                        }
                    }
                    
                    Button {
                        HapticManager.shared.impact(.light)
                        showingSwitchConfig = true
                    } label: {
                        HStack {
                            Image(systemName: "filemenu.and.selection")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("配置管理")
                        }
                    }

                    Button {
                        HapticManager.shared.impact(.light)
                        showingCustomRules = true
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("附加规则")
                        }
                    }
                    
                    Button {
                        HapticManager.shared.impact(.light)
                        showingRestartService = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("重启服务")
                        }
                    }

                    Button {
                        HapticManager.shared.impact(.light)
                        showingWebView = true
                    } label: {
                        HStack {
                            Image(systemName: "safari")
                                .foregroundColor(.blue)
                                .frame(width: 25)
                            Text("网页访问")
                        }
                    }
                }
            }

            // 版本信息 Section
            if server.status == .ok {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        // App 信息
                        HStack(spacing: 12) {
                            Image(systemName: "app.badge")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("App 信息")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Clash Dash")
                                    .font(.subheadline)
                                Text("版本: \(appVersion) (\(buildVersion))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        // 内核信息
                        HStack(spacing: 12) {
                            Image(systemName: "cpu")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("内核信息")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(kernelType)")
                                    .font(.subheadline)
                                Text("版本: \(versionDisplay)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if server.source == .openWRT {
                                    Text("运行时长: \(kernelRunningTime)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        
                        // 插件信息
                        if server.source == .openWRT {
                            HStack(spacing: 12) {
                                Image(systemName: "shippingbox")
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("插件信息")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(pluginName)
                                        .font(.subheadline)
                                    Text("版本: \(pluginVersion)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    if server.source == .openWRT {
                                        Text("运行时长: \(pluginRunningTime)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("运行信息")
                        .textCase(.none)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingConfigSubscription) {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                NavigationStack {
                    ConfigSubscriptionView(server: server)
                }
            }
        }
        .sheet(isPresented: $showingSwitchConfig) {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                NavigationStack {
                    OpenClashConfigView(viewModel: viewModel.serverViewModel, server: server)
                }
            }
        }
        .sheet(isPresented: $showingCustomRules) {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                NavigationStack {
                    OpenClashRulesView(server: server)
                }
            }
        }
        .sheet(isPresented: $showingRestartService) {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                NavigationStack {
                    RestartServiceView(viewModel: viewModel.serverViewModel, server: server)
                }
            }
        }
        .sheet(isPresented: $showingServiceLog) {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                NavigationStack {
                    ServiceLogView(server: server)
                }
            }
        }
        .fullScreenCover(isPresented: $showingWebView) {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                NavigationStack {
                    LuCIWebView(server: server)
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            fetchPluginVersion()
            if server.source == .surge {
                fetchSurgeFeatures()
            }
        }
    }
}

#Preview {
    NavigationStack {
        MoreView(server: ClashServer(name: "测试服务器", url: "10.1.1.2", port: "9090", secret: "123456"))
    }
} 