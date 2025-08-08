import SwiftUI

struct OverviewCardSettingsView: View {
    @StateObject private var settings = OverviewCardSettings()
    @AppStorage("subscriptionCardStyle") private var subscriptionCardStyle = SubscriptionCardStyle.classic
    @AppStorage("modeSwitchCardStyle") private var modeSwitchCardStyle = ModeSwitchCardStyle.classic
    @AppStorage("showWaveEffect") private var showWaveEffect = false
    @AppStorage("showWaterDropEffect") private var showWaterDropEffect = true
    @AppStorage("showNumberAnimation") private var showNumberAnimation = true
    @AppStorage("showSpeedNumberAnimation") private var showSpeedNumberAnimation = false
    @AppStorage("showConnectionsBackground") private var showConnectionsBackground = true
    @AppStorage("speedChartStyle") private var speedChartStyle = SpeedChartStyle.line
    @AppStorage("autoRefreshSubscriptionCard") private var autoRefreshSubscriptionCard = false
    @AppStorage("autoTestConnectivity") private var autoTestConnectivity = true
    @AppStorage("connectivityTimeout") private var connectivityTimeout: Double = 5.0
    @AppStorage("connectivityWebsiteVisibility") private var connectivityWebsiteVisibilityData: Data = Data()
    @AppStorage("connectivityWebsiteOrder") private var connectivityWebsiteOrderData: Data = Data()
    @State private var editMode: EditMode = .active
    @State private var connectivityWebsiteVisibility: [String: Bool] = [:]
    @State private var connectivityWebsiteOrder: [UUID] = []
    private let logger = LogManager.shared
    
    // 固定网站ID映射，确保ID稳定性
    private let fixedWebsiteIds: [String: UUID] = [
        "YouTube": UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        "Google": UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        "GitHub": UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        "Apple": UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    ]
    
    // 默认网站列表 - 固定不可更改
    private var defaultWebsites: [WebsiteStatus] {
        [
            WebsiteStatus(id: fixedWebsiteIds["YouTube"]!, name: "YouTube", url: "https://www.youtube.com", icon: "play.rectangle.fill"),
            WebsiteStatus(id: fixedWebsiteIds["Google"]!, name: "Google", url: "https://www.google.com", icon: "magnifyingglass"),
            WebsiteStatus(id: fixedWebsiteIds["GitHub"]!, name: "GitHub", url: "https://github.com", icon: "chevron.left.forwardslash.chevron.right"),
            WebsiteStatus(id: fixedWebsiteIds["Apple"]!, name: "Apple", url: "https://www.apple.com", icon: "apple.logo")
        ]
    }
    
    // 返回排序后的网站列表
    private var orderedWebsites: [WebsiteStatus] {
        // 如果有保存的顺序，按照顺序返回
        if !connectivityWebsiteOrder.isEmpty {
            var ordered: [WebsiteStatus] = []
            // 首先添加有序列表中的网站
            for id in connectivityWebsiteOrder {
                if let website = defaultWebsites.first(where: { $0.id == id }) {
                    ordered.append(website)
                }
            }
            // 添加其他未包含在顺序中的网站
            for website in defaultWebsites {
                if !connectivityWebsiteOrder.contains(website.id) {
                    ordered.append(website)
                }
            }
            return ordered
        } else {
            // 返回默认列表
            return defaultWebsites
        }
    }
    
    var body: some View {
        List {
            Section {
                ForEach(settings.cardOrder) { card in
                    HStack {
                        Image(systemName: card.icon)
                            .foregroundColor(.accentColor)
                            .frame(width: 24)
                        
                        Text(card.description)
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { settings.cardVisibility[card] ?? true },
                            set: { _ in 
                                settings.toggleVisibility(for: card)
                                HapticManager.shared.impact(.light)
                            }
                        ))
                    }
                }
                .onMove { source, destination in
                    settings.moveCard(from: source, to: destination)
                    HapticManager.shared.impact(.medium)
                }
            } header: {
                SectionHeader(title: "卡片设置", systemImage: "rectangle.on.rectangle")
            } footer: {
                Text("拖动可以调整顺序，使用开关可以控制卡片的显示或隐藏")
            }
            
