import SwiftUI
import NetworkExtension

/// 侧边栏视图 - 用于大屏设备的导航
struct SidebarView: View {
    @ObservedObject var viewModel: ServerViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @Binding var selectedServer: ClashServer?
    @Binding var selectedSidebarItem: SidebarItem?
    @Binding var showingAddSheet: Bool
    @Binding var editingServer: ClashServer?
    
    // 模式切换成功回调
    var onModeChange: ((String) -> Void)?
    var onShowConfigSubscription: ((ClashServer) -> Void)?
    var onShowSwitchConfig: ((ClashServer) -> Void)?
    var onShowCustomRules: ((ClashServer) -> Void)?
    var onShowRestartService: ((ClashServer) -> Void)?
    
    // WiFi相关
    @State private var currentWiFiSSID: String = ""
    @State private var forceRefresh: Bool = false
    @AppStorage("hideDisconnectedServers") private var hideDisconnectedServers = false
    @AppStorage("enableWiFiBinding") private var enableWiFiBinding = false
    @EnvironmentObject private var bindingManager: WiFiBindingManager
    
    // 状态管理
    @State private var showHiddenServers = false
    @State private var showingSourceCode = false
    
    // 私有计算属性
    private var filteredServers: [ClashServer] {
        _ = forceRefresh
        return viewModel.servers.filter { server in
            !viewModel.isServerHidden(server, currentWiFiSSID: currentWiFiSSID)
        }
    }
    
    private var hiddenServers: [ClashServer] {
        return viewModel.servers.filter { server in
            viewModel.isServerHidden(server, currentWiFiSSID: currentWiFiSSID)
        }
    }
    
