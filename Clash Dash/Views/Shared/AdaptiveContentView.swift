import SwiftUI

/// 自适应主容器视图 - 根据设备类型选择合适的布局
struct AdaptiveContentView: View {
    @StateObject private var viewModel = ServerViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var bindingManager: WiFiBindingManager
    
    // 大屏设备的状态管理
    @State private var selectedServer: ClashServer?
    @State private var selectedSidebarItem: SidebarItem?
    @State private var showingAddSheet = false
    @State private var editingServer: ClashServer?
    @State private var showingModeChangeSuccess = false
    @State private var lastChangedMode = ""
    
    // 主题设置
    @AppStorage("appThemeMode") private var appThemeMode = AppThemeMode.system
    
    var body: some View {
        Group {
            if shouldUseSplitView {
                // 大屏设备使用 NavigationSplitView
                splitViewLayout
            } else {
                // 小屏设备使用原有的 NavigationStack
                compactLayout
            }
        }
        .preferredColorScheme(colorScheme)
        .sheet(isPresented: $showingAddSheet) {
            AddServerView(viewModel: viewModel)
        }
        .sheet(item: $editingServer) { server in
            EditServerView(viewModel: viewModel, server: server)
        }
        .alert("连接错误", isPresented: $viewModel.showError) {
            Button("确定", role: .cancel) {}
        } message: {
            if let details = viewModel.errorDetails {
                Text("\(viewModel.errorMessage ?? "")\n\n\(details)")
            } else {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .overlay(alignment: .bottom) {
            if showingModeChangeSuccess {
                modeChangeSuccessView
            }
        }
        .onAppear {
            viewModel.setBingingManager(bindingManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ControllersUpdated"))) { _ in
            Task { @MainActor in
                viewModel.loadServers()
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            }
        }
    }
    
    /// 是否应该使用分割视图布局
    private var shouldUseSplitView: Bool {
        // 在 iPad 和 Mac 上使用分割视图，但不在 iPhone 横屏时使用
        switch DeviceDetection.deviceType {
        case .iPad, .mac:
            return true
        case .iPhone:
            return false
        }
    }
    
    /// 分割视图布局（大屏设备）
    private var splitViewLayout: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: viewModel,
                settingsViewModel: settingsViewModel,
                selectedServer: $selectedServer,
                selectedSidebarItem: $selectedSidebarItem,
                showingAddSheet: $showingAddSheet,
                editingServer: $editingServer,
                onModeChange: { mode in showModeChangeSuccess(mode: mode) },
                onShowConfigSubscription: { server in showConfigSubscriptionView(for: server) },
                onShowSwitchConfig: { server in showSwitchConfigView(for: server) },
                onShowCustomRules: { server in showCustomRulesView(for: server) },
                onShowRestartService: { server in showRestartServiceView(for: server) }
            )
        } detail: {
            DetailContentView(
                selectedServer: $selectedServer,
                selectedSidebarItem: $selectedSidebarItem,
                settingsViewModel: settingsViewModel
            )
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    /// 紧凑布局（小屏设备）
    private var compactLayout: some View {
        ContentView()
            .environmentObject(bindingManager)
    }
    
    /// 模式切换成功提示视图
    private var modeChangeSuccessView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
            Text("已切换至\(ModeUtils.getModeText(lastChangedMode))")
                .foregroundColor(.primary)
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(25)
        .shadow(radius: 10, x: 0, y: 5)
        .padding(.bottom, 30)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            // 2 秒后隐藏提示
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showingModeChangeSuccess = false
                }
            }
        }
    }
    
    /// 计算颜色方案
    private var colorScheme: ColorScheme? {
        switch appThemeMode {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil
        }
    }
    
    /// 显示模式切换成功
    func showModeChangeSuccess(mode: String) {
        lastChangedMode = mode
        withAnimation {
            showingModeChangeSuccess = true
        }
    }
    
    // MARK: - 服务器操作方法
    private func showSwitchConfigView(for server: ClashServer) {
        editingServer = nil  // 清除编辑状态
        let configView = OpenClashConfigView(viewModel: viewModel, server: server)
        let sheet = UIHostingController(rootView: configView)
        
        // 设置 sheet 的首选样式
        sheet.modalPresentationStyle = .formSheet
        sheet.sheetPresentationController?.detents = [.medium(), .large()]
        sheet.sheetPresentationController?.prefersGrabberVisible = true
        
        // 获取当前的 window scene
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(sheet, animated: true)
        }
    }
    
    private func showConfigSubscriptionView(for server: ClashServer) {
        editingServer = nil  // 清除编辑状态
        let configView = ConfigSubscriptionView(server: server)
        let sheet = UIHostingController(rootView: configView)
        
        // 设置 sheet 的首选样式
        sheet.modalPresentationStyle = .formSheet
        sheet.sheetPresentationController?.detents = [.medium(), .large()]
        sheet.sheetPresentationController?.prefersGrabberVisible = true
        
        // 获取当前的 window scene
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(sheet, animated: true)
        }
    }
    
    private func showCustomRulesView(for server: ClashServer) {
        editingServer = nil  // 清除编辑状态
        let rulesView = OpenClashRulesView(server: server)
        let sheet = UIHostingController(rootView: rulesView)
        
        sheet.modalPresentationStyle = .formSheet
        sheet.sheetPresentationController?.detents = [.medium(), .large()]
        sheet.sheetPresentationController?.prefersGrabberVisible = true
        sheet.sheetPresentationController?.selectedDetentIdentifier = .medium
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(sheet, animated: true)
        }
    }
    
    private func showRestartServiceView(for server: ClashServer) {
        editingServer = nil  // 清除编辑状态
        let restartView = RestartServiceView(viewModel: viewModel, server: server)
        let sheet = UIHostingController(rootView: restartView)
        
        sheet.modalPresentationStyle = .formSheet
        sheet.sheetPresentationController?.detents = [.medium(), .large()]
        sheet.sheetPresentationController?.prefersGrabberVisible = true
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(sheet, animated: true)
        }
    }
}

#Preview("iPad") {
    AdaptiveContentView()
        .environmentObject(WiFiBindingManager())
}

#Preview("iPhone") {
    AdaptiveContentView()
        .environmentObject(WiFiBindingManager())
} 