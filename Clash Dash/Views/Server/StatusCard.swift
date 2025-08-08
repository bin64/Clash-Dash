import SwiftUI

// 状态卡片组件
struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var monitor: NetworkMonitor
    @AppStorage("showWaveEffect") private var showWaveEffect = true
    @AppStorage("showWaterDropEffect") private var showWaterDropEffect = true
    @AppStorage("showNumberAnimation") private var showNumberAnimation = true
    @AppStorage("showSpeedNumberAnimation") private var showSpeedNumberAnimation = false
    @AppStorage("showConnectionsBackground") private var showConnectionsBackground = true
    
    // 添加可选的连接信息参数
    let connectionInfo: [String]?
    
    init(title: String, value: String, icon: String, color: Color, monitor: NetworkMonitor, connectionInfo: [String]? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
        self.monitor = monitor
        self.connectionInfo = connectionInfo
    }
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? 
            Color(.systemGray6) : 
            Color(.systemBackground)
    }
    
    private func extractSpeed() -> Double {
        let components = value.split(separator: " ")
        guard components.count == 2,
              let speed = Double(components[0]),
              let unit = components.last else {
            return 0
        }
        
        switch unit {
        case "MB/s":
            return speed * 1_000_000
        case "KB/s":
            return speed * 1_000
        case "B/s":
            return speed
        default:
            return 0
        }
    }
    
    // 判断是否是实时速度卡片
    private var isSpeedCard: Bool {
        return (title == "下载" || title == "上传") && !title.contains("总量")
    }
    
    // 判断是否应该使用动画效果
    private var shouldUseAnimation: Bool {
        if isSpeedCard {
            return showNumberAnimation && showSpeedNumberAnimation
        } else {
            return showNumberAnimation
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // 使用条件判断决定是否使用动画数字视图
            if shouldUseAnimation {
                AnimatedNumberView(value: value, color: .primary)
                    .minimumScaleFactor(0.5)
            } else {
                Text(value)
                    .font(.title2)
                    .bold()
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            ZStack {
                cardBackgroundColor
                if showWaveEffect && isSpeedCard {
                    WaveBackground(
                        color: color,
                        speed: extractSpeed(),
                        monitor: monitor,
                        isDownload: title == "下载"
                    )
                }
                if showWaterDropEffect && title.contains("总量") {
                    WaterDropEffect(
                        color: color,
                        monitor: monitor,
                        isUpload: title.contains("上传")
                    )
                }
                // 显示连接信息背景（受开关控制）
                if showConnectionsBackground, let connections = connectionInfo, !connections.isEmpty {
                    ConnectionInfoBackground(connections: connections, color: color)
                }
            }
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// 连接信息背景组件 - 队列管理的无限滚动，iPad优化
struct ConnectionInfoBackground: View {
    let connections: [String]
    let color: Color
    @State private var scrollOffset: CGFloat = 0
    @State private var timer: Timer?
    @State private var displayQueue: [String] = [] // 显示队列
    @State private var currentIndex = 0 // 当前滚动到的索引
    @State private var isInitialized = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // iPad vs iPhone 自适应参数
    private var isLargeScreen: Bool {
        DeviceDetection.isLargeScreen
    }
    
    private var lineHeight: CGFloat {
        isLargeScreen ? 28 : 16  // iPad 需要更高的行以容纳两行信息
    }
    
    private var scrollSpeed: CGFloat {
        // 基础速度
        let baseSpeed: CGFloat = isLargeScreen ? 0.2 : 0.15
        
        // 根据连接数量动态调整速度
        let connectionCount = max(1, connections.count)  // 至少为1，避免除零
        let speedMultiplier = min(3.0, sqrt(Double(connectionCount) / 5.0))  // 使用平方根避免速度增长过快
        
        return baseSpeed * CGFloat(speedMultiplier)
    }
    
    private var displayWidth: CGFloat {
        isLargeScreen ? 200 : 140  // iPad 更宽
    }
    
    private var displayHeight: CGFloat {
        isLargeScreen ? 120 : 80  // iPad 更高
    }
    
    private let minQueueSize = 5
    private let maxQueueSize = 20
    
    var body: some View {
        GeometryReader { geometry in
            HStack {
                Spacer()
                
                // 右下角显示区域
                VStack {
                    Spacer()
                    
                    // 无限滚动容器
                    ZStack {
                        // 使用队列管理的显示系统
                        if !displayQueue.isEmpty {
                            let visibleItems = getVisibleItems()
                            
                            VStack(spacing: 0) {
                                ForEach(Array(visibleItems.enumerated()), id: \.offset) { index, connection in
                                    if isLargeScreen {
                                        // iPad: 显示更丰富的信息
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(connection)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(color.opacity(0.4))
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            
                                            // 显示协议和状态信息
                                            // Text("tcp • active")
                                            //     .font(.caption2)
                                            //     .foregroundColor(color.opacity(0.2))
                                        }
                                        .frame(width: displayWidth, height: lineHeight, alignment: .trailing)
                                    } else {
                                        // iPhone: 保持简洁
                                        Text(connection)
                                            .font(.caption2)
                                            .foregroundColor(color.opacity(0.25))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .frame(width: displayWidth, height: lineHeight, alignment: .trailing)
                                    }
                                }
                            }
                            .offset(y: scrollOffset)
                        }
                    }
                    .onAppear {
                        initializeQueue()
                    }
                    .onDisappear {
                        stopScrolling()
                    }
                    .onChange(of: connections) { newConnections in
                        checkAndUpdateQueue(newConnections)
                    }
                    .frame(width: displayWidth, height: displayHeight)
                    .clipped()
                    .mask(
                        // 渐变遮罩效果，模拟云层消失
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.3),
                                Color.white,
                                Color.white,
                                Color.white.opacity(0.3),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .padding(.trailing, isLargeScreen ? 16 : 12)
                .padding(.bottom, isLargeScreen ? 12 : 8)
            }
        }
    }
    
    // 初始化队列
    private func initializeQueue() {
        guard !isInitialized && !connections.isEmpty else { return }
        displayQueue = Array(connections.prefix(maxQueueSize))
        currentIndex = 0
        isInitialized = true
        startInfiniteScrolling()
    }
    
    // 检查队列状态并在需要时更新（智能队列管理）
    private func checkAndUpdateQueue(_ newConnections: [String]) {
        guard isInitialized else { return }
        guard !newConnections.isEmpty else { return }
        
        // 计算队列中剩余未显示的项目数量
        let remainingItems = displayQueue.count - currentIndex
        
        // 只有当剩余项目少于最小值时，才补充新数据
        if remainingItems < minQueueSize {
            // 从新连接中选择一些项目添加到队列末尾
            let newItems = Array(newConnections.shuffled().prefix(min(10, maxQueueSize - displayQueue.count)))
            
            // 避免重复项目
            let uniqueNewItems = newItems.filter { !displayQueue.contains($0) }
            
            if !uniqueNewItems.isEmpty {
                displayQueue.append(contentsOf: uniqueNewItems)
                
                // 限制队列最大大小
                if displayQueue.count > maxQueueSize {
                    let trimCount = displayQueue.count - maxQueueSize
                    displayQueue.removeFirst(trimCount)
                    currentIndex = max(0, currentIndex - trimCount)
                }
            }
        }
    }
    
    private func startInfiniteScrolling() {
        guard !displayQueue.isEmpty else { return }
        
        // 停止现有定时器
        stopScrolling()
        
        let cycleDuration: TimeInterval = 0.016 // ~60fps
        
                timer = Timer.scheduledTimer(withTimeInterval: cycleDuration, repeats: true) { _ in
            // 平滑向下滚动
            scrollOffset -= scrollSpeed
            
            // 检查是否滚动了一行的距离
            if scrollOffset <= -lineHeight {
                // 更新当前索引（指向队列中的下一个项目）
                currentIndex = (currentIndex + 1) % displayQueue.count
                
                // 重置滚动偏移，继续下一行的滚动
                scrollOffset += lineHeight
            }
        }
     }
     
     // 获取当前可见的项目
     private func getVisibleItems() -> [String] {
         guard !displayQueue.isEmpty else { return [] }
         
         // 根据设备类型计算可见区域需要多少行（加上上下缓冲区）
         let visibleLines = Int(displayHeight / lineHeight) + 4  // 可见行数 + 缓冲
         
         var visibleItems: [String] = []
         
         // 从当前索引开始，获取足够的项目填满可见区域
         for i in 0..<visibleLines {
             let index = (currentIndex + i) % displayQueue.count
             visibleItems.append(displayQueue[index])
         }
         
         return visibleItems
     }
     
    private func stopScrolling() {
        timer?.invalidate()
        timer = nil
    }
} 