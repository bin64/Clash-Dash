import SwiftUI
import Shared

enum ConnectionRowStyle: String, CaseIterable, Identifiable {
    case classic
    case modern
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .classic: return "详细"
        case .modern: return "简约"
        }
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("appThemeMode") private var appThemeMode = AppThemeMode.system
    @AppStorage("proxyViewStyle") private var proxyViewStyle = ProxyViewStyle.detailed
    @AppStorage("hideDisconnectedServers") private var hideDisconnectedServers = false
    @AppStorage("enableWiFiBinding") private var enableWiFiBinding = false
    @AppStorage("enableHapticFeedback") private var enableHapticFeedback = true
    @AppStorage("connectionRowStyle") private var connectionRowStyle = ConnectionRowStyle.classic
    @AppStorage("lowDelayThreshold") private var lowDelayThreshold = 240
    @AppStorage("mediumDelayThreshold") private var mediumDelayThreshold = 500
    @AppStorage("widgetDefaultServer") private var widgetDefaultServer: String = ""
    @AppStorage("showDelayRingChart") private var showDelayRingChart = false
    @AppStorage("useFloatingTabs") private var useFloatingTabs = false
    @State private var lowDelaySliderValue: Double = 0
    @State private var mediumDelaySliderValue: Double = 0
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject private var bindingManager: WiFiBindingManager
    @State private var showServerSelectionSheet = false
    
    var body: some View {
        Form {
            Section {
                Picker("主题模式", selection: $appThemeMode) {
                    ForEach(AppThemeMode.allCases) { mode in
                        Text(mode.description)
                            .tag(mode)
                    }
                }
                
                Picker("代理视图样式", selection: $proxyViewStyle) {
                    ForEach(ProxyViewStyle.allCases) { style in
                        Text(style.description)
                            .tag(style)
                    }
                }
                
                if proxyViewStyle == .zash {
                    Toggle("显示延迟环形图", isOn: $showDelayRingChart)
                }
                
                Toggle("使用浮动标签页", isOn: $useFloatingTabs)

                NavigationLink {
                    OverviewCardSettingsView()
                } label: {
                    SettingRow(
                        title: "概览页面设置",
                        value: ""
                    )
                }
                
                NavigationLink {
                    ConnectionsSettingsView()
                } label: {
                    SettingRow(
                        title: "连接页面设置",
                        value: ""
                    )
                }
            } header: {
                SectionHeader(title: "外观设置", systemImage: "paintbrush")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("延迟阈值范围")
                        Spacer()
                        Text("\(lowDelayThreshold)-\(mediumDelayThreshold) ms")
                            .monospacedDigit()
                    }
                    
                    DualSlider(
                        lowValue: $lowDelaySliderValue,
                        highValue: $mediumDelaySliderValue,
                        range: 100...800,
                        step: 10,
                        lowColor: DelayColor.low,
                        highColor: DelayColor.medium
                    )
                    .onChange(of: lowDelaySliderValue) { newValue in
                        lowDelayThreshold = Int(newValue)
                        HapticManager.shared.impact(.light)
                    }
                    .onChange(of: mediumDelaySliderValue) { newValue in
                        mediumDelayThreshold = Int(newValue)
                        HapticManager.shared.impact(.light)
                    }
                    
                    Text("低于\(lowDelayThreshold)ms显示为绿色，\(lowDelayThreshold)ms到\(mediumDelayThreshold)ms之间显示为黄色，高于\(mediumDelayThreshold)ms显示为橙色")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .onAppear {
                    lowDelaySliderValue = Double(lowDelayThreshold)
                    mediumDelaySliderValue = Double(mediumDelayThreshold)
                }
            } header: {
                SectionHeader(title: "延迟阈值设置", systemImage: "speedometer")
            }
            
            Section {
                Toggle("启用触感反馈", isOn: $enableHapticFeedback)
            } header: {
                SectionHeader(title: "触感反馈", systemImage: "hand.tap")
            }
            
            Section {
                Toggle("隐藏无法连接的控制器", isOn: $hideDisconnectedServers)
            } header: {
                SectionHeader(title: "超时隐藏", systemImage: "eye.slash")
            }
            
            Section {
                SettingToggleRow(
                    title: "根据 Wi-Fi 显示控制器列表",
                    subtitle: "根据当前连接的 Wi-Fi 网络自动显示对应的控制器",
                    isOn: Binding(
                        get: { enableWiFiBinding },
                        set: { newValue in
                            if !newValue {
                                enableWiFiBinding = false
                                bindingManager.onEnableChange()
                                return
                            }
                            
                            if locationManager.authorizationStatus == .denied {
                                locationManager.showLocationDeniedAlert = true
                                return
                            }
                            locationManager.requestWhenInUseAuthorization()
                            enableWiFiBinding = true
                            bindingManager.onEnableChange()
                        }
                    )
                )
                
                if enableWiFiBinding {
                    NavigationLink {
                        WiFiBindingView()
                    } label: {
                        SettingRow(
                            title: "Wi-Fi 绑定设置",
                            value: ""
                        )
                    }
                    
                    NavigationLink {
                        DefaultServersView()
                    } label: {
                        SettingRow(
                            title: "默认显示控制器",
                            value: ""
                        )
                    }
                }
            } header: {
                SectionHeader(title: "Wi-Fi 绑定", systemImage: "wifi")
            }
            
            Section {
                Button(action: {
                    showServerSelectionSheet = true
                }) {
                    SettingRow(
                        title: "Widget 默认控制器",
                        value: widgetDefaultServer.isEmpty ? "未设置" : widgetDefaultServer
                    )
                }
            } header: {
                SectionHeader(title: "Widget 设置", systemImage: "rectangle.on.rectangle")
            } footer: {
                Text("设置 Widget 默认显示的控制器信息，无需等待 App 启动即可显示")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showServerSelectionSheet) {
            ServerSelectionView(selectedServer: $widgetDefaultServer)
        }
        .alert("需要位置权限", isPresented: $locationManager.showLocationDeniedAlert) {
            Button("取消", role: .cancel) { }
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("需要位置权限才能获取 Wi-Fi 信息。请在设置中开启位置权限。")
        }
    }
}

