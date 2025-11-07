import Foundation
import Combine
// 添加 LogManager
private let logger = LogManager.shared

struct ProxyNode: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let alive: Bool
    let delay: Int
    let history: [ProxyHistory]
    
    // 实现 Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // 实现 Equatable
    static func == (lhs: ProxyNode, rhs: ProxyNode) -> Bool {
        return lhs.id == rhs.id
    }
}

struct ProxyHistory: Codable, Hashable {
    let time: String
    let delay: Int
}

// Surge API 数据模型
struct SurgePolicies: Codable {
    let policyGroups: [String]  // 策略组名称列表
    let proxies: [String]       // 代理策略名称列表

    private enum CodingKeys: String, CodingKey {
        case policyGroups = "policy-groups"
        case proxies
    }
}

struct SurgePolicy: Codable, Hashable {
    let name: String
    let typeDescription: String
    let isGroup: Bool?
    let lineHash: String?

    private enum CodingKeys: String, CodingKey {
        case name, typeDescription, isGroup, lineHash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        typeDescription = try container.decode(String.self, forKey: .typeDescription)
        isGroup = try container.decodeIfPresent(Bool.self, forKey: .isGroup)
        lineHash = try container.decodeIfPresent(String.self, forKey: .lineHash)
    }
}

struct SurgePolicyGroups: Codable {
    let groups: [String: [SurgePolicy]]

    init(groups: [String: [SurgePolicy]]) {
        self.groups = groups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.decode([String: [SurgePolicy]].self, forKey: .groups)
    }

    private enum CodingKeys: String, CodingKey {
        case groups = ""
    }

    // 自定义编码，因为 Surge API 返回的是动态键名的对象
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groups, forKey: .groups)
    }
}

struct SurgePolicySelection: Codable {
    let policy: String
}

struct SurgePolicyTestResult: Codable {
    // URL 测试策略的结果
    let time: Double?
    let winner: String?
    let results: [String: [String: SurgePolicyTestItem]]?

    // Select 策略测试的结果
    let policyTestResults: [String: SurgePolicyTestItem]?

    private enum CodingKeys: String, CodingKey {
        case time, winner, results
        case policyTestResults
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 尝试解析 URL 测试格式
        time = try container.decodeIfPresent(Double.self, forKey: .time)
        winner = try container.decodeIfPresent(String.self, forKey: .winner)
        results = try container.decodeIfPresent([String: [String: SurgePolicyTestItem]].self, forKey: .results)

        // 尝试解析 Select 测试格式
        if results == nil {
            policyTestResults = try container.decodeIfPresent([String: SurgePolicyTestItem].self, forKey: .policyTestResults)
        } else {
            policyTestResults = nil
        }
    }
}

struct SurgePolicyTestItem: Codable {
    let tcp: Double?
    let rtt: Double?
    let receive: Double?
    let available: Bool?
    let tfo: Bool?

    // URL 测试特有的字段
    let time: Double?
}

// Surge 性能基准测试结果数据模型
struct SurgeBenchmarkResult: Codable {
    let lastTestErrorMessage: String?
    let lastTestScoreInMS: Double
    let lastTestDate: Double

    // 计算延迟值，遵循 Surge 的逻辑
    var latency: Int {
        // 如果 lastTestScoreInMS 为 0 且有错误信息，设为 -1
        if lastTestScoreInMS == 0 && lastTestErrorMessage != nil {
            return -1
        }
        // 否则返回整数形式的延迟
        return Int(lastTestScoreInMS.rounded())
    }

    var hasError: Bool {
        return lastTestErrorMessage != nil
    }

    // 将 macOS/iOS 时间戳转换为 Date
    var lastTestDateAsDate: Date? {
        // macOS/iOS 时间戳是从 2001 年 1 月 1 日开始的秒数
        let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
        let macOSReference = Date(timeIntervalSince1970: 978307200) // 2001-01-01 00:00:00 UTC
        return Date(timeInterval: lastTestDate, since: macOSReference)
    }

    // 检查是否需要重新测速（lastTestScoreInMS 为 -1 或者超过2分钟）
    var needsRetest: Bool {
        // 如果从未测试过（lastTestScoreInMS 为 -1）
        if lastTestScoreInMS == -1 {
            return true
        }

        // 如果测试过但超过2分钟
        if let testDate = lastTestDateAsDate {
            let twoMinutesAgo = Date().addingTimeInterval(-2 * 60)
            return testDate < twoMinutesAgo
        }

        // 如果没有测试日期，也需要重新测试
        return true
    }
}

struct ProxyGroup: Identifiable, Hashable {
    let id = UUID()
    let name: String
    var type: String
    var now: String
    let all: [String]
    let alive: Bool
    let icon: String?
    
    init(name: String, type: String, now: String, all: [String], alive: Bool = true, icon: String? = nil) {
        self.name = name
        self.type = type
        self.now = now
        self.all = all
        self.alive = alive
        self.icon = icon
    }
    
    // 实现 Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(now)
    }
    
    // 实现 Equatable
    static func == (lhs: ProxyGroup, rhs: ProxyGroup) -> Bool {
        return lhs.name == rhs.name && lhs.now == rhs.now
    }
}

// 更新数据模型
struct ProxyProvider: Codable {
    let name: String
    let type: String
    let vehicleType: String
    let proxies: [ProxyDetail]
    let testUrl: String?
    let subscriptionInfo: SubscriptionInfo?
    let updatedAt: String?
    let hidden: Bool?
    
    // 添加验证方法
    var isValid: Bool {
        guard let info = subscriptionInfo else { return true }
        return info.isValid
    }
}

struct ProxyProvidersResponse: Codable {
    let providers: [String: ProxyProvider]
}

// 添加 Provider 模型
struct Provider: Identifiable, Codable, Equatable {
    var id: String { name }
    let name: String
    let type: String
    let vehicleType: String
    let updatedAt: String?
    let subscriptionInfo: SubscriptionInfo?
    let hidden: Bool?
    
    static func == (lhs: Provider, rhs: Provider) -> Bool {
        return lhs.id == rhs.id
    }
}

struct SubscriptionInfo: Codable {
    let upload: Int64
    let download: Int64
    let total: Int64
    let expire: Int64
    
    enum CodingKeys: String, CodingKey {
        case upload = "Upload"
        case download = "Download"
        case total = "Total"
        case expire = "Expire"
    }
    
    // 添加验证方法
    var isValid: Bool {
        // 验证流量数据是否有效
        let uploadValid = upload >= 0 && !Double(upload).isInfinite && !Double(upload).isNaN
        let downloadValid = download >= 0 && !Double(download).isInfinite && !Double(download).isNaN
        let totalValid = total >= 0 && !Double(total).isInfinite && !Double(total).isNaN
        
        // 安全计算总使用量
        let uploadDouble = Double(upload)
        let downloadDouble = Double(download)
        
        // 检查是否任一值接近或等于 Int64 最大值
        if uploadDouble >= Double(Int64.max) / 2 || downloadDouble >= Double(Int64.max) / 2 {
            return false // 数值太大，认为无效
        }
        
        return uploadValid && downloadValid && totalValid
    }
    
    // 安全获取总流量
    var safeUsedTraffic: Double {
        let uploadDouble = Double(upload)
        let downloadDouble = Double(download)
        
        if uploadDouble.isFinite && downloadDouble.isFinite {
            return uploadDouble + downloadDouble
        }
        return 0
    }
}

class ProxyViewModel: ObservableObject {
    @Published var providers: [Provider] = []
    @Published var groups: [ProxyGroup] = []
    @Published var nodes: [ProxyNode] = []
    @Published var providerNodes: [String: [ProxyNode]] = [:]
    @Published var testingNodes: Set<String> = []
    @Published var lastUpdated = Date()
    @Published var lastDelayTestTime = Date()
    @Published var testingGroups: Set<String> = []
    @Published var savedNodeOrder: [String: [String]] = [:] // 移除 private 修饰符
    @Published var testingProviders: Set<String> = []
    @Published var allProxyDetails: [String: ProxyDetail] = [:] // 新增：保存所有代理的详细信息
    @Published var groupSelections: [String: String] = [:] // Surge 策略组选择状态
    @Published var currentOutboundMode: String = "rule" // 当前代理模式 (rule/proxy/direct)
    
    private let server: ClashServer
    private var currentTask: Task<Void, Never>?
    private let settingsViewModel = SettingsViewModel()
    
    // 从 UserDefaults 读取设置
    private var testUrl: String {
        UserDefaults.standard.string(forKey: "speedTestURL") ?? "http://www.gstatic.com/generate_204"
    }
    
    private var testTimeout: Int {
        // 添加默认值 5000，与 GlobalSettingsView 中的默认值保持一致
        UserDefaults.standard.integer(forKey: "speedTestTimeout") == 0 
            ? 5000 
            : UserDefaults.standard.integer(forKey: "speedTestTimeout")
    }
    
    init(server: ClashServer) {
        self.server = server
        Task {
            await fetchProxies()
            settingsViewModel.fetchConfig(server: server)
        }
    }
    
