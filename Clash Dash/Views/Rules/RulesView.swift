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
                    SearchBar(text: $viewModel.searchText, placeholder: "搜索规则")
                        .padding(.horizontal)
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
        RulesListRepresentable(
            rules: viewModel.rules,
            filteredRules: filteredRules,
            sections: filteredSections,
            allSections: allSections.map(String.init)
        )
    }
    
    private var filteredRules: [String: [RulesViewModel.Rule]] {
        let filtered = viewModel.searchText.isEmpty ? viewModel.rules :
            viewModel.rules.filter { rule in
                rule.payload.localizedCaseInsensitiveContains(viewModel.searchText) ||
                rule.type.localizedCaseInsensitiveContains(viewModel.searchText) ||
                rule.proxy.localizedCaseInsensitiveContains(viewModel.searchText)
            }
        
        return ["Rules": filtered]
    }
    
    private var providersView: some View {
        Group {
            if viewModel.providers.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("没有找到规则订阅信息")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
            } else {
                ZStack(alignment: .bottomTrailing) {
                    ProvidersListRepresentable(
                        providers: viewModel.providers,
                        searchText: viewModel.searchText,
                        onRefresh: { [weak viewModel] provider in
                            Task {
                                await viewModel?.refreshProvider(provider.name)
                            }
                        }
                    )
                    
                    // 添加更新全部按钮
                    Button(action: {
                        Task {
                            await viewModel.refreshAllProviders()
                        }
                    }) {
                        ZStack {
                            BlurView(style: .systemThinMaterial)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                            
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(viewModel.isRefreshingAll ? .secondary : .primary)
                                .rotationEffect(.degrees(viewModel.isRefreshingAll ? 360 : 0))
                                .animation(
                                    viewModel.isRefreshingAll ?
                                        Animation.linear(duration: 1).repeatForever(autoreverses: false) :
                                        .default,
                                    value: viewModel.isRefreshingAll
                                )
                        }
                    }
                    .disabled(viewModel.isRefreshingAll)
                    .opacity(viewModel.isRefreshingAll ? 0.6 : 1.0)
                    .animation(.easeInOut, value: viewModel.isRefreshingAll)
                    .padding(.trailing, 16)
                    .padding(.bottom, floatingTabBarVisible ? 168 : 80)  // 给搜索按钮留出空间，考虑浮动标签栏
                    .animation(.easeInOut(duration: 0.3), value: floatingTabBarVisible)
                    .onChange(of: floatingTabBarVisible) { newValue in
                        print("🔄 更新全部按钮 - 浮动标签栏可见性变化: \(newValue)")
                    }
                }
            }
        }
    }
    
    private var filteredSections: [String] {
        ["Rules"]
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
                BlurView(style: .systemThinMaterial)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                
                Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, floatingTabBarVisible ? 104 : 16)
        .animation(.easeInOut(duration: 0.3), value: floatingTabBarVisible)
        .onChange(of: floatingTabBarVisible) { newValue in
            print("🔍 搜索按钮 - 浮动标签栏可见性变化: \(newValue)")
        }
    }
}

private let allSections = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ#")

// 新增 UITableView 包装器
struct RulesListRepresentable: UIViewRepresentable {
    let rules: [RulesViewModel.Rule]
    let filteredRules: [String: [RulesViewModel.Rule]]
    let sections: [String]
    let allSections: [String]
    
    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.register(RuleCell.self, forCellReuseIdentifier: "RuleCell")
        tableView.sectionIndexColor = .systemBlue
        tableView.sectionIndexBackgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        
        // 添加这些配置来优化视图切换
        tableView.estimatedRowHeight = 44
        tableView.estimatedSectionHeaderHeight = 28
        tableView.remembersLastFocusedIndexPath = true
        return tableView
    }
    
    func updateUIView(_ tableView: UITableView, context: Context) {
        // 先更新 coordinator 的数据
        context.coordinator.rules = rules
        context.coordinator.filteredRules = filteredRules
        context.coordinator.sections = sections
        context.coordinator.allSections = allSections
        
        // 在主线程上安全地更新 UI
        DispatchQueue.main.async {
            // 禁用动画以避免更新问题
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(rules: rules, filteredRules: filteredRules, sections: sections, allSections: allSections)
    }
    
    class Coordinator: NSObject, UITableViewDelegate, UITableViewDataSource {
        var rules: [RulesViewModel.Rule]
        var filteredRules: [String: [RulesViewModel.Rule]]
        var sections: [String]
        var allSections: [String]
        
        init(rules: [RulesViewModel.Rule], filteredRules: [String: [RulesViewModel.Rule]], sections: [String], allSections: [String]) {
            self.rules = rules
            self.filteredRules = filteredRules
            self.sections = sections
            self.allSections = allSections
        }
        
        // 实现必要的 UITableView 数据源方法
        func numberOfSections(in tableView: UITableView) -> Int {
            return sections.count
        }
        
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            let sectionKey = sections[section]
            return filteredRules[sectionKey]?.count ?? 0
        }
        
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "RuleCell", for: indexPath) as! RuleCell
            let sectionKey = sections[indexPath.section]
            if let rules = filteredRules[sectionKey] {
                cell.configure(with: rules[indexPath.row])
            }
            return cell
        }
        
        func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            return nil // 不显示分组标题
        }
        
        // 添加视图生命周期方法
        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            // 确保单元格在显示前已经完成布局
            cell.layoutIfNeeded()
        }
        
        func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            // 清理不再显示的单元格
        }
    }
}

