import SwiftUI

struct RulesView: View {
    let server: ClashServer
    @StateObject private var viewModel: RulesViewModel
    @State private var selectedTab = RuleTab.rules
    @State private var showSearch = false
    @Environment(\.floatingTabBarVisible) private var floatingTabBarVisible
    
    init(server: ClashServer) {
        self.server = server
        _viewModel = StateObject(wrappedValue: RulesViewModel(server: server))
    }
    
    enum RuleTab {
        case rules
        case providers
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                Picker("规则类型", selection: $selectedTab) {
                    Text("规则")
                        .tag(RuleTab.rules)
                    Text("规则订阅")
                        .tag(RuleTab.providers)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if showSearch {
                    ModernSearchBar(text: $viewModel.searchText, placeholder: selectedTab == .rules ? "搜索规则" : "搜索规则订阅")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Group {
                    switch selectedTab {
                    case .rules:
                        LazyView(rulesList)
                            .transition(.opacity)
                    case .providers:
                        LazyView(providersView)
                            .transition(.opacity)
                    }
                }
            }
            
            searchButton
        }
        .animation(.easeInOut, value: selectedTab)
        .animation(.easeInOut, value: showSearch)
        .onAppear {
            Task {
                await viewModel.fetchData()
            }
        }
        .refreshable {
            await viewModel.fetchData()
        }
    }
    
    private var rulesList: some View {
        ModernRulesListView(
            rules: filteredRules,
            searchText: viewModel.searchText
        )
    }
    
    private var filteredRules: [RulesViewModel.Rule] {
        return viewModel.searchText.isEmpty ? viewModel.rules :
            viewModel.rules.filter { rule in
                rule.payload.localizedCaseInsensitiveContains(viewModel.searchText) ||
                rule.type.localizedCaseInsensitiveContains(viewModel.searchText) ||
                rule.proxy.localizedCaseInsensitiveContains(viewModel.searchText)
            }
    }
    
    private var providersView: some View {
        Group {
            if viewModel.providers.isEmpty {
                ModernEmptyStateView()
            } else {
                ZStack(alignment: .bottomTrailing) {
                    ModernProvidersListView(
                        providers: viewModel.providers,
                        searchText: viewModel.searchText,
                        onRefresh: { [weak viewModel] provider in
                            Task {
                                await viewModel?.refreshProvider(provider.name)
                            }
                        }
                    )
                    
                    // 精美的全部更新按钮
                    ModernRefreshAllButton(
                        isRefreshing: viewModel.isRefreshingAll,
                        action: {
                        Task {
                            await viewModel.refreshAllProviders()
                        }
                        }
                    )
                    .padding(.trailing, 16)
                    .padding(.bottom, floatingTabBarVisible ? 168 : 80)
                    .animation(.easeInOut(duration: 0.3), value: floatingTabBarVisible)
                }
            }
        }
    }
    

    
    private var searchButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showSearch.toggle()
                if !showSearch {
                    viewModel.searchText = ""
                }
            }
        }) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 48, height: 48)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.3), Color.pink.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .frame(width: 48, height: 48)
                
                Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.orange, Color.pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(showSearch ? 0.9 : 1.0)
                    .rotationEffect(.degrees(showSearch ? 90 : 0))
            }
        }
        .scaleEffect(showSearch ? 1.05 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSearch)
        .padding(.trailing, 16)
        .padding(.bottom, floatingTabBarVisible ? 104 : 16)
        .animation(.easeInOut(duration: 0.3), value: floatingTabBarVisible)
    }
}



// 添加 LazyView 来优化视图加载
struct LazyView<Content: View>: View {
    let build: () -> Content
    
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    
    var body: Content {
        build()
    }
}

// MARK: - 现代化UI组件

// 现代化搜索栏
struct ModernSearchBar: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: isFocused ? [Color.blue, Color.purple] : [Color.secondary, Color.secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .animation(.easeInOut(duration: 0.2), value: isFocused)
            
            TextField(placeholder, text: $text)
                .font(.system(.body, design: .rounded))
                .focused($isFocused)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isFocused ?
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [Color.clear, Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: Color.black.opacity(isFocused ? 0.1 : 0.05), radius: isFocused ? 8 : 4, x: 0, y: 2)
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .animation(.easeInOut(duration: 0.2), value: text.isEmpty)
    }
}

// 精美的空状态视图
struct ModernEmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("暂无规则订阅")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text("当前控制器没有配置规则订阅源")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// 现代化规则列表
struct ModernRulesListView: View {
    let rules: [RulesViewModel.Rule]
    let searchText: String
    
    var body: some View {
        Group {
            if rules.isEmpty {
                RulesEmptyStateView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                            ModernRuleCard(rule: rule)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                                .animation(
                                    .spring(response: 0.5, dampingFraction: 0.8)
                                        .delay(Double(index % 20) * 0.02), // 限制动画延迟
                                    value: rules.count
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
    }
}

// 规则专用空状态视图
struct RulesEmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.1), Color.blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.green, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("暂无规则数据")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                Text("当前控制器没有配置规则")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// 精美的规则卡片
struct ModernRuleCard: View {
    let rule: RulesViewModel.Rule
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // 左侧主体内容
                VStack(alignment: .leading, spacing: 6) {
                    // 主要内容：规则内容
                    Text(rule.payload)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // 底部信息行
                    HStack(spacing: 4) {
                        // 箭头和代理
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        
                        Text(rule.proxy)
                            .font(.system(.caption2, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                }
                
                // 右侧规则类型标签
                EmbossedRuleTypeTag(type: rule.type)
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isPressed ? 
                                    [Color.green.opacity(0.3), Color.blue.opacity(0.3)] :
                                    [Color.primary.opacity(0.05), Color.primary.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isPressed ? 1.0 : 0.5
                        )
                )
                .shadow(
                    color: Color.black.opacity(isPressed ? 0.06 : 0.03),
                    radius: isPressed ? 8 : 4,
                    x: 0,
                    y: isPressed ? 3 : 1
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPressed)
        .onTapGesture {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isPressed = false
                }
            }
        }
    }
}

// 浮雕刻印效果的规则类型标签
struct EmbossedRuleTypeTag: View {
    let type: String
    @State private var isVisible = false
    