            Section {
                Picker("订阅信息卡片样式", selection: $subscriptionCardStyle) {
                    ForEach(SubscriptionCardStyle.allCases, id: \.self) { style in
                        Text(style.description).tag(style)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("自动刷新订阅信息", isOn: $autoRefreshSubscriptionCard)
                    Text("每次进入概览页面时自动刷新订阅信息卡片")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("订阅信息会优先从 OpenClash 或 Nikki 中获取，如果获取失败则会从 Clash 配置中获取（使用 proxy-providers 才能显示订阅信息）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Picker("代理切换卡片样式", selection: $modeSwitchCardStyle) {
                    ForEach(ModeSwitchCardStyle.allCases, id: \.self) { style in
                        Text(style.description).tag(style)
                    }
                }
                
                Picker("速率图表样式", selection: $speedChartStyle) {
                    ForEach(SpeedChartStyle.allCases, id: \.self) { style in
                        Text(style.description).tag(style)
                    }
                }
                
                Toggle("速度卡片波浪效果", isOn: $showWaveEffect)
                
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("流量卡片水滴效果", isOn: $showWaterDropEffect)
                    Text("一滴水滴约为 10MB 的流量")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                                 VStack(alignment: .leading, spacing: 4) {
                     Toggle("数字变化动画效果", isOn: $showNumberAnimation)
                     Text("数据变化时显示平滑过渡动画")
                         .font(.caption)
                         .foregroundColor(.secondary)
                 }
                 
                 VStack(alignment: .leading, spacing: 4) {
                     Toggle("实时速度数字动画", isOn: $showSpeedNumberAnimation)
                     Text("上传下载实时速度数字变化时应用动画效果")
                         .font(.caption)
                         .foregroundColor(.secondary)
                 }
                 
                 VStack(alignment: .leading, spacing: 4) {
                     Toggle("显示活动连接背景效果", isOn: $showConnectionsBackground)
                     Text("在‘活动连接’卡片右下角显示滚动的连接信息背景")
                         .font(.caption)
                         .foregroundColor(.secondary)
                 }
            } header: {
                SectionHeader(title: "卡片样式", systemImage: "greetingcard")
            }
            
            // 连通性检测设置部分
            Section {
                Toggle("进入概览页面时自动检测", isOn: $autoTestConnectivity)
                    .padding(.vertical, 4)
                    .onChange(of: autoTestConnectivity) { _ in
                        HapticManager.shared.impact(.light)
                    }
            } header: {
                SectionHeader(title: "连通性检测设置", systemImage: "network")
            }
            
            Section {
                ForEach(orderedWebsites) { website in
                    HStack {
                        // Image(systemName: "line.3.horizontal")
                        //     .foregroundColor(.gray.opacity(0.5))
                        //     .font(.system(size: 14))
                        //     .opacity(editMode.isEditing ? 1 : 0)
                        //     .padding(.trailing, 6)
                        
                        Image(systemName: website.icon)
                            .foregroundColor(.accentColor)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(website.name)
                                .font(.headline)
                            Text(website.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { connectivityWebsiteVisibility[website.id.uuidString] ?? true },
                            set: { isVisible in
                                connectivityWebsiteVisibility[website.id.uuidString] = isVisible
                                saveWebsiteVisibility()
                                HapticManager.shared.impact(.light)
                            }
                        ))
                    }
                }
                .onMove { source, destination in
                    var updatedOrder = orderedWebsites.map { $0.id }
                    updatedOrder.move(fromOffsets: source, toOffset: destination)
                    connectivityWebsiteOrder = updatedOrder
                    saveWebsiteOrder()
                    HapticManager.shared.impact(.medium)
                }
            } header: {
                Text("网站列表")
            } footer: {
                Text("拖动可以调整网站显示顺序，使用开关控制要显示的网站")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("连接超时时间")
                        Spacer()
                        Text("\(Int(connectivityTimeout))秒")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $connectivityTimeout, in: 3...30, step: 1) { 
                        Text("超时时间")
                    } minimumValueLabel: {
                        Text("3秒")
                            .font(.caption)
                    } maximumValueLabel: {
                        Text("30秒")
                            .font(.caption)
                    }
                    .onChange(of: connectivityTimeout) { _ in
                        HapticManager.shared.impact(.light)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("超时设置")
            } footer: {
                Text("连接超时时间决定检测等待的最长时间")
            }
            
            Section {
                Button(action: {
                    resetConnectivitySettings()
                    HapticManager.shared.notification(.warning)
                }) {
                    Text("恢复连通性检测默认设置")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("概览页面设置")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .onAppear {
            loadWebsiteVisibility()
            loadWebsiteOrder()
        }
    }
    
    private func loadWebsiteVisibility() {
        if let savedVisibility = try? JSONDecoder().decode([String: Bool].self, from: connectivityWebsiteVisibilityData) {
            connectivityWebsiteVisibility = savedVisibility
            logger.debug("成功加载网站可见性设置")
        } else {
            // 默认所有网站都显示
            var defaultVisibility: [String: Bool] = [:]
            for website in defaultWebsites {
                defaultVisibility[website.id.uuidString] = true
            }
            connectivityWebsiteVisibility = defaultVisibility
            logger.debug("使用默认网站可见性设置")
        }
    }
    
    private func saveWebsiteVisibility() {
        if let encoded = try? JSONEncoder().encode(connectivityWebsiteVisibility) {
            connectivityWebsiteVisibilityData = encoded
            logger.debug("保存网站可见性设置")
        } else {
            logger.error("保存网站可见性设置失败")
        }
    }
    
    private func loadWebsiteOrder() {
        if let savedOrder = try? JSONDecoder().decode([UUID].self, from: connectivityWebsiteOrderData) {
            connectivityWebsiteOrder = savedOrder
            logger.debug("成功加载网站顺序设置")
        } else {
            // 默认按原始顺序
            connectivityWebsiteOrder = defaultWebsites.map { $0.id }
            logger.debug("使用默认网站顺序")
        }
    }
    
    private func saveWebsiteOrder() {
        if let encoded = try? JSONEncoder().encode(connectivityWebsiteOrder) {
            connectivityWebsiteOrderData = encoded
            logger.debug("保存网站顺序设置")
        } else {
            logger.error("保存网站顺序设置失败")
        }
    }
    
    private func resetConnectivitySettings() {
        // 重置为默认值
        var defaultVisibility: [String: Bool] = [:]
        for website in defaultWebsites {
            defaultVisibility[website.id.uuidString] = true
        }
        connectivityWebsiteVisibility = defaultVisibility
        connectivityWebsiteOrder = defaultWebsites.map { $0.id }
        connectivityTimeout = 5.0
        autoTestConnectivity = true
        saveWebsiteVisibility()
        saveWebsiteOrder()
    }
}

// 图标类别结构
struct IconCategory: Identifiable {
    var id = UUID()
    var name: String
    var icons: [String]
} 