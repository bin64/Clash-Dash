import SwiftUI
import Charts
import Darwin
import UIKit

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
    @State private var showProxyQuickMenu = false
    @State private var isKeyboardVisible = false
    @State private var keyboardHeight: CGFloat = 0
    
    // 根据设备类型和屏幕方向计算浮动标签栏的最大宽度
    private func floatingTabBarMaxWidth(for screenSize: CGSize) -> CGFloat {
        #if targetEnvironment(macCatalyst)
        return 520
        #else
        let isLandscape = screenSize.width > screenSize.height
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 480
        } else if isLandscape {
            // iPhone横屏时也使用紧凑布局
            return 420
        } else {
            // iPhone竖屏时使用全宽
            return .infinity
        }
        #endif
    }
    
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
                .contentShape(Rectangle())
                // 全局滚动监听已接管显隐逻辑，这里不再附加手势，避免与内部 ScrollView 竞争
                
                // 浮动标签栏
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FloatingTabBar(selectedTab: $selectedTab, onProxyLongPress: {
                            HapticManager.shared.impact(.rigid)
                            showProxyQuickMenu = true
                        })
                            .frame(maxWidth: floatingTabBarMaxWidth(for: geometry.size))
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, isKeyboardVisible ? 0 : geometry.safeAreaInsets.bottom + 25)
                    .offset(y: calculateTabBarOffset(geometry: geometry))
                    .opacity(isKeyboardVisible ? 0 : 1)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isTabBarVisible)
                    .animation(.spring(response: 0.4, dampingFraction: 0.9), value: isKeyboardVisible)
                    .animation(.spring(response: 0.4, dampingFraction: 0.9), value: keyboardHeight)
                }
                .zIndex(99999)
            }
            .overlay(
                GlobalPanObserver { deltaY, state, velocity, translation in
                    guard !isKeyboardVisible else { return }
                    // 优先判断垂直方向意图
                    if abs(velocity.x) > abs(velocity.y) { return }
                    let deltaThreshold: CGFloat = 4
                    let velocityThreshold: CGFloat = 120
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if deltaY < -deltaThreshold || velocity.y < -velocityThreshold {
                            isTabBarVisible = false
                        } else if deltaY > deltaThreshold || velocity.y > velocityThreshold {
                            isTabBarVisible = true
                        }
                    }
                }
                .allowsHitTesting(false)
            )
            .environment(\.floatingTabBarVisible, isTabBarVisible)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(isPresented: $showProxyQuickMenu) {
            ProxyQuickMenuView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
            // 监听键盘显示/隐藏通知
            addKeyboardObservers()
        }
        .onDisappear {
            networkMonitor.stopMonitoring()
            // 移除键盘通知监听
            removeKeyboardObservers()
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == 0 {
                networkMonitor.startMonitoring(server: server)
            } else {
                networkMonitor.stopMonitoring()
            }
        }
        .onChange(of: settingsViewModel.httpPort) { newPort in
            // print("📣 HTTP端口已更新: \(newPort)")
            connectivityViewModel.setupWithServer(server, httpPort: newPort, settingsViewModel: settingsViewModel)
            // print("已更新ConnectionViewModel中的端口: \(newPort)")
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
                // print("⚙️ ServerDetailView - 初始服务器设置, 端口: \(settingsViewModel.httpPort)")
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
        .background(TabBarLongPressRecognizer(onLongPress: { index in
            if index == 1 { // 代理
                HapticManager.shared.impact(.rigid)
                showProxyQuickMenu = true
            }
        }))
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
            // print("📣 HTTP端口已更新: \(newPort)")
            connectivityViewModel.setupWithServer(server, httpPort: newPort, settingsViewModel: settingsViewModel)
            // print("已更新ConnectionViewModel中的端口: \(newPort)")
        }
        .sheet(isPresented: $showProxyQuickMenu) {
            ProxyQuickMenuView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
        let threshold: CGFloat = 8
        let translationY = value.translation.height
        let predictedY = value.predictedEndTranslation.height
        let effectiveY = abs(predictedY) > abs(translationY) ? predictedY : translationY

        withAnimation(.easeInOut(duration: 0.25)) {
            if effectiveY < -threshold {
                // 向上滑动（内容向下滚）- 隐藏
                isTabBarVisible = false
            } else if effectiveY > threshold {
                // 向下滑动（内容向上滚）- 显示
                isTabBarVisible = true
            }
        }
    }
    
    // MARK: - 标签栏位置计算
    private func calculateTabBarOffset(geometry: GeometryProxy) -> CGFloat {
        if isKeyboardVisible {
            // 键盘显示时，将标签栏完全移出屏幕底部
            return geometry.size.height + 100
        } else if !isTabBarVisible {
            // 滚动隐藏时的偏移
            return 120
        } else {
            // 正常显示状态
            return 0
        }
    }
    
    // MARK: - 键盘监听方法
    private func addKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                let keyboardRectangle = keyboardFrame.cgRectValue
                let keyboardHeight = keyboardRectangle.height
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                    self.keyboardHeight = keyboardHeight
                    self.isKeyboardVisible = true
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                self.keyboardHeight = 0
                self.isKeyboardVisible = false
            }
        }
    }
    
    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
}

