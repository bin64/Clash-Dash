import SwiftUI

struct ConnectionsView: View {
    let server: ClashServer
    @StateObject private var viewModel = ConnectionsViewModel()
    @StateObject private var tagViewModel = ClientTagViewModel()
    @State private var searchText = ""
    @State private var selectedProtocols: Set<String> = ["TCP", "UDP"]
    @State private var connectionFilter: ConnectionFilter = .active
    @State private var showMenu = false
    @State private var showClientTagSheet = false
    @State private var selectedConnection: ClashConnection?
    @Environment(\.floatingTabBarVisible) private var floatingTabBarVisible
    
    // 获取默认排序设置
    @AppStorage("defaultConnectionSortOption") private var defaultSortOption = DefaultConnectionSortOption.startTime
    @AppStorage("defaultConnectionSortAscending") private var defaultSortAscending = false
    
    // 修改排序状态，使用默认值初始化
    @State private var selectedSortOption: SortOption
    @State private var isAscending: Bool
    
    init(server: ClashServer) {
        self.server = server
        // 使用默认排序设置初始化状态
        let defaultOption = UserDefaults.standard.string(forKey: "defaultConnectionSortOption") ?? DefaultConnectionSortOption.startTime.rawValue
        let defaultAscending = UserDefaults.standard.bool(forKey: "defaultConnectionSortAscending")
        
        // 将DefaultConnectionSortOption转换为SortOption
        _selectedSortOption = State(initialValue: SortOption(rawValue: defaultOption) ?? .startTime)
        _isAscending = State(initialValue: defaultAscending)
    }
    
    // 添加计算属性来获取不同类型的连接数量
    private var activeConnectionsCount: Int {
        viewModel.connections.filter { $0.isAlive }.count
    }
    
    private var closedConnectionsCount: Int {
        viewModel.connections.filter { !$0.isAlive }.count
    }
    
    private var tcpConnectionsCount: Int {
        viewModel.connections.filter { connection in
            let isMatchingState = connectionFilter == .active ? connection.isAlive : !connection.isAlive
            return isMatchingState && connection.metadata.network.uppercased() == "TCP"
        }.count
    }
    
    private var udpConnectionsCount: Int {
        viewModel.connections.filter { connection in
            let isMatchingState = connectionFilter == .active ? connection.isAlive : !connection.isAlive
            return isMatchingState && connection.metadata.network.uppercased() == "UDP"
        }.count
    }
    
    // 添加确认对话框的状态
    @State private var showCloseAllConfirmation = false
    @State private var showClearClosedConfirmation = false
    @State private var showCloseFilteredConfirmation = false
    
    // 添加枚举类型
    private enum ConnectionFilter {
        case active   // 正活跃
        case closed   // 已断开
        
        var title: String {
            switch self {
            case .active: return "正活跃"
            case .closed: return "已断开"
            }
        }
    }
    
    // 添加排序类型枚举
    private enum SortOption: String, CaseIterable {
        case startTime = "开始时间"
        case download = "下载流量"
        case upload = "上传流量"
        case downloadSpeed = "下载速度"
        case uploadSpeed = "上传速度"
        
        var icon: String {
            switch self {
            case .startTime: return "clock"
            case .download: return "arrow.down.circle"
            case .upload: return "arrow.up.circle"
            case .downloadSpeed: return "arrow.down.circle.fill"
            case .uploadSpeed: return "arrow.up.circle.fill"
            }
        }
    }
    
    // 添加控制搜索栏显示的状态
    @State private var showSearch = false
    
    // 在 struct ConnectionsView 的开头添加状态变量
    @State private var showDeviceFilter = false
    @State private var selectedDevices: Set<String> = []  // 存储选中的设备ID（IP或设备名称）
    
    // 添加视图模式枚举和状态
    private enum ViewMode {
        case list
        case map
    }
    @State private var viewMode: ViewMode = .list
    
    // 添加排序 sheet 状态
    @State private var showSortSheet = false
    
