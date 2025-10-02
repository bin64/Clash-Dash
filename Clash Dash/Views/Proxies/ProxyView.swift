import SwiftUI

// 添加到文件顶部，在 LoadingView 之前
struct CardBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    var cardBackgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray5) : Color(.secondarySystemBackground)
    }
    
    func body(content: Content) -> some View {
        content
            .background(cardBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.05 : 0.1), radius: colorScheme == .dark ? 2 : 4, x: 0, y: 1)
    }
}

extension View {
    func cardBackground() -> some View {
        modifier(CardBackgroundModifier())
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("加载中")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// 首先添加一个图片缓存管理器
class ImageCache {
    static let shared = ImageCache()
    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private var diskCacheCount: Int = 0
    private let maxMemoryCount = 30  // 进一步减少内存缓存数量
    private let queue = DispatchQueue(label: "com.clashdash.imagecache", qos: .utility)
    
    private var cacheDirectory: URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("ImageCache")
    }
    
    private init() {
        memoryCache.countLimit = maxMemoryCount
        
        // 在后台队列中创建缓存目录
        queue.async {
            if let cacheDir = self.cacheDirectory {
                try? self.fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            }
            self.updateDiskCacheCount()
        }
    }
    
    var count: Int {
        return diskCacheCount
    }
    
    private func updateDiskCacheCount() {
        guard let cacheDir = cacheDirectory else { return }
        diskCacheCount = (try? fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil))?.count ?? 0
    }
    
    func set(_ image: UIImage, for url: String) {
        let key = url as NSString
        memoryCache.setObject(image, forKey: key)
        
        // 保存到磁盘
        guard let data = image.pngData(),
              let cacheDir = cacheDirectory else { return }
        
        let fileURL = cacheDir.appendingPathComponent(key.hash.description)
        try? data.write(to: fileURL)
        
        // 更新缓存计数
        updateDiskCacheCount()
    }
    
    func get(_ url: String) -> UIImage? {
        let key = url as NSString
        
        // 先从内存缓存中查找
        if let cachedImage = memoryCache.object(forKey: key) {
            return cachedImage
        }
        
        // 从磁盘加载
        guard let cacheDir = cacheDirectory else { return nil }
        let fileURL = cacheDir.appendingPathComponent(key.hash.description)
        
        if let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            // 加载成功后保存到内存缓存
            memoryCache.setObject(image, forKey: key)
            return image
        }
        
        return nil
    }
    
    func removeAll() {
        // 清除内存缓存
        memoryCache.removeAllObjects()
        
        // 清除磁盘缓存
        guard let cacheDir = cacheDirectory else { return }
        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        // 更新缓存计数
        diskCacheCount = 0
    }
}


// 添加 AsyncImagePhase 枚举
enum AsyncImagePhase {
    case empty
    case success(Image)
    case failure(Error)
}

// 创建一个自定义的缓存图片视图
struct CachedAsyncImage: View {
    let url: String
    @State private var phase: AsyncImagePhase = .empty
    
    var body: some View {
        Group {
            switch phase {
            case .empty:
                // 开始加载时检查缓存
                Color.clear
                    .onAppear {
                        loadImage()
                    }
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                EmptyView()
            @unknown default:
                EmptyView()
            }
        }
    }
    
    private func loadImage() {
        // 首先检查缓存
        if let cachedImage = ImageCache.shared.get(url) {
            self.phase = .success(Image(uiImage: cachedImage))
            return
        }
        
        // 如果缓存中没有，则下载图片
        guard let imageURL = URL(string: url) else {
            self.phase = .failure(URLError(.badURL))
            return
        }
        
        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.phase = .failure(error)
                }
                return
            }
            
            guard let data = data,
                  let downloadedImage = UIImage(data: data) else {
                DispatchQueue.main.async {
                    self.phase = .failure(URLError(.cannotDecodeContentData))
                }
                return
            }
            
            // 保存到缓存
            ImageCache.shared.set(downloadedImage, for: url)
            
            // 在主线程更新 UI
            DispatchQueue.main.async {
                self.phase = .success(Image(uiImage: downloadedImage))
            }
        }.resume()
    }
}



struct ProxyView: View {
    let server: ClashServer
    @StateObject private var viewModel: ProxyViewModel
    @State private var selectedGroupId: String?
    @State private var isRefreshing = false
    @State private var showProviderSheet = false
    @Namespace private var animation
    @AppStorage("proxyViewStyle") private var proxyViewStyle = ProxyViewStyle.detailed
    @AppStorage("hideProxyProviders") private var hideProxyProviders = false
    
