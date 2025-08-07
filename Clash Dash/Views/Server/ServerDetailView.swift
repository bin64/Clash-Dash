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
                            // print("⚙️ ServerDetailView - 初始服务器设置, 端口: \(settingsViewModel.httpPort)")
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
                        .padding(.horizontal, 20)
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 25)
                        .offset(y: isTabBarVisible ? 0 : 120)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isTabBarVisible)
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
                // print("📱 ServerDetailView - 隐藏浮动标签栏")
            } else if translationY > threshold {
                // Dragging down (content scrolling up) - show tab bar
                isTabBarVisible = true
                // print("📱 ServerDetailView - 显示浮动标签栏")
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
    @State private var animationOffset: CGFloat = 0
    @State private var indicatorOffset: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var isAnimating: Bool = false
    @State private var scaleX: CGFloat = 1.0
    @State private var scaleY: CGFloat = 1.0
    @State private var previousSelectedTab: Int = 0
    @State private var skewX: CGFloat = 0.0 // 水平倾斜
    @State private var cornerRadius: CGFloat = 20.0 // 动态圆角
    
    @Environment(\.colorScheme) private var colorScheme
    
    private let tabs = [
        (index: 0, title: "概览", icon: "chart.line.uptrend.xyaxis"),
        (index: 1, title: "代理", icon: "globe"),
        (index: 2, title: "规则", icon: "ruler"),
        (index: 3, title: "连接", icon: "link"),
        (index: 4, title: "更多", icon: "ellipsis")
    ]
    
    var body: some View {
        GeometryReader { geometry in
            let tabWidth = geometry.size.width / CGFloat(tabs.count)
            
            ZStack {
                // 背景 - 适配深色模式
                RoundedRectangle(cornerRadius: 25)
                    .fill(colorScheme == .dark ? .thickMaterial : .ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: colorScheme == .dark ? [
                                        Color.black.opacity(0.9),
                                        Color.gray.opacity(0.3)
                                    ] : [
                                        Color.white.opacity(0.9),
                                        Color.white.opacity(0.7)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blur(radius: 0.5)
                    )
                    .overlay(
                        // 深色模式下添加微弱的边框光晕
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(
                                colorScheme == .dark ? 
                                    Color.white.opacity(0.1) : Color.clear,
                                lineWidth: 0.5
                            )
                    )
                    .shadow(
                        color: colorScheme == .dark ? 
                            Color.black.opacity(0.6) : Color.black.opacity(0.15), 
                        radius: 15, x: 0, y: 8
                    )
                    .shadow(
                        color: colorScheme == .dark ? 
                            Color.black.opacity(0.3) : Color.black.opacity(0.05), 
                        radius: 5, x: 0, y: 2
                    )
                
                // 活跃指示器背景 - 方向性水滴效果，适配深色模式
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: colorScheme == .dark ? [
                                Color.accentColor.opacity(0.35),
                                Color.accentColor.opacity(0.25)
                            ] : [
                                Color.accentColor.opacity(0.25),
                                Color.accentColor.opacity(0.15)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: tabWidth - 16, height: 50)
                    .scaleEffect(x: scaleX, y: scaleY)
                    .rotation3DEffect(
                        .degrees(skewX),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.5
                    )
                    .offset(x: indicatorOffset)
                
                // 标签按钮
                HStack(spacing: 0) {
                    ForEach(tabs, id: \.index) { tab in
                        Button(action: {
                            // 触发方向性水滴变形动画
                            triggerDirectionalLiquidAnimation(
                                from: selectedTab,
                                to: tab.index
                            ) {
                                selectedTab = tab.index
                                updateIndicatorPosition(for: tab.index, tabWidth: tabWidth, totalWidth: geometry.size.width)
                            }
                            HapticManager.shared.impact(.medium)
                        }) {
                            VStack(spacing: 4) {
                                // 固定高度的图标容器，确保对齐
                                ZStack {
                                                                    Image(systemName: tab.icon)
                                    .font(.system(size: selectedTab == tab.index ? 18 : 16, weight: .semibold))
                                    .foregroundColor(
                                        selectedTab == tab.index ? 
                                            .accentColor : 
                                            (colorScheme == .dark ? .secondary : .secondary)
                                    )
                                    .scaleEffect(selectedTab == tab.index ? 1.1 : 1.0)
                                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: selectedTab)
                                }
                                .frame(width: 24, height: 24) // 固定图标容器尺寸
                                
                                // 固定高度的文字容器，确保对齐
                                Text(tab.title)
                                    .font(.system(size: 11, weight: selectedTab == tab.index ? .semibold : .medium))
                                    .foregroundColor(
                                        selectedTab == tab.index ? 
                                            .accentColor : 
                                            (colorScheme == .dark ? Color.secondary : Color.secondary)
                                    )
                                    .scaleEffect(selectedTab == tab.index ? 1.05 : 1.0)
                                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: selectedTab)
                                    .frame(height: 14) // 固定文字容器高度
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(TabButtonStyle())
                    }
                }
            }
            .onAppear {
                containerWidth = geometry.size.width
                // 立即初始化指示器位置到第一个标签（索引0）
                updateIndicatorPosition(for: selectedTab, tabWidth: containerWidth / CGFloat(tabs.count), totalWidth: containerWidth)
            }
            .onChange(of: selectedTab) { newTab in
                updateIndicatorPosition(for: newTab, tabWidth: containerWidth / CGFloat(tabs.count), totalWidth: containerWidth)
            }
            .onChange(of: geometry.size.width) { newWidth in
                containerWidth = newWidth
                updateIndicatorPosition(for: selectedTab, tabWidth: containerWidth / CGFloat(tabs.count), totalWidth: containerWidth)
            }
        }
        .frame(height: 70)
    }
    
    private func updateIndicatorPosition(for index: Int, tabWidth: CGFloat, totalWidth: CGFloat) {
        // 计算每个标签的中心位置，相对于容器左边缘
        let tabCenterX = (CGFloat(index) + 0.5) * tabWidth
        // 计算相对于容器中心的偏移
        let containerCenterX = totalWidth / 2
        // 指示器偏移 = 标签中心 - 容器中心
        // 对于索引0（第一个标签），这会产生负偏移，将指示器放在左侧
        indicatorOffset = tabCenterX - containerCenterX
    }
    
    private func triggerDirectionalLiquidAnimation(from: Int, to: Int, completion: @escaping () -> Void) {
        // 判断移动方向
        let isMovingRight = to > from
        let distance = abs(to - from)
        let intensity = min(CGFloat(distance) * 0.3, 1.0) // 根据距离调整强度
        
        // 开始动画状态
        isAnimating = true
        previousSelectedTab = from
        
        // 第一阶段：蓄力变形（0.1秒）
        withAnimation(.easeIn(duration: 0.1)) {
            // 根据方向进行预变形
            if isMovingRight {
                scaleX = 1.2 + intensity * 0.2  // 右移时右侧拉伸更多
                skewX = -3 - intensity * 2       // 向右倾斜
            } else {
                scaleX = 1.2 + intensity * 0.2  // 左移时左侧拉伸更多
                skewX = 3 + intensity * 2        // 向左倾斜
            }
            scaleY = 0.85 - intensity * 0.1  // 垂直压缩
            cornerRadius = 15 - intensity * 3 // 圆角变小，更像水滴
        }
        
        // 第二阶段：运动变形（0.6秒）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                completion() // 执行位置更新
                
                // 运动中的极端变形
                if isMovingRight {
                    scaleX = 0.6 - intensity * 0.1  // 水平极度压缩
                    skewX = -8 - intensity * 4       // 更强的右倾斜
                } else {
                    scaleX = 0.6 - intensity * 0.1  // 水平极度压缩  
                    skewX = 8 + intensity * 4        // 更强的左倾斜
                }
                scaleY = 1.3 + intensity * 0.2  // 垂直拉伸
                cornerRadius = 25 + intensity * 5 // 运动时变得更圆润
            }
            
            // 第三阶段：弹性恢复（0.4秒）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    scaleX = 1.0
                    scaleY = 1.0
                    skewX = 0.0
                    cornerRadius = 20.0
                }
                
                // 结束动画状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isAnimating = false
                }
            }
        }
    }
}

// 自定义按钮样式
struct TabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack {
        ServerDetailView(server: ClashServer(name: "测试服务器", url: "10.1.1.166", port: "8099", secret: "123456"))
    }
} 