    var body: some View {
        Text(type)
            .font(.system(.callout, design: .rounded))
            .fontWeight(.bold)
            .foregroundStyle(.secondary.opacity(0.6))
            .scaleEffect(isVisible ? 1.0 : 0.9)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.15), value: isVisible)
            .onAppear {
                isVisible = true
            }
    }
}

// 规则类型标签（保留原版本以备使用）
struct ModernRuleTypeTag: View {
    let type: String
    @State private var isVisible = false
    
    private var tagColor: Color {
        switch type.lowercased() {
        case "domain", "domain-suffix", "domain-keyword":
            return .blue
        case "ip-cidr", "ip-cidr6":
            return .green
        case "geoip":
            return .orange
        case "process-name":
            return .purple
        case "final":
            return .red
        default:
            return .gray
        }
    }
    
    var body: some View {
        Text(type)
            .font(.system(.caption2, design: .rounded))
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tagColor, tagColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(tagColor.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(color: tagColor.opacity(0.3), radius: 1, x: 0, y: 0.5)
            )
            .scaleEffect(isVisible ? 1.0 : 0.8)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.05), value: isVisible)
            .onAppear {
                isVisible = true
            }
    }
}

// 现代化规则订阅列表
struct ModernProvidersListView: View {
    let providers: [RulesViewModel.RuleProvider]
    let searchText: String
    let onRefresh: (RulesViewModel.RuleProvider) -> Void
    
    private var filteredProviders: [RulesViewModel.RuleProvider] {
        searchText.isEmpty ? providers :
            providers.filter { provider in
                provider.name.localizedCaseInsensitiveContains(searchText) ||
                provider.behavior.localizedCaseInsensitiveContains(searchText) ||
                provider.vehicleType.localizedCaseInsensitiveContains(searchText)
            }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(filteredProviders.enumerated()), id: \.element.id) { index, provider in
                    ModernProviderCard(provider: provider, onRefresh: onRefresh)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        .animation(
                            .spring(response: 0.6, dampingFraction: 0.8)
                                .delay(Double(index) * 0.1),
                            value: filteredProviders.count
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// 精美的订阅源卡片
struct ModernProviderCard: View {
    let provider: RulesViewModel.RuleProvider
    let onRefresh: (RulesViewModel.RuleProvider) -> Void
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 主要内容区域
            VStack(alignment: .leading, spacing: 8) {
                // 标题行
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name)
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 3) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            
                            Text("\(provider.ruleCount) 条规则")
                                .font(.system(.caption2, design: .rounded))
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    ModernRefreshButton(
                        isRefreshing: provider.isRefreshing,
                        action: { onRefresh(provider) }
                    )
                }
                
                // 标签行
                HStack(spacing: 6) {
                    ModernTag(text: provider.vehicleType, color: .blue)
                    ModernTag(text: provider.behavior, color: .green)
                    Spacer()
                }
                
                // 更新时间行
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("更新于 \(provider.formattedUpdateTime)")
                        .font(.system(size: 10, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundStyle(.tertiary)
                    
                    Spacer()
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    // 渐变边框效果
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isPressed ? 
                                    [Color.blue.opacity(0.3), Color.purple.opacity(0.3)] :
                                    [Color.primary.opacity(0.06), Color.primary.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isPressed ? 1.5 : 0.5
                        )
                )
                .shadow(
                    color: Color.black.opacity(isPressed ? 0.08 : 0.04),
                    radius: isPressed ? 12 : 8,
                    x: 0,
                    y: isPressed ? 4 : 2
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPressed)
        .onTapGesture {
            // 添加轻微的触觉反馈
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isPressed = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isPressed = false
                }
            }
        }
    }
}

// 现代化标签组件
struct ModernTag: View {
    let text: String
    let color: Color
    @State private var isVisible = false
    
    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .rounded))
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule()
                            .stroke(color.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(color: color.opacity(0.3), radius: 2, x: 0, y: 1)
            )
            .scaleEffect(isVisible ? 1.0 : 0.8)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.1), value: isVisible)
            .onAppear {
                isVisible = true
            }
    }
}

// 现代化刷新按钮
struct ModernRefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 28, height: 28)
                
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing ?
                            Animation.linear(duration: 1).repeatForever(autoreverses: false) :
                            .default,
                        value: isRefreshing
                    )
            }
        }
        .disabled(isRefreshing)
        .opacity(isRefreshing ? 0.6 : 1.0)
        .scaleEffect(isRefreshing ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isRefreshing)
    }
}

// 全部更新按钮
struct ModernRefreshAllButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 3)
                
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isRefreshing ? [Color.secondary] : [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing ?
                            Animation.linear(duration: 1.2).repeatForever(autoreverses: false) :
                            .spring(response: 0.4, dampingFraction: 0.8),
                        value: isRefreshing
                    )
            }
        }
        .disabled(isRefreshing)
        .scaleEffect(isRefreshing ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRefreshing)
    }
}

// 添加 BlurView 支持
struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        return view
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

#Preview {
    NavigationStack {
        RulesView(server: ClashServer(name: "测试服务器",
                                    url: "10.1.1.2",
                                    port: "9090",
                                    secret: "123456"))
    }
} 

