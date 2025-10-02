import SwiftUI
import UIKit
import SafariServices
import Network
import NetworkExtension
import CoreLocation

struct ContentView: View {
    @StateObject private var viewModel: ServerViewModel
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var locationManager = LocationManager()
    @State private var showingAddSheet = false
    @State private var editingServer: ClashServer?
    @State private var selectedQuickLaunchServer: ClashServer?
    @State private var showQuickLaunchDestination = false
    @State private var showingAddOpenWRTSheet = false
    @State private var showingModeChangeSuccess = false
    @State private var lastChangedMode = ""
    @State private var showingSourceCode = false
    @State private var currentWiFiSSID: String = ""
    @State private var forceRefresh: Bool = false  // 添加强制刷新标志
    @AppStorage("appThemeMode") private var appThemeMode = AppThemeMode.system
    @AppStorage("hideDisconnectedServers") private var hideDisconnectedServers = false
    @AppStorage("enableWiFiBinding") private var enableWiFiBinding = false
    @Environment(\.scenePhase) private var scenePhase
    
    // 使用 EnvironmentObject 来共享 WiFiBindingManager
    @EnvironmentObject private var bindingManager: WiFiBindingManager

    private let logger = LogManager.shared

    @State private var isDragging = false
    @State private var draggedServer: ClashServer?
    @Namespace private var animation
    @State private var draggedOffset: CGFloat = 0
    @State private var dragTargetIndex: Int?
    @State private var dragDirection: DragDirection = .none
    @State private var showLocalNetworkDeniedAlert = false
    @State private var isOnHomeScreen = true // 跟踪是否在首页

    private enum DragDirection {
        case up, down, none
    }

    init() {
        _viewModel = StateObject(wrappedValue: ServerViewModel())
    }

    // 添加触觉反馈生成器
    
    
    // 添加过滤后的服务器列表计算属性
    private var filteredServers: [ClashServer] {
        // 使用 forceRefresh 来强制重新计算，但不使用它的值
        _ = forceRefresh
        
        // 使用 isServerHidden 方法来过滤服务器
        return viewModel.servers.filter { server in
            !viewModel.isServerHidden(server, currentWiFiSSID: currentWiFiSSID)
        }
    }
    
    // 添加隐藏的服务器列表计算属性
    private var hiddenServers: [ClashServer] {
        return viewModel.servers.filter { server in
            viewModel.isServerHidden(server, currentWiFiSSID: currentWiFiSSID)
        }
    }
    
    // 添加展开/收起状态
    @State private var showHiddenServers = false
    
