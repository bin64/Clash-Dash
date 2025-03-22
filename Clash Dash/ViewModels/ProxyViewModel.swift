import Foundation
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

struct ProxyGroup: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: String
    let now: String
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
        let scheme = server.clashUseSSL ? "https" : "http"
        
        // 处理路径中的特殊字符
        let encodedPath = path.components(separatedBy: "/").map { component in
            component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
        }.joined(separator: "/")
        
        guard let url = URL(string: "\(scheme)://\(server.url):\(server.port)/\(encodedPath)") else {
            // print("❌ 无效的 URL，原始路径: \(path)")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // print("📡 创建请求: \(url)")
        return request
    }
    
    @MainActor
    func fetchProxies() async {
        // print("🔄 开始获取代理数据...")
        do {
            // 1. 获取 proxies 数据
            guard let proxiesRequest = makeRequest(path: "proxies") else { 
                // print("❌ 创建 proxies 请求失败")
                logger.error("创建 proxies 请求失败")
                return 
            }
            // print("📡 发送 proxies 请求...")
            let (proxiesData, _) = try await URLSession.secure.data(for: proxiesRequest)
            
            // 2. 获取 providers 数据
            guard let providersRequest = makeRequest(path: "providers/proxies") else { 
                // print("❌ 创建 providers 请求失败")
                logger.error("创建 providers 请求失败")
                return 
            }
            // print("📡 发送 providers 请求...")
            let (providersData, _) = try await URLSession.secure.data(for: providersRequest)
            
            var allNodes: [ProxyNode] = []
            
            // 3. 处理 proxies 数据
            if let proxiesResponse = try? JSONDecoder().decode(ProxyResponse.self, from: proxiesData) {
                // logger.log("✅ 成功解析 proxies 数据")
                logger.info("成功解析 proxies 数据")
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
                self.groups = proxiesResponse.proxies.compactMap { name, proxy in
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
                // print("📊 代理组数量: \(self.groups.count)")
                
                // 打印组的变化
                // for group in self.groups {
                //     if let oldGroup = oldGroups.first(where: { $0.name == group.name }) {
                //         if oldGroup.now != group.now {
                //             print("📝 组 \(group.name) 的选中节点已更新: \(oldGroup.now) -> \(group.now)")
                //         }
                //     }
                // }
            } else {
                // print("❌ 解析 proxies 数据失败")
                logger.error("解析 proxies 数据失败")
            }
            
            // 4. 处理 providers 数据
            if let providersResponse = try? JSONDecoder().decode(ProxyProvidersResponse.self, from: providersData) {
                // print("✅ 成功解析 providers 数据")
                logger.info("成功解析 providers 数据")
                // print("📦 代理提供者数量: \(providersResponse.providers.count)")
                
                // 更新 providers 属性时保持固定排序
                self.providers = providersResponse.providers.map { name, provider in
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
                    self.providerNodes[providerName] = nodes
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
                print("❌ 解析 providers 数据失败")
                // 尝试打印原始数据以进行调试
//                let jsonString = String(data: providersData, encoding: .utf8)
                    // print("📝 原始 providers 数据:")
                    // print(jsonString)
                
            }
            
            // 5. 更新节点数据
            self.nodes = allNodes
            // print("📊 总节点数量: \(allNodes.count)")
            objectWillChange.send()
            
        } catch {
            logger.error("获取代理错误: \(error)")
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
                    _ = await MainActor.run {
                        for (nodeName, delay) in delays {
                            updateNodeDelay(nodeName: nodeName, delay: delay)
                        }
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
        logger.info("开始切换代理 - 组:\(groupName), 新节点:\(proxyName)")
        
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
            // print("❌ 创建延迟测试请求失败")
            return
        }
        
        // 添加测试参数
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "url", value: testUrl),
            URLQueryItem(name: "timeout", value: "\(testTimeout)")
        ]
        
        guard let finalUrl = components?.url else {
            // print("❌ 创建最终 URL 失败")
            return
        }
        request.url = finalUrl
        
        // 设置测试状态
        testingNodes.insert(nodeName)
        // print("🔄 节点已加入测试集合: \(nodeName)")
        objectWillChange.send()
        
        do {
            let (data, response) = try await URLSession.secure.data(for: request)
            // print("✅ 收到延迟测试响应")
            
            if server.clashUseSSL,
               let httpsResponse = response as? HTTPURLResponse,
               httpsResponse.statusCode == 400 {
                // print("❌ SSL 连接失败")
                testingNodes.remove(nodeName)
                objectWillChange.send()
                return
            }
            
            // 解析延迟数据
            struct DelayResponse: Codable {
                let delay: Int
            }
            
            if let delayResponse = try? JSONDecoder().decode(DelayResponse.self, from: data) {
                logger.debug("📊 节点 \(nodeName) 的新延迟: \(delayResponse.delay)")
                // 更新节点延迟
                updateNodeDelay(nodeName: nodeName, delay: delayResponse.delay)
                testingNodes.remove(nodeName)
                self.lastDelayTestTime = Date()
                objectWillChange.send()
                // print("✅ 延迟更新完成")
            } else {
                // print("❌ 解析延迟数据失败")
                testingNodes.remove(nodeName)
                objectWillChange.send()
            }
            
        } catch {
            // print("❌ 测试节点延迟时发生错误: \(error)")
            testingNodes.remove(nodeName)
            objectWillChange.send()
            handleNetworkError(error)
        }
    }
    
    // 修改更新节点延迟的方法
    private func updateNodeDelay(nodeName: String, delay: Int) {
        // logger.log("🔄 开始更新节点延迟 - 节点:\(nodeName), 新延迟:\(delay)")
        
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
            logger.info("节点延迟已更新 - 原延迟:\(oldDelay), 新延迟:\(delay)")
            objectWillChange.send()
        } else {
            logger.error("⚠️ 未找到要更新的节点: \(nodeName)")
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
        
        logger.error("刷新所有数据完成")
    }
    
    // 修改组测速方法
    @MainActor
    func testGroupSpeed(groupName: String) async {
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
        testingGroups.insert(groupName)
        objectWillChange.send()
        
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
            print("创建最终 URL 失败")
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
                print("SSL 连接失败，服务器可能不支持 HTTPS")
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
                    updateNodeDelay(nodeName: nodeName, delay: delay)
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
                        logger.info("🔄 URL-Test 组测速完成，自动切换到最佳节点: \(bestNode) (延迟: \(lowestDelay)ms)")
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
                self.lastDelayTestTime = Date()
                objectWillChange.send()
            }
        } catch {
            // print("测速过程出错: \(error)")
            handleNetworkError(error)
        }
        
        // print("测速完成，移除测速状态")
        testingGroups.remove(groupName)
        objectWillChange.send()
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
                await MainActor.run {
                    // 更新节点延迟
                    updateNodeDelay(nodeName: proxyName, delay: delayResponse.delay)
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
    private func sortNodes(_ nodes: [String], sortOrder: String) -> [String] {
        switch sortOrder {
        case "latencyAsc":
            return nodes.sorted { node1, node2 in
                let delay1 = getNodeDelay(nodeName: node1)
                let delay2 = getNodeDelay(nodeName: node2)
                if delay1 == 0 { return false }
                if delay2 == 0 { return true }
                return delay1 < delay2
            }
        case "latencyDesc":
            return nodes.sorted { node1, node2 in
                let delay1 = getNodeDelay(nodeName: node1)
                let delay2 = getNodeDelay(nodeName: node2)
                if delay1 == 0 { return false }
                if delay2 == 0 { return true }
                return delay1 > delay2
            }
        case "nameAsc":
            return nodes.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        case "nameDesc":
            return nodes.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
        default:
            return nodes
        }
    }
    
    // 修改 getNodeDelay 方法
    func getNodeDelay(nodeName: String, visitedGroups: Set<String> = []) -> Int {
        // 检查是否是特殊节点（不区分大小写）
        let upperNodeName = nodeName.uppercased()
        if ["REJECT"].contains(upperNodeName) {
            return 0
        }
        
        // 防止循环依赖
        if visitedGroups.contains(nodeName) {
            return 0
        }
        
        // 1. 首先检查是否是实际节点
        if let node = nodes.first(where: { $0.name == nodeName }) {
            return node.delay
        }
        
        // 2. 然后检查是否是代理组
        if let group = groups.first(where: { $0.name == nodeName }) {
            var visited = visitedGroups
            visited.insert(nodeName)
            
            // 如果是负载均衡组，计算所有子节点的平均延迟
            if group.type == "LoadBalance" {
                let delays = group.all.compactMap { childNodeName -> Int? in
                    let delay = getNodeDelay(nodeName: childNodeName, visitedGroups: visited)
                    return delay > 0 ? delay : nil
                }
                
                // 如果有有效延迟，返回平均值
                if !delays.isEmpty {
                    return delays.reduce(0, +) / delays.count
                }
                return 0
            }
            
            // 对于其他类型的组，获取当前选中的节点延迟
            let currentNodeName = group.now
            return getNodeDelay(nodeName: currentNodeName, visitedGroups: visited)
        }
        
        return 0
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