// 修改 RuleCell
class RuleCell: UITableViewCell {
    private let payloadLabel = UILabel()
    private let proxyLabel = UILabel()
    private let typeLabel = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        // 禁用选择效果
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // 移除右侧箭头
        accessoryType = .none
        
        let topStack = UIStackView(arrangedSubviews: [payloadLabel, proxyLabel])
        topStack.distribution = .equalSpacing
        topStack.spacing = 8
        
        let mainStack = UIStackView(arrangedSubviews: [topStack, typeLabel])
        mainStack.axis = .vertical
        mainStack.spacing = 4
        
        contentView.addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
        
        // 设置字体和颜色
        payloadLabel.font = .systemFont(ofSize: 15)
        proxyLabel.font = .systemFont(ofSize: 13)
        typeLabel.font = .systemFont(ofSize: 13)
        
        proxyLabel.textColor = .systemBlue
        typeLabel.textColor = .secondaryLabel
        
        // 配置标签属性
        proxyLabel.textAlignment = .right
        proxyLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        payloadLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    
    func configure(with rule: RulesViewModel.Rule) {
        payloadLabel.text = rule.payload
        proxyLabel.text = rule.proxy
        typeLabel.text = rule.type
    }
}

// 新增 ProvidersListRepresentable
struct ProvidersListRepresentable: UIViewRepresentable {
    let providers: [RulesViewModel.RuleProvider]
    let searchText: String
    let onRefresh: (RulesViewModel.RuleProvider) -> Void
    
    private var filteredProviders: [String: [RulesViewModel.RuleProvider]] {
        let filtered = searchText.isEmpty ? providers :
            providers.filter { provider in
                provider.name.localizedCaseInsensitiveContains(searchText) ||
                provider.behavior.localizedCaseInsensitiveContains(searchText) ||
                provider.vehicleType.localizedCaseInsensitiveContains(searchText)
            }
        
        return ["规则订阅": filtered]
    }
    
    private var sections: [String] {
        ["规则订阅"]
    }
    
    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.register(ProviderCell.self, forCellReuseIdentifier: "ProviderCell")
        tableView.showsVerticalScrollIndicator = false
        tableView.estimatedRowHeight = 88
        tableView.estimatedSectionHeaderHeight = 28
        tableView.remembersLastFocusedIndexPath = true
        return tableView
    }
    
    func updateUIView(_ tableView: UITableView, context: Context) {
        context.coordinator.providers = providers
        context.coordinator.filteredProviders = filteredProviders
        context.coordinator.sections = sections
        
        DispatchQueue.main.async {
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            providers: providers,
            filteredProviders: filteredProviders,
            sections: sections,
            onRefresh: onRefresh
        )
    }
    
    class Coordinator: NSObject, UITableViewDelegate, UITableViewDataSource {
        var providers: [RulesViewModel.RuleProvider]
        var filteredProviders: [String: [RulesViewModel.RuleProvider]]
        var sections: [String]
        let onRefresh: (RulesViewModel.RuleProvider) -> Void
        
        init(providers: [RulesViewModel.RuleProvider],
             filteredProviders: [String: [RulesViewModel.RuleProvider]],
             sections: [String],
             onRefresh: @escaping (RulesViewModel.RuleProvider) -> Void) {
            self.providers = providers
            self.filteredProviders = filteredProviders
            self.sections = sections
            self.onRefresh = onRefresh
        }
        
        func numberOfSections(in tableView: UITableView) -> Int {
            return sections.count
        }
        
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            let sectionKey = sections[section]
            return filteredProviders[sectionKey]?.count ?? 0
        }
        
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ProviderCell", for: indexPath) as! ProviderCell
            let sectionKey = sections[indexPath.section]
            if let providers = filteredProviders[sectionKey] {
                let provider = providers[indexPath.row]
                cell.configure(with: provider, onRefresh: { [weak self] in
                    self?.onRefresh(provider)
                })
            }
            return cell
        }
        
        func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            return nil
        }
    }
}