        var body: some View {
        List {
            // 服务器分组
            Section("控制器") {
                if viewModel.servers.isEmpty {
                    // 空状态
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.title2)
                            .foregroundColor(.secondary.opacity(0.7))
                        
                        Text("没有控制器")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            HapticManager.shared.impact(.light)
                            showingAddSheet = true
                        }) {
                            Label("添加控制器", systemImage: "plus.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                } else if filteredServers.isEmpty && !viewModel.servers.isEmpty {
                    // 过滤状态
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash")
                            .font(.title2)
                            .foregroundColor(.secondary.opacity(0.7))
                        
                        if hideDisconnectedServers {
                            Text("所有控制器已被自动隐藏")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("当前 Wi-Fi 下没有绑定的控制器")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                } else {
                    // 正常服务器列表
                    ForEach(filteredServers) { server in
                        SidebarServerRow(
                            server: server,
                            isSelected: selectedServer?.id == server.id,
                            visibleServersCount: filteredServers.count,
                            onEdit: { editingServer = server },
                            viewModel: viewModel,
                            settingsViewModel: settingsViewModel,
                            onModeChange: onModeChange,
                            onShowConfigSubscription: onShowConfigSubscription,
                            onShowSwitchConfig: onShowSwitchConfig,
                            onShowCustomRules: onShowCustomRules,
                            onShowRestartService: onShowRestartService
                        )
                        .onTapGesture {
                            selectedServer = server
                            selectedSidebarItem = .server(server.id)
                            HapticManager.shared.impact(.light)
                        }
                    }
                    
                    // 隐藏的服务器
                    if !hiddenServers.isEmpty {
                        // 自定义展开/收起按钮，避免与List的selection冲突
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showHiddenServers.toggle()
                                HapticManager.shared.impact(.light)
                            }
                        }) {
                            HStack(spacing: 10) {
                                // 左侧：眼睛图标
                                ZStack {
                                    Circle()
                                        .fill(Color.gray.opacity(0.1))
                                        .frame(width: 24, height: 24)
                                    
                                    Image(systemName: "eye.slash")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                                
                                // 中间：文字信息
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("隐藏的控制器")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                    
                                    Text("\(hiddenServers.count) 个项目")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary.opacity(0.7))
                                }
                                
                                Spacer()
                                
                                // 右侧：展开箭头
                                Image(systemName: showHiddenServers ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .rotationEffect(.degrees(showHiddenServers ? 0 : 0))
                                    .animation(.easeInOut(duration: 0.2), value: showHiddenServers)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.gray.opacity(0.08),
                                                Color.gray.opacity(0.04)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 隐藏服务器列表
                        if showHiddenServers {
                            ForEach(hiddenServers) { server in
                                                                                                    SidebarServerRow(
                                    server: server,
                                    isSelected: selectedServer?.id == server.id,
                                    isHidden: true,
                                    visibleServersCount: filteredServers.count + hiddenServers.count,
                                    onEdit: { editingServer = server },
                                    viewModel: viewModel,
                                    settingsViewModel: settingsViewModel,
                                    onModeChange: onModeChange,
                                    onShowConfigSubscription: onShowConfigSubscription,
                                    onShowSwitchConfig: onShowSwitchConfig,
                                    onShowCustomRules: onShowCustomRules,
                                    onShowRestartService: onShowRestartService
                                )
                                .onTapGesture {
                                    selectedServer = server
                                    selectedSidebarItem = .server(server.id)
                                    HapticManager.shared.impact(.light)
                                }
                                .padding(.leading, 12) // 增加缩进显示层级
                            }
                        }
                    }
                }
            }
            
            // 设置分组
            Section("设置") {
                SidebarSettingsRow(
                    title: "全局配置",
                    icon: "gearshape.fill",
                    iconColor: .gray,
                    item: .globalSettings,
                    isSelected: selectedSidebarItem == .globalSettings
                )
                .onTapGesture {
                    selectedServer = nil
                    selectedSidebarItem = .globalSettings
                    HapticManager.shared.impact(.light)
                }
                
                SidebarSettingsRow(
                    title: "外观设置",
                    icon: "paintbrush.fill",
                    iconColor: .cyan,
                    item: .appearanceSettings,
                    isSelected: selectedSidebarItem == .appearanceSettings
                )
                .onTapGesture {
                    selectedServer = nil
                    selectedSidebarItem = .appearanceSettings
                    HapticManager.shared.impact(.light)
                }
                
                SidebarSettingsRow(
                    title: "运行日志",
                    icon: "doc.text.fill",
                    iconColor: .orange,
                    item: .logs,
                    isSelected: selectedSidebarItem == .logs
                )
                .onTapGesture {
                    selectedServer = nil
                    selectedSidebarItem = .logs
                    HapticManager.shared.impact(.light)
                }
                
                SidebarSettingsRow(
                    title: "如何使用",
                    icon: "questionmark.circle.fill",
                    iconColor: .blue,
                    item: .help,
                    isSelected: selectedSidebarItem == .help
                )
                .onTapGesture {
                    selectedServer = nil
                    selectedSidebarItem = .help
                    HapticManager.shared.impact(.light)
                }
                
                // 查看源码 - 直接打开网页，样式与其他设置项保持一致
                Button {
                    HapticManager.shared.impact(.light)
                    showingSourceCode = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.body)
                            .foregroundColor(.purple)
                            .frame(width: 20)
                        
                        Text("源码查看")
                            .font(.subheadline)
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
            }
        }
        .listStyle(SidebarListStyle())
        .navigationTitle("Clash Dash")
        .overlay(
            // 版本信息（左下角，完全透明背景）
            VStack {
                Spacer()
                HStack {
                    Text("Ver: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0") Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0")")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.4))
                        .monospacedDigit()
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .allowsHitTesting(false) // 不阻挡下方的交互
        )
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
        .onAppear {
            updateWiFiStatus()
            Task {
                await viewModel.checkAllServersStatus()
            }
            
            // 设置默认选择
            if selectedSidebarItem == nil {
                if let firstServer = filteredServers.first {
                    selectedServer = firstServer
                    selectedSidebarItem = .server(firstServer.id)
                } else {
                    selectedSidebarItem = .globalSettings
                }
            }
        }
        .onChange(of: enableWiFiBinding) { newValue in
            updateWiFiStatus()
        }
        .onChange(of: bindingManager.bindings) { _ in
            withAnimation {
                forceRefresh.toggle()
            }
            Task {
                await viewModel.checkAllServersStatus()
            }
        }
        .refreshable {
            await viewModel.checkAllServersStatus()
        }

        .sheet(isPresented: $showingSourceCode) {
            if let url = URL(string: "https://github.com/bin64/Clash-Dash") {
                SafariWebView(url: url)
                    .ignoresSafeArea()
            }
        }
    }
    
    private func updateWiFiStatus() {
        if enableWiFiBinding {
            NEHotspotNetwork.fetchCurrent { network in
                DispatchQueue.main.async {
                    if let network = network {
                        currentWiFiSSID = network.ssid
                        UserDefaults.standard.set(network.ssid, forKey: "current_ssid")
                        viewModel.logWiFiBindingSummary(currentWiFiSSID: network.ssid)
                    } else {
                        currentWiFiSSID = ""
                        UserDefaults.standard.set("", forKey: "current_ssid")
                        viewModel.logWiFiBindingSummary(currentWiFiSSID: "")
                    }
                }
            }
        } else {
            currentWiFiSSID = ""
            UserDefaults.standard.set("", forKey: "current_ssid")
            viewModel.logWiFiBindingSummary(currentWiFiSSID: "")
        }
    }
}