    // 在 SortOption 枚举前添加 DeviceFilterButton
    private var deviceFilterButton: some View {
        Button {
            showDeviceFilter.toggle()
        } label: {
            Image(systemName: "desktopcomputer")
                .foregroundColor(selectedDevices.isEmpty ? .accentColor : .gray)
                .font(.system(size: 16))
                .frame(width: 28, height: 28)
        }
        .sheet(isPresented: $showDeviceFilter) {
            NavigationStack {
                ZStack {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    
                    ScrollView {
                        VStack(spacing: 16) {
                            let devices = getActiveDevices()
                            if devices.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                        .rotationEffect(.degrees(showDeviceFilter ? 0 : -10))
                                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: showDeviceFilter)
                                    
                                    Text("暂无设备记录")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxHeight: .infinity)
                            } else {
                                // 状态统计卡片
                                VStack(spacing: 8) {
                                    HStack(spacing: 16) {
                                        // 总设备
                                        VStack(spacing: 2) {
                                            Text("\(devices.count)")
                                                .font(.system(size: 24, weight: .medium))
                                            Text("总设备")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        
                                        // 分隔线
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 1, height: 32)
                                        
                                        // 活跃设备
                                        VStack(spacing: 2) {
                                            Text("\(devices.filter { $0.activeCount > 0 }.count)")
                                                .font(.system(size: 24, weight: .medium))
                                                .foregroundColor(.green)
                                            Text("活跃设备")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        
                                        // 分隔线
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 1, height: 32)
                                        
                                        // 已筛选
                                        VStack(spacing: 2) {
                                            Text("\(selectedDevices.count)")
                                                .font(.system(size: 24, weight: .medium))
                                                .foregroundColor(.blue)
                                            Text("已筛选")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .padding(.vertical, 12)
                                    
                                    Divider()
                                        .padding(.horizontal, -16)
                                    
                                    // 快捷操作按钮
                                    HStack(spacing: 12) {
                                        Button {
                                            withAnimation {
                                                selectedDevices.removeAll()
                                            }
                                        } label: {
                                            HStack {
                                                Image(systemName: "eye")
                                                Text("显示全部")
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.blue)
                                        
                                        Button {
                                            withAnimation {
                                                selectedDevices = Set(devices.map(\.id))
                                            }
                                        } label: {
                                            HStack {
                                                Image(systemName: "eye.slash")
                                                Text("全部隐藏")
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.red)
                                    }
                                    .padding(.horizontal, 2)
                                }
                                .padding(16)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 2)
                                .padding(.horizontal)
                                
                                // 设备列表
                                LazyVStack(spacing: 12) {
                                    ForEach(Array(devices).sorted(by: { device1, device2 in
                                        let name1 = device1.name?.lowercased() ?? device1.id.lowercased()
                                        let name2 = device2.name?.lowercased() ?? device2.id.lowercased()
                                        return name1 < name2
                                    }), id: \.id) { device in
                                        Button {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                if selectedDevices.contains(device.id) {
                                                    selectedDevices.remove(device.id)
                                                } else {
                                                    selectedDevices.insert(device.id)
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 12) {
                                                // 选中状态指示
                                                ZStack {
                                                    Circle()
                                                        .fill(selectedDevices.contains(device.id) ? Color.gray.opacity(0.1) : Color.accentColor.opacity(0.1))
                                                        .frame(width: 40, height: 40)
                                                    
                                                    Image(systemName: selectedDevices.contains(device.id) ? "eye.slash.fill" : "eye.fill")
                                                        .foregroundColor(selectedDevices.contains(device.id) ? .gray : .accentColor)
                                                        .font(.system(size: 16))
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack {
                                                        Text(device.name ?? device.id)
                                                            .font(.system(size: 16, weight: .medium))
                                                            .foregroundColor(device.activeCount > 0 ? .primary : .secondary)
                                                        
                                                        if device.activeCount > 0 {
                                                            HStack(spacing: 4) {
                                                                Circle()
                                                                    .fill(Color.green)
                                                                    .frame(width: 6, height: 6)
                                                                    .opacity(0.8)
                                                            }
                                                        }
                                                    }
                                                    
                                                    HStack(spacing: 12) {
                                                        if device.activeCount > 0 {
                                                            Text("\(device.activeCount) 个活跃连接")
                                                                .foregroundColor(.green)
                                                        } else {
                                                            Text("无活跃连接")
                                                                .foregroundColor(.secondary)
                                                        }
                                                        
                                                    
                                                            Text(device.id)
                                                                .foregroundColor(.secondary)
                                                        
                                                    }
                                                    .font(.caption)
                                                }
                                                
                                                Spacer()
                                            }
                                            .padding(12)
                                            .background(Color(.secondarySystemGroupedBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
                .navigationTitle("设备筛选")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") {
                            showDeviceFilter = false
                        }
                        .fontWeight(.medium)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    // 添加一个设备模型来存储设备信息
    private struct Device: Identifiable, Hashable {
        let id: String      // IP 地址
        let name: String?   // 设备标签名称（如果有）
        let activeCount: Int  // 活跃连接数
        
        var displayName: String {
            let baseName = name ?? id
            return "\(baseName) (\(activeCount))"
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: Device, rhs: Device) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    // 修改获取设备的方法
    private func getActiveDevices() -> Set<Device> {
        return Set(viewModel.deviceCache.map { ip in
            let activeCount = viewModel.connections.filter { 
                $0.isAlive && $0.metadata.sourceIP == ip 
            }.count
            
            return Device(
                id: ip,
                name: tagViewModel.tags.first(where: { $0.ip == ip })?.name,
                activeCount: activeCount
            )
        })
    }
    
    // 修改过滤连接的计算属性
    private var filteredConnections: [ClashConnection] {
        var connections = viewModel.connections.filter { connection in
            // 反转设备过滤条件：如果设备在选中列表中,则不显示
            let deviceMatches = !selectedDevices.contains(connection.metadata.sourceIP)
            
            // 根据连接状态过滤
            let stateMatches = connectionFilter == .active ? connection.isAlive : !connection.isAlive
            
            // 添加搜索过滤逻辑
            let searchMatches = searchText.isEmpty || {
                let searchTerm = searchText.lowercased()
                let metadata = connection.metadata
                
                // 检查源 IP 和端口
                if "\(metadata.sourceIP):\(metadata.sourcePort)".lowercased().contains(searchTerm) {
                    return true
                }
                
                // 检查主机名
                if metadata.host.lowercased().contains(searchTerm) {
                    return true
                }
                
                // 检查设备标签（如果有的话）
                if let deviceName = tagViewModel.tags.first(where: { $0.ip == metadata.sourceIP })?.name,
                   deviceName.lowercased().contains(searchTerm) {
                    return true
                }
                
                return false
            }()
            
            return deviceMatches && stateMatches && searchMatches
        }
        
        // 修改排序逻辑
        connections.sort { conn1, conn2 in
            switch selectedSortOption {
            case .startTime:
                return conn1.start.compare(conn2.start) == (isAscending ? .orderedAscending : .orderedDescending)
            case .download:
                return isAscending ? conn1.download < conn2.download : conn1.download > conn2.download
            case .upload:
                return isAscending ? conn1.upload < conn2.upload : conn1.upload > conn2.upload
            case .downloadSpeed:
                return isAscending ? conn1.downloadSpeed < conn2.downloadSpeed : conn1.downloadSpeed > conn2.downloadSpeed
            case .uploadSpeed:
                return isAscending ? conn1.uploadSpeed < conn2.uploadSpeed : conn1.uploadSpeed > conn2.uploadSpeed
            }
        }
        
        return connections
    }
    
    // 修改菜单按钮部分
    var menuButtons: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if showMenu {
                // 固定一个最小宽度以防元素长度差异导致主按钮横向被挤动
                // 根据贴纸最宽可能值估算，保证主按钮位置稳定
                Color.clear.frame(width: 1) // 保持对齐标记
                    .frame(maxWidth: 0)

                // 搜索按钮 - 添加到菜单的最上方
                StickerMenuButton(
                    text: "搜索连接",
                    icon: "magnifyingglass",
                    tint: showSearch ? .green : .blue,
                    action: {
                        withAnimation {
                            showSearch.toggle()
                            if !showSearch {
                                // 隐藏搜索栏时清空搜索内容
                                searchText = ""
                            }
                        }
                        showMenu = false
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                
                // 如果有搜索结果，显示终止筛选连接的按钮
                if !searchText.isEmpty && !filteredConnections.isEmpty {
                    StickerMenuButton(
                        text: "终止筛选",
                        icon: "xmark.circle",
                        tint: .red,
                        action: {
                            showCloseFilteredConfirmation = true
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // 暂停/继续监控
                StickerMenuButton(
                    text: viewModel.isMonitoring ? "暂停监控" : "继续监控",
                    icon: viewModel.isMonitoring ? "pause.fill" : "play.fill",
                    tint: .accentColor,
                    action: {
                        viewModel.toggleMonitoring()
                        showMenu = false
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                
                // 客户端标签
                StickerMenuButton(
                    text: "客户端标签",
                    icon: "tag.fill",
                    tint: .blue,
                    action: {
                        showClientTagSheet = true
                        showMenu = false
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                
                // 刷新视图
                StickerMenuButton(
                    text: "刷新",
                    icon: "arrow.clockwise",
                    tint: .green,
                    action: {
                        Task {
                            await viewModel.refresh()
                        }
                        showMenu = false
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                
                // 清理已断开连接
                StickerMenuButton(
                    text: "清理已断开连接",
                    icon: "trash.fill",
                    tint: .orange,
                    action: {
                        showClearClosedConfirmation = true
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                
                // 终止所有连接
                StickerMenuButton(
                    text: "打断全部连接",
                    icon: "xmark.circle.fill",
                    tint: .red,
                    action: {
                        showCloseAllConfirmation = true
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // 修改主按钮的旋转角度
            Button(action: {
                HapticManager.shared.impact(.light)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showMenu.toggle()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 48, height: 48)
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                        .overlay {
                            Image(systemName: "ellipsis")
                                .rotationEffect(.degrees(showMenu ? 90 : 0))
                                .foregroundColor(.accentColor)
                                .font(.system(size: 24, weight: .semibold))
                        }
                }
            }
        }
        .alert("确定清理已断开连接", isPresented: $showClearClosedConfirmation) {
            Button("取消", role: .cancel) { }
            Button("清理", role: .destructive) {
                viewModel.clearClosedConnections()
                showMenu = false
            }
        } message: {
            Text("确定要清除所有已断开的连接吗？\n这将从列表中移除 \(closedConnectionsCount) 个已断开的连接。")
        }
        .alert("确认终止所有连接", isPresented: $showCloseAllConfirmation) {
            Button("取消", role: .cancel) { }
            Button("终止", role: .destructive) {
                viewModel.closeAllConnections()
                showMenu = false
            }
        } message: {
            Text("确定要终止所有活跃的连接吗？\n这将断开 \(activeConnectionsCount) 个正在活跃的连接。")
        }
        .alert("确认终止筛选连接", isPresented: $showCloseFilteredConfirmation) {
            Button("取消", role: .cancel) { }
            Button("终止", role: .destructive) {
                let connectionIds = filteredConnections.map { $0.id }
                viewModel.closeConnections(connectionIds)
                showMenu = false
            }
        } message: {
            Text("确定要终止筛选出的连接吗？\n这将断开 \(filteredConnections.count) 个连接。")
        }
    }
    
    // 修改过滤标签组件
    struct FilterTag: View {
        let title: String
        let count: Int
        let isSelected: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(title)
                        .foregroundColor(.blue)
                        .font(.system(size: 12, weight: .medium))
                    Text("(\(count))")
                        .foregroundColor(.blue)
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(height: 28)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.15))
                )
                .opacity(isSelected ? 1.0 : 0.6)
            }
            .buttonStyle(.plain)
        }
    }
    
    // 修改过滤标签栏
    var filterBar: some View {
        HStack(spacing: 6) {
            // 连接状态切换器
            Picker("连接状态", selection: $connectionFilter) {
                Text("正活跃 (\(activeConnectionsCount))")
                    .tag(ConnectionFilter.active)
                Text("已断开 (\(closedConnectionsCount))")
                    .tag(ConnectionFilter.closed)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            
            Spacer(minLength: 0)
            
            // 添加视图模式切换按钮
            Button(action: {
                withAnimation {
                    viewMode = viewMode == .list ? .map : .list
                }
            }) {
                Image(systemName: viewMode == .list ? "map" : "list.bullet")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 16))
                    .frame(width: 28, height: 28)
            }
            
            // 添加设备过滤按钮
            deviceFilterButton
            
            // 排序按钮
            Button {
                showSortSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: selectedSortOption.icon)
                        .foregroundColor(.accentColor)
                        .font(.system(size: 16))
                    Image(systemName: isAscending ? "chevron.up" : "chevron.down")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 12))
                }
                .frame(width: 48, height: 28)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }
    
    // 精致小巧的排序选择器
    private var sortSheetView: some View {
        VStack(spacing: 0) {
            // 精美的顶部装饰
            VStack(spacing: 12) {
                // 标题区域
                HStack(spacing: 12) {
                    // 装饰图标
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("排序方式")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("\(selectedSortOption.rawValue) • \(isAscending ? "升序" : "降序")")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            // 选项卡片列表
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedSortOption == option {
                                    isAscending.toggle()
                                } else {
                                    selectedSortOption = option
                                    isAscending = false
                                }
                            }
                        } label: {
                            HStack(spacing: 14) {
                                // 精美图标设计
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            selectedSortOption == option ? 
                                            LinearGradient(
                                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ) :
                                            LinearGradient(
                                                colors: [Color(.systemGray6), Color(.systemGray5)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 36, height: 36)
                                        .shadow(
                                            color: selectedSortOption == option ? 
                                            Color.accentColor.opacity(0.3) : Color.black.opacity(0.05),
                                            radius: selectedSortOption == option ? 4 : 2,
                                            x: 0,
                                            y: selectedSortOption == option ? 2 : 1
                                        )
                                    
                                    Image(systemName: option.icon)
                                        .foregroundColor(selectedSortOption == option ? .white : .accentColor)
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                
                                // 文字内容
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(option.rawValue)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.primary)
                                    
                                    if selectedSortOption == option {
                                        Text(isAscending ? "升序排列" : "降序排列")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                // 状态指示器
                                if selectedSortOption == option {
                                    HStack(spacing: 6) {
                                        // 方向切换按钮
                                        Button {
                                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                                isAscending.toggle()
                                            }
                                        } label: {
                                            ZStack {
                                                Circle()
                                                    .fill(isAscending ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                                                    .frame(width: 28, height: 28)
                                                
                                                Image(systemName: isAscending ? "arrow.up" : "arrow.down")
                                                    .foregroundColor(isAscending ? .blue : .orange)
                                                    .font(.system(size: 12, weight: .bold))
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        
                                        // 选中指示
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                            .font(.system(size: 18))
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemBackground))
                                    .shadow(
                                        color: Color.black.opacity(selectedSortOption == option ? 0.08 : 0.03),
                                        radius: selectedSortOption == option ? 8 : 3,
                                        x: 0,
                                        y: selectedSortOption == option ? 3 : 1
                                    )
                            )
                            .scaleEffect(selectedSortOption == option ? 1.02 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
    }
    
    private func EmptyStateView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("暂无连接")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("当前没有活跃的网络连接")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // 连接状态栏
                HStack {
                    // 状态信息
                    Image(systemName: viewModel.connectionState.statusIcon)
                        .foregroundColor(viewModel.connectionState.statusColor)
                        .rotationEffect(viewModel.connectionState.isConnecting ? .degrees(360) : .degrees(0))
                        .animation(viewModel.connectionState.isConnecting ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.connectionState)
                    
                    Text(viewModel.connectionState.message)
                        .font(.footnote)
                    
                    if viewModel.connectionState.isConnecting {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    
                    Spacer()
                    
                    // 流量统计
                    HStack(spacing: 12) {
                        Label(viewModel.formatBytes(viewModel.totalDownload), systemImage: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                        Label(viewModel.formatBytes(viewModel.totalUpload), systemImage: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                    }
                    .font(.footnote)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(viewModel.connectionState.statusColor.opacity(0.1))
                
                // 过滤标签栏
                filterBar
                
                // 搜索栏 - 有条件地显示
                if showSearch {
                    SearchBar(text: $searchText, placeholder: "搜索 IP、端口、主机名、设备标签")
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                if viewModel.connections.isEmpty {
                    EmptyStateView()
                } else {
                    if viewMode == .list {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredConnections) { connection in
                                    if viewModel.connectionRowStyle == .modern {
                                        ModernConnectionRow(
                                            connection: connection,
                                            viewModel: viewModel,
                                            tagViewModel: tagViewModel,
                                            onClose: {
                                                HapticManager.shared.impact(.light)
                                                viewModel.closeConnection(connection.id)
                                            },
                                            selectedConnection: $selectedConnection
                                        )
                                    } else {
                                        ConnectionRow(
                                            connection: connection,
                                            viewModel: viewModel,
                                            tagViewModel: tagViewModel,
                                            onClose: {
                                                HapticManager.shared.impact(.light)
                                                viewModel.closeConnection(connection.id)
                                            },
                                            selectedConnection: $selectedConnection
                                        )
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: filteredConnections)
                        }
                        .background(Color(.systemGroupedBackground))
                    } else {
                        // 地图视图
                        ConnectionMapView(
                            connections: viewModel.connections,
                            isActiveMode: connectionFilter == .active,
                            searchText: searchText,
                            selectedDevices: selectedDevices
                        )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemGroupedBackground))
                    }
                }
            }
            
            menuButtons
                .padding(.trailing, 16)
                .padding(.top, 16)
                .padding(.bottom, floatingTabBarVisible ? 104 : 16)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .animation(.easeInOut(duration: 0.3), value: floatingTabBarVisible)
        }
        .sheet(item: $selectedConnection) { connection in
            NavigationStack {
                ZStack {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                    
                    ConnectionDetailView(
                        connection: connection,
                        viewModel: viewModel
                    )
                }
                .navigationTitle("连接详情")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDragIndicator(.visible)
            .presentationDetents([.large])
        }
        .onAppear {
            viewModel.startMonitoring(server: server)
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
        .sheet(isPresented: $showClientTagSheet) {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                NavigationStack {
                    ClientTagView(
                        viewModel: viewModel,
                        tagViewModel: tagViewModel
                    )
                }
            }
        }
        .sheet(isPresented: $showSortSheet) {
            sortSheetView
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

// 菜单按钮组件
struct MenuButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            action()
        }) {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 40, height: 40)
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                .overlay {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 14, weight: .semibold))
                }
        }
    }
}

// 贴纸样式的菜单子项（文字 + 图标）
struct StickerMenuButton: View {
    let text: String
    let icon: String
    var tint: Color = .blue
    var action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.impact(.light)
            action()
        }) {
            StickerTagView(
                text: text,
                systemImage: icon,
                tint: tint,
                rotation: .degrees(-3),
                iconPosition: .trailing,
                contentPadding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10),
                textFont: .system(size: 13, weight: .medium),
                iconFont: .system(size: 14, weight: .semibold),
                cornerRadius: 12,
                shadowRadius: 6,
                shadowOpacity: 0.04
            )
        }
        .buttonStyle(.plain)
    }
}

// 添加自定义搜索栏组件
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    NavigationStack {
        ConnectionsView(
            server: ClashServer(
                name: "测试服务器",
                url: "10.1.1.2",
                port: "9090",
                secret: "123456"
            )
        )
    }
} 
