import SwiftUI

struct MultiColumnProxyView: View {
    let server: ClashServer
    @StateObject private var viewModel: ProxyViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedGroup: ProxyGroup?
    @AppStorage("allowManualURLTestGroupSwitch") private var allowManualURLTestGroupSwitch = false
    @State private var showURLTestAlert = false
    
    // 计算每行显示的列数
    private var columnsCount: Int {
        // 根据设备尺寸和方向动态调整列数
        switch horizontalSizeClass {
        case .compact:
            return 2 // iPhone 竖屏
        case .regular:
            return 4 // iPad 或 iPhone 横屏
        default:
            return 2
        }
    }
    
    init(server: ClashServer) {
        self.server = server
        self._viewModel = StateObject(wrappedValue: ProxyViewModel(server: server))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 24) {
                    if viewModel.groups.isEmpty {
                        LoadingView()
                    } else {
                        // 代理组网格
                        let columns = makeColumns(availableWidth: geometry.size.width)
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.getSortedGroups(), id: \.name) { group in
                                MultiColumnGroupCard(group: group, viewModel: viewModel, containerWidth: geometry.size.width)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        HapticManager.shared.impact(.light)
                                        selectedGroup = group
                                    }
                            }
                        }
                        .padding(.horizontal)
                        
                        // 代理提供者部分
                        if !UserDefaults.standard.bool(forKey: "hideProxyProviders") {
                            let httpProviders = viewModel.providers
                                .filter { ["HTTP", "FILE"].contains($0.vehicleType.uppercased()) }
                                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                            
                            if !httpProviders.isEmpty {
                                VStack(alignment: .leading, spacing: 16) {
                                    Text("代理提供者")
                                        .font(.system(.title3, design: .rounded))
                                        .fontWeight(.semibold)
                                        .padding(.horizontal)
                                    
                                    LazyVGrid(columns: columns, spacing: 16) {
                                        ForEach(httpProviders, id: \.name) { provider in
                                            MultiColumnProviderCard(
                                                provider: provider,
                                                nodes: viewModel.providerNodes[provider.name] ?? [],
                                                viewModel: viewModel,
                                                containerWidth: geometry.size.width
                                            )
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await viewModel.fetchProxies()
        }
        .task {
            await viewModel.fetchProxies()
        }
        .sheet(item: $selectedGroup) { group in
            NavigationStack {
                GeometryReader { sheetGeometry in
                    ScrollView {
                        let columns = makeSheetColumns(availableWidth: sheetGeometry.size.width)
                        
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(group.all.indices, id: \.self) { index in
                                let nodeName = group.all[index]
                                ProxyNodeCard(
                                    nodeName: nodeName,
                                    node: viewModel.nodes.first { $0.name == nodeName },
                                    isSelected: viewModel.groups.first(where: { $0.name == group.name })?.now == nodeName,
                                    isTesting: viewModel.testingNodes.contains(nodeName),
                                    viewModel: viewModel
                                )
                                .onTapGesture {
                                    HapticManager.shared.impact(.light)
                                    
                                    if group.type == "URLTest" && !allowManualURLTestGroupSwitch {
                                        // 显示不支持手动切换的提示
                                        showURLTestAlert = true
                                        HapticManager.shared.notification(.error)
                                        return
                                    }
                                    
                                    Task {
                                        await viewModel.selectProxy(groupName: group.name, proxyName: nodeName)
                                        await MainActor.run {
                                            // 添加成功的触觉反馈
                                            HapticManager.shared.notification(.success)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .navigationTitle(group.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Task {
                                    await viewModel.testGroupSpeed(groupName: group.name)
                                }
                            } label: {
                                Label("测速", systemImage: "bolt.horizontal")
                            }
                        }
                        
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") {
                                selectedGroup = nil
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("自动测速选择分组", isPresented: $showURLTestAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("该分组不支持手动切换节点，可在全局设置中启用手动切换")
        }
    }
    
    // 修改辅助方法
    private func makeColumns(availableWidth: CGFloat) -> [GridItem] {
        let horizontalPadding: CGFloat = 32 // 左右总边距
        let spacing: CGFloat = 16 // 卡片之间的间距
        let minCardWidth: CGFloat = 160
        let maxCardWidth: CGFloat = 200
        
        let width = availableWidth - horizontalPadding
        let optimalColumnCount = max(2, Int(width / (minCardWidth + spacing)))
        let cardWidth = min(maxCardWidth, (width - (CGFloat(optimalColumnCount - 1) * spacing)) / CGFloat(optimalColumnCount))
        
        return Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: optimalColumnCount)
    }
    
    private func makeSheetColumns(availableWidth: CGFloat) -> [GridItem] {
        let horizontalPadding: CGFloat = 32
        let spacing: CGFloat = 12
        let minCardWidth: CGFloat = 160
        let maxCardWidth: CGFloat = 200
        
        let width = availableWidth - horizontalPadding
        let optimalColumnCount = max(2, Int(width / (minCardWidth + spacing)))
        let cardWidth = min(maxCardWidth, (width - (CGFloat(optimalColumnCount - 1) * spacing)) / CGFloat(optimalColumnCount))
        
        return Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: optimalColumnCount)
    }
}

// 修改卡片视图
struct MultiColumnGroupCard: View {
    let group: ProxyGroup
    @ObservedObject var viewModel: ProxyViewModel
    let containerWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardDimensions: (width: CGFloat, height: CGFloat) {
        let horizontalPadding: CGFloat = 32
        let spacing: CGFloat = 16
        let minCardWidth: CGFloat = 160
        let maxCardWidth: CGFloat = 200
        
        let width = containerWidth - horizontalPadding
        let optimalColumnCount = max(2, Int(width / (minCardWidth + spacing)))
        let cardWidth = min(maxCardWidth, (width - (CGFloat(optimalColumnCount - 1) * spacing)) / CGFloat(optimalColumnCount))
        
        return (width: cardWidth, height: 100)
    }
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground)
    }
    
    var body: some View {
        CardContent(group: group, viewModel: viewModel)
            .padding(12)
            .frame(width: cardDimensions.width, height: cardDimensions.height)
            .background(CardBackground(group: group, backgroundColor: cardBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                radius: 10,
                x: 0,
                y: 4
            )
            .scaleEffect(viewModel.testingGroups.contains(group.name) ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.testingGroups.contains(group.name))
            .contentShape(Rectangle())
    }
}

// 添加卡片内容视图
private struct CardContent: View {
    let group: ProxyGroup
    @ObservedObject var viewModel: ProxyViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 顶部区域：名称
            HStack {
                Text(group.name)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if group.type == "URLTest" {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption2)
                } else if group.type == "LoadBalance" {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.blue)
                        .font(.caption2)
                }
                
                Spacer(minLength: 0)
            }
            
            Spacer()
            
            // 底部区域：当前选中的节点
            VStack(alignment: .leading, spacing: 4) {
                // 分隔线
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 1)
                
                // 节点信息
                HStack(alignment: .center) {
                    if viewModel.testingGroups.contains(group.name) {
                        DelayTestingView()
                            .foregroundStyle(.blue)
                            .scaleEffect(0.7)
                    } else {
                        // 节点名称
                        if group.type == "LoadBalance" {
                            Text("负载均衡")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(group.now)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

// 添加卡片背景视图
private struct CardBackground: View {
    let group: ProxyGroup
    let backgroundColor: Color
    @Environment(\.colorScheme) private var colorScheme
    
    // 添加辅助函数来处理名称
    private var displayInfo: (icon: String, name: String) {
        let name = group.name
        guard let firstScalar = name.unicodeScalars.first,
              firstScalar.properties.isEmoji else {
            return (String(name.prefix(1)).uppercased(), name)
        }
        
        // 如果第一个字符是 emoji，将其作为图标
        let emoji = String(name.unicodeScalars.prefix(1))
        let remainingName = name.dropFirst()
        return (emoji, String(remainingName).trimmingCharacters(in: .whitespaces))
    }
    
    // 添加动态颜色生成
    private var iconColor: Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal]
        let hash = abs(group.name.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        ZStack {
            // 底层卡片背景
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
            
            // 图标或首字母作为背景
            GeometryReader { geo in
                Group {
                    if let iconUrl = group.icon, !iconUrl.isEmpty {
                        // 图标容器
                        ZStack {
                            // 背景光晕
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            iconColor.opacity(0.2),
                                            iconColor.opacity(0.05),
                                            .clear
                                        ],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: geo.size.width * 0.4
                                    )
                                )
                                .frame(width: geo.size.width * 1.2, height: geo.size.width * 1.2)
                            
                            // 主图标
                            CachedAsyncImage(url: iconUrl)
                                .frame(width: geo.size.width * 0.7, height: geo.size.width * 0.7)
                                .shadow(color: iconColor.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .opacity(colorScheme == .dark ? 0.3 : 0.4)
                    } else {
                        Text(displayInfo.icon)
                            .font(.system(size: geo.size.width * 0.6, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        iconColor,
                                        iconColor.opacity(0.7)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(colorScheme == .dark ? 0.2 : 0.25)
                    }
                }
                .position(
                    x: geo.size.width * 0.7,
                    y: geo.size.height * 0.5
                )
                .rotationEffect(Angle(degrees: -10))
            }
            
            // 顶部渐变效果
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            backgroundColor.opacity(0.95),
                            backgroundColor.opacity(0.85),
                            backgroundColor.opacity(0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    // 添加微妙的光泽效果
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(colorScheme == .dark ? 0.05 : 0.1),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                }
        }
    }
}

// 修改提供者卡片视图
struct MultiColumnProviderCard: View {
    let provider: Provider
    let nodes: [ProxyNode]
    @ObservedObject var viewModel: ProxyViewModel
    let containerWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @State private var isUpdating = false
    @State private var showingUpdateSuccess = false
    @State private var showingSheet = false
    
    private var cardDimensions: (width: CGFloat, height: CGFloat) {
        let horizontalPadding: CGFloat = 32
        let spacing: CGFloat = 16
        let minCardWidth: CGFloat = 160
        let maxCardWidth: CGFloat = 200
        
        let width = containerWidth - horizontalPadding
        let optimalColumnCount = max(2, Int(width / (minCardWidth + spacing)))
        let cardWidth = min(maxCardWidth, (width - (CGFloat(optimalColumnCount - 1) * spacing)) / CGFloat(optimalColumnCount))
        
        return (width: cardWidth, height: 100)
    }
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground)
    }
    
    // 获取更新时间
    private var updateTime: String? {
        guard let updatedAt = provider.updatedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let updateDate = formatter.date(from: updatedAt) ?? Date()
        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .short
        return relativeFormatter.localizedString(for: updateDate, relativeTo: Date())
    }
    
    // 添加辅助函数来处理名称
    private var displayInfo: (icon: String, name: String) {
        let name = provider.name
        guard let firstScalar = name.unicodeScalars.first,
              firstScalar.properties.isEmoji else {
            return (String(name.prefix(1)).uppercased(), name)
        }
        let emoji = String(name.unicodeScalars.prefix(1))
        let remainingName = name.dropFirst()
        return (emoji, String(remainingName).trimmingCharacters(in: .whitespaces))
    }
    
    // 添加缺失的计算属性
    private var usageInfo: String? {
        let currentProvider = viewModel.providers.first { $0.name == provider.name } ?? provider
        guard let info = currentProvider.subscriptionInfo,
              info.total > 0 || info.upload > 0 || info.download > 0 else { return nil }
        let used = Double(info.upload + info.download)
        return "\(formatBytes(Int64(used))) / \(formatBytes(info.total))"
    }
    
    private var timeInfo: (update: String, expire: String)? {
        let currentProvider = viewModel.providers.first { $0.name == provider.name } ?? provider
        guard let updatedAt = currentProvider.updatedAt else { return nil }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let updateDate = formatter.date(from: updatedAt) ?? Date()
        
        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .short
        
        if let info = currentProvider.subscriptionInfo,
           info.expire > 0 || info.total > 0 || info.upload > 0 || info.download > 0 {
            return (
                update: relativeFormatter.localizedString(for: updateDate, relativeTo: Date()),
                expire: info.expire > 0 ? formatExpireDate(info.expire) : ""
            )
        }
        
        return (
            update: relativeFormatter.localizedString(for: updateDate, relativeTo: Date()),
            expire: ""
        )
    }
    
    // 添加辅助格式化函数
    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        
        if gb >= 1 {
            return String(format: "%.0fGB", gb)
        } else if mb >= 1 {
            return String(format: "%.0fMB", mb)
        } else if kb >= 1 {
            return String(format: "%.0fKB", kb)
        } else {
            return "\(bytes)B"
        }
    }
    
    private func formatExpireDate(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 顶部：名称和类型
            HStack {
                Text(provider.name)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer(minLength: 0)
                
                // 添加更新按钮
                Button {
                    Task {
                        HapticManager.shared.impact(.light)
                        isUpdating = true
                        
                        await withTaskCancellationHandler {
                            await viewModel.updateProxyProvider(providerName: provider.name)
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            await viewModel.fetchProxies()
                            
                            await MainActor.run {
                                HapticManager.shared.notification(.success)
                                isUpdating = false
                                withAnimation {
                                    showingUpdateSuccess = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation {
                                        showingUpdateSuccess = false
                                    }
                                }
                            }
                        } onCancel: {
                            Task { @MainActor in
                                isUpdating = false
                                HapticManager.shared.notification(.error)
                            }
                        }
                    }
                } label: {
                    Group {
                        if isUpdating {
                            ProgressView()
                                .tint(.blue)
                                .scaleEffect(0.7)
                        } else if showingUpdateSuccess {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(width: 20, height: 20)
                }
                .disabled(isUpdating)
            }
            
            Spacer()
            
            // 底部：流量信息和节点数量
            VStack(alignment: .leading, spacing: 4) {
                // 分隔线
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 1)
                
                // 流量信息
                HStack(alignment: .center) {
                    if isUpdating {
                        DelayTestingView()
                            .foregroundStyle(.blue)
                            .scaleEffect(0.7)
                    } else {
                        if let usage = usageInfo {
                            Text(usage)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("无流量信息")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    Text("\(nodes.count)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: cardDimensions.width, height: cardDimensions.height)
        .background(ProviderCardBackground(provider: provider, backgroundColor: cardBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
            radius: 10,
            x: 0,
            y: 4
        )
        .scaleEffect(isUpdating ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isUpdating)
        .onTapGesture {
            HapticManager.shared.impact(.light)
            showingSheet = true
        }
        .sheet(isPresented: $showingSheet) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        // 详细信息卡片
                        VStack(alignment: .leading, spacing: 12) {
                            if let usage = usageInfo {
                                HStack {
                                    Text("流量使用")
                                        .font(.headline)
                                    Spacer()
                                    Text(usage)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            if let times = timeInfo {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("更新时间")
                                            .font(.headline)
                                        Spacer()
                                        Text(times.update)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    if !times.expire.isEmpty {
                                        HStack {
                                            Text("到期时间")
                                                .font(.headline)
                                            Spacer()
                                            Text(times.expire)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        // 节点列表
                        LazyVGrid(columns: makeSheetColumns(), spacing: 12) {
                            ForEach(nodes) { node in
                                ProxyNodeCard(
                                    nodeName: node.name,
                                    node: node,
                                    isSelected: false,
                                    isTesting: viewModel.testingNodes.contains(node.name),
                                    viewModel: viewModel
                                )
                                .onTapGesture {
                                    HapticManager.shared.impact(.light)
                                    Task {
                                        await viewModel.healthCheckProviderProxy(
                                            providerName: provider.name,
                                            proxyName: node.name
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle(provider.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await viewModel.healthCheckProvider(providerName: provider.name)
                            }
                        } label: {
                            Label("测速", systemImage: "bolt.horizontal")
                        }
                    }
                    
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") {
                            showingSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    private func makeSheetColumns() -> [GridItem] {
        let screenWidth = UIScreen.main.bounds.width
        let spacing: CGFloat = 12
        let minCardWidth: CGFloat = 160
        let maxCardWidth: CGFloat = 200
        
        let columnsCount = max(2, Int(screenWidth / (minCardWidth + spacing * 2)))
        return Array(repeating: GridItem(.flexible(minimum: minCardWidth, maximum: maxCardWidth), spacing: spacing), count: columnsCount)
    }
}

// 重命名提供者卡片背景
private struct ProviderCardBackground: View {
    let provider: Provider
    let backgroundColor: Color
    @Environment(\.colorScheme) private var colorScheme
    
    // 添加辅助函数来处理名称
    private var displayInfo: (icon: String, name: String) {
        let name = provider.name
        guard let firstScalar = name.unicodeScalars.first,
              firstScalar.properties.isEmoji else {
            return (String(name.prefix(1)).uppercased(), name)
        }
        let emoji = String(name.unicodeScalars.prefix(1))
        let remainingName = name.dropFirst()
        return (emoji, String(remainingName).trimmingCharacters(in: .whitespaces))
    }
    
    // 添加动态颜色生成
    private var iconColor: Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .green, .teal]
        let hash = abs(provider.name.hashValue)
        return colors[hash % colors.count]
    }
    
    var body: some View {
        ZStack {
            // 底层卡片背景
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
            
            // 图标或首字母作为背景
            GeometryReader { geo in
                Text(displayInfo.icon)
                    .font(.system(size: geo.size.width * 0.6, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                iconColor,
                                iconColor.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(colorScheme == .dark ? 0.2 : 0.25)
                    .position(
                        x: geo.size.width * 0.7,
                        y: geo.size.height * 0.5
                    )
                    .rotationEffect(Angle(degrees: -10))
            }
            
            // 顶部渐变效果
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            backgroundColor.opacity(0.95),
                            backgroundColor.opacity(0.85),
                            backgroundColor.opacity(0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    // 添加微妙的光泽效果
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(colorScheme == .dark ? 0.05 : 0.1),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                }
        }
    }
}

#Preview {
    MultiColumnProxyView(server: ClashServer(name: "测试服务器", url: "192.168.1.1", port: "9090", secret: "123456"))
} 