/// 侧边栏项目枚举
enum SidebarItem: Hashable, Identifiable {
    case server(UUID)
    case globalSettings
    case appearanceSettings
    case logs
    case help
    
    var id: String {
        switch self {
        case .server(let id):
            return "server-\(id)"
        case .globalSettings:
            return "global-settings"
        case .appearanceSettings:
            return "appearance-settings"
        case .logs:
            return "logs"
        case .help:
            return "help"
        }
    }
}

/// 侧边栏服务器行视图
struct SidebarServerRow: View {
    let server: ClashServer
    let isSelected: Bool
    let isHidden: Bool
    let visibleServersCount: Int  // 可见服务器数量
    let onEdit: () -> Void
    @ObservedObject var viewModel: ServerViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    
    // 回调函数
    let onModeChange: ((String) -> Void)?
    let onShowConfigSubscription: ((ClashServer) -> Void)?
    let onShowSwitchConfig: ((ClashServer) -> Void)?
    let onShowCustomRules: ((ClashServer) -> Void)?
    let onShowRestartService: ((ClashServer) -> Void)?
    
    init(server: ClashServer, 
         isSelected: Bool, 
         isHidden: Bool = false,
         visibleServersCount: Int,
         onEdit: @escaping () -> Void, 
         viewModel: ServerViewModel, 
         settingsViewModel: SettingsViewModel,
         onModeChange: ((String) -> Void)? = nil,
         onShowConfigSubscription: ((ClashServer) -> Void)? = nil,
         onShowSwitchConfig: ((ClashServer) -> Void)? = nil,
         onShowCustomRules: ((ClashServer) -> Void)? = nil,
         onShowRestartService: ((ClashServer) -> Void)? = nil) {
        self.server = server
        self.isSelected = isSelected
        self.isHidden = isHidden
        self.visibleServersCount = visibleServersCount
        self.onEdit = onEdit
        self.viewModel = viewModel
        self.settingsViewModel = settingsViewModel
        self.onModeChange = onModeChange
        self.onShowConfigSubscription = onShowConfigSubscription
        self.onShowSwitchConfig = onShowSwitchConfig
        self.onShowCustomRules = onShowCustomRules
        self.onShowRestartService = onShowRestartService
    }
    
    // 计算是否应该显示选中状态
    private var shouldShowSelection: Bool {
        // 始终根据选中状态显示，让用户清楚看到当前选中的控制器
        return isSelected
    }
    
    // 计算未选中状态的透明度和缩放
    private var unselectedStyle: (opacity: Double, scale: Double) {
        if isSelected {
            return (1.0, 1.0)
        } else {
            // 未选中的控制器稍微降低透明度和缩放，增强视觉层次
            return (0.75, 0.96)
        }
    }
    