    private func makeRequest(path: String) -> URLRequest? {
        // 根据服务器类型选择正确的 SSL 设置
        let useSSL: Bool
        switch server.source {
        case .surge:
            useSSL = server.surgeUseSSL
        case .clashController, .openWRT:
            useSSL = server.clashUseSSL
        }
        let scheme = useSSL ? "https" : "http"
        
        // 处理路径中的特殊字符
        let encodedPath = path.components(separatedBy: "/").map { component in
            component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
        }.joined(separator: "/")
        
        guard let url = URL(string: "\(scheme)://\(server.url):\(server.port)/\(encodedPath)") else {
            // print("无效的 URL，原始路径: \(path)")
            return nil
        }
        
        var request = URLRequest(url: url)

        // 根据服务器类型设置不同的认证头
        switch server.source {
        case .surge:
            // Surge 使用 x-key 认证头
            if let surgeKey = server.surgeKey, !surgeKey.isEmpty {
                request.setValue(surgeKey, forHTTPHeaderField: "x-key")
            }
        case .clashController, .openWRT:
            // Clash/OpenWRT 使用 Authorization 头
            request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        }

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // print("📡 创建请求: \(url)")
        return request
    }
    
    @MainActor
    func fetchProxies() async {
        logger.info("开始获取代理数据 - 服务器类型: \(server.source)")

        do {
            if server.source == .surge {
                // Surge 服务器：使用 Surge API
                await fetchSurgeProxies()
            } else {
                // Clash/OpenWRT 服务器：使用原有的 Clash API
                await fetchClashProxies()
            }
        } catch {
            logger.error("获取代理数据失败: \(error.localizedDescription)")
            handleNetworkError(error)
        }
    }

    // 获取 Clash 代理数据（原有逻辑）
    private func fetchClashProxies() async {
        do {
            // 更新当前代理模式（从 UserDefaults 获取）
            await MainActor.run {
                self.currentOutboundMode = UserDefaults.standard.string(forKey: "currentMode") ?? "rule"
            }
            // 1. 获取 proxies 数据
            guard let proxiesRequest = makeRequest(path: "proxies") else {
                logger.error("创建 proxies 请求失败")
                return
            }
            let (proxiesData, _) = try await URLSession.secure.data(for: proxiesRequest)

            // 2. 获取 providers 数据
            guard let providersRequest = makeRequest(path: "providers/proxies") else {
                logger.error("创建 providers 请求失败")
                return
            }
            let (providersData, _) = try await URLSession.secure.data(for: providersRequest)

            var allNodes: [ProxyNode] = []
            var groupsToUpdate: [ProxyGroup] = []
            var allProxyDetailsToUpdate: [String: ProxyDetail] = [:]

            // 3. 处理 proxies 数据
            if let proxiesResponse = try? JSONDecoder().decode(ProxyResponse.self, from: proxiesData) {
                // logger.log("成功解析 proxies 数据")
                logger.info("成功解析 proxies 数据")
                allProxyDetailsToUpdate = proxiesResponse.proxies // 保存所有代理的详细信息

                let proxyNodes = proxiesResponse.proxies.map { name, proxy in
                    ProxyNode(
                        id: proxy.id ?? UUID().uuidString,
                        name: name,
                        type: proxy.type,
                        alive: proxy.alive ?? true,
                        delay: proxy.history.last?.delay ?? 0,
                        history: proxy.history
                    )
                }
                allNodes.append(contentsOf: proxyNodes)

                // 更新组数据
//                let oldGroups = self.groups
                groupsToUpdate = proxiesResponse.proxies.compactMap { name, proxy in
                    guard proxy.all != nil else { return nil }
                    if proxy.hidden == true { return nil }
                    return ProxyGroup(
                        name: name,
                        type: proxy.type,
                        now: proxy.now ?? "",
                        all: proxy.all ?? [],
                        alive: proxy.alive ?? true,
                        icon: proxy.icon
                    )
                }
                // print("代理组数量: \(self.groups.count)")

                // 打印组的变化
                // for group in self.groups {
                //     if let oldGroup = oldGroups.first(where: { $0.name == group.name }) {
                //         if oldGroup.now != group.now {
                //             print("📝 组 \(group.name) 的选中节点已更新: \(oldGroup.now) -> \(group.now)")
                //         }
                //     }
                // }
            } else {
                // print("解析 proxies 数据失败")
                logger.error("解析 proxies 数据失败")
            }

            var providersToUpdate: [Provider] = []
            var providerNodesToUpdate: [String: [ProxyNode]] = [:]

            // 4. 处理 providers 数据
            if let providersResponse = try? JSONDecoder().decode(ProxyProvidersResponse.self, from: providersData) {
                // print("成功解析 providers 数据")
                logger.info("成功解析 providers 数据")
                // print("📦 代理提供者数量: \(providersResponse.providers.count)")

                // 更新 providers 属性时保持固定排序
                providersToUpdate = providersResponse.providers.map { name, provider in
                    Provider(
                        name: name,
                        type: provider.type,
                        vehicleType: provider.vehicleType,
                        updatedAt: provider.updatedAt,
                        subscriptionInfo: provider.subscriptionInfo,
                        hidden: provider.hidden
                    )
                }
                .filter { provider in
                    // 过滤掉 hidden 为 true 的提供者
                    if provider.hidden == true { return false }
                    // 过滤掉无效的订阅信息
                    if let info = provider.subscriptionInfo, !info.isValid {
                        return false
                    }
                    return true
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                // print("📦 更新后的提供者数量: \(self.providers.count)")

                // 更新 providerNodes
                for (providerName, provider) in providersResponse.providers {
                    let nodes = provider.proxies.map { proxy in
                        ProxyNode(
                            id: proxy.id ?? UUID().uuidString,
                            name: proxy.name,
                            type: proxy.type,
                            alive: proxy.alive ?? true,
                            delay: proxy.history.last?.delay ?? 0,
                            history: proxy.history
                        )
                    }
                    providerNodesToUpdate[providerName] = nodes
                    // print("📦 提供者 \(providerName) 的节点数量: \(nodes.count)")
                }

                let providerNodes = providersResponse.providers.flatMap { _, provider in
                    provider.proxies.map { proxy in
                        ProxyNode(
                            id: proxy.id ?? UUID().uuidString,
                            name: proxy.name,
                            type: proxy.type,
                            alive: proxy.alive ?? true,
                            delay: proxy.history.last?.delay ?? 0,
                            history: proxy.history
                        )
                    }
                }
                allNodes.append(contentsOf: providerNodes)
            } else {
                print("解析 providers 数据失败")
                // 尝试打印原始数据以进行调试
//                let jsonString = String(data: providersData, encoding: .utf8)
                    // print("📝 原始 providers 数据:")
                    // print(jsonString)

            }

            // 在主线程上更新所有@Published属性
            await MainActor.run {
                self.allProxyDetails = allProxyDetailsToUpdate
                self.groups = groupsToUpdate
                self.providers = providersToUpdate
                self.providerNodes = providerNodesToUpdate
                self.nodes = allNodes
                objectWillChange.send()
            }

            // 检查是否所有节点都超时
            let nonSpecialNodes = allNodes.filter { node in
                !["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"].contains(node.name.uppercased())
            }

            if !nonSpecialNodes.isEmpty {
                let allNodesTimeout = nonSpecialNodes.allSatisfy { node in
                    node.delay == 0
                }

                if allNodesTimeout {
                    logger.warning("检测到所有节点都处于超时状态")

                    // 尝试对 GLOBAL 组进行一次自动测速
                    if self.groups.contains(where: { $0.name == "GLOBAL" }) {
                        logger.info("正在对 GLOBAL 组进行自动测速以尝试刷新节点状态")
                        Task {
                            await self.testGroupSpeed(groupName: "GLOBAL")
                        }
                    }
                }
            }

        } catch {
            logger.error("获取代理错误: \(error)")
            handleNetworkError(error)
        }
    }

    // 获取 Surge 代理数据
    private func fetchSurgeProxies() async {
        do {
            async let policiesTask = fetchSurgePolicies()
            async let policyGroupsTask = fetchSurgePolicyGroups()

            let (policies, policyGroups) = try await (policiesTask, policyGroupsTask)

            logger.info("获取到 Surge 数据 - 策略组: \(policies.policyGroups.count), 代理: \(policies.proxies.count)")

            // 获取当前代理模式
            let currentMode = try await fetchSurgeOutboundMode()
            logger.info("当前代理模式: \(currentMode)")

            // 更新当前代理模式属性
            await MainActor.run {
                self.currentOutboundMode = currentMode
            }

            // 将 Surge 数据转换为 Clash 格式
            var allNodes: [ProxyNode] = []
            var proxyGroups: [ProxyGroup] = []
            var localGroupSelections: [String: String] = [:]

            if currentMode == "proxy" {
                // 全局模式：创建一个 Global Proxy 组，包含所有代理
                logger.info("全局模式：创建 Global Proxy 组")

                // 获取 Global 模式的当前选择
                let globalSelection = try await fetchSurgeGlobalSelection()

                // 创建 Global Proxy 组，包含所有 proxies 和 policy-groups
                var allGlobalPolicies: [String] = []
                allGlobalPolicies.append(contentsOf: policies.proxies)
                allGlobalPolicies.append(contentsOf: policies.policyGroups)

                let globalGroup = ProxyGroup(
                    name: "Global Proxy",
                    type: "SurgeGlobal",
                    now: globalSelection,
                    all: allGlobalPolicies,
                    alive: true,
                    icon: nil
                )
                proxyGroups.append(globalGroup)
                localGroupSelections["Global Proxy"] = globalSelection

                // 处理策略组中的策略
                for groupName in policies.policyGroups {
                    if let groupPolicies = policyGroups.groups[groupName] {
                        // 将策略转换为 ProxyNode
                        for policy in groupPolicies {
                            let node = ProxyNode(
                                id: "\(groupName)_\(policy.name)",
                                name: policy.name,
                                type: policy.typeDescription,
                                alive: true,
                                delay: 0, // Surge 不提供延迟信息
                                history: []
                            )
                            allNodes.append(node)
                        }
                    }
                }

                // 处理单独的代理策略
                for proxyName in policies.proxies {
                    let node = ProxyNode(
                        id: "proxy_\(proxyName)",
                        name: proxyName,
                        type: "SurgeProxy",
                        alive: true,
                        delay: 0,
                        history: []
                    )
                    allNodes.append(node)
                }

            } else {
                // 非全局模式：显示正常的策略组
                logger.info("非全局模式：显示正常策略组")

                // 并发获取所有策略组的当前选择
                var selectionTasks: [String: Task<String?, Error>] = [:]
                for groupName in policies.policyGroups {
                    selectionTasks[groupName] = Task {
                        do {
                            return try await fetchSurgePolicySelection(groupName: groupName)
                        } catch {
                            logger.warning("获取策略组 '\(groupName)' 的当前选择失败: \(error.localizedDescription)")
                            return nil
                        }
                    }
                }

                // 等待所有选择获取完成
                for (groupName, task) in selectionTasks {
                    do {
                        let selection = try await task.value
                        localGroupSelections[groupName] = selection ?? ""
                    } catch {
                        logger.error("等待策略组 '\(groupName)' 选择结果时出错: \(error.localizedDescription)")
                        localGroupSelections[groupName] = ""
                    }
                }

                // 处理策略组
                for groupName in policies.policyGroups {
                    if let policies = policyGroups.groups[groupName] {
                        // 获取当前选中的策略（从并发获取的结果中）
                        let currentSelection = localGroupSelections[groupName] ?? ""

                        // 获取策略名称列表
                        let policyNames = policies.map { $0.name }

                        // 创建 ProxyGroup
                        let proxyGroup = ProxyGroup(
                            name: groupName,
                            type: "SurgePolicyGroup",
                            now: currentSelection,
                            all: policyNames,
                            alive: true,
                            icon: nil
                        )
                        proxyGroups.append(proxyGroup)

                        // 将策略转换为 ProxyNode
                        for policy in policies {
                            let node = ProxyNode(
                                id: "\(groupName)_\(policy.name)",
                                name: policy.name,
                                type: policy.typeDescription,
                                alive: true,
                                delay: 0, // Surge 不提供延迟信息
                                history: []
                            )
                            allNodes.append(node)
                        }
                    }
                }

                // 处理单独的代理策略
                for proxyName in policies.proxies {
                    let node = ProxyNode(
                        id: "proxy_\(proxyName)",
                        name: proxyName,
                        type: "SurgeProxy",
                        alive: true,
                        delay: 0,
                        history: []
                    )
                    allNodes.append(node)
                }
            }

            // 更新数据
            await MainActor.run {
                self.groups = proxyGroups
                self.nodes = allNodes
                self.providers = [] // Surge 没有 providers 概念
                self.providerNodes = [:]
                self.groupSelections = localGroupSelections // 保存策略组选择状态
                self.lastUpdated = Date()
                objectWillChange.send()
            }

            logger.info("成功转换 Surge 数据为 Clash 格式 - 模式: \(currentMode), 组: \(proxyGroups.count), 节点: \(allNodes.count)")

            // 执行智能测速（仅在非全局模式下）
            if currentMode != "global" {
                await performSmartSpeedTest(policyGroups: policyGroups)
            }

        } catch {
            logger.error("获取 Surge 代理数据失败: \(error.localizedDescription)")
            handleNetworkError(error)
        }
    }
    
    func testGroupDelay(groupName: String, nodes: [ProxyNode]) async {
        for node in nodes {
            if node.name == "REJECT" || node.name == "DIRECT" {
                continue
            }
            
            let encodedGroupName = groupName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? groupName
            let path = "group/\(encodedGroupName)/delay"
            
            guard var request = makeRequest(path: path) else { continue }
            
            var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: true)
            components?.queryItems = [
                URLQueryItem(name: "url", value: testUrl),
                URLQueryItem(name: "timeout", value: "\(testTimeout)")
            ]
            
            guard let finalUrl = components?.url else { continue }
            request.url = finalUrl
            
            _ = await MainActor.run {
                testingNodes.insert(node.name)
            }
            
            do {
                let (data, response) = try await URLSession.secure.data(for: request)
                
                // 检查 HTTPS 响应
                if server.clashUseSSL,
                   let httpsResponse = response as? HTTPURLResponse,
                   httpsResponse.statusCode == 400 {
                    // print("SSL 连接失败，服务器可能不支持 HTTPS")
                    continue
                }
                
                if let delays = try? JSONDecoder().decode([String: Int].self, from: data) {
                    for (nodeName, delay) in delays {
                        await updateNodeDelay(nodeName: nodeName, delay: delay)
                    }
                    await MainActor.run {
                        testingNodes.remove(node.name)
                    }
                }
            } catch {
                _ = await MainActor.run {
                    testingNodes.remove(node.name)
                }
                handleNetworkError(error)
            }
        }
    }
    