    // 添加触觉反馈生成器
    
    
    init(server: ClashServer) {
        self.server = server
        self._viewModel = StateObject(wrappedValue: ProxyViewModel(server: server))
    }
    
    var body: some View {
        Group {
            switch proxyViewStyle {
            case .detailed:
                ScrollView {
                    LazyVStack(spacing: 20) {
                        if viewModel.groups.isEmpty {
                            LoadingView()
                        } else {
                            VStack(spacing: 20) {
                                ProxyGroupsOverview(groups: viewModel.getSortedGroups(), viewModel: viewModel)
                                    .drawingGroup(opaque: false)
                                
                                if !hideProxyProviders {
                                    let httpProviders = viewModel.providers
                                        .filter { ["HTTP", "FILE"].contains($0.vehicleType.uppercased()) }
                                        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                                    
                                    if !httpProviders.isEmpty {
                                        ProxyProvidersSection(
                                            providers: httpProviders,
                                            nodes: viewModel.providerNodes,
                                            viewModel: viewModel
                                        )
                                        .drawingGroup(opaque: false)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                .background(Color(.systemGroupedBackground))
                .refreshable {
                    await refreshData()
                }
            case .compact:
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.getSortedGroups(), id: \.name) { group in
                            CompactGroupCard(group: group, viewModel: viewModel)
                        }
                        .padding(.horizontal)
                        
                        if !hideProxyProviders {
                            let httpProviders = viewModel.providers
                                .filter { ["HTTP", "FILE"].contains($0.vehicleType.uppercased()) }
                                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                            
                            if !httpProviders.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("代理提供者")
                                        .font(.headline)
                                        .padding(.horizontal)
                                    
                                    LazyVStack(spacing: 12) {
                                        ForEach(httpProviders, id: \.name) { provider in
                                            CompactProviderCard(
                                                provider: provider,
                                                nodes: viewModel.providerNodes[provider.name] ?? [],
                                                viewModel: viewModel
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
                .background(Color(.systemGroupedBackground))
                .refreshable {
                    await refreshData()
                }
            case .multiColumn:
                MultiColumnProxyView(server: server)
            case .zash:
                ZashProxyView(server: server)
            }
        }
        .task {
            await viewModel.fetchProxies()
        }
    }
    
    private func refreshData() async {
        withAnimation(.easeInOut(duration: 0.2)) {
            isRefreshing = true
        }
        await viewModel.fetchProxies()
        withAnimation(.easeInOut(duration: 0.2)) {
            isRefreshing = false
        }
        
        HapticManager.shared.notification(.success)
    }
    
    private func sortNodes(_ nodeNames: [String], _ allNodes: [ProxyNode], groupName: String) -> [ProxyNode] {
        let specialNodes = ["DIRECT", "REJECT"]
        var matchedNodes = nodeNames.compactMap { name in
            if specialNodes.contains(name) {
                if let existingNode = allNodes.first(where: { $0.name == name }) {
                    return existingNode
                }
                return ProxyNode(
                    id: UUID().uuidString,
                    name: name,
                    type: "Special",
                    alive: true,
                    delay: 0,
                    history: []
                )
            }
            return allNodes.first { $0.name == name }
        }
        
        // 检查是否需要隐藏不可用代理
        let hideUnavailable = UserDefaults.standard.bool(forKey: "hideUnavailableProxies")
        if hideUnavailable {
            matchedNodes = matchedNodes.filter { node in
                specialNodes.contains(node.name) || node.delay > 0
            }
        }
        
        return matchedNodes.sorted { node1, node2 in
            if node1.name == "DIRECT" { return true }
            if node2.name == "DIRECT" { return false }
            if node1.name == "REJECT" { return true }
            if node2.name == "REJECT" { return false }
            if node1.name == groupName { return true }
            if node2.name == groupName { return false }
            
            if node1.delay == 0 { return false }
            if node2.delay == 0 { return true }
            return node1.delay < node2.delay
        }
    }
}

// 代理组概览卡片
struct ProxyGroupsOverview: View {
    let groups: [ProxyGroup]
    @ObservedObject var viewModel: ProxyViewModel
    
    var body: some View {
        LazyVStack(spacing: 16) {
            ForEach(groups, id: \.name) { group in
                GroupCard(group: group, viewModel: viewModel)
                    .drawingGroup(opaque: false)  // 优化渲染
            }
        }
    }
}

// 单个代理组卡片
struct GroupCard: View {
    let group: ProxyGroup
    @ObservedObject var viewModel: ProxyViewModel
    @State private var showingProxySelector = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground)
    }
    
    private var delayStats: (green: Int, yellow: Int, red: Int, timeout: Int, unknown: Int) {
        var green = 0
        var yellow = 0
        var red = 0
        var timeout = 0
        var unknown = 0
        
        let hideUnavailable = UserDefaults.standard.bool(forKey: "hideUnavailableProxies")
        
        for nodeName in group.all {
            // 使用 viewModel 的方法获取延迟
            let delay = viewModel.getNodeDelay(nodeName: nodeName)
            
            if hideUnavailable && delay <= 0 && !["DIRECT", "REJECT"].contains(nodeName) {
                continue
            }
            
            switch delay {
            case -1: unknown += 1
            case 0: timeout += 1
            case DelayColor.lowRange: green += 1
            case DelayColor.mediumRange: yellow += 1
            default: red += 1
            }
        }
        
        return (green, yellow, red, timeout, unknown)
    }
    
    private var totalNodes: Int {
        let hideUnavailable = UserDefaults.standard.bool(forKey: "hideUnavailableProxies")
        
        if hideUnavailable {
            return group.all.filter { nodeName in
                if ["DIRECT", "REJECT"].contains(nodeName) {
                    return true
                }
                let delay = viewModel.getNodeDelay(nodeName: nodeName)
                return delay > 0 // 只显示有有效延迟的节点
            }.count
        } else {
            return group.all.count
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 标题行
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        // 使用新的缓存图片组件
                        if let iconUrl = group.icon {
                            CachedAsyncImage(url: iconUrl)
                                .frame(width: 16, height: 16)
                        }
                        
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
                        } else if group.type == "Smart" {
                            if #available(iOS 18.0, *) {
                                Image(systemName: "apple.intelligence")
                                    .foregroundStyle(.blue)
                                    .font(.caption2)
                            } else {
                                Image(systemName: "wand.and.rays.inverse")
                                    .foregroundStyle(.blue)
                                    .font(.caption2)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // 节点数量标签
                Text("\(totalNodes) 个节点")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
            }
            
            Divider()
                .padding(.horizontal, -12)
            
            // 当前节点信息
            HStack(spacing: 6) {
                Image(systemName: getNodeIcon(for: group.now))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                
                if viewModel.testingGroups.contains(group.name) {
                    DelayTestingView()
                        .foregroundStyle(.blue)
                        .scaleEffect(0.7)
                } else {
                    // 获取实际节点的延迟
                    let (_, finalDelay) = viewModel.getActualNodeAndDelay(nodeName: group.now)
                    
                    // 显示当前状态
                    if group.type == "LoadBalance" {
                        Text("负载均衡")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        // 显示直接选中的节点名称
                        Text(group.now)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        
                        // 显示实际节点的延迟
                        if finalDelay > 0 {
                            Text("\(finalDelay) ms")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(DelayColor.color(for: finalDelay).opacity(0.1))
                                .foregroundStyle(DelayColor.color(for: finalDelay))
                                .clipShape(Capsule())
                        } else if finalDelay == 0 {
                            Text("超时")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(DelayColor.color(for: finalDelay).opacity(0.1))
                                .foregroundStyle(DelayColor.color(for: finalDelay))
                                .clipShape(Capsule())
                        } else {
                            Text("未知")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(DelayColor.color(for: finalDelay).opacity(0.1))
                                .foregroundStyle(DelayColor.color(for: finalDelay))
                                .clipShape(Capsule())
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            // 使用新的延迟统计条
            DelayBar(
                green: delayStats.green,
                yellow: delayStats.yellow,
                red: delayStats.red,
                timeout: delayStats.timeout,
                unknown: delayStats.unknown,
                total: totalNodes
            )
            .padding(.horizontal, 2)
        }
        .padding(12)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)
        .drawingGroup(opaque: false)  // 优化渲染
        .onTapGesture {
            // 添加触觉反馈
            HapticManager.shared.impact(.light)
            
            // 显示选择器
            showingProxySelector = true
        }
        .sheet(isPresented: $showingProxySelector) {
            ProxySelectorSheet(
                group: group,
                viewModel: viewModel
            )
        }
    }
    
    private func getStatusColor(for nodeName: String) -> Color {
        switch nodeName {
        case "DIRECT":
            return .green
        case "REJECT":
            return .red
        default:
            return .blue
        }
    }
    
    private func getNodeIcon(for nodeName: String) -> String {
        switch nodeName {
        case "DIRECT":
            return "arrow.up.forward"
        case "REJECT":
            return "xmark.circle"
        default:
            if let node = viewModel.nodes.first(where: { $0.name == nodeName }) {
                switch node.type.lowercased() {
                case "ss", "shadowsocks":
                    return "bolt.shield"
                case "vmess":
                    return "v.circle"
                case "trojan":
                    return "shield.lefthalf.filled"
                case "http", "https":
                    return "globe"
                case "socks", "socks5":
                    return "network"
                default:
                    return "antenna.radiowaves.left.and.right"
                }
            }
            return "antenna.radiowaves.left.and.right"
        }
    }
}

// 代理提供者部分
struct ProxyProvidersSection: View {
    let providers: [Provider] // 这里已经是过滤后的提供者
    let nodes: [String: [ProxyNode]]
    @ObservedObject var viewModel: ProxyViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("代理提供者")
                .font(.title2.bold())
            
            ForEach(providers.sorted(by: { $0.name < $1.name })) { provider in
                // let _ = print("📦 显示订阅提供者: \(provider.name)")
                ProxyProviderCard(
                    provider: provider,
                    nodes: nodes[provider.name] ?? [],
                    viewModel: viewModel
                )
            }
        }
    }
}

// 修改 ProxyProviderCard
struct ProxyProviderCard: View {
    let provider: Provider
    let nodes: [ProxyNode]
    @ObservedObject var viewModel: ProxyViewModel
    @State private var isUpdating = false
    @State private var updateStatus: UpdateStatus = .none
    @State private var selectedProvider: Provider?
    @Environment(\.colorScheme) private var colorScheme

    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground)
    }
    
    // 添加更新状态枚举
    private enum UpdateStatus {
        case none
        case updating
        case success
        case failure
    }
    
    // 添加计算属性获取最新的提供者数据
    private var currentProvider: Provider {
        viewModel.providers.first { $0.name == provider.name } ?? provider
    }
    
    // 添加触觉反馈生成器
    
    
    private var trafficInfo: (used: String, total: String, percentage: Double)? {
        guard let info = currentProvider.subscriptionInfo,
              // 添加判断：只有当总流量不为 0 时才显示流量信息
              info.total > 0 else { return nil }
        let used = Double(info.upload + info.download)
        let total = Double(info.total)
        
        // 安全计算剩余流量百分比，确保值在合理范围内
        guard used.isFinite && total.isFinite && total > 0 else { return nil }
        let remaining = max(0, total - used) // 确保剩余流量不为负数
        let percentage = min(100, max(0, (remaining / total) * 100)) // 确保百分比在 0-100 范围内
        
        return (formatBytes(Int64(used)), formatBytes(info.total), percentage)
    }
    
    private var relativeUpdateTime: String {
        guard let updatedAt = currentProvider.updatedAt else {
            // print("Provider \(provider.name) updatedAt is nil")
            return "从未更新"
        }
        
        // print("Provider \(provider.name) updatedAt: \(updatedAt)")
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: updatedAt) else {
            // print("Failed to parse date: \(updatedAt)")
            return "未知"
        }
        
        let interval = Date().timeIntervalSince(date)
        
        switch interval {
        case 0..<60:
            return "刚刚"
        case 60..<3600:
            let minutes = Int(interval / 60)
            return "\(minutes) 分钟前"
        case 3600..<86400:
            let hours = Int(interval / 3600)
            return "\(hours) 小时前"
        case 86400..<604800:
            let days = Int(interval / 86400)
            return "\(days) 天前"
        case 604800..<2592000:
            let weeks = Int(interval / 604800)
            return "\(weeks) 周前"
        default:
            let months = Int(interval / 2592000)
            return "\(months) 个月前"
        }
    }
    
    private var expirationDate: String? {
        guard let info = currentProvider.subscriptionInfo,
              // 添加判断：只有当总流量不为 0 时才显示到期时间
              info.total > 0 && info.expire > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(info.expire))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(provider.name)
                            .font(.headline)
                        
                        Text(provider.vehicleType)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    
                    // 更新时间
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("更新时间：\(relativeUpdateTime)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 操作按钮
                HStack(spacing: 12) {
                    Button {
                        Task {
                            // 添加触觉反馈
                            HapticManager.shared.impact(.light)
                            
                            // print("Updating provider: \(provider.name)")
                            updateStatus = .updating
                            
                            do {
                                await viewModel.updateProxyProvider(providerName: provider.name)
                                updateStatus = .success
                                // 成功的触觉反馈
                                
                                HapticManager.shared.notification(.success)
                                
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                                updateStatus = .none
                            } catch {
                                // print("Provider update failed: \(error)")
                                updateStatus = .failure
                                // 失败时的触觉反馈
                                
                                HapticManager.shared.notification(.error) 
                                
                                try await Task.sleep(nanoseconds: 2_000_000_000)
                                updateStatus = .none
                            }
                            
                            await viewModel.fetchProxies()
                        }
                    } label: {
                        Group {
                            switch updateStatus {
                            case .none:
                                Image(systemName: "arrow.clockwise")
                            case .updating:
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.gray)
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .failure:
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(width: 20, height: 20) // 固定大小避免图标切换时的跳动
                    }
                    .disabled(updateStatus != .none)
                    .animation(.spring(), value: updateStatus)
                    
                    Button {
                        // 添加触觉反馈
                        HapticManager.shared.impact(.light)
                        
                        // print("Opening node selector for provider: \(provider.name)")
                        selectedProvider = provider
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
            }
            
            
            
            // 到期时间
            if let expireDate = expirationDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text("到期时间：\(expireDate)")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            // 流量信息
            if let (used, total, percentage) = trafficInfo {
                VStack(alignment: .leading, spacing: 8) {
                    // 流量进度条
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {  // 修改为右对齐
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(.systemGray5))
                                .frame(height: 4)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(getTrafficColor(percentage: percentage))
                                .frame(width: max(0, min(geometry.size.width, geometry.size.width * CGFloat(max(0, min(percentage, 100))) / 100)), height: 4)
                        }
                    }
                    .frame(height: 4)
                    
                    // 流量信息
                    HStack {
                        Text("\(used) / \(total)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(String(format: "剩余 %.1f%%", percentage))  // 修改文字显示为剩余百分比
                            .font(.caption)
                            .foregroundColor(getTrafficColor(percentage: percentage))
                    }
                }
            }
        }
        .padding(12)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)
        .onTapGesture {
            // 添加触觉反馈
            HapticManager.shared.impact(.light)
            
            // print("Opening node selector for provider: \(provider.name)")
            selectedProvider = provider
        }
        .sheet(item: $selectedProvider) { provider in
            ProviderNodeSelector(
                provider: provider,
                nodes: nodes,
                viewModel: viewModel
            )
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
    
    private func getTrafficColor(percentage: Double) -> Color {
        if percentage > 50 {  // 修改颜色判断逻辑
            return .green
        } else if percentage > 20 {
            return .yellow
        } else {
            return .red
        }
    }
}

// 添加节点选择 Sheet
struct ProviderNodeSelector: View {
    let provider: Provider
    let nodes: [ProxyNode]
    @ObservedObject var viewModel: ProxyViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isTestingAll = false
    @State private var testingNodes = Set<String>()
    
    // 添加触觉反馈生成器
    
    
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(nodes) { node in
                        ProxyNodeCard(
                            nodeName: node.name,
                            node: node,
                            isSelected: false,
                            isTesting: testingNodes.contains(node.name) || isTestingAll,
                            viewModel: viewModel
                        )
                        .onTapGesture {
                            // 添加触觉反馈
                            HapticManager.shared.impact(.light)
                            
                            Task {
                                // print("Testing node: \(node.name) in provider: \(provider.name)")
                                testingNodes.insert(node.name)
                                
                                await withTaskCancellationHandler {
                                    await viewModel.healthCheckProviderProxy(
                                        providerName: provider.name,
                                        proxyName: node.name
                                    )
                                    await viewModel.fetchProxies()
                                    await MainActor.run {
                                        testingNodes.remove(node.name)
                                        HapticManager.shared.notification(.success)
                                    }
                                } onCancel: {
                                    Task { @MainActor in
                                        testingNodes.remove(node.name)
                                        HapticManager.shared.notification(.error)
                                    }
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
                        // 添加触觉反馈
                        HapticManager.shared.impact(.light)
                        
                        Task {
                            // print("Testing all nodes in provider: \(provider.name)")
                            await MainActor.run {
                                isTestingAll = true
                            }
                            
                            await withTaskCancellationHandler {
                                await viewModel.healthCheckProvider(providerName: provider.name)
                                await viewModel.fetchProxies()
                                await MainActor.run {
                                    isTestingAll = false
                                    HapticManager.shared.notification(.success)
                                }
                            } onCancel: {
                                Task { @MainActor in
                                    isTestingAll = false
                                    HapticManager.shared.notification(.error)
                                }
                            }
                        }
                    } label: {
                        if isTestingAll {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Label("测速", systemImage: "bolt.horizontal")
                        }
                    }
                    .disabled(isTestingAll)
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        // 添加触觉反馈
                        HapticManager.shared.impact(.light)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// 其他辅助视图和法保持不变...

struct ProvidersSheetView: View {
    let providers: [Provider]
    let nodes: [String: [ProxyNode]]
    @ObservedObject var viewModel: ProxyViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(providers.sorted(by: { $0.name < $1.name })) { provider in
                    Section(provider.name) {
                        if let nodes = nodes[provider.name] {
                            ForEach(nodes) { node in
                                HStack {
                                    Text(node.name)
                                    Spacer()
                                    if node.delay > 0 {
                                        Text("\(node.delay) ms")
                                            .foregroundStyle(getDelayColor(node.delay))
                                    } else {
                                        Text("超时")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("代理提供者")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func getDelayColor(_ delay: Int) -> Color {
        DelayColor.color(for: delay)
    }
}

struct ScrollClipModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.scrollClipDisabled()
        } else {
            content
        }
    }
}

// 修改 ProxySelectorSheet 使用网格布局
struct ProxySelectorSheet: View {
    let group: ProxyGroup
    @ObservedObject var viewModel: ProxyViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showURLTestAlert = false
    @AppStorage("proxyGroupSortOrder") private var proxyGroupSortOrder = ProxyGroupSortOrder.default
    @AppStorage("allowManualURLTestGroupSwitch") private var allowManualURLTestGroupSwitch = false
    
    // 添加计算属性来获取可用节点
    private var availableNodes: [String] {
        let hideUnavailable = UserDefaults.standard.bool(forKey: "hideUnavailableProxies")
        
        // 使用保存的节点顺序
        let nodes = viewModel.savedNodeOrder[group.name] ?? group.all
        
        // 只进行隐藏过滤，不重新排序
        return nodes.filter { nodeName in
            if ["DIRECT", "REJECT", "PROXY"].contains(nodeName) {
                return true
            }
            
            if hideUnavailable {
                let delay = viewModel.getNodeDelay(nodeName: nodeName)
                return delay > 0
            }
            
            return true
        }
    }
    
    // 递归检查代理组是否包含实际节点
    private func hasActualNodes(in group: ProxyGroup, visitedGroups: Set<String>) -> Bool {
        var visited = visitedGroups
        visited.insert(group.name)
        
        for nodeName in group.all {
            // 如果是特殊节点，返回 true
            if ["DIRECT", "REJECT"].contains(nodeName) {
                return true
            }
            
            // 如果是已访问过的代理组，跳过以避免循环
            if visited.contains(nodeName) {
                continue
            }
            
            // 如果是代理组，递归检查
            if let subGroup = viewModel.groups.first(where: { $0.name == nodeName }) {
                if hasActualNodes(in: subGroup, visitedGroups: visited) {
                    return true
                }
            } else {
                // 不是代理组，认为是实际节点
                return true
            }
        }
        
        return false
    }
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading) {
                    // 节点计
                    HStack {
                        Text("节点列表")
                            .font(.headline)
                        Spacer()
                        Text("\(availableNodes.count) 个节点")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // 节点网格
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(availableNodes, id: \.self) { nodeName in
                            let node = viewModel.nodes.first { $0.name == nodeName }
                            
                            ProxyNodeCard(
                                nodeName: nodeName,
                                node: node,
                                isSelected: group.now == nodeName,
                                isTesting: node.map { viewModel.testingNodes.contains($0.id) } ?? false,
                                viewModel: viewModel
                            )
                            .onTapGesture {
                                // 添加触觉反馈
                                
                                HapticManager.shared.impact(.light)
                                
                                if group.type == "URLTest" && !allowManualURLTestGroupSwitch {
                                    showURLTestAlert = true
                                } else {
                                    Task {
                                        // 先切换节点
                                        await viewModel.selectProxy(groupName: group.name, proxyName: nodeName)
                                        
                                        // 添加成功的触觉反馈
                                        HapticManager.shared.notification(.success)

                                        // 移除自动关闭
                                        // dismiss()
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .onAppear {
                // 在显示时，如果还没有保存的顺序，就保存当前排序后的顺序
                if viewModel.savedNodeOrder[group.name] == nil {
                    let sortedNodes = viewModel.getSortedNodes(group.all, in: group)
                    viewModel.saveNodeOrder(for: group.name, nodes: sortedNodes)
                }
                
                // 打印当前代理组的嵌套情况
                print("\n===== 代理组[\(group.name)]嵌套结构 =====")
                viewModel.printNodeStructure(nodeName: group.now, level: 1, visitedGroups: Set([group.name]))
                print("------------------------")
                
                // 打印当前代理组的完整路径
                let path = viewModel.getNodePath(groupName: group.name)
                print("完整代理路径: \(path)")
                print("=========================\n")
            }
            .onDisappear {
                // 在关闭时清除保存的顺序，这样下次打开时会重新排序
                viewModel.clearSavedNodeOrder(for: group.name)
            }
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text(group.name)
                            .font(.headline)
                        
                        if viewModel.testingGroups.contains(group.name) {
                            DelayTestingView()
                                .foregroundStyle(.blue)
                                .scaleEffect(0.8)
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // 添加触觉反馈
                      
                        HapticManager.shared.impact(.light)
                        
                        Task {
                            await viewModel.testGroupSpeed(groupName: group.name)
                            // 添加成功的触觉反馈
                            
                            HapticManager.shared.notification(.success)
                        }
                    } label: {
                        Label("测速", systemImage: "bolt.horizontal")
                    }
                    .disabled(viewModel.testingGroups.contains(group.name))
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        // 添加触觉反馈
                        
                        HapticManager.shared.impact(.light)
                        
                        dismiss()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.testingGroups.contains(group.name))
            .alert("自动测速选择分组", isPresented: $showURLTestAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("该分组不支持手动切换节点，可在全局设置中启用手动切换")
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// 修改 ProxyView.swift 中的 ProxyNodeCard 结构体
struct ProxyNodeCard: View {
    let nodeName: String
    let node: ProxyNode?
    let isSelected: Bool
    let isTesting: Bool
    @ObservedObject var viewModel: ProxyViewModel
    var delay: Int? = nil // 添加可选参数，允许外部传入计算好的延迟
    @Environment(\.colorScheme) private var colorScheme
    
    // 修改 nodeDelay 计算属性
    private var nodeDelay: Int {
        // 如果外部传入了延迟值，直接使用
        if let delay = delay {
            return delay
        }
        
        // 否则使用 viewModel 的方法获取
        return viewModel.getNodeDelay(nodeName: nodeName)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 节点名称和选中状态
            HStack {
                Text(nodeName)
                    .font(.system(.subheadline, design: .rounded))
                    .bold()
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
            }
            
            // 节点类型和延迟
            HStack {
                // 如果是代理组，显示 "代理组"，否则显示节点类型
                if viewModel.groups.contains(where: { $0.name == nodeName }) {
                    Text("代理组")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                } else {
                    Text(node?.type ?? "Special")
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                if nodeName == "REJECT" {
                    Text("阻断")
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.1))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                } else if isTesting {
                    DelayTestingView()
                        .foregroundStyle(.blue)
                        .scaleEffect(0.8)
                        .transition(.opacity)
                } else {
                    // 获取延迟
                    let delay = nodeDelay
                    if delay > 0 {
                        Text("\(delay) ms")
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(getDelayColor(delay).opacity(0.1))
                            .foregroundStyle(getDelayColor(delay))
                            .clipShape(Capsule())
                            .transition(.opacity)
                    } else if delay == 0 {
                        Text("超时")
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                            .transition(.opacity)
                    } else {
                        Text("未知")
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.1))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardBackground()  // 使用新的背景修饰符
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.blue, lineWidth: 2)
                    .drawingGroup(opaque: false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    private func getDelayColor(_ delay: Int) -> Color {
        DelayColor.color(for: delay)
    }
}

// 更新 DelayColor 构造，增加颜色饱和度
struct DelayColor {
    // 延迟范围常量
    static var lowRange: ClosedRange<Int> {
        let threshold = UserDefaults.standard.integer(forKey: "lowDelayThreshold")
        return 0...(threshold == 0 ? 240 : threshold)
    }
    
    static var mediumRange: ClosedRange<Int> {
        let lowThreshold = UserDefaults.standard.integer(forKey: "lowDelayThreshold")
        let mediumThreshold = UserDefaults.standard.integer(forKey: "mediumDelayThreshold")
        return (lowThreshold == 0 ? 241 : lowThreshold + 1)...(mediumThreshold == 0 ? 500 : mediumThreshold)
    }
    
    static var highThreshold: Int {
        UserDefaults.standard.integer(forKey: "mediumDelayThreshold")
    }
    
    static func color(for delay: Int) -> Color {
        switch delay {
        case -1:
            return Color(red: 0.5, green: 0.5, blue: 0.5) // 灰色表示无延迟信息
        case 0:
            return Color(red: 1.0, green: 0.2, blue: 0.2) // 更艳的红色表示超时
        case lowRange:
            return Color(red: 0.2, green: 0.8, blue: 0.2) // 鲜艳的绿色
        case mediumRange:
            return Color(red: 1.0, green: 0.75, blue: 0.0) // 明亮的黄色
        default:
            return Color(red: 1.0, green: 0.5, blue: 0.0) // 鲜艳的橙色
        }
    }
    
    static let unknown = Color(red: 0.5, green: 0.5, blue: 0.5) // 灰色表示无延迟信息
    static let disconnected = Color(red: 1.0, green: 0.2, blue: 0.2) // 更鲜艳的红色
    static let low = Color(red: 0.2, green: 0.8, blue: 0.2) // 鲜艳的绿色
    static let medium = Color(red: 1.0, green: 0.75, blue: 0.0) // 明亮的黄色
    static let high = Color(red: 1.0, green: 0.5, blue: 0.0) // 鲜艳的橙色
}

// 修改延迟测试动画组件
struct DelayTestingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .foregroundStyle(.blue)
            .onAppear {
                withAnimation(
                    .linear(duration: 1)
                    .repeatForever(autoreverses: false)
                ) {
                    isAnimating = true
                }
            }
            .onDisappear {
                isAnimating = false
            }
    }
}

//  GroupCard 中替换原来的延迟统计条部分
struct DelayBar: View {
    let green: Int
    let yellow: Int
    let red: Int
    let timeout: Int
    let unknown: Int
    let total: Int
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                Group {
                    // 低延迟部分
                    if green > 0 {
                        DelaySegment(
                            width: CGFloat(green) / CGFloat(total) * geometry.size.width,
                            color: DelayColor.low,
                            isFirst: true,
                            isLast: yellow == 0 && red == 0 && timeout == 0 && unknown == 0
                        )
                    }
                    
                    // 中等延迟部分
                    if yellow > 0 {
                        DelaySegment(
                            width: CGFloat(yellow) / CGFloat(total) * geometry.size.width,
                            color: DelayColor.medium,
                            isFirst: green == 0,
                            isLast: red == 0 && timeout == 0 && unknown == 0
                        )
                    }
                    
                    // 高延迟部分
                    if red > 0 {
                        DelaySegment(
                            width: CGFloat(red) / CGFloat(total) * geometry.size.width,
                            color: DelayColor.high,
                            isFirst: green == 0 && yellow == 0,
                            isLast: timeout == 0 && unknown == 0
                        )
                    }
                    
                    // 超时部分
                    if timeout > 0 {
                        DelaySegment(
                            width: CGFloat(timeout) / CGFloat(total) * geometry.size.width,
                            color: DelayColor.disconnected,
                            isFirst: green == 0 && yellow == 0 && red == 0,
                            isLast: unknown == 0
                        )
                    }
                    
                    // 未知延迟部分
                    if unknown > 0 {
                        DelaySegment(
                            width: CGFloat(unknown) / CGFloat(total) * geometry.size.width,
                            color: DelayColor.unknown,
                            isFirst: green == 0 && yellow == 0 && red == 0 && timeout == 0,
                            isLast: true
                        )
                    }
                }
                .drawingGroup(opaque: false)  // 优化渲染性能
            }
        }
        .frame(height: 6)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray6))
                .drawingGroup(opaque: false)  // 优化背景渲染
        )
    }
}

// 延迟条段组件
struct DelaySegment: View {
    let width: CGFloat
    let color: Color
    let isFirst: Bool
    let isLast: Bool
    
    var body: some View {
        color
            .frame(width: max(width, 0))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 3,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .cornerRadius(isFirst ? 3 : 0, corners: .topLeft)
            .cornerRadius(isFirst ? 3 : 0, corners: .bottomLeft)
            .cornerRadius(isLast ? 3 : 0, corners: .topRight)
            .cornerRadius(isLast ? 3 : 0, corners: .bottomRight)
    }
}

// 添加圆角辅助扩展
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
            
    }
}

// 添加性能优化修饰符
struct PerformanceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            // 禁用离屏渲染
            .drawingGroup(opaque: false)
            // 减少不必要的布局计算
            .layoutPriority(1)
    }
}



#Preview {
    NavigationStack {
        ProxyView(server: ClashServer(name: "测试服务器", url: "192.168.110.45", port: "9090", secret: "123456"))
    }
}
