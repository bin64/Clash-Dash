import SwiftUI

struct CompactGroupCard: View {
    let group: ProxyGroup
    @ObservedObject var viewModel: ProxyViewModel
    @State private var showProxySelector = false
    @State private var isExpanded = false
    @AppStorage("hideUnavailableProxies") private var hideUnavailableProxies = false
    @AppStorage("proxyGroupSortOrder") private var proxyGroupSortOrder = ProxyGroupSortOrder.default
    @AppStorage("pinBuiltinProxies") private var pinBuiltinProxies = false
    @AppStorage("autoSpeedTestBeforeSwitch") private var autoSpeedTestBeforeSwitch = true
    @AppStorage("allowManualURLTestGroupSwitch") private var allowManualURLTestGroupSwitch = false
    @State private var currentNodeOrder: [String]?
    @State private var displayedNodes: [String] = []
    @State private var showURLTestAlert = false
    @Environment(\.colorScheme) var colorScheme
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? 
            Color(.systemGray6) : 
            Color(.systemBackground)
    }
    
    // 获取当前选中节点的延迟颜色
    private var currentNodeColor: Color {
        if group.type == "LoadBalance" {
            return .blue
        }
        let delay = viewModel.getNodeDelay(nodeName: group.now)
        return DelayColor.color(for: delay)
    }
    
    // Add separate function for sorting
    // 排序优先级：有效延迟 > 超时(0) > 无延迟信息(-1)
    private func getSortedNodes() -> [String] {
        // First separate special nodes and normal nodes
        let specialNodes = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"]
        let normalNodes = group.all.filter { node in
            !specialNodes.contains(node.uppercased())
        }
        let specialNodesPresent = group.all.filter { node in
            specialNodes.contains(node.uppercased())
        }
        
        // Sort nodes according to settings
        var sortedNodes = pinBuiltinProxies ? normalNodes : group.all
        switch proxyGroupSortOrder {
        case .latencyAsc:
            sortedNodes.sort { node1, node2 in
                let delay1 = viewModel.getNodeDelay(nodeName: node1)
                let delay2 = viewModel.getNodeDelay(nodeName: node2)
                
                // 优先级排序：有效延迟 > 超时 > 无延迟信息
                if delay1 > 0 && delay2 <= 0 { return true }
                if delay1 <= 0 && delay2 > 0 { return false }
                if delay1 == 0 && delay2 == -1 { return true }
                if delay1 == -1 && delay2 == 0 { return false }
                
                // 两者都是有效延迟，按延迟大小排序
                if delay1 > 0 && delay2 > 0 {
                    return delay1 < delay2
                }
                
                return false // 两者都是无效值时保持原顺序
            }
        case .latencyDesc:
            sortedNodes.sort { node1, node2 in
                let delay1 = viewModel.getNodeDelay(nodeName: node1)
                let delay2 = viewModel.getNodeDelay(nodeName: node2)
                
                // 优先级排序：有效延迟 > 超时 > 无延迟信息
                if delay1 > 0 && delay2 <= 0 { return true }
                if delay1 <= 0 && delay2 > 0 { return false }
                if delay1 == 0 && delay2 == -1 { return true }
                if delay1 == -1 && delay2 == 0 { return false }
                
                // 两者都是有效延迟，按延迟大小倒序排序
                if delay1 > 0 && delay2 > 0 {
                    return delay1 > delay2
                }
                
                return false // 两者都是无效值时保持原顺序
            }
        case .nameAsc:
            sortedNodes.sort { $0 < $1 }
        case .nameDesc:
            sortedNodes.sort { $0 > $1 }
        case .default:
            break
        }
        
        // Return sorted nodes with special nodes at top if pinned
        return pinBuiltinProxies ? specialNodesPresent + sortedNodes : sortedNodes
    }
    
    private func updateDisplayedNodes() {
        var nodes = currentNodeOrder ?? getSortedNodes()
        
        if hideUnavailableProxies {
            nodes = nodes.filter { nodeName in
                if nodeName == "DIRECT" || nodeName == "REJECT" {
                    return true
                }
                return viewModel.getNodeDelay(nodeName: nodeName) > 0
            }
        }
        
        displayedNodes = nodes
    }
    
    // 添加动画时间计算函数
    private func getAnimationDuration() -> Double {
        let baseTime = 0.3  // 基础动画时间
        let nodeCount = group.all.count
        
        // 根据节点数量计算额外时间
        // 每20个节点增加0.1秒，最多增加0.4秒
        let extraTime = min(Double(nodeCount) / 20.0 * 0.1, 0.4)
        
        return baseTime + extraTime
    }
    
    // 添加辅助函数来处理名称
    private var displayInfo: (icon: String, name: String) {
        let name = group.name
        guard let firstScalar = name.unicodeScalars.first,
              firstScalar.properties.isEmoji else {
            return (String(name.prefix(1)).uppercased(), name)
        }
        
        // 如果第一个字符是 emoji，将其作为图标，并从名称中移除
        let emoji = String(name.unicodeScalars.prefix(1))
        let remainingName = name.dropFirst()
        return (emoji, String(remainingName).trimmingCharacters(in: .whitespaces))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                // 添加触觉反馈
                HapticManager.shared.impact(.light)
                
                // 使用计算的动画时间
                withAnimation(.spring(
                    response: getAnimationDuration(),
                    dampingFraction: 0.8
                )) {
                    isExpanded.toggle()
                    if isExpanded {
                        updateDisplayedNodes()
                    } else {
                        currentNodeOrder = nil
                    }
                }
            } label: {
                HStack(spacing: 15) {
                    // 左侧图标和名称
                    HStack(spacing: 10) {
                        // 图标部分
                        Group {
                            if let iconUrl = group.icon, !iconUrl.isEmpty {
                                CachedAsyncImage(url: iconUrl)
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Text(displayInfo.icon)
                                    .font(.system(size: 18, weight: .medium))
                                    .frame(width: 36, height: 36)
                                    .background(currentNodeColor.opacity(0.1))
                                    .foregroundStyle(currentNodeColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(displayInfo.name)
                                    .font(.system(.body, design: .default))
                                    .fontWeight(.semibold)

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

                            if group.type == "LoadBalance" {
                                Text("负载均衡")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else if viewModel.testingGroups.contains(group.name) {
                                DelayTestingView()
                                    .foregroundStyle(.blue)
                                    .scaleEffect(0.7)
                            } else {
                                HStack(spacing: 4) {
                                    Text(group.now)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // 右侧状态
                    HStack(alignment: .center, spacing: 0) {
                        Spacer()
                            .frame(width: 20)
                        
                        // 竖条分隔符
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(width: 3, height: 30)
                            .opacity(0.3)
                            .padding(.trailing, 10)
                        
                        // 节点数量和容器
                        HStack(spacing: 10) {
                            if isExpanded {
                                SpeedTestButton(
                                    isTesting: viewModel.testingGroups.contains(group.name)
                                ) {
                                    Task {
                                        await viewModel.testGroupSpeed(groupName: group.name)
                                    }
                                }
                            } else {
                                Text("\(group.all.count)")
                                    .fontWeight(.medium)
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16))
                                .foregroundStyle(Color(.tertiaryLabel))
                                .fontWeight(.bold)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                        .frame(width: 55, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(height: 64)
                .background(cardBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .mask {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .padding(.bottom, isExpanded ? -16 : 0)
                }
            }
            .buttonStyle(.plain)
            
            // 展开的详细内容
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, 16)
                    
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(displayedNodes, id: \.self) { nodeName in
                                ProxyNodeRow(
                                    nodeName: nodeName,
                                    isSelected: nodeName == group.now,
                                    delay: viewModel.getNodeDelay(nodeName: nodeName)
                                )
                                .onTapGesture {
                                    // 添加触觉反馈
                                    HapticManager.shared.impact(.light)
                                    
                                    if group.type == "URLTest" && !allowManualURLTestGroupSwitch {
                                        showURLTestAlert = true
                                        HapticManager.shared.notification(.error)
                                    } else {
                                        Task {
                                            if currentNodeOrder == nil {
                                                currentNodeOrder = displayedNodes
                                            }
                                            await viewModel.selectProxy(groupName: group.name, proxyName: nodeName)
                                            HapticManager.shared.notification(.success)
                                        }
                                    }
                                }
                                
                                if nodeName != displayedNodes.last {
                                    Divider()
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 500) // 限制最大高度
                }
                .background(cardBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Update nodes when hideUnavailableProxies changes
        .onChange(of: hideUnavailableProxies) { _ in
            if isExpanded {
                updateDisplayedNodes()
            }
        }
        // Update nodes when proxyGroupSortOrder changes
        .onChange(of: proxyGroupSortOrder) { _ in
            if isExpanded && currentNodeOrder == nil {
                updateDisplayedNodes()
            }
        }
        .alert("自动测速选择分组", isPresented: $showURLTestAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("该分组不支持手动切换节点，可在全局设置中启用手动切换")
        }
    }
}

#Preview {
    CompactGroupCard(
        group: ProxyGroup(
            name: "测试组",
            type: "Selector",
            now: "测试节点很长的名字测试节点很长的名字",
            all: ["节点1", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2", "节点2"],
            alive: true,
            icon: nil
        ),
        viewModel: ProxyViewModel(
            server: ClashServer(
                name: "测试服务器",
                url: "localhost",
                port: "9090",
                secret: "123456"
            )
        )
    )
    .padding()
} 