    private func handleNetworkError(_ error: Error) {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .secureConnectionFailed:
                // print("SSL 连接失败：服务器 SSL 证书无效")
                logger.error("SSL 连接失败：服务器 SSL 证书无效")
            case .serverCertificateHasBadDate:
                // print("SSL 错误：服务器证书已过期")
                logger.error("SSL 错误：服务器证书已过期")
            case .serverCertificateUntrusted:
                // print("SSL 错误：服务器证书不受信任")
                logger.error("SSL 错误：服务器证书不受信任")
            case .serverCertificateNotYetValid:
                // print("SSL 错误：服务器证书尚未生效")
                logger.error("SSL 错误：服务器证书尚未生效")
            case .cannotConnectToHost:
                // print("无法连接到服务器：\(server.clashUseSSL ? "HTTPS" : "HTTP") 连接失败")
                logger.error("无法连接到服务器：\(server.clashUseSSL ? "HTTPS" : "HTTP") 连接失败")
            default:
                // print("网络错误：\(urlError.localizedDescription)")
                logger.error("网络错误：\(urlError.localizedDescription)")
            }
        } else {
            // print("其他错误：\(error.localizedDescription)")
            logger.error("其他错误：\(error.localizedDescription)")
        }
    }
    
    @MainActor
    func selectProxy(groupName: String, proxyName: String) async {
        logger.info("开始切换代理 - 服务器类型: \(server.source), 组:\(groupName), 新节点:\(proxyName)")

        if server.source == .surge {
            // Surge 服务器：使用 Surge API
            await selectSurgeProxy(groupName: groupName, proxyName: proxyName)
        } else {
            // Clash/OpenWRT 服务器：使用原有逻辑
            await selectClashProxy(groupName: groupName, proxyName: proxyName)
        }
    }

    // Clash 代理选择（原有逻辑）
    private func selectClashProxy(groupName: String, proxyName: String) async {
        // 检查是否需要自动测速
        let shouldAutoTest = UserDefaults.standard.bool(forKey: "autoSpeedTestBeforeSwitch")
        logger.debug("自动测速设置状态: \(shouldAutoTest)")

        if shouldAutoTest {
            logger.debug("准备进行自动测速")
            // 只有在需要测速时才获取实际节点并测速
            let nodeToTest = await getActualNode(proxyName)
            logger.debug("获取到实际节点: \(nodeToTest)")

            if nodeToTest != "REJECT" {
                logger.debug("开始测试节点延迟")
                await testNodeDelay(nodeName: nodeToTest)
            } else {
                logger.debug("跳过 REJECT 节点的测速")
            }
        } else {
            logger.debug("自动测速已关闭，跳过测速步骤")
        }

        // 不需要在这里进行 URL 编码，因为 makeRequest 已经处理了
        guard var request = makeRequest(path: "proxies/\(groupName)") else {
            logger.error("创建请求失败")
            return
        }

        request.httpMethod = "PUT"
        let body = ["name": proxyName]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (_, response) = try await URLSession.secure.data(for: request)
            logger.info("切换请求成功")

            if server.clashUseSSL,
               let httpsResponse = response as? HTTPURLResponse,
               httpsResponse.statusCode == 400 {
                return
            }

            // 检查是否需要断开旧连接
            if UserDefaults.standard.bool(forKey: "autoDisconnectOldProxy") {
                logger.info("正在断开旧连接...")

                // 获取当前活跃的连接
                guard let connectionsRequest = makeRequest(path: "connections") else { return }
                let (data, _) = try await URLSession.secure.data(for: connectionsRequest)
                
                if let connectionsResponse = try? JSONDecoder().decode(ConnectionsResponse.self, from: data) {
                    let totalConnections = connectionsResponse.connections.count
                    logger.info("当前活跃连接数: \(totalConnections)")
                    
                    // 找到需要断开的连接
                    let connectionsToClose = connectionsResponse.connections.filter { connection in
                        // 检查该连接是否与当前正在切换的代理组相关
                        // logger.debug("检查连接: \(connection.chains.joined(separator: " → "))")
                        // logger.debug("切换组: \(groupName), 新节点: \(proxyName)")
                        
                        if let groupIndex = connection.chains.firstIndex(of: groupName) {
                            // 如果连接链中包含该组，检查是否需要断开
                            if groupIndex + 1 < connection.chains.count {
                                // 组后面的节点不是我们新选择的节点则需要断开
                                let currentProxy = connection.chains[groupIndex + 1]
                                let shouldClose = currentProxy != proxyName
                                
                                if shouldClose {
                                    logger.debug("需要断开连接: 当前使用\(currentProxy), 切换到\(proxyName)")
                                }
                                
                                return shouldClose
                            }
                        }
                        
                        return false
                    }
                    logger.info("找到 \(connectionsToClose.count) 个需要断开的连接")
                    
                    // 遍历并关闭连接
                    for connection in connectionsToClose {
                        // 构建关闭连接的请求
                        guard var closeRequest = makeRequest(path: "connections/\(connection.id)") else { 
                            logger.error("创建关闭连接请求失败: \(connection.id)")
                            continue 
                        }
                        closeRequest.httpMethod = "DELETE"
                        
                        // 发送关闭请求
                        let (_, closeResponse) = try await URLSession.secure.data(for: closeRequest)
                        if let closeHttpResponse = closeResponse as? HTTPURLResponse,
                           closeHttpResponse.statusCode == 204 {
                            logger.debug("成功关闭连接: \(connection.id), 目标: \(connection.metadata.host):\(connection.metadata.destinationPort)")
                        } else {
                            logger.error("关闭连接失败: \(connection.id)")
                        }
                    }
                    
                    logger.info("完成断开旧连接操作，成功关闭 \(connectionsToClose.count) 个连接")
                } else {
                    logger.error("获取连接信息失败")
                }
            }
            
            await fetchProxies()
            logger.info("代理切换完成")
            
        } catch {
            handleNetworkError(error)
        }
    }

    // Surge 代理选择
    private func selectSurgeProxy(groupName: String, proxyName: String) async {
        do {
            if groupName == "Global Proxy" {
                // Global Proxy 组使用特殊的 API
                try await selectSurgeGlobalPolicy(policyName: proxyName)
                logger.info("Surge Global 模式切换完成 - 策略: \(proxyName)")

                // 确认切换结果
                let confirmedSelection = try await fetchSurgeGlobalSelection()
                logger.info("Surge Global 模式切换确认 - 确认的选择: \(confirmedSelection)")

                // 更新 UI 数据
                await MainActor.run {
                    // 更新 groupSelections
                    self.groupSelections[groupName] = confirmedSelection

                    // 更新对应的 ProxyGroup 的 now 属性
                    if let groupIndex = self.groups.firstIndex(where: { $0.name == groupName }) {
                        self.groups[groupIndex].now = confirmedSelection
                    }

                    // 通知 UI 更新
                    self.objectWillChange.send()
                }
            } else {
                // 普通策略组使用原有的逻辑
                // 1. 发送 POST 请求切换代理组选择
                try await selectSurgePolicy(groupName: groupName, policyName: proxyName)
                logger.info("Surge 代理切换 POST 请求完成 - 组: \(groupName), 策略: \(proxyName)")

                // 2. 发送 GET 请求确认切换结果
                let confirmedSelection = try await fetchSurgePolicySelection(groupName: groupName)
                logger.info("Surge 代理切换确认 - 组: \(groupName), 确认的选择: \(confirmedSelection)")

                // 3. 更新 UI 数据
                await MainActor.run {
                    // 更新 groupSelections
                    self.groupSelections[groupName] = confirmedSelection

                    // 更新对应的 ProxyGroup 的 now 属性
                    if let groupIndex = self.groups.firstIndex(where: { $0.name == groupName }) {
                        self.groups[groupIndex].now = confirmedSelection
                    }

                    // 通知 UI 更新
                    self.objectWillChange.send()
                }
            }

        } catch {
            logger.error("Surge 代理切换失败: \(error.localizedDescription)")
            handleNetworkError(error)
        }
    }

    // 添加获取实际节点的方法
    private func getActualNode(_ nodeName: String, visitedGroups: Set<String> = []) async -> String {
        // 防止循环依赖
        if visitedGroups.contains(nodeName) {
            return nodeName
        }
        
        // 如果是代理组，递归获取当前选中的节点
        if let group = groups.first(where: { $0.name == nodeName }) {
            var visited = visitedGroups
            visited.insert(nodeName)
            return await getActualNode(group.now, visitedGroups: visited)
        }
        
        // 如果是实际节点或特殊节点，直接返回
        return nodeName
    }
    
    @MainActor
    func testNodeDelay(nodeName: String) async {
        // print("⏱️ 开始测试节点延迟: \(nodeName)")
        
        // 不需要在这里进行 URL 编码，因为 makeRequest 已经处理了
        guard var request = makeRequest(path: "proxies/\(nodeName)/delay") else {
            // print("创建延迟测试请求失败")
            return
        }
        
        // 添加测试参数
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "url", value: testUrl),
            URLQueryItem(name: "timeout", value: "\(testTimeout)")
        ]
        
        guard let finalUrl = components?.url else {
            // print("创建最终 URL 失败")
            return
        }
        request.url = finalUrl
        
        // 设置测试状态
        testingNodes.insert(nodeName)
        // print("节点已加入测试集合: \(nodeName)")
        objectWillChange.send()
        
        do {
            let (data, response) = try await URLSession.secure.data(for: request)
            // print("收到延迟测试响应")
            
            if server.clashUseSSL,
               let httpsResponse = response as? HTTPURLResponse,
               httpsResponse.statusCode == 400 {
                // print("SSL 连接失败")
                testingNodes.remove(nodeName)
                objectWillChange.send()
                return
            }
            
            // 解析延迟数据
            struct DelayResponse: Codable {
                let delay: Int
            }
            
            if let delayResponse = try? JSONDecoder().decode(DelayResponse.self, from: data) {
                logger.debug("节点 \(nodeName) 的新延迟: \(delayResponse.delay)")
                // 更新节点延迟
                await updateNodeDelay(nodeName: nodeName, delay: delayResponse.delay)
                await MainActor.run {
                    testingNodes.remove(nodeName)
                    self.lastDelayTestTime = Date()
                    objectWillChange.send()
                }
                // print("延迟更新完成")
            } else {
                // print("解析延迟数据失败")
                testingNodes.remove(nodeName)
                objectWillChange.send()
            }
            
        } catch {
            // print("测试节点延迟时发生错误: \(error)")
            testingNodes.remove(nodeName)
            objectWillChange.send()
            handleNetworkError(error)
        }
    }
    
    // 修改更新节点延迟的方法
    private func updateNodeDelay(nodeName: String, delay: Int) async {
        // logger.log("开始更新节点延迟 - 节点:\(nodeName), 新延迟:\(delay)")

        await MainActor.run {
            if let index = nodes.firstIndex(where: { $0.name == nodeName }) {
                let oldDelay = nodes[index].delay
                let updatedNode = ProxyNode(
                    id: nodes[index].id,
                    name: nodeName,
                    type: nodes[index].type,
                    alive: true,
                    delay: delay,
                    history: nodes[index].history
                )
                nodes[index] = updatedNode
                logger.info("节点（\(nodeName)）延迟已更新 - 原延迟:\(oldDelay), 新延迟:\(delay)")
                objectWillChange.send()
            } else {
                logger.error("未找到要更新的节点: \(nodeName)")
            }
        }
    }
    
    @MainActor
    func refreshAllData() async {
        // 1. 获取理数据
        await fetchProxies()
        
        // 2. 测试所有节点延迟
        for group in groups {
            if let nodes = providerNodes[group.name] {
                await testGroupDelay(groupName: group.name, nodes: nodes)
            }
        }
        
        logger.info("刷新所有数据完成")
    }
    
    // 修改组测速方法
    @MainActor
    func testGroupSpeed(groupName: String) async {
        logger.info("开始测速 - 服务器类型: \(server.source), 组: \(groupName)")

        if server.source == .surge {
            // Surge 服务器：使用 Surge API
            await testSurgeGroupSpeed(groupName: groupName)
        } else {
            // Clash/OpenWRT 服务器：使用原有逻辑
            await testClashGroupSpeed(groupName: groupName)
        }
    }

    // Clash 组测速（原有逻辑）
    private func testClashGroupSpeed(groupName: String) async {
        // print("开始测速组: \(groupName)")
        // print("测速前节点状态:")
        if let group = groups.first(where: { $0.name == groupName }) {
            for nodeName in group.all {
                if nodes.contains(where: { $0.name == nodeName }) {
                    // print("节点: \(nodeName), 延迟: \(node.delay)")
                }
            }
        }

        // 添加到测速集合
        await MainActor.run {
            testingGroups.insert(groupName)
            objectWillChange.send()
        }

        let encodedGroupName = groupName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? groupName
        guard var request = makeRequest(path: "group/\(encodedGroupName)/delay") else {
            // print("创建请求失败")
            return
        }
        
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "url", value: testUrl),
            URLQueryItem(name: "timeout", value: "\(testTimeout)")
        ]
        
        guard let finalUrl = components?.url else {
            // print("创建最终 URL 失败")
            return
        }
        request.url = finalUrl
        
        // print("发送测速请求: \(finalUrl)")
        
        do {
            let (data, response) = try await URLSession.secure.data(for: request)
            // print("收到服务器响应: \(response)")
            
            if server.clashUseSSL,
               let httpsResponse = response as? HTTPURLResponse,
               httpsResponse.statusCode == 400 {
                // print("SSL 连接失败，服务器可能不支持 HTTPS")
                testingGroups.remove(groupName)
                objectWillChange.send()
                return
            }
            
            // print("解析响应数据...")
            if let decodedData = try? JSONDecoder().decode([String: Int].self, from: data) {
                // print("\n收到测速响应:")
                for (nodeName, delay) in decodedData {
                    // print("节点: \(nodeName), 新延迟: \(delay)")
                    // 直接更新节点延迟，不需要先 fetchProxies
                    await updateNodeDelay(nodeName: nodeName, delay: delay)
                }
                
                // 如果是 URL-Test 类型的组，自动切换到延迟最低的节点
                if let group = groups.first(where: { $0.name == groupName }),
                   group.type == "URLTest" {
                    // 找出延迟最低的节点
                    var lowestDelay = Int.max
                    var bestNode = ""
                    
                    for nodeName in group.all {
                        if nodeName == "DIRECT" || nodeName == "REJECT" {
                            continue
                        }
                        let delay = getNodeDelay(nodeName: nodeName)
                        if delay > 0 && delay < lowestDelay {
                            lowestDelay = delay
                            bestNode = nodeName
                        }
                    }
                    
                    // 如果找到了最佳节点，切换到该节点
                    if !bestNode.isEmpty {
                        logger.info("URL-Test 组测速完成，自动切换到最佳节点: \(bestNode) (延迟: \(lowestDelay)ms)")
                        await selectProxy(groupName: groupName, proxyName: bestNode)
                    }
                }
                
                // print("\n更新后节点状态:")
                if let group = groups.first(where: { $0.name == groupName }) {
                    for nodeName in group.all {
                        if nodes.contains(where: { $0.name == nodeName }) {
                            // print("节点: \(nodeName), 最终延迟: \(node.delay)")
                        }
                    }
                }
                
                // 更新最后测试时间并通知视图更新
                await MainActor.run {
                    self.lastDelayTestTime = Date()
                    objectWillChange.send()
                }
            }
        } catch {
            // print("测速过程出错: \(error)")
            handleNetworkError(error)
        }

        // print("测速完成，移除测速状态")
        await MainActor.run {
            testingGroups.remove(groupName)
            objectWillChange.send()
        }
    }

    // Surge 组测速
    private func testSurgeGroupSpeed(groupName: String) async {
        do {
            // 添加到测速集合
            await MainActor.run {
                testingGroups.insert(groupName)
                objectWillChange.send()
            }

            logger.info("开始 Surge 策略组测速: \(groupName)")

            // 1. 触发策略组测速
            _ = try await testSurgePolicyGroup(groupName: groupName)

            // 2. 等待一段时间让测速完成
            try await Task.sleep(nanoseconds: 500_000_000) // 等待 0.5 秒

            // 3. 获取策略组的策略列表和性能基准测试结果
            async let policyGroupsTask = fetchSurgePolicyGroups()
            async let benchmarkResultsTask = fetchSurgeBenchmarkResults()

            let (policyGroups, benchmarkResults) = try await (policyGroupsTask, benchmarkResultsTask)

            logger.info("获取到 \(benchmarkResults.count) 个策略的测速结果")

            // 4. 获取指定策略组的策略列表
            guard let groupPolicies = policyGroups.groups[groupName] else {
                logger.warning("未找到策略组 '\(groupName)' 的策略列表")
                await MainActor.run {
                    self.lastDelayTestTime = Date()
                    testingGroups.remove(groupName)
                    objectWillChange.send()
                }
                return
            }

            // 5. 通过 lineHash 匹配策略与性能数据
            for policy in groupPolicies {
                guard let lineHash = policy.lineHash else {
                    logger.warning("策略 '\(policy.name)' 没有 lineHash，跳过")
                    continue
                }

                // 在性能基准结果中查找匹配的策略
                if let benchmarkResult = benchmarkResults[lineHash] {
                    let delay = benchmarkResult.latency

                    // 更新对应节点的延迟
                    await updateNodeDelay(nodeName: policy.name, delay: delay)

                    let errorInfo = benchmarkResult.hasError ? " (错误: \(benchmarkResult.lastTestErrorMessage ?? "未知"))" : ""
                    print("策略 '\(policy.name)' 测速结果: 延迟=\(delay)ms\(errorInfo)")
                    logger.info("策略 '\(policy.name)' 测速结果: 延迟=\(delay)ms\(errorInfo)")
                } else {
                    logger.warning("策略 '\(policy.name)' (lineHash: \(lineHash)) 没有找到对应的性能基准数据")
                }
            }

            logger.info("Surge 策略组测速完成: \(groupName)")

            await MainActor.run {
                self.lastDelayTestTime = Date()
                testingGroups.remove(groupName)
                objectWillChange.send()
            }

        } catch {
            logger.error("Surge 策略组测速失败: \(error.localizedDescription)")
            handleNetworkError(error)

            await MainActor.run {
                testingGroups.remove(groupName)
                objectWillChange.send()
            }
        }
    }

    @MainActor
    func updateProxyProvider(providerName: String) async {
        let encodedProviderName = providerName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? providerName
        guard var request = makeRequest(path: "providers/proxies/\(encodedProviderName)") else { return }
        
        request.httpMethod = "PUT"

        // print("\(request.url)")
        
        do {
            let (_, response) = try await URLSession.secure.data(for: request)
            
            if server.clashUseSSL,
               let httpsResponse = response as? HTTPURLResponse,
               httpsResponse.statusCode == 400 {
                // print("SSL 连接失败，服务器可能不支持 HTTPS")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                // print("代理提供者 \(providerName) 更新成功")
                logger.info("代理提供者 \(providerName) 更新成功")
                
                // 等待一小段时间确保服务器处理完成
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                
                // 在主线程上更新
                _ = await MainActor.run {
                    // 更新时间戳
                    self.lastUpdated = Date()
                    
                    // 刷数据
                    Task {
                        await self.fetchProxies()
                    }
                }
            } else {
                logger.error("代理提供者 \(providerName) 更新失败")
            }
        } catch {
            handleNetworkError(error)
        }
    }
    
    // 代理提供者整体健康检查
    @MainActor
    func healthCheckProvider(providerName: String) async {
        let encodedProviderName = providerName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? providerName
        guard let request = makeRequest(path: "providers/proxies/\(encodedProviderName)/healthcheck") else { return }
        
        // 添加到测试集合
        testingProviders.insert(providerName)
        objectWillChange.send()
        
        do {
            let (_, response) = try await URLSession.secure.data(for: request)
            
            if server.clashUseSSL,
               let httpsResponse = response as? HTTPURLResponse,
               httpsResponse.statusCode == 400 {
                // print("SSL 连接失败，服务器可能不支持 HTTPS")
                testingProviders.remove(providerName)  // 记得移除
                return
            }
            
            // 等待一小段时间确保服务器处理完成
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            
            // 在主线程刷新数据
            _ = await MainActor.run {
                Task {
                    await self.fetchProxies()
                    self.lastDelayTestTime = Date()
                    testingProviders.remove(providerName)  // 记得移除
                    objectWillChange.send()
                }
            }
            
        } catch {
            testingProviders.remove(providerName)  // 记得移除
            handleNetworkError(error)
        }
    }
    
    // 代理提供者中单个节点的健康检查
    @MainActor
    func healthCheckProviderProxy(providerName: String, proxyName: String) async {
        let encodedProviderName = providerName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? providerName
        let encodedProxyName = proxyName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? proxyName
        
        guard var request = makeRequest(path: "providers/proxies/\(encodedProviderName)/\(encodedProxyName)/healthcheck") else { return }
        
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "url", value: testUrl),
            URLQueryItem(name: "timeout", value: "\(testTimeout)")
        ]
        
        guard let finalUrl = components?.url else { return }
        request.url = finalUrl

        // print("\(request.url)")
        
        // 设置测试状
        await MainActor.run {
            testingNodes.insert(proxyName)
            objectWillChange.send()
        }
        
        do {
            let (data, response) = try await URLSession.secure.data(for: request)
            
            if server.clashUseSSL,
               let httpsResponse = response as? HTTPURLResponse,
               httpsResponse.statusCode == 400 {
                // print("SSL 连接失败，服务器可能不支持 HTTPS")
                _ = await MainActor.run {
                    testingNodes.remove(proxyName)
                    objectWillChange.send()
                }
                return
            }
            
            // 解析返回的延迟数据
            struct DelayResponse: Codable {
                let delay: Int
            }
            
            if let delayResponse = try? JSONDecoder().decode(DelayResponse.self, from: data) {
                // 更新节点延迟
                await updateNodeDelay(nodeName: proxyName, delay: delayResponse.delay)
                await MainActor.run {
                    testingNodes.remove(proxyName)
                    self.lastDelayTestTime = Date()  // 发视图更新
                    objectWillChange.send()
                    
                    // 刷新数据
                    Task {
                        await self.fetchProxies()
                    }
                }
            } else {
                // 如果析失败，确保移除节点名称
                await MainActor.run {
                    testingNodes.remove(proxyName)
                    objectWillChange.send()
                }
            }
            
        } catch {
            _ = await MainActor.run {
                testingNodes.remove(proxyName)
                objectWillChange.send()
            }
            handleNetworkError(error)
        }
    }
    
    // 修改 getSortedGroups 方法，只保留 GLOBAL 组排序逻辑
    func getSortedGroups() -> [ProxyGroup] {
        // 对于 Surge 控制器，根据代理模式决定显示内容
        if server.source == .surge {
            // Surge API 返回: rule(规则)/proxy(全局)/direct(直连)
            // 我们将 proxy 映射为 global 模式
            let isGlobalMode = currentOutboundMode == "proxy"

            if isGlobalMode {
                // 全局模式下只显示 Global Proxy 组
                return groups.filter { $0.name == "Global Proxy" }
            } else {
                // 非全局模式显示正常的策略组，保持 API 返回的顺序
                return groups.filter { $0.name != "Global Proxy" }
            }
        }

        // 对于 Clash/OpenWRT 控制器，使用原来的排序逻辑
        // 获取智能显示设置
        let smartDisplay = UserDefaults.standard.bool(forKey: "smartProxyGroupDisplay")

        // 如果启用了智能显示，根据当前模式过滤组
        if smartDisplay {
            // 获取当前模式
            let currentMode = UserDefaults.standard.string(forKey: "currentMode") ?? "rule"

            // 根据模式过滤组
            let filteredGroups = groups.filter { group in
                switch currentMode {
                case "global":
                    // 全局模式下只显示 GLOBAL 组
                    return group.name == "GLOBAL"
                case "rule", "direct":
                    // 规则和直连模式下隐藏 GLOBAL 组
                    return group.name != "GLOBAL"
                default:
                    return true
                }
            }

            // 对过滤后的组进行排序
            if let globalGroup = groups.first(where: { $0.name == "GLOBAL" }) {
                var sortIndex = globalGroup.all
                sortIndex.append("GLOBAL")

                return filteredGroups.sorted { group1, group2 in
                    let index1 = sortIndex.firstIndex(of: group1.name) ?? Int.max
                    let index2 = sortIndex.firstIndex(of: group2.name) ?? Int.max
                    return index1 < index2
                }
            }

            return filteredGroups.sorted { $0.name < $1.name }
        }

        // 如果没有启用智能显示，使用原来的排序逻辑
        if let globalGroup = groups.first(where: { $0.name == "GLOBAL" }) {
            var sortIndex = globalGroup.all
            sortIndex.append("GLOBAL")

            return groups.sorted { group1, group2 in
                let index1 = sortIndex.firstIndex(of: group1.name) ?? Int.max
                let index2 = sortIndex.firstIndex(of: group2.name) ?? Int.max
                return index1 < index2
            }
        }

        return groups.sorted { $0.name < $1.name }
    }
    
    // 修改节点排序方法
    func getSortedNodes(_ nodeNames: [String], in group: ProxyGroup) -> [String] {
        // 获取排序设置
        let sortOrder = UserDefaults.standard.string(forKey: "proxyGroupSortOrder") ?? "default"
        let pinBuiltinProxies = UserDefaults.standard.bool(forKey: "pinBuiltinProxies")
        let hideUnavailable = UserDefaults.standard.bool(forKey: "hideUnavailableProxies")
        
        // 如果不置顶内置策略，且排序方式为默认，则保持原始顺序
        if !pinBuiltinProxies && sortOrder == "default" {
            if hideUnavailable {
                return nodeNames.filter { node in
                    getNodeDelay(nodeName: node) > 0
                }
            }
            return nodeNames
        }
        
        // 特殊节点始终排在最前面（添加 PROXY）
        let builtinNodes = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"]
        let specialNodes = nodeNames.filter { node in
            builtinNodes.contains(node.uppercased())
        }
        let normalNodes = nodeNames.filter { node in
            !builtinNodes.contains(node.uppercased())
        }
        
        // 对普通节点应用隐藏不可用代理的设置
        let filteredNormalNodes = hideUnavailable ? 
            normalNodes.filter { node in
                getNodeDelay(nodeName: node) > 0
            } : normalNodes
            
        // 如果开启了置顶内置策略，直接返回特殊节点+排序后的普通节点
        if pinBuiltinProxies {
            let sortedNormalNodes = sortNodes(filteredNormalNodes, sortOrder: sortOrder)
            return specialNodes + sortedNormalNodes
        }
        
        // 如果没有开启置顶内置策略，所有节点一起参与排序
        let allNodes = hideUnavailable ? 
            (specialNodes + filteredNormalNodes) : nodeNames
        return sortNodes(allNodes, sortOrder: sortOrder)
    }
    
    // 添加辅助方法来处理节点排序
    // 排序优先级：有效延迟 > 超时(0) > 无延迟信息(-1)
    private func sortNodes(_ nodes: [String], sortOrder: String) -> [String] {
        switch sortOrder {
        case "latencyAsc":
            return nodes.sorted { node1, node2 in
                let delay1 = getNodeDelay(nodeName: node1)
                let delay2 = getNodeDelay(nodeName: node2)
                
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
        case "latencyDesc":
            return nodes.sorted { node1, node2 in
                let delay1 = getNodeDelay(nodeName: node1)
                let delay2 = getNodeDelay(nodeName: node2)
                
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
        case "nameAsc":
            return nodes.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        case "nameDesc":
            return nodes.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
        default:
            return nodes
        }
    }
    
    // 修改 getNodeDelay 方法,增加对 LoadBalance 类型的特殊处理
    // 返回值说明: -1=无延迟信息, 0=超时, >0=有效延迟
    func getNodeDelay(nodeName: String, visitedGroups: Set<String> = []) -> Int {
        // 防止循环引用
        if visitedGroups.contains(nodeName) {
            return -1 // 循环引用认为是无延迟信息
        }
        
        // 如果是内置节点,直接返回其延迟
        if ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"].contains(nodeName.uppercased()) {
            // 查找节点并返回延迟
            if let node = nodes.first(where: { $0.name == nodeName }) {
                return node.delay
            }
            return -1 // 内置节点找不到认为是无延迟信息
        }
        
        var visitedCopy = visitedGroups
        visitedCopy.insert(nodeName)

        // 优先检查 allProxyDetails 是否为组类型
        if let detail = self.allProxyDetails[nodeName], detail.all != nil {
            if detail.type == "LoadBalance" {
                // LoadBalance 组的延迟可能直接记录在 nodes 数组中
                if let node = nodes.first(where: { $0.name == nodeName }) {
                    return node.delay
                }
                return -1 // 如果 LB 组本身不在 nodes 中，则认为无延迟信息
            }
            
            // 其他类型的代理组 (Selector, URLTest 等), 递归获取当前选中节点的延迟
            if let currentNow = detail.now, !currentNow.isEmpty {
                return getNodeDelay(nodeName: currentNow, visitedGroups: visitedCopy)
            } else {
                // 如果组没有 now 指向或指向为空，则认为无延迟信息
                return -1
            }
        }
        
        // 如果不是 allProxyDetails 中的组，则检查是否为普通节点
        if let node = nodes.first(where: { $0.name == nodeName }) {
            return node.delay
        }
        
        return -1 // 未找到节点或无法解析，返回-1表示无延迟信息
    }
    
    // 添加打印代理组嵌套结构的方法
    func printProxyGroupStructure() {
        print("\n===== 代理组嵌套结构 =====")
        for group in groups {
            print("代理组: \(group.name) [\(group.type)]")
            printNodeStructure(nodeName: group.now, level: 1, visitedGroups: Set([group.name]))
            print("------------------------")
        }
        print("=========================\n")
    }
    
    // 辅助方法：递归打印节点结构
    func printNodeStructure(nodeName: String, level: Int, visitedGroups: Set<String>) {
        let indent = String(repeating: "  ", count: level)
        
        // 防止循环引用
        if visitedGroups.contains(nodeName) {
            print("\(indent)循环引用: \(nodeName)")
            return
        }
        
        // 特殊内置节点
        if ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"].contains(nodeName.uppercased()) {
            print("\(indent)📌 内置节点: \(nodeName)")
            return
        }
        
        var visitedCopy = visitedGroups
        visitedCopy.insert(nodeName)
        
        // 优先检查 allProxyDetails 是否为组类型
        if let detail = self.allProxyDetails[nodeName], detail.all != nil {
            //  使用新的 getNodeDelay 获取延迟
            let effectiveDelay = getNodeDelay(nodeName: nodeName, visitedGroups: Set())
            print("\(indent)📦 子代理组: \(nodeName) [\(detail.type)] 延迟: \(effectiveDelay)ms")
            
            if detail.type == "LoadBalance" {
                print("\(indent)  ⚖️ 负载均衡组，包含 \(detail.all?.count ?? 0) 个节点")
                // 可选：如果需要，可以打印 LoadBalance 组的成员
                // for memberNodeName in detail.all ?? [] {
                //     printNodeStructure(nodeName: memberNodeName, level: level + 1, visitedGroups: visitedCopy)
                // }
                return
            }
            
            // 其他类型的代理组 (Selector, URLTest), 如果 'now' 存在则递归
            if let currentNow = detail.now, !currentNow.isEmpty {
                printNodeStructure(nodeName: currentNow, level: level + 1, visitedGroups: visitedCopy)
            } else {
                print("\(indent)  👉 (组配置不完整或已达末端)")
            }
            return
        }
        
        // 如果不是 allProxyDetails 中的组，则检查是否为普通节点
        if let node = nodes.first(where: { $0.name == nodeName }) {
            print("\(indent)🔸 实际节点: \(nodeName) 延迟: \(node.delay)ms")
            return
        }
        
        // 未找到的节点
        print("\(indent)❓ 未知节点: \(nodeName)")
    }
    
    // 添加一个方法来获取并打印节点的完整路径
    func getNodePath(groupName: String) -> String {
        var path = [groupName]
        var visitedGroups = Set<String>([groupName])
        var currentName = groupName
        
        while let proxyGroup = groups.first(where: { $0.name == currentName }) {
            if proxyGroup.type == "LoadBalance" {
                path.append("[\(proxyGroup.type)]")
                break
            }
            
            let nextName = proxyGroup.now
            if visitedGroups.contains(nextName) {
                path.append("循环引用: \(nextName)")
                break
            }
            
            path.append(nextName)
            visitedGroups.insert(nextName)
            currentName = nextName
            
            // 如果是特殊节点或普通节点则结束
            if ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"].contains(nextName.uppercased()) ||
                !groups.contains(where: { $0.name == nextName }) {
                break
            }
        }
        
        return path.joined(separator: " → ")
    }
    
    // 添加获取实际节点和延迟的方法
    // 返回值说明: 延迟 -1=无延迟信息, 0=超时, >0=有效延迟
    func getActualNodeAndDelay(nodeName: String, visitedGroups: Set<String> = []) -> (String, Int) {
        // 防止循环依赖
        if visitedGroups.contains(nodeName) {
            return (nodeName, -1)
        }
        
        var visitedCopy = visitedGroups
        visitedCopy.insert(nodeName)

        // 优先检查 allProxyDetails 是否为组类型
        if let detail = self.allProxyDetails[nodeName], detail.all != nil {
            if detail.type == "LoadBalance" {
                // 对于 LoadBalance 组，其本身就是一个节点，直接返回其信息
                let delay = getNodeDelay(nodeName: nodeName, visitedGroups: Set()) // 使用更新后的 getNodeDelay
                return (nodeName, delay)
            }
            
            // 其他类型的代理组 (Selector, URLTest 等), 递归获取
            if let currentNow = detail.now, !currentNow.isEmpty {
                return getActualNodeAndDelay(nodeName: currentNow, visitedGroups: visitedCopy)
            } else {
                // 如果组没有 now 指向或指向为空，则返回组本身，无延迟信息
                return (nodeName, -1)
            }
        }
        
        // 如果不是 allProxyDetails 中的组，则检查是否为普通节点
        if let node = nodes.first(where: { $0.name == nodeName }) {
            return (node.name, node.delay)
        }
        
        // 如果是特殊节点 (DIRECT/REJECT) 或未知节点
        return (nodeName, -1)
    }
    
    // 添加方法来保存节点顺序
    func saveNodeOrder(for groupName: String, nodes: [String]) {
        savedNodeOrder[groupName] = nodes
    }
    
    // 添加方法来清除保存的节点顺序
    func clearSavedNodeOrder(for groupName: String) {
        savedNodeOrder.removeValue(forKey: groupName)
    }
}