// 全局 Pan 观察器：将 UIPanGestureRecognizer 安装到窗口上，且与所有手势同时识别，不拦截点击
struct GlobalPanObserver: UIViewRepresentable {
    typealias PanCallback = (_ deltaY: CGFloat, _ state: UIGestureRecognizer.State, _ velocity: CGPoint, _ translation: CGPoint) -> Void
    let onPan: PanCallback

    func makeCoordinator() -> Coordinator {
        Coordinator(onPan: onPan)
    }

    func makeUIView(context: Context) -> AttachView {
        let view = AttachView()
        view.onAttachedToWindow = { window in
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: AttachView, context: Context) { }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let onPan: PanCallback
        private weak var windowRef: UIWindow?
        private var panRecognizer: UIPanGestureRecognizer?
        private var lastTranslation: CGPoint = .zero

        init(onPan: @escaping PanCallback) {
            self.onPan = onPan
        }

        func attach(to window: UIWindow?) {
            guard let window else { return }
            guard panRecognizer == nil else { return }
            windowRef = window
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            recognizer.minimumNumberOfTouches = 1
            recognizer.maximumNumberOfTouches = 1
            window.addGestureRecognizer(recognizer)
            panRecognizer = recognizer
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let window = windowRef else { return }
            let translation = gesture.translation(in: window)
            let velocity = gesture.velocity(in: window)

            if gesture.state == .began {
                lastTranslation = translation
            }

            let delta = CGPoint(x: translation.x - lastTranslation.x, y: translation.y - lastTranslation.y)
            onPan(delta.y, gesture.state, velocity, translation)
            lastTranslation = translation

            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                lastTranslation = .zero
            }
        }

        // 允许与所有手势同时识别，避免与 ScrollView 等互斥
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        // 确保不阻断子视图手势：不要求失败关系
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }

    final class AttachView: UIView {
        var onAttachedToWindow: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onAttachedToWindow?(self.window)
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
    var onProxyLongPress: (() -> Void)? = nil
    
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
                    .allowsHitTesting(false)
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
                    .allowsHitTesting(false)
                
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
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in
                                    if tab.index == 1 {
                                        onProxyLongPress?()
                                    }
                                }
                        )
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

//#pragma mark - Proxy Quick Menu

struct ProxyQuickMenuView: View {
    @AppStorage("hideUnavailableProxies") private var hideUnavailableProxies = false
    @AppStorage("proxyGroupSortOrder") private var proxyGroupSortOrder = ProxyGroupSortOrder.default
    @AppStorage("pinBuiltinProxies") private var pinBuiltinProxies = false
    @AppStorage("hideProxyProviders") private var hideProxyProviders = false
    @AppStorage("smartProxyGroupDisplay") private var smartProxyGroupDisplay = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var sortExpanded = false
    @State private var showContent = false

    var body: some View {
        NavigationStack {
            ZStack {
                // 简洁背景
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // 简洁头部
                        CompactHeaderSection()
                        
                        // 排序控制
                        CompactSectionCard {
                            CompactSortSection(
                                isExpanded: $sortExpanded,
                                selectedOrder: $proxyGroupSortOrder
                            )
                        }
                        
                        // 显示选项
                        CompactSectionCard {
                            VStack(spacing: 0) {
                                CompactToggleRow(
                                    icon: "eye.slash.fill", tint: .purple,
                                    title: "隐藏不可用代理",
                                    isOn: $hideUnavailableProxies
                                )
                                Divider().padding(.leading, 40)
                                
                                CompactToggleRow(
                                    icon: "pin.fill", tint: .orange,
                                    title: "置顶内置策略",
                                    isOn: $pinBuiltinProxies
                                )
                                Divider().padding(.leading, 40)
                                
                                CompactToggleRow(
                                    icon: "shippingbox.fill", tint: .blue,
                                    title: "隐藏代理提供者",
                                    isOn: $hideProxyProviders
                                )
                                Divider().padding(.leading, 40)
                                
                                CompactToggleRow(
                                    icon: "globe.asia.australia.fill", tint: .green,
                                    title: "智能 Global 代理组显示",
                                    isOn: $smartProxyGroupDisplay
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 10)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showContent)
                }
                .navigationTitle("显示偏好")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            HapticManager.shared.impact(.light)
                            dismiss()
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showContent = true
            }
        }
    }
}

