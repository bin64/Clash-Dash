import SwiftUI
import Charts
import Darwin

struct ServerDetailView: View {
    let server: ClashServer
    @StateObject private var networkMonitor = NetworkMonitor()
    @State private var selectedTab = 0
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ServerDetailViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()
    @State private var showingModeChangeSuccess = false
    @State private var lastChangedMode = ""
    @State private var showingConfigSubscription = false
    @State private var showingSwitchConfig = false
    @State private var showingCustomRules = false
    @State private var showingRestartService = false
    @EnvironmentObject private var bindingManager: WiFiBindingManager
    @StateObject private var subscriptionManager: SubscriptionManager
    @StateObject private var connectivityViewModel = ConnectivityViewModel()
    
    init(server: ClashServer) {
        self.server = server
        self._subscriptionManager = StateObject(wrappedValue: SubscriptionManager(server: server))
        
        // 设置 UITabBar 的外观
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground
        
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().standardAppearance = appearance
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 概览标签页
            OverviewTab(
                server: server, 
                monitor: networkMonitor, 
                selectedTab: $selectedTab, 
                settingsViewModel: settingsViewModel,
                connectivityViewModel: connectivityViewModel
            )
            .onAppear {
                HapticManager.shared.impact(.light)
                // 首先获取配置
                settingsViewModel.fetchConfig(server: server) 
                
                // 初始设置端口，传入settingsViewModel以支持fallback到mixedPort
                connectivityViewModel.setupWithServer(server, httpPort: settingsViewModel.httpPort, settingsViewModel: settingsViewModel)
                print("⚙️ ServerDetailView - 初始服务器设置, 端口: \(settingsViewModel.httpPort)")
            }
            .tabItem {
                Label("概览", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(0)
            
            // 代理标签页
            ProxyView(server: server)
                .onAppear {
                    HapticManager.shared.impact(.light)
                }
                .tabItem {
                    Label("代理", systemImage: "globe")
                }
                .tag(1)
                
            // 规则标签页
            RulesView(server: server)
                .onAppear {
                    HapticManager.shared.impact(.light)
                }
                .tabItem {
                    Label("规则", systemImage: "ruler")
                }
                .tag(2)
            
            // 连接标签页
            ConnectionsView(server: server)
                .onAppear {
                    HapticManager.shared.impact(.light)
                }
                .tabItem {
                    Label("连接", systemImage: "link")
                }
                .tag(3)
            
            // 更多标签页
            MoreView(server: server)
                .onAppear {
                    HapticManager.shared.impact(.light)
                }
                .tabItem {
                    Label("更多", systemImage: "ellipsis")
                }
                .tag(4)
        }
        .navigationTitle(server.name.isEmpty ? "\(server.openWRTUrl ?? server.url):\(server.openWRTPort ?? server.port)" : server.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if server.isQuickLaunch {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Spacer()
                            .frame(width: 25)
                        Text(server.name.isEmpty ? "\(server.openWRTUrl ?? server.url):\(server.openWRTPort ?? server.port)" : server.name)
                            .font(.headline)
                        Image(systemName: "bolt.circle.fill")
                            .foregroundColor(.yellow)
                            .font(.subheadline)
                    }
                }
            } else {
                ToolbarItem(placement: .principal) {
                    Text(server.name.isEmpty ? "\(server.openWRTUrl ?? server.url):\(server.openWRTPort ?? server.port)" : server.name)
                        .font(.headline)
                }
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .onAppear {
            viewModel.serverViewModel.setBingingManager(bindingManager)
            // 如果当前是概览标签页，启动监控
            if selectedTab == 0 {
                networkMonitor.startMonitoring(server: server)
            }
        }
        .onDisappear {
            networkMonitor.stopMonitoring()
        }
        .onChange(of: selectedTab) { newTab in
            // 当标签页切换时，根据是否是概览标签页来启动或停止监控
            if newTab == 0 {
                networkMonitor.startMonitoring(server: server)
            } else {
                networkMonitor.stopMonitoring()
            }
        }
        // 监听HTTP端口变化
        .onChange(of: settingsViewModel.httpPort) { newPort in
            print("📣 HTTP端口已更新: \(newPort)")
            connectivityViewModel.setupWithServer(server, httpPort: newPort, settingsViewModel: settingsViewModel)
            print("🔄 已更新ConnectionViewModel中的端口: \(newPort)")
        }
    }
    
    private func showModeChangeSuccess(mode: String) {
        lastChangedMode = mode
        withAnimation {
            showingModeChangeSuccess = true
        }
        // 2 秒后隐藏提示
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showingModeChangeSuccess = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        ServerDetailView(server: ClashServer(name: "测试服务器", url: "10.1.1.166", port: "8099", secret: "123456"))
    }
} 