// API 响应模型
struct ProxyResponse: Codable {
    let proxies: [String: ProxyDetail]
}

// 修改 ProxyDetail 结构体，使其更灵活
struct ProxyDetail: Codable {
    let name: String
    let type: String
    let now: String?
    let all: [String]?
    let history: [ProxyHistory]
    let icon: String?
    
    // 添加可选字段
    let alive: Bool?
    let hidden: Bool?
    let tfo: Bool?
    let udp: Bool?
    let xudp: Bool?
    let extra: [String: AnyCodable]?
    let id: String?
    
    private enum CodingKeys: String, CodingKey {
        case name, type, now, all, history
        case alive, hidden, icon, tfo, udp, xudp, extra, id
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 必需字段
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        
        // 可选字段
        now = try container.decodeIfPresent(String.self, forKey: .now)
        all = try container.decodeIfPresent([String].self, forKey: .all)
        
        // 处理 history 字段
        if let historyArray = try? container.decode([ProxyHistory].self, forKey: .history) {
            history = historyArray
        } else {
            history = []
        }
        
        // 其他可选字段
        alive = try container.decodeIfPresent(Bool.self, forKey: .alive)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        tfo = try container.decodeIfPresent(Bool.self, forKey: .tfo)
        udp = try container.decodeIfPresent(Bool.self, forKey: .udp)
        xudp = try container.decodeIfPresent(Bool.self, forKey: .xudp)
        extra = try container.decodeIfPresent([String: AnyCodable].self, forKey: .extra)
        id = try container.decodeIfPresent(String.self, forKey: .id)
    }
}

