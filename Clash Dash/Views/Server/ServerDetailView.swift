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
    @AppStorage("useFloatingTabs") private var useFloatingTabs = false
    @State private var isTabBarVisible = true
    @State private var lastScrollOffset: CGFloat = 0
    
    init(server: ClashServer) {
        self.server = server
        self._subscriptionManager = StateObject(wrappedValue: SubscriptionManager(server: server))
        
        // 设置 UITabBar 的外观 (仅在不使用浮动标签页时)
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground
        
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().standardAppearance = appearance
    }
    
    var body: some View {
        if useFloatingTabs {
            floatingTabsView
        } else {
            fixedTabsView
        }
    }
    
    @ViewBuilder
    private var floatingTabsView: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景内容
                Group {
                    switch selectedTab {
                    case 0:
                        OverviewTab(
                            server: server, 
                            monitor: networkMonitor, 
                            selectedTab: $selectedTab, 
                            settingsViewModel: settingsViewModel,
                            connectivityViewModel: connectivityViewModel
                        )
                        .onAppear {
                            HapticManager.shared.impact(.light)
                            settingsViewModel.fetchConfig(server: server) 
                            connectivityViewModel.setupWithServer(server, httpPort: settingsViewModel.httpPort, settingsViewModel: settingsViewModel)
                            print("⚙️ ServerDetailView - 初始服务器设置, 端口: \(settingsViewModel.httpPort)")
                        }
                    case 1:
                        ProxyView(server: server)
                            .onAppear {
                                HapticManager.shared.impact(.light)
                            }
                    case 2:
                        RulesView(server: server)
                            .onAppear {
                                HapticManager.shared.impact(.light)
                            }
                    case 3:
                        ConnectionsView(server: server)
                            .onAppear {
                                HapticManager.shared.impact(.light)
                            }
                    case 4:
                        MoreView(server: server)
                            .onAppear {
                                HapticManager.shared.impact(.light)
                            }
                    default:
                        EmptyView()
                    }
                }
                
                // 浮动标签栏
                VStack {
                    Spacer()
                    FloatingTabBar(selectedTab: $selectedTab)
                    .padding(.horizontal, 16)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
                    .offset(y: isTabBarVisible ? 0 : 100)
                    .animation(.easeInOut(duration: 0.3), value: isTabBarVisible)
                }
            }
            .environment(\.floatingTabBarVisible, isTabBarVisible)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    handleDragGesture(value)
                }
        )
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
            if selectedTab == 0 {
                networkMonitor.startMonitoring(server: server)
            }
        }
        .onDisappear {
            networkMonitor.stopMonitoring()
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == 0 {
                networkMonitor.startMonitoring(server: server)
            } else {
                networkMonitor.stopMonitoring()
            }
        }
        .onChange(of: settingsViewModel.httpPort) { newPort in
            print("📣 HTTP端口已更新: \(newPort)")
            connectivityViewModel.setupWithServer(server, httpPort: newPort, settingsViewModel: settingsViewModel)
            print("🔄 已更新ConnectionViewModel中的端口: \(newPort)")
        }
    }
    
    @ViewBuilder
    private var fixedTabsView: some View {
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
                settingsViewModel.fetchConfig(server: server) 
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
            if selectedTab == 0 {
                networkMonitor.startMonitoring(server: server)
            }
        }
        .onDisappear {
            networkMonitor.stopMonitoring()
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == 0 {
                networkMonitor.startMonitoring(server: server)
            } else {
                networkMonitor.stopMonitoring()
            }
        }
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
    
    private func handleDragGesture(_ value: DragGesture.Value) {
        let threshold: CGFloat = 20
        let translationY = value.translation.height
        
        withAnimation(.easeInOut(duration: 0.3)) {
            if translationY < -threshold {
                // Dragging up (content scrolling down) - hide tab bar
                isTabBarVisible = false
                print("📱 ServerDetailView - 隐藏浮动标签栏")
            } else if translationY > threshold {
                // Dragging down (content scrolling up) - show tab bar
                isTabBarVisible = true
                print("📱 ServerDetailView - 显示浮动标签栏")
            }
        }
    }
}

// Environment key for floating tab bar visibility
struct FloatingTabBarVisibleKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var floatingTabBarVisible: Bool {
        get { self[FloatingTabBarVisibleKey.self] }
        set { self[FloatingTabBarVisibleKey.self] = newValue }
    }
}

struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    
    private let tabs = [
        (index: 0, title: "概览", icon: "chart.line.uptrend.xyaxis"),
        (index: 1, title: "代理", icon: "globe"),
        (index: 2, title: "规则", icon: "ruler"),
        (index: 3, title: "连接", icon: "link"),
        (index: 4, title: "更多", icon: "ellipsis")
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.index) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab.index
                    }
                    HapticManager.shared.impact(.light)
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(selectedTab == tab.index ? .accentColor : .secondary)
                        
                        Text(tab.title)
                            .font(.caption2)
                            .foregroundColor(selectedTab == tab.index ? .accentColor : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
}

#Preview {
    NavigationStack {
        ServerDetailView(server: ClashServer(name: "测试服务器", url: "10.1.1.166", port: "8099", secret: "123456"))
    }
} 
