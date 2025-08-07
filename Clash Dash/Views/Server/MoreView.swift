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
    
    private let logger = LogManager.shared
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知版本"
    private let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? 
            Color(.systemGray6) : 
            Color(.systemBackground)
    }
    
    private var versionDisplay: String {
        guard let version = server.version else { return "未知版本" }
        return version
    }
    
    private var kernelType: String {
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
    
    var body: some View {
        List {
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
        }
    }
}

#Preview {
    NavigationStack {
        MoreView(server: ClashServer(name: "测试服务器", url: "10.1.1.2", port: "9090", secret: "123456"))
    }
} 