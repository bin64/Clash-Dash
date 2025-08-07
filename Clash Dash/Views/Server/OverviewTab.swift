import SwiftUI
import Charts
private let logger = LogManager.shared
// 2. 更新 OverviewTab
struct OverviewTab: View {
    let server: ClashServer
    @ObservedObject var monitor: NetworkMonitor
    @StateObject private var settings = OverviewCardSettings()
    @StateObject private var subscriptionManager: SubscriptionManager
    @StateObject private var connectivityViewModel: ConnectivityViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedTab: Int
    @AppStorage("autoTestConnectivity") private var autoTestConnectivity = true
    @State private var showingDirectConnectionInfoSheet = false
    @State private var showingProxyConnectionInfoSheet = false
    
    init(server: ClashServer, monitor: NetworkMonitor, selectedTab: Binding<Int>, settingsViewModel: SettingsViewModel, connectivityViewModel: ConnectivityViewModel) {
        self.server = server
        self.monitor = monitor
        self._selectedTab = selectedTab
        self.settingsViewModel = settingsViewModel
        self._subscriptionManager = StateObject(wrappedValue: SubscriptionManager(server: server))
        self._connectivityViewModel = StateObject(wrappedValue: connectivityViewModel)
    }
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? 
            Color(.systemGray6) : 
            Color(.systemBackground)
    }
    
    private func maxMemoryValue(_ memoryHistory: [MemoryRecord]) -> Double {
        // 获取当前数据中的最大值
        let maxMemory = memoryHistory.map { $0.usage }.max() ?? 0
        
        // 如果没有数据或数据小，使用最小刻度
        if maxMemory < 50 { // 小于 50MB
            return 50 // 50MB
        }
        
        // 计算合适的刻度值
        let magnitude = pow(10, floor(log10(maxMemory)))
        let normalized = maxMemory / magnitude
        
        // 选择合适的刻度倍数：1, 2, 5, 10
        let scale: Double
        if normalized <= 1 {
            scale = 1
        } else if normalized <= 2 {
            scale = 2
        } else if normalized <= 5 {
            scale = 5
        } else {
            scale = 10
        }
        
        // 计算最终的最大值，并留出一些余量（120%）
        return magnitude * scale * 1.2
    }
    
    private func loadWebsiteSettings() {
        // 加载网站可见性和排序设置
        connectivityViewModel.loadWebsiteVisibility()
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Color.clear
                    .frame(height: 8)
                
                ForEach(settings.cardOrder) { card in
                    if settings.cardVisibility[card] ?? true {
                        switch card {
                        case .speed:
                            // 速度卡片
                            if settings.cardVisibility[.speed] ?? true {
                                HStack(spacing: 16) {
                                    StatusCard(
                                        title: "下载",
                                        value: monitor.downloadSpeed,
                                        icon: "arrow.down.circle",
                                        color: .blue,
                                        monitor: monitor
                                    )
                                    StatusCard(
                                        title: "上传",
                                        value: monitor.uploadSpeed,
                                        icon: "arrow.up.circle",
                                        color: .green,
                                        monitor: monitor
                                    )
                                }
                            }
                            
                        case .totalTraffic:
                            // 总流量卡片
                            HStack(spacing: 16) {
                                StatusCard(
                                    title: "下载总量",
                                    value: monitor.totalDownload,
                                    icon: "arrow.down.circle.fill",
                                    color: .blue,
                                    monitor: monitor
                                )
                                StatusCard(
                                    title: "上传总量",
                                    value: monitor.totalUpload,
                                    icon: "arrow.up.circle.fill",
                                    color: .green,
                                    monitor: monitor
                                )
                            }
                            
                        case .status:
                            // 状态卡片
                            HStack(spacing: 16) {
                                StatusCard(
                                    title: "活动连接",
                                    value: "\(monitor.activeConnections)",
                                    icon: "link.circle.fill",
                                    color: .orange,
                                    monitor: monitor,
                                    connectionInfo: monitor.latestConnections
                                )
                                .onTapGesture {
                                    selectedTab = 3
                                    HapticManager.shared.impact(.light)
                                }
                                StatusCard(
                                    title: "内存使用",
                                    value: monitor.memoryUsage,
                                    icon: "memorychip",
                                    color: .purple,
                                    monitor: monitor
                                )
                            }
                            
                        case .speedChart:
                            // 速率图表
                            SpeedChartView(speedHistory: monitor.speedHistory)
                                .padding()
                                .background(cardBackgroundColor)
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                            
                        case .memoryChart:
                            // 只在 Meta 服务器上显示内存图表
                            if server.serverType != .premium {
                                ChartCard(title: "内存使用", icon: "memorychip") {
                                    Chart {
                                        // 添加预设的网格线和标签
                                        ForEach(Array(stride(from: 0, to: maxMemoryValue(monitor.memoryHistory), by: maxMemoryValue(monitor.memoryHistory)/4)), id: \.self) { value in
                                            RuleMark(
                                                y: .value("Memory", value)
                                            )
                                            .lineStyle(StrokeStyle(lineWidth: 1))
                                            .foregroundStyle(.gray.opacity(0.1))
                                        }
                                        
                                        ForEach(monitor.memoryHistory) { record in
                                            AreaMark(
                                                x: .value("Time", record.timestamp),
                                                y: .value("Memory", record.usage)
                                            )
                                            .foregroundStyle(.purple.opacity(0.3))
                                            
                                            LineMark(
                                                x: .value("Time", record.timestamp),
                                                y: .value("Memory", record.usage)
                                            )
                                            .foregroundStyle(.purple)
                                        }
                                    }
                                    .frame(height: 200)
                                    .chartYAxis {
                                        AxisMarks(position: .leading) { value in
                                            if let memory = value.as(Double.self) {
                                                AxisGridLine()
                                                AxisValueLabel {
                                                    Text("\(Int(memory)) MB")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                    .chartYScale(domain: 0...maxMemoryValue(monitor.memoryHistory))
                                    .chartXAxis {
                                        AxisMarks(values: .automatic(desiredCount: 3))
                                    }
                                }
                            }
                            
                        case .modeSwitch:
                            ModeSwitchCard(server: server)
                            
                        case .subscription:
                            if !subscriptionManager.subscriptions.isEmpty {
                                let subscriptions = subscriptionManager.subscriptions
                                let lastUpdateTime = subscriptionManager.lastUpdateTime
                                let isLoading = subscriptionManager.isLoading
                                
                                SubscriptionInfoCard(
                                    subscriptions: subscriptions,
                                    lastUpdateTime: lastUpdateTime,
                                    isLoading: isLoading
                                ) {
                                    await subscriptionManager.refresh()
                                }
                            }
                            
                        case .connectivity:
                            ConnectivityCard(
                                viewModel: connectivityViewModel,
                                settingsViewModel: settingsViewModel,
                                showingDirectConnectionInfo: $showingDirectConnectionInfoSheet,
                                showingProxyConnectionInfo: $showingProxyConnectionInfoSheet
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            monitor.resetRealtimeData() // 重置实时监控数据，保留累积数据
            
            // 设置连通性检测
            loadWebsiteSettings()
            
            // 只有当连通性检测卡片显示且启用了自动检测时，才启动连通性检测
            if autoTestConnectivity && (settings.cardVisibility[.connectivity] ?? true) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    connectivityViewModel.testAllConnectivity()
                }
            } else if settings.cardVisibility[.connectivity] ?? true {
                // 确保连通性卡片显示时，网站状态一定是干净的初始状态
                // 不会显示错误状态，而是显示未检测状态（中间态）
                connectivityViewModel.resetWebsiteStatus()
            }
            
            Task {
                await subscriptionManager.fetchSubscriptionInfo() // 获取订阅信息
            }
        }
        .sheet(isPresented: $showingDirectConnectionInfoSheet) {
            DirectConnectionInfoView(
                isPresented: $showingDirectConnectionInfoSheet,
                proxyAddress: connectivityViewModel.clashServer?.url ?? "N/A",
                httpPort: settingsViewModel.httpPort,
                mixedPort: settingsViewModel.mixedPort,
                usedPort: connectivityViewModel.httpPort
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingProxyConnectionInfoSheet) {
            ProxyConnectionInfoView(
                isPresented: $showingProxyConnectionInfoSheet,
                proxyAddress: connectivityViewModel.clashServer?.url ?? "N/A",
                usedPort: connectivityViewModel.httpPort
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
} 