// 添加 AnyCodable 类型来处理任意类型的值
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// 添加 ProviderResponse 结构体
struct ProviderResponse: Codable {
    let type: String
    let vehicleType: String
    let proxies: [ProxyInfo]?
    let testUrl: String?
    let subscriptionInfo: SubscriptionInfo?
    let updatedAt: String?
}

// 添加 Extra 结构体定义
struct Extra: Codable {
    let alpn: [String]?
    let tls: Bool?
    let skip_cert_verify: Bool?
    let servername: String?
}

struct ProxyInfo: Codable {
    let name: String
    let type: String
    let alive: Bool
    let history: [ProxyHistory]
    let extra: Extra?
    let id: String?
    let tfo: Bool?
    let xudp: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case name, type, alive, history, extra, id, tfo, xudp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        alive = try container.decode(Bool.self, forKey: .alive)
        history = try container.decode([ProxyHistory].self, forKey: .history)
        
        // Meta 服务器特有的字段设为选
        extra = try container.decodeIfPresent(Extra.self, forKey: .extra)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        tfo = try container.decodeIfPresent(Bool.self, forKey: .tfo)
        xudp = try container.decodeIfPresent(Bool.self, forKey: .xudp)
    }
    
    // 添加编码方法
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(alive, forKey: .alive)
        try container.encode(history, forKey: .history)
        try container.encodeIfPresent(extra, forKey: .extra)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(tfo, forKey: .tfo)
        try container.encodeIfPresent(xudp, forKey: .xudp)
    }
}