    // 自定义选中配色方案，避免系统强调色影响
    private var selectionColors: (background: [Color], border: [Color], accent: Color) {
        #if targetEnvironment(macCatalyst)
        // Mac专用配色：使用更突出的蓝色渐变
        return (
            background: [Color(red: 0.94, green: 0.96, blue: 1.0), Color(red: 0.88, green: 0.93, blue: 0.99)],
            border: [Color(red: 0.6, green: 0.75, blue: 0.95), Color(red: 0.45, green: 0.65, blue: 0.9)],
            accent: Color(red: 0.2, green: 0.45, blue: 0.85)
        )
        #else
        // iOS配色：使用更鲜明的蓝色渐变
        return (
            background: [Color(red: 0.90, green: 0.94, blue: 1.0), Color(red: 0.82, green: 0.90, blue: 0.98)],
            border: [Color(red: 0.5, green: 0.7, blue: 0.95), Color(red: 0.35, green: 0.6, blue: 0.9)],
            accent: Color(red: 0.15, green: 0.4, blue: 0.85)
        )
        #endif
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // 左侧：服务器类型图标 + 状态指示器
            ZStack {
                // 背景圆形
                Circle()
                    .fill(
                        shouldShowSelection 
                        ? (server.status == .ok ? Color.green.opacity(0.2) : selectionColors.accent.opacity(0.15))
                        : (server.status == .ok ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                    )
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .stroke(
                                shouldShowSelection 
                                ? (server.status == .ok ? Color.green.opacity(0.3) : selectionColors.accent.opacity(0.4))
                                : Color.clear,
                                lineWidth: shouldShowSelection ? 1 : 0
                            )
                    )
                    .scaleEffect(shouldShowSelection ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: shouldShowSelection)
                
                // 服务器类型图标
                Image(systemName: server.source == .clashController ? "server.rack" : server.luciPackage == .openClash ? "o.square" : "n.square")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(
                        shouldShowSelection 
                        ? (server.status == .ok ? .green : selectionColors.accent)
                        : (server.status == .ok ? .green : .gray)
                    )
                    .animation(.easeInOut(duration: 0.2), value: shouldShowSelection)
                
                // 状态指示器（右上角小圆点）
                if server.status == .ok {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .offset(x: 9, y: -9)
                        .shadow(color: Color.green.opacity(0.3), radius: shouldShowSelection ? 2 : 0)
                        .animation(.easeInOut(duration: 0.2), value: shouldShowSelection)
                }
            }
            
            // 中间：服务器信息
            VStack(alignment: .leading, spacing: 1) {
                // 服务器名称
                HStack(spacing: 4) {
                    Text(server.name.isEmpty ? server.url : server.name)
                        .font(.system(size: 13, weight: shouldShowSelection ? .semibold : .medium))
                        .foregroundColor(
                            isHidden ? .secondary : 
                            shouldShowSelection ? selectionColors.accent : .primary.opacity(0.8)
                        )
                        .lineLimit(1)
                        .animation(.easeInOut(duration: 0.2), value: shouldShowSelection)
                    
                    // 快速启动图标
                    if server.isQuickLaunch {
                        Image(systemName: "bolt.circle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.yellow)
                            .shadow(color: .yellow.opacity(0.3), radius: 1)
                    }
                    
                    Spacer()
                }
                
                // 服务器地址和类型
                HStack(spacing: 4) {
                    Text("\(server.url):\(server.port)")
                        .font(.system(size: 11))
                        .foregroundColor(shouldShowSelection ? .secondary : .secondary.opacity(0.7))
                        .lineLimit(1)
                    
                    if server.status == .ok {
                        // 类型标签
                        Text(server.source == .clashController ? "Clash" : server.luciPackage == .openClash ? "OpenClash" : "Nikki")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(
                                shouldShowSelection 
                                ? (server.status == .ok ? .green : selectionColors.accent)
                                : (server.status == .ok ? .green : .gray)
                            )
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(
                                        shouldShowSelection
                                        ? (server.status == .ok ? Color.green.opacity(0.2) : selectionColors.accent.opacity(0.15))
                                        : (server.status == .ok ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                                    )
                            )
                            .animation(.easeInOut(duration: 0.2), value: shouldShowSelection)
                    }
                    
                    Spacer()
                }
            }
            
            // 右侧：连接状态
            if server.status == .ok {
                Image(systemName: "wifi.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(shouldShowSelection ? .green : .green.opacity(0.7))
                    .scaleEffect(shouldShowSelection ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: shouldShowSelection)
            } else if server.status == .error {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(shouldShowSelection ? .red : .red.opacity(0.7))
                    .scaleEffect(shouldShowSelection ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: shouldShowSelection)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            // 精致的选中效果背景
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: shouldShowSelection ? 
                            selectionColors.background : [Color.clear, Color.clear]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: shouldShowSelection ? 
                                    selectionColors.border : [Color.clear, Color.clear]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: shouldShowSelection ? 1 : 0
                        )
                )
                .shadow(
                    color: shouldShowSelection ? selectionColors.accent.opacity(0.2) : Color.clear,
                    radius: shouldShowSelection ? 4 : 0,
                    x: 0,
                    y: shouldShowSelection ? 2 : 0
                )
                .scaleEffect(shouldShowSelection ? 1.02 : unselectedStyle.scale)
                .animation(.easeInOut(duration: 0.25), value: shouldShowSelection)
        )
        .opacity(isHidden ? 0.6 : unselectedStyle.opacity)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .serverContextMenu(
            viewModel: viewModel,
            settingsViewModel: settingsViewModel,
            server: server,
            showMoveOptions: false, // 在侧边栏中禁用移动选项
            onEdit: onEdit,
            onModeChange: { mode in onModeChange?(mode) },
            onShowConfigSubscription: { onShowConfigSubscription?(server) },
            onShowSwitchConfig: { onShowSwitchConfig?(server) },
            onShowCustomRules: { onShowCustomRules?(server) },
            onShowRestartService: { onShowRestartService?(server) }
        )
    }
}