// 修改 ProviderCell
class ProviderCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let countLabel = UILabel()
    private let typeLabel = UILabel()
    private let behaviorLabel = UILabel()
    private let timeLabel = UILabel()
    private let refreshButton = UIButton()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        // 禁用选择效果
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        let mainStack = UIStackView(arrangedSubviews: [
            createTopRow(),
            createMiddleRow(),
            createBottomRow()
        ])
        mainStack.axis = .vertical
        mainStack.spacing = 6  // 减小间距
        
        contentView.addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
        
        // 调整字体大小
        nameLabel.font = .systemFont(ofSize: 15, weight: .medium)  // 减小主标题大小
        countLabel.font = .systemFont(ofSize: 13)
        typeLabel.font = .systemFont(ofSize: 11)  // 减小标签字体
        behaviorLabel.font = .systemFont(ofSize: 11)
        timeLabel.font = .systemFont(ofSize: 11)
        
        // 设置标签样式
        countLabel.textColor = .secondaryLabel
        typeLabel.textColor = .white
        behaviorLabel.textColor = .white
        timeLabel.textColor = .tertiaryLabel
        
        // 设置标签背景
        typeLabel.backgroundColor = .systemBlue.withAlphaComponent(0.8)  // 稍微透明一点
        behaviorLabel.backgroundColor = .systemGreen.withAlphaComponent(0.8)
        
        // 圆角和内边距
        [typeLabel, behaviorLabel].forEach { label in
            label.layer.cornerRadius = 3  // 减小圆角
            label.layer.masksToBounds = true
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.8
            
            // 减小内边距
            label.layoutMargins = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.heightAnchor.constraint(equalToConstant: 16)  // 减小高度
            ])
        }
        
        // 设置刷新按钮
        refreshButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        refreshButton.tintColor = .systemBlue
        
        // 移除右侧箭头
        accessoryType = .none
    }
    
    private func createTopRow() -> UIView {
        let stack = UIStackView(arrangedSubviews: [nameLabel, countLabel])
        stack.distribution = .equalSpacing
        return stack
    }
    
    private func createMiddleRow() -> UIView {
        let stack = UIStackView(arrangedSubviews: [typeLabel, behaviorLabel])
        stack.spacing = 8
        stack.distribution = .fillProportionally
        stack.alignment = .center
        return stack
    }
    
    private func createBottomRow() -> UIView {
        let stack = UIStackView(arrangedSubviews: [timeLabel, refreshButton])
        stack.distribution = .equalSpacing
        return stack
    }
    
    func configure(with provider: RulesViewModel.RuleProvider, onRefresh: @escaping () -> Void) {
        nameLabel.text = provider.name
        countLabel.text = "\(provider.ruleCount) 条规则"
        typeLabel.text = provider.vehicleType
        behaviorLabel.text = provider.behavior
        timeLabel.text = "更新于 " + provider.formattedUpdateTime
        
        // 根据刷新状态更新按钮状态
        refreshButton.isEnabled = !provider.isRefreshing
        if provider.isRefreshing {
            // 创建旋转动画
            let rotation = CABasicAnimation(keyPath: "transform.rotation")
            rotation.fromValue = 0
            rotation.toValue = 2 * Double.pi
            rotation.duration = 1
            rotation.repeatCount = .infinity
            refreshButton.layer.add(rotation, forKey: "rotation")
        } else {
            refreshButton.layer.removeAnimation(forKey: "rotation")
        }
        
        // 移除之前的所有动作
        refreshButton.removeTarget(nil, action: nil, for: .allEvents)
        refreshButton.addAction(UIAction { _ in
            onRefresh()
        }, for: .touchUpInside)
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