struct ServerSelectionView: View {
    @Binding var selectedServer: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var serverViewModel = ServerViewModel()
    private let sharedDataManager = SharedDataManager.shared
    private let userDefaults = UserDefaults(suiteName: "group.ym.si.clashdash")
    
    var body: some View {
        NavigationStack {
            List {
                if serverViewModel.servers.isEmpty {
                    Section {
                        Text("没有可用的控制器")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(serverViewModel.servers) { server in
                        Button(action: {
                            let serverAddress = "\(server.url):\(server.port)"
                            print("[AppearanceSettings] 选择服务器: \(serverAddress)")
                            print("[AppearanceSettings] 当前服务器名称: \(server.name)")
                            
                            selectedServer = serverAddress
                            
                            // 保存 secret 和 SSL 设置
                            userDefaults?.set(server.clashUseSSL, forKey: "\(serverAddress)_useSSL")
                            userDefaults?.set(server.secret, forKey: "\(serverAddress)_secret")
                            print("[AppearanceSettings] Secret 和 SSL 已保存")
                            
                            // 同时保存到 SharedDataManager
                            sharedDataManager.saveClashStatus(
                                serverAddress: serverAddress,
                                serverName: server.name,
                                activeConnections: 0,
                                uploadTotal: 0,
                                downloadTotal: 0,
                                memoryUsage: nil,
                                secret: server.secret,
                                useSSL: server.clashUseSSL
                            )
                            
                            // 保存到 widgetDefaultServer
                            userDefaults?.set(serverAddress, forKey: "widgetDefaultServer")
                            userDefaults?.synchronize()
                            
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(server.name.isEmpty ? "\(server.url):\(server.port)" : server.name)
                                        .foregroundColor(.primary)
                                    if !server.name.isEmpty {
                                        Text("\(server.url):\(server.port)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if "\(server.url):\(server.port)" == selectedServer {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择控制器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                print("[AppearanceSettings] 视图出现")
                print("[AppearanceSettings] 当前选中的服务器: \(selectedServer)")
                
                Task { @MainActor in
                    serverViewModel.loadServers()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
            .environmentObject(WiFiBindingManager())
    }
} 