    // 添加一个新的私有视图来处理单个服务器行
    private func serverRowView(for server: ClashServer, index: Int) -> some View {
        let isTarget = dragTargetIndex == index && draggedServer?.id != server.id
        let offset: CGFloat = {
            guard isTarget else { return 0 }
            if let draggedServer = draggedServer,
               let draggedIndex = viewModel.servers.firstIndex(where: { $0.id == draggedServer.id }) {
                return draggedIndex > index ? 80 : -80
            }
            return 0
        }()
        
        return NavigationLink(destination: ServerDetailView(server: server)
            .onAppear {
                // 导航到详情页面时，标记不在首页
                print("🚪 导航到服务器详情页面: \(server.name)")
                isOnHomeScreen = false
                print("🏠 isOnHomeScreen 设置为: \(isOnHomeScreen)")
            }
            .onDisappear {
                // 从详情页面返回时，标记回到首页
                print("⬅️ 从服务器详情页面返回首页")
                isOnHomeScreen = true
                print("🏠 isOnHomeScreen 设置为: \(isOnHomeScreen)")
            }
        ) {
            ServerRowView(server: server)
                .serverContextMenu(
                    viewModel: viewModel,
                    settingsViewModel: settingsViewModel,
                    server: server,
                    onEdit: { editingServer = server },
                    onModeChange: { mode in showModeChangeSuccess(mode: mode) },
                    onShowConfigSubscription: { showConfigSubscriptionView(for: server) },
                    onShowSwitchConfig: { showSwitchConfigView(for: server) },
                    onShowCustomRules: { showCustomRulesView(for: server) },
                    onShowRestartService: { showRestartServiceView(for: server) }
                )
                .matchedGeometryEffect(id: server.id, in: animation)
                .offset(y: offset)
                .animation(.easeInOut(duration: 0.3), value: offset)
        }
        .buttonStyle(PlainButtonStyle())
        .onDrag {
            self.draggedServer = server
            self.isDragging = true
            let provider = NSItemProvider(object: server.id.uuidString as NSString)
            provider.suggestedName = "松手完成排序"
            return provider
        }
        .dropDestination(for: String.self) { items, location in
            guard let draggedServer = self.draggedServer,
                  let fromIndex = viewModel.servers.firstIndex(where: { $0.id == draggedServer.id }),
                  let toIndex = viewModel.servers.firstIndex(where: { $0.id == server.id }) else {
                return false
            }
            
            if fromIndex != toIndex {
                withAnimation(.easeInOut) {
                    viewModel.moveServer(from: fromIndex, to: toIndex)
                    HapticManager.shared.impact(.medium)
                }
            }
            self.isDragging = false
            self.dragTargetIndex = nil
            self.dragDirection = .none
            return true
        } isTargeted: { isTargeted in
            if isTargeted {
                if let draggedServer = self.draggedServer,
                   let draggedIndex = viewModel.servers.firstIndex(where: { $0.id == draggedServer.id }),
                   let currentIndex = viewModel.servers.firstIndex(where: { $0.id == server.id }) {
                    // 当拖拽到目标位置时，立即执行移动
                    if draggedIndex != currentIndex {
                        withAnimation(.easeInOut) {
                            viewModel.moveServer(from: draggedIndex, to: currentIndex)
                            HapticManager.shared.impact(.soft)
                        }
                    }
                }
                dragTargetIndex = index
            }
        }
    }

    // 权限校验与 Wi‑Fi SSID 更新
    private func ensureLocalNetworkPermission() {
        // logger.debug("开始检测本地网络权限…")
        Task { @MainActor in
            let granted = await LocalNetworkAuthorization().requestAuthorization()
            logger.debug("本地网络权限状态: \(granted ? "已授权" : "被拒绝")")
            if !granted {
                showLocalNetworkDeniedAlert = true
            }
        }
    }
    