// MARK: - Surge API Methods
extension ProxyViewModel {

    // 获取 Surge 策略和策略组列表
    func fetchSurgePolicies() async throws -> SurgePolicies {
        guard let request = makeRequest(path: "v1/policies") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.secure.data(for: request)
        let policies = try JSONDecoder().decode(SurgePolicies.self, from: data)
        logger.info("成功获取 Surge 策略列表 - 策略组: \(policies.policyGroups.count), 代理: \(policies.proxies.count)")
        return policies
    }

    // 获取 Surge 策略组详细信息
    func fetchSurgePolicyGroups() async throws -> SurgePolicyGroups {
        guard let request = makeRequest(path: "v1/policy_groups") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.secure.data(for: request)

        // Surge API 返回的是一个对象，每个键都是策略组名，值是策略数组
        // 我们需要特殊处理这个响应
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = jsonObject as? [String: [[String: Any]]] else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid policy groups format"))
        }

        var groups: [String: [SurgePolicy]] = [:]
        for (groupName, policiesData) in dict {
            let policies = try policiesData.map { policyDict -> SurgePolicy in
                let policyData = try JSONSerialization.data(withJSONObject: policyDict, options: [])
                return try JSONDecoder().decode(SurgePolicy.self, from: policyData)
            }
            groups[groupName] = policies
        }