// MARK: - Compact Components

struct CompactHeaderSection: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Text("快速调整代理显示选项")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

struct CompactSectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: () -> Content
    
    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
        )
    }
}

struct CompactSortSection: View {
    @Binding var isExpanded: Bool
    @Binding var selectedOrder: ProxyGroupSortOrder
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                HapticManager.shared.impact(.light)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.accentColor)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("排序方式")
                            .font(.body.weight(.medium))
                            .foregroundColor(.primary)
                        Text(selectedOrder.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(ProxyGroupSortOrder.allCases) { order in
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                selectedOrder = order
                            }
                            HapticManager.shared.impact(.light)
                        } label: {
                            HStack {
                                Text(order.description)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if order == selectedOrder {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(order == selectedOrder ? 
                                       Color.accentColor.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        
                        if order != ProxyGroupSortOrder.allCases.last {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .clipped()
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                ))
            }
        }
    }
}

struct CompactToggleRow: View {
    let icon: String
    let tint: Color
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .scaleEffect(0.8)
                .onChange(of: isOn) { _ in
                    HapticManager.shared.impact(.light)
                }
        }
        .padding(12)
    }
}



//#pragma mark - UITabBar Long Press Recognizer

struct TabBarLongPressRecognizer: UIViewRepresentable {
    let onLongPress: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLongPress: onLongPress)
    }

    func makeUIView(context: Context) -> AttachableView {
        let view = AttachableView()
        view.onAttachedToWindow = { window in
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: AttachableView, context: Context) { }

    final class Coordinator: NSObject {
        private let onLongPress: (Int) -> Void
        private var longPressRecognizer: UILongPressGestureRecognizer?
        private weak var observedTabBar: UITabBar?
        private weak var windowRef: UIWindow?
        private var findTimer: Timer?

        init(onLongPress: @escaping (Int) -> Void) {
            self.onLongPress = onLongPress
        }

        func attach(to window: UIWindow?) {
            guard let window else { return }
            windowRef = window
            guard observedTabBar == nil else { return }
            startFindingTabBar()
        }

        private func startFindingTabBar() {
            findTimer?.invalidate()
            var attemptsRemaining = 40 // ~10s @0.25s
            findTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                guard let window = self.windowRef else { timer.invalidate(); return }
                if let tabBar = self.findTabBar(in: window) {
                    timer.invalidate()
                    self.attachRecognizer(to: tabBar)
                } else {
                    attemptsRemaining -= 1
                    if attemptsRemaining <= 0 { timer.invalidate() }
                }
            }
            RunLoop.main.add(findTimer!, forMode: .common)
        }

        private func attachRecognizer(to tabBar: UITabBar) {
            guard observedTabBar == nil else { return }
            observedTabBar = tabBar
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
            recognizer.minimumPressDuration = 0.5
            recognizer.cancelsTouchesInView = false
            tabBar.addGestureRecognizer(recognizer)
            longPressRecognizer = recognizer
        }

        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let tabBar = observedTabBar else { return }
            let location = gesture.location(in: tabBar)
            let count = tabBar.items?.count ?? 0
            guard count > 0 else { return }
            let widthPerItem = tabBar.bounds.width / CGFloat(count)
            var index = Int(location.x / max(widthPerItem, 1))
            index = max(0, min(index, count - 1))
            onLongPress(index)
        }

        private func findTabBar(in root: UIView) -> UITabBar? {
            if let bar = root as? UITabBar { return bar }
            for sub in root.subviews {
                if let bar = findTabBar(in: sub) { return bar }
            }
            return nil
        }
    }

    final class AttachableView: UIView {
        var onAttachedToWindow: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onAttachedToWindow?(self.window)
        }
    }
}

#Preview {
    NavigationStack {
        ServerDetailView(server: ClashServer(name: "测试服务器", url: "10.1.1.166", port: "8099", secret: "123456"))
    }
} 