    private func locationAuthDescription(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedWhenInUse: return "使用期间已授权"
        case .authorizedAlways: return "始终已授权"
        case .denied: return "被拒绝"
        case .restricted: return "受限"
        case .notDetermined: return "未确定"
        @unknown default: return "未知"
        }
    }
    
    private func updateWiFiSSIDWithChecks() {
        guard enableWiFiBinding else {
            logger.debug("Wi‑Fi 绑定功能未启用，跳过获取 Wi‑Fi 信息")
            currentWiFiSSID = ""
            UserDefaults.standard.set("", forKey: "current_ssid")
            return
        }
        
        let status = locationManager.authorizationStatus
        logger.debug("位置权限状态: \(locationAuthDescription(status))")
        switch status {
        case .notDetermined:
            logger.debug("位置权限未确定，发起请求…")
            locationManager.requestWhenInUseAuthorization()
            return
        case .denied:
            logger.debug("位置权限被拒绝，无法获取 Wi‑Fi 名称")
            locationManager.showLocationDeniedAlert = true
            return
        case .restricted:
            logger.debug("位置权限受限，无法获取 Wi‑Fi 名称")
            locationManager.showLocationDeniedAlert = true
            return
        default:
            break
        }
        
        NEHotspotNetwork.fetchCurrent { network in
            DispatchQueue.main.async {
                if let network = network {
                    logger.debug("检测到 Wi‑Fi: \(network.ssid)")
                    currentWiFiSSID = network.ssid
                    UserDefaults.standard.set(network.ssid, forKey: "current_ssid")
                    viewModel.logWiFiBindingSummary(currentWiFiSSID: network.ssid)
                } else {
                    logger.debug("未检测到 Wi‑Fi 连接")
                    currentWiFiSSID = ""
                    UserDefaults.standard.set("", forKey: "current_ssid")
                    viewModel.logWiFiBindingSummary(currentWiFiSSID: "")
                }
            }
        }
    }

    // 添加一个新的私有视图来处理服务器列表
    private func serverListView() -> some View {
        ForEach(Array(filteredServers.enumerated()), id: \.element.id) { index, server in
            serverRowView(for: server, index: index)
        }
        .onChange(of: isDragging) { dragging in
            if !dragging {
                draggedServer = nil
                dragTargetIndex = nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.servers.isEmpty {
                        // 真正的空状态（没有任何服务器）
                        VStack(spacing: 20) {
                            Spacer()
                                .frame(height: 60)
                            
                            Image(systemName: "server.rack")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary.opacity(0.7))
                                .padding(.bottom, 10)
                            
                            Text("没有控制器")
                                .font(.title2)
                                .fontWeight(.medium)
                            
                            Text("点击添加按钮来添加一个新的控制器")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            
                            Menu {
                                Button(action: {
                                    HapticManager.shared.impact(.light)
                                    showingAddSheet = true
                                }) {
                                    Label("添加控制器", systemImage: "plus.circle")
                                }
                            } label: {
                                Text("添加控制器")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 160, height: 44)
                                    .background(Color.blue)
                                    .cornerRadius(22)
                                    .onTapGesture {
                                        HapticManager.shared.impact(.light)
                                    }
                            }
                            .padding(.top, 20)
                            .padding(.bottom, 40)
                        }
                    } else if filteredServers.isEmpty && !viewModel.servers.isEmpty {
                        // 所有服务器都被过滤掉的状态
                        VStack(spacing: 20) {
                            Spacer()
                                .frame(height: 60)
                            
                            Image(systemName: "server.rack")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary.opacity(0.7))
                                .padding(.bottom, 10)
                            
                            if hideDisconnectedServers {
                                Text("所有控制器已被自动隐藏")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                Text("请在外观设置中关闭隐藏无法连接的控制器来显示全部控制器")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                    .padding(.bottom, 40)
                            } else {
                                Text("当前 Wi‑Fi 下没有绑定的控制器")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                Text("您可以在 Wi‑Fi 绑定设置中添加控制器")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                                    .padding(.bottom, 40)
                            }
                        }
                    } else {
                        // 使用新的服务器列表视图
                        serverListView()
                        
                        // 隐藏控制器部分保持不变
                        if !hiddenServers.isEmpty {
                            Button(action: {
                                withAnimation {
                                    showHiddenServers.toggle()
                                    HapticManager.shared.impact(.light)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: showHiddenServers ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(showHiddenServers ? "收起隐藏的 \(hiddenServers.count) 个控制器" : "展开隐藏的 \(hiddenServers.count) 个控制器")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                            .padding(.top, 4)
                            
                            if showHiddenServers {
                                VStack(spacing: 12) {
                                    ForEach(hiddenServers) { server in
                                        NavigationLink {
                                            ServerDetailView(server: server)
                                                .onAppear {
                                                    HapticManager.shared.impact(.light)
                                                }
                                        } label: {
                                            ServerRowView(server: server)
                                                .serverContextMenu(
                                                    viewModel: viewModel,
                                                    settingsViewModel: settingsViewModel,
                                                    server: server,
                                                    showMoveOptions: false,  // 禁用移动选项
                                                    onEdit: { editingServer = server },
                                                    onModeChange: { mode in showModeChangeSuccess(mode: mode) },
                                                    onShowConfigSubscription: { showConfigSubscriptionView(for: server) },
                                                    onShowSwitchConfig: { showSwitchConfigView(for: server) },
                                                    onShowCustomRules: { showCustomRulesView(for: server) },
                                                    onShowRestartService: { showRestartServiceView(for: server) }
                                                )
                                                .opacity(0.6)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .onTapGesture {
                                            HapticManager.shared.impact(.light)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // 设置卡片
                    VStack(spacing: 16) {
                        SettingsLinkRow(
                            title: "全局配置",
                            icon: "gearshape.fill",
                            iconColor: .gray,
                            destination: GlobalSettingsView()
                        )
                        
                        SettingsLinkRow(
                            title: "外观设置",
                            icon: "paintbrush.fill",
                            iconColor: .cyan,
                            destination: AppearanceSettingsView()
                        )
                        
                        SettingsLinkRow(
                            title: "运行日志",
                            icon: "doc.text.fill",
                            iconColor: .orange,
                            destination: LogsView()
                        )
                        
                        SettingsLinkRow(
                            title: "如何使用",
                            icon: "questionmark.circle.fill",
                            iconColor: .blue,
                            destination: HelpView()
                        )
                        
                        Button {
                            HapticManager.shared.impact(.light)
                            showingSourceCode = true
                        } label: {
                            HStack {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.body)
                                    .foregroundColor(.purple)
                                    .frame(width: 32)
                                
                                Text("源码查看")
                                    .font(.body)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    
                    // 版本信息
                    Text("Ver: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0") Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0")")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                        .padding(.top, 8)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Clash Dash")
            .navigationDestination(isPresented: $showQuickLaunchDestination) {
                if let server = selectedQuickLaunchServer ?? viewModel.servers.first {
                    ServerDetailView(server: server)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        HapticManager.shared.impact(.light)
                        showingAddSheet = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddServerView(viewModel: viewModel)
            }
            .sheet(item: $editingServer) { server in
                EditServerView(viewModel: viewModel, server: server)
            }
            .sheet(isPresented: $showingSourceCode) {
                if let url = URL(string: "https://github.com/bin64/Clash-Dash") {
                    SafariWebView(url: url)
                        .ignoresSafeArea()
                }
            }
            .refreshable {
                print("🔄 用户触发下拉刷新，执行服务器状态检查")
                await viewModel.checkAllServersStatus()
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
            .alert("需要位置权限来获取 Wi‑Fi 信息", isPresented: $locationManager.showLocationDeniedAlert) {
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请在“设置-隐私与安全-定位服务”中允许“使用期间访问”，并获取精确位置，或请关闭 Wi‑Fi 绑定功能")
            }
            .alert("需要本地网络权限", isPresented: $showLocalNetworkDeniedAlert) {
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请在“设置-隐私与安全-本地网络”中允许访问，以便发现并连接局域网设备")
            }
            .overlay(alignment: .bottom) {
                if showingModeChangeSuccess {
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
                }
            }
        }
        .preferredColorScheme(colorScheme)
        .onAppear {
            // print("🎬 ContentView 出现")
            // 获取当前 Wi-Fi SSID
            if enableWiFiBinding {
                logger.debug("Wi‑Fi 绑定已启用，准备检查权限并获取 Wi‑Fi 信息…")
                ensureLocalNetworkPermission()
                updateWiFiSSIDWithChecks()
            } else {
                logger.debug("Wi‑Fi 绑定功能未启用，跳过获取 Wi‑Fi 信息")
                currentWiFiSSID = ""
                UserDefaults.standard.set("", forKey: "current_ssid")
            }
            
            // 检查是否有快速启动的服务器
            _ = viewModel.servers.contains(where: { $0.isQuickLaunch })

            if let quickLaunchServer = viewModel.servers.first(where: { $0.isQuickLaunch }) {
                selectedQuickLaunchServer = quickLaunchServer
                showQuickLaunchDestination = true
                print("⚡ 检测到快速启动服务器: \(quickLaunchServer.name)，跳过首页服务器状态检查")
            } else {
                // 首次打开时刷新服务器列表（仅在没有快速启动时）
                print("🏠 首次打开App，当前在首页，执行服务器状态检查")
                Task {
                    await viewModel.checkAllServersStatus()
                }
            }
            
            viewModel.setBingingManager(bindingManager)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                // print("应用进入活动状态")
                // 从后台返回前台时刷新服务器列表和 Wi‑Fi 状态
                // 检查是否有快速启动服务器，如果有则跳过检查
                let hasQuickLaunch = viewModel.servers.contains(where: { $0.isQuickLaunch })

                if hasQuickLaunch {
                    print("⚡ 检测到快速启动服务器，从后台返回前台时跳过服务器状态检查")
                } else {
                    // 只有在首页且没有快速启动服务器时才检查状态，避免在详情页面的 Tab 中重复检查
                    print("📱 从后台返回前台，当前是否在首页: \(isOnHomeScreen)")
                    if isOnHomeScreen {
                        print("✅ 在首页，执行服务器状态检查")
                        Task {
                            await viewModel.checkAllServersStatus()
                        }
                    } else {
                        print("❌ 不在首页，跳过服务器状态检查")
                    }
                }
                
                if enableWiFiBinding {
                    logger.debug("App 回到前台，重新检查本地网络与位置权限…")
                    ensureLocalNetworkPermission()
                    updateWiFiSSIDWithChecks()
                } else {
                    // print("Wi-Fi 绑定功能未启用，跳过获取 Wi-Fi 信息")
                    currentWiFiSSID = ""
                    UserDefaults.standard.set("", forKey: "current_ssid")
                }
            }
        }
        // 监听定位授权变化后，再次尝试更新 SSID
        .onChange(of: locationManager.authorizationStatus) { newStatus in
            logger.debug("位置权限变更: \(locationAuthDescription(newStatus))")
            if enableWiFiBinding {
                updateWiFiSSIDWithChecks()
            }
        }
        // 添加对 enableWiFiBinding 变化的监听
        .onChange(of: enableWiFiBinding) { newValue in
            if newValue {
                // 功能启用时获取 Wi‑Fi 信息
                logger.debug("开启 Wi‑Fi 绑定，检查权限并获取 Wi‑Fi 信息…")
                ensureLocalNetworkPermission()
                updateWiFiSSIDWithChecks()
            } else {
                print("Wi-Fi 绑定功能已禁用，清空 Wi-Fi 信息")
                currentWiFiSSID = ""
                UserDefaults.standard.set("", forKey: "current_ssid")
            }
        }
        // 添加对 WiFiBindingManager 变化的监听
        .onChange(of: bindingManager.bindings) { newBindings in
            print("📝 Wi-Fi 绑定发生变化，新的绑定数量: \(newBindings.count)")
            logger.debug("Wi-Fi 绑定发生变化，新的绑定数量: \(newBindings.count)")
            // 强制刷新 filteredServers
            withAnimation {
                // print("触发强制刷新")
                forceRefresh.toggle()  // 切换强制刷新标志
            }
            // 刷新服务器状态
            // 只有在首页时才检查服务器状态，避免在详情页面的 Tab 中重复检查
            print("📡 Wi-Fi 绑定变化，当前是否在首页: \(isOnHomeScreen)")
            if isOnHomeScreen {
                print("✅ 在首页，因Wi-Fi绑定变化执行服务器状态检查")
                Task {
                    // print("开始刷新服务器状态")
                    await viewModel.checkAllServersStatus()
                    // print("服务器状态刷新完成")
                }
            } else {
                print("❌ 不在首页，跳过Wi-Fi绑定变化导致的服务器状态检查")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ControllersUpdated"))) { _ in
            Task { @MainActor in
                viewModel.loadServers()
                // 添加触觉反馈
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            }
        }
    }
    
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
}

struct SettingsLinkRow<Destination: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let destination: Destination
    
    var body: some View {
        NavigationLink(destination: destination) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(iconColor)
                    .frame(width: 32)
                
                Text(title)
                    .font(.body)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WiFiBindingManager())  // 为预览提供一个环境对象
}

