import SwiftUI

struct SubscriptionInfoCard: View {
    let subscriptions: [SubscriptionCardInfo]
    let lastUpdateTime: Date?
    let isLoading: Bool
    let onRefresh: () async -> Void
    
    @State private var currentIndex = 0
    @State private var isButtonPressed = false
    @State private var dragOffset = CGSize.zero
    @Namespace private var animation
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("subscriptionCardStyle") private var cardStyle = SubscriptionCardStyle.classic
    @AppStorage("autoRefreshSubscriptionCard") private var autoRefreshSubscriptionCard = false
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日"
        return formatter
    }()
    
    private var cardBackgroundColor: Color {
        Color(.secondarySystemGroupedBackground)
    }
    
    private func formatTraffic(_ bytes: Double) -> String {
        if bytes >= 1024 * 1024 * 1024 {
            return String(format: "%.1f GB", bytes / (1024 * 1024 * 1024))
        } else if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", bytes / (1024 * 1024))
        } else {
            return String(format: "%.1f KB", bytes / 1024)
        }
    }
    
    private func formatUpdateTime(_ date: Date?) -> String {
        guard let date = date else { return "未更新" }
        let now = Date()
        let diff = now.timeIntervalSince(date)
        
        if diff < 10 {
            return "刚刚更新"
        } else if diff < 60 {
            return "\(Int(diff))秒前更新"
        } else if diff < 3600 {
            return "\(Int(diff / 60))分钟前更新"
        } else if diff < 86400 {
            return "\(Int(diff / 3600))小时前更新"
        } else {
            return "\(Int(diff / 86400))天前更新"
        }
    }
    
    private func getProgressColor(_ percentage: Double) -> Color {
        let remainingPercentage = 100.0 - percentage
        switch remainingPercentage {
        case 50..<200:
            return .green
        case 20..<50:
            return .orange
        default:
            return .red
        }
    }
    
    private var modernCardContent: some View {
        ZStack {
            if !subscriptions.isEmpty {
                ForEach(Array(subscriptions.enumerated()), id: \.element.id) { index, subscription in
                    let offset = CGFloat(index - currentIndex)
                    let isCurrentCard = index == currentIndex
                    let dragAmount = abs(dragOffset.width)
                    let threshold: CGFloat = 50
                    
                    // 计算变形和位移
                    let scale = isCurrentCard ? 1.0 : 0.85
                    let xOffset = dragOffset.width + offset * 320
                    let yOffset = isCurrentCard ? 0.0 : 20.0
                    
                    // 计算水滴效果
                    let progress = min(dragAmount / threshold, 1.0)
                    let dropScale = isCurrentCard ? (1.0 - progress * 0.1) : scale
                    let dropOffset = isCurrentCard ? (dragOffset.width > 0 ? 15.0 : -15.0) * progress : 0
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 16) {
                            // 左侧信息
                            VStack(alignment: .leading, spacing: 6) {
                                // 标题和图标
                                HStack(spacing: 6) {
                                    Image(systemName: "network.badge.shield.half.filled")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.blue.gradient)
                                    if let name = subscription.name {
                                        Text(name)
                                            .font(.system(size: 18, weight: .medium))
                                    }
                                }
                                
                                // 剩余时间
                                if let expiryDate = subscription.expiryDate {
                                    let remainingDays = Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
                                    Text("剩余时间")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                    if remainingDays > 0 {
                                        Text("\(remainingDays) 天")
                                            .font(.system(size: 22, weight: .medium))
                                    } else {
                                        Text("无限期")
                                            .font(.system(size: 22, weight: .medium))
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            // 右侧百分比显示
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(Int(100 - subscription.percentageUsed))%")
                                    .font(.system(size: 42, weight: .medium))
                                
                                // 简化的进度条设计
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(Color(.systemGray5))
                                            .frame(height: 3)
                                        
                                        if subscription.totalTraffic > 0 {
                                            RoundedRectangle(cornerRadius: 1.5)
                                                .fill(
                                                    getProgressColor(subscription.percentageUsed)
                                                        .opacity(0.8)
                                                )
                                                .frame(width: max(0, min(geometry.size.width, geometry.size.width * CGFloat(subscription.usedTraffic / subscription.totalTraffic))))
                                        }
                                    }
                                }
                                .frame(width: 80, height: 3)
                                
                                Text("\(formatTraffic(subscription.usedTraffic)) / \(formatTraffic(subscription.totalTraffic))")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 更新时间和按钮
                        if isCurrentCard {
                            ZStack {
                                // 更新时间（左对齐）
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 10))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.secondary)
                                    Text(formatUpdateTime(lastUpdateTime))
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // 点点指示器（居中）
                                if subscriptions.count > 1 {
                                    HStack(spacing: 4) {
                                        ForEach(0..<subscriptions.count, id: \.self) { index in
                                            Circle()
                                                .fill(index == currentIndex ? Color.blue : Color.gray.opacity(0.3))
                                                .frame(width: 5, height: 5)
                                        }
                                    }
                                }
                                
                                // 刷新按钮（右对齐）
                                Button(action: {
                                    Task {
                                        await onRefresh()
                                    }
                                }) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 14))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.blue)
                                        .rotationEffect(.degrees(isLoading ? 360 : 0))
                                        .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }
                    .padding(16)
                    .background(cardBackgroundColor)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                           radius: 8, x: 0, y: 4)
                    .offset(x: xOffset + dropOffset)
                    .offset(y: yOffset)
                    .scaleEffect(dropScale)
                    .opacity(isCurrentCard ? 1.0 : 0.5)
                    .zIndex(isCurrentCard ? 1 : 0)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                if subscriptions.count > 1 {
                                    self.dragOffset = CGSize(width: gesture.translation.width, height: 0)
                                }
                            }
                            .onEnded { gesture in
                                if subscriptions.count > 1 {
                                    let threshold: CGFloat = 50
                                    let velocity = gesture.predictedEndLocation.x - gesture.location.x
                                    
                                    if abs(gesture.translation.width) > threshold || abs(velocity) > 100 {
                                        withAnimation(.interpolatingSpring(stiffness: 150, damping: 15)) {
                                            if gesture.translation.width > 0 {
                                                currentIndex = (currentIndex - 1 + subscriptions.count) % subscriptions.count
                                            } else {
                                                currentIndex = (currentIndex + 1) % subscriptions.count
                                            }
                                            HapticManager.shared.impact(.light)
                                            self.dragOffset = .zero
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            self.dragOffset = .zero
                                        }
                                    }
                                }
                            }
                    )
                }
            } else {
                Text("暂无订阅信息")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                    .padding(16)
                    .background(cardBackgroundColor)
                    .cornerRadius(16)
            }
        }
        .animation(.interpolatingSpring(stiffness: 150, damping: 15), value: currentIndex)
    }
    
    private var classicCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题栏
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.blue.gradient)
                    Text("订阅信息")
                        .font(.system(size: 14, weight: .medium))
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    if subscriptions.count > 1 {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                currentIndex = (currentIndex + 1) % subscriptions.count
                                isButtonPressed = true
                                HapticManager.shared.impact(.light)
                                
                                // 重置按钮状态
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isButtonPressed = false
                                }
                            }
                        }) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.blue.gradient)
                                .scaleEffect(isButtonPressed ? 0.8 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isButtonPressed)
                        }
                    }
                    
                    Button(action: {
                        Task {
                            await onRefresh()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.blue.gradient)
                            .rotationEffect(.degrees(isLoading ? 360 : 0))
                            .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
                    }
                }
            }
            
            if !subscriptions.isEmpty {
                let subscription = subscriptions[currentIndex]
                
                VStack(alignment: .leading, spacing: 10) {
                    // 订阅名称和到期时间
                    HStack(alignment: .center) {
                        if let name = subscription.name {
                            Text(name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        if let expiryDate = subscription.expiryDate {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                let remainingDays = Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
                                if remainingDays > 0 {
                                    Text("\(dateFormatter.string(from: expiryDate))")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("无限期")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(.systemGray6))
                            )
                        }
                    }
                    
                    // 流量使用进度条
                    VStack(spacing: 6) {
                        HStack {
                            Text("流量使用")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if subscription.totalTraffic > 0 {
                                Text("\(formatTraffic(subscription.usedTraffic)) / \(formatTraffic(subscription.totalTraffic))")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("无限制")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray5))
                                
                                if subscription.totalTraffic > 0 {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(
                                            getProgressColor(subscription.percentageUsed)
                                                .gradient
                                        )
                                        .frame(width: max(0, min(geometry.size.width, geometry.size.width * CGFloat(subscription.usedTraffic / subscription.totalTraffic))))
                                }
                            }
                            .frame(height: 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(.systemGray4), lineWidth: 0.5)
                            )
                        }
                        .frame(height: 8)
                        
                        // 百分比和更新时间
                        HStack {
                            Text("\(String(format: "%.1f%%", 100 - subscription.percentageUsed)) 剩余")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 10))
                                Text(formatUpdateTime(lastUpdateTime))
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .leading)))
            } else {
                Text("暂无订阅信息")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackgroundColor)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                       radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4).opacity(0.5), lineWidth: 0.5)
        )
    }
    
    var body: some View {
        Group {
            switch cardStyle {
            case .classic:
                classicCardContent
            case .modern:
                modernCardContent
            }
        }
        .onAppear {
            if autoRefreshSubscriptionCard {
                Task {
                    await onRefresh()
                }
            }
        }
    }
} 