/// 侧边栏设置行视图
struct SidebarSettingsRow: View {
    let title: String
    let icon: String
    let iconColor: Color
    let item: SidebarItem
    let isSelected: Bool
    
    // 自定义选中配色方案，与SidebarServerRow保持一致
    private var selectionColors: (background: [Color], border: [Color], accent: Color) {
        #if targetEnvironment(macCatalyst)
        // Mac专用配色：使用更突出的蓝色渐变
        return (
            background: [Color(red: 0.94, green: 0.96, blue: 1.0), Color(red: 0.88, green: 0.93, blue: 0.99)],
            border: [Color(red: 0.6, green: 0.75, blue: 0.95), Color(red: 0.45, green: 0.65, blue: 0.9)],
            accent: Color(red: 0.2, green: 0.45, blue: 0.85)
        )
        #else
        // iOS配色：使用更鲜明的蓝色渐变
        return (
            background: [Color(red: 0.90, green: 0.94, blue: 1.0), Color(red: 0.82, green: 0.90, blue: 0.98)],
            border: [Color(red: 0.5, green: 0.7, blue: 0.95), Color(red: 0.35, green: 0.6, blue: 0.9)],
            accent: Color(red: 0.15, green: 0.4, blue: 0.85)
        )
        #endif
    }
    
    // 计算未选中状态的缩放（设置项目保持正常透明度）
    private var unselectedScale: Double {
        return isSelected ? 1.02 : 1.0
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(isSelected ? selectionColors.accent : iconColor)
                .frame(width: 20)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
            
            // 标题
            Text(title)
                .font(.system(.subheadline, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? selectionColors.accent : .primary)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
            
            Spacer()
        }
        .padding(.vertical, 4)
        .background(
            // 精致的选中效果背景
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: isSelected ? 
                            selectionColors.background : [Color.clear, Color.clear]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: isSelected ? 
                                    selectionColors.border : [Color.clear, Color.clear]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: isSelected ? 1 : 0
                        )
                )
                .shadow(
                    color: isSelected ? selectionColors.accent.opacity(0.2) : Color.clear,
                    radius: isSelected ? 4 : 0,
                    x: 0,
                    y: isSelected ? 2 : 0
                )
                .scaleEffect(unselectedScale)
                .animation(.easeInOut(duration: 0.25), value: isSelected)
        )
    }
}

#Preview {
    NavigationSplitView {
        SidebarView(
            viewModel: ServerViewModel(),
            settingsViewModel: SettingsViewModel(),
            selectedServer: .constant(nil),
            selectedSidebarItem: .constant(nil),
            showingAddSheet: .constant(false),
            editingServer: .constant(nil),
            onModeChange: { _ in },
            onShowConfigSubscription: { _ in },
            onShowSwitchConfig: { _ in },
            onShowCustomRules: { _ in },
            onShowRestartService: { _ in }
        )
        .environmentObject(WiFiBindingManager())
    } detail: {
        Text("选择一个项目")
            .foregroundColor(.secondary)
    }
} 