        // 创建 SurgePolicyGroups 实例
        let policyGroups = SurgePolicyGroups(groups: groups)
        return policyGroups
    }

    // 获取指定策略组当前选择的策略
    func fetchSurgePolicySelection(groupName: String) async throws -> String {
        // Surge 使用 surgeUseSSL 设置
        let scheme = server.surgeUseSSL ? "https" : "http"

        // 对策略组名称进行 URL 编码
        let encodedGroupName = groupName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? groupName

        // 构建完整的 URL
        let urlString = "\(scheme)://\(server.url):\(server.port)/v1/policy_groups/select?group_name=\(encodedGroupName)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)

        // Surge 使用 x-key 认证头
        if let surgeKey = server.surgeKey, !surgeKey.isEmpty {
            request.setValue(surgeKey, forHTTPHeaderField: "x-key")
        }

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // print("request: \(request)")

        let (data, _) = try await URLSession.secure.data(for: request)
        // print("Response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode data")")
        let selection = try JSONDecoder().decode(SurgePolicySelection.self, from: data)
        logger.info("策略组 '\(groupName)' 当前选择: \(selection.policy)")
        return selection.policy
    }

    // 选择策略组中的策略
    func selectSurgePolicy(groupName: String, policyName: String) async throws {
        guard var request = makeRequest(path: "v1/policy_groups/select") else {
            throw URLError(.badURL)
        }

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "group_name": groupName,
            "policy": policyName
        ]

        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.secure.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        logger.info("成功切换策略组 '\(groupName)' 到策略 '\(policyName)'")
    }

    // 测试策略组中的所有策略
    func testSurgePolicyGroup(groupName: String) async throws -> SurgePolicyTestResult {
        guard var request = makeRequest(path: "v1/policy_groups/test") else {
            throw URLError(.badURL)
        }

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["group_name": groupName]
        request.httpBody = try JSONEncoder().encode(body)

        // 设置较长的超时时间，因为性能测试可能需要一些时间
        request.timeoutInterval = 30

        let (data, _) = try await URLSession.secure.data(for: request)
        let result = try JSONDecoder().decode(SurgePolicyTestResult.self, from: data)
        logger.info("策略组 '\(groupName)' 性能测试完成")
        return result
    }

    // 获取策略性能基准测试结果
    func fetchSurgeBenchmarkResults() async throws -> [String: SurgeBenchmarkResult] {
        guard let request = makeRequest(path: "v1/policies/benchmark_results") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.secure.data(for: request)
        let results = try JSONDecoder().decode([String: SurgeBenchmarkResult].self, from: data)
        logger.info("获取到 \(results.count) 个策略的性能基准测试结果")
        return results
    }

    // 智能测速：找到最少策略组集合来覆盖所有需要测速的策略
    private func findOptimalGroupsForRetest(
        policiesNeedingRetest: Set<String>,
        policyGroups: SurgePolicyGroups
    ) -> [String] {
        // print("DEBUG: 开始寻找最优策略组集合")
        // print("DEBUG: 需要覆盖的策略: \(Array(policiesNeedingRetest))")
        // print("DEBUG: 可用策略组数量: \(policyGroups.groups.count)")

        var remainingPolicies = policiesNeedingRetest
        var selectedGroups: [String] = []

        // 贪心算法：每次选择覆盖最多剩余策略的策略组
        while !remainingPolicies.isEmpty {
            // print("DEBUG: 剩余需要覆盖的策略数量: \(remainingPolicies.count)")
            var bestGroup: String? = nil
            var maxCoverage = 0

            for (groupName, policies) in policyGroups.groups {
                let policyNames = Set(policies.map { $0.name })
                let coverage = policyNames.intersection(remainingPolicies).count

                if coverage > 0 {
                    // print("DEBUG: 策略组 '\(groupName)' 能覆盖 \(coverage) 个策略")
                }

                if coverage > maxCoverage {
                    maxCoverage = coverage
                    bestGroup = groupName
                }
            }

            guard let selectedGroup = bestGroup, maxCoverage > 0 else {
                // print("DEBUG: 找不到能覆盖更多策略的策略组，停止算法")
                break
            }

            // print("DEBUG: 选择策略组 '\(selectedGroup)'，覆盖 \(maxCoverage) 个策略")
            selectedGroups.append(selectedGroup)

            // 从剩余策略中移除已被覆盖的策略
            let groupPolicies = Set(policyGroups.groups[selectedGroup]?.map { $0.name } ?? [])
            let beforeCount = remainingPolicies.count
            remainingPolicies.subtract(groupPolicies)
            let afterCount = remainingPolicies.count
            // print("DEBUG: 移除覆盖的策略后，剩余策略数量: \(beforeCount) -> \(afterCount)")
        }

        // print("DEBUG: 算法完成，选择策略组: \(selectedGroups)")
        return selectedGroups
    }

    // 执行智能测速
    private func performSmartSpeedTest(policyGroups: SurgePolicyGroups) async {
        do {
            logger.info("开始智能测速...")

            // 1. 获取当前的基准测试结果
            let benchmarkResults = try await fetchSurgeBenchmarkResults()

            // 2. 筛选出需要重新测速的策略（通过 lineHash 匹配）
            var policiesNeedingRetest = Set<String>() // 存储实际的策略名称

            //  print("DEBUG: 基准测试结果总计: \(benchmarkResults.count) 个策略")
            // print("DEBUG: 策略组信息:")
            for (groupName, policies) in policyGroups.groups {
                // print("  - 策略组 '\(groupName)':")
                for policy in policies {
                    //  print("    - '\(policy.name)' (lineHash: \(policy.lineHash ?? "nil"))")
                }
            }

            // 通过 lineHash 匹配需要测速的策略
            for (groupName, policies) in policyGroups.groups {
                for policy in policies {
                    guard let lineHash = policy.lineHash else {
                        // print("DEBUG: 策略 '\(policy.name)' 没有 lineHash，跳过")
                        continue
                    }

                    // 检查基准测试结果中是否有这个 lineHash
                    if let benchmarkResult = benchmarkResults[lineHash], benchmarkResult.needsRetest {
                        policiesNeedingRetest.insert(policy.name)
                        // print("DEBUG: 策略 '\(policy.name)' (lineHash: \(lineHash)) 需要重新测速")
                    } else if let policyHashResult = benchmarkResults["POLICY::\(lineHash)"], policyHashResult.needsRetest {
                        // 也检查 POLICY::hash 格式
                        policiesNeedingRetest.insert(policy.name)
                        // print("DEBUG: 策略 '\(policy.name)' (POLICY::\(lineHash)) 需要重新测速")
                    }
                }
            }

            // print("DEBUG: 需要重新测速的策略名称: \(Array(policiesNeedingRetest))")

            if policiesNeedingRetest.isEmpty {
                logger.info("没有策略需要重新测速")
                return
            }

            logger.info("发现 \(policiesNeedingRetest.count) 个策略需要重新测速")

            // 3. 找到最优的策略组集合
            let optimalGroups = findOptimalGroupsForRetest(
                policiesNeedingRetest: policiesNeedingRetest,
                policyGroups: policyGroups
            )

            // print("DEBUG: 找到的最优策略组: \(optimalGroups)")

            if optimalGroups.isEmpty {
                logger.warning("无法找到合适的策略组来进行测速")
                // print("DEBUG: 需要测速的策略: \(Array(policiesNeedingRetest))")
                return
            }

            logger.info("将对 \(optimalGroups.count) 个策略组进行测速: \(optimalGroups.joined(separator: ", "))")

            // 4. 并发对选中的策略组进行测速
            await withTaskGroup(of: Void.self) { group in
                for groupName in optimalGroups {
                    group.addTask {
                        do {
                            _ = try await self.testSurgePolicyGroup(groupName: groupName)
                            logger.info("策略组 '\(groupName)' 测速完成")
                        } catch {
                            logger.error("策略组 '\(groupName)' 测速失败: \(error.localizedDescription)")
                        }
                    }
                }
            }

            // 5. 等待测速完成
            try await Task.sleep(nanoseconds: 500_000_000) // 等待 0.5 秒

            // 6. 获取最新的基准测试结果
            let updatedResults = try await fetchSurgeBenchmarkResults()

            // 7. 更新节点延迟信息（通过 lineHash 匹配）
            for (groupName, policies) in policyGroups.groups {
                for policy in policies {
                    guard let lineHash = policy.lineHash else {
                        continue
                    }

                    // 检查更新后的基准测试结果
                    if let benchmarkResult = updatedResults[lineHash] {
                        let delay = benchmarkResult.latency
                        await updateNodeDelay(nodeName: policy.name, delay: delay)
                        // print("DEBUG: 更新策略 '\(policy.name)' (lineHash: \(lineHash)) 的延迟: \(delay)ms")
                    } else if let policyHashResult = updatedResults["POLICY::\(lineHash)"] {
                        // 也检查 POLICY::hash 格式
                        let delay = policyHashResult.latency
                        await updateNodeDelay(nodeName: policy.name, delay: delay)
                        // print("DEBUG: 更新策略 '\(policy.name)' (POLICY::\(lineHash)) 的延迟: \(delay)ms")
                    }
                }
            }

            logger.info("智能测速完成，共更新了 \(updatedResults.count) 个策略的延迟信息")

        } catch {
            logger.error("智能测速失败: \(error.localizedDescription)")
        }
    }

    // 获取当前代理模式
    func fetchSurgeOutboundMode() async throws -> String {
        guard let request = makeRequest(path: "v1/outbound") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.secure.data(for: request)

        struct OutboundMode: Codable {
            let mode: String
        }

        let outboundMode = try JSONDecoder().decode(OutboundMode.self, from: data)
        logger.info("当前代理模式: \(outboundMode.mode)")
        return outboundMode.mode
    }

    // 获取 Global 模式当前选择的策略
    func fetchSurgeGlobalSelection() async throws -> String {
        guard let request = makeRequest(path: "v1/outbound/global") else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.secure.data(for: request)
        let selection = try JSONDecoder().decode(SurgePolicySelection.self, from: data)
        logger.info("Global 模式当前选择: \(selection.policy)")
        return selection.policy
    }

    // 设置 Global 模式选择的策略
    func selectSurgeGlobalPolicy(policyName: String) async throws {
        guard var request = makeRequest(path: "v1/outbound/global") else {
            throw URLError(.badURL)
        }

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["policy": policyName]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.secure.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        logger.info("成功设置 Global 模式为策略: \(policyName)")
    }
} 
