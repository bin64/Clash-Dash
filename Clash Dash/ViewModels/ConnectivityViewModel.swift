import Foundation
import SwiftUI
import Combine

private let logger = LogManager.shared

// 将WebsiteStatus改为类，这样可以使用@Published
class WebsiteStatus: Identifiable, ObservableObject {
    let id: UUID
    let name: String
    let url: String
    let icon: String
    
    @Published var isConnected: Bool = false
    @Published var isChecking: Bool = false
    @Published var error: String? = nil
    @Published var usedProxy: Bool = false
    
    init(id: UUID = UUID(), name: String, url: String, icon: String, isConnected: Bool = false, isChecking: Bool = false, error: String? = nil, usedProxy: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.icon = icon
        self.isConnected = isConnected
        self.isChecking = isChecking
        self.error = error
        self.usedProxy = usedProxy
    }
}

enum ConnectivityTestResult {
    case success
    case failure(String)
    case inProgress
}

class ConnectivityViewModel: ObservableObject {
    // 默认网站列表定义
    private let defaultWebsites: [WebsiteStatus] = [
        WebsiteStatus(name: "Google", url: "http://www.google.com", icon: "magnifyingglass"),
        WebsiteStatus(name: "YouTube", url: "http://www.youtube.com", icon: "play.rectangle.fill"),
        WebsiteStatus(name: "Github", url: "http://github.com", icon: "chevron.left.forwardslash.chevron.right"),
        WebsiteStatus(name: "Apple", url: "http://www.apple.com", icon: "apple.logo")
    ]
    
    @Published var websites: [WebsiteStatus] = []
    @Published var isTestingAll = false
    @Published var isUsingProxy = false
    
    @Published var proxyTested = false     // 是否测试过代理
    @Published var showProxyInfo = false   // 显示代理信息
    @Published var proxyErrorDetails = ""  // 代理错误详情
    
    var clashServer: ClashServer? // 改为公开属性
    var httpPort: String = ""     // 改为公开属性
    
    private var cancellables = Set<AnyCancellable>()
    
    // 固定网站ID映射，确保ID稳定性
    private let fixedWebsiteIds: [String: UUID] = [
        "YouTube": UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        "Google": UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        "GitHub": UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        "Apple": UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    ]
    
    init() {
        // 初始化网站列表
        logger.debug("🌐 初始化ConnectivityViewModel")
        for website in defaultWebsites {
            if let fixedId = fixedWebsiteIds[website.name] {
                logger.debug("🔄 添加固定ID网站: \(website.name) (ID: \(fixedId))")
                websites.append(WebsiteStatus(
                    id: fixedId,
                    name: website.name,
                    url: website.url,
                    icon: website.icon
                ))
            } else {
                logger.debug("🔄 添加动态ID网站: \(website.name)")
                websites.append(website)
            }
        }
        logger.debug("✅ 初始化完成，共\(websites.count)个网站")
    }
    
    // 通过设置服务器信息来准备测试环境
    func setupWithServer(_ server: ClashServer, httpPort: String) {
        let previousServer = self.clashServer?.url ?? "无"
        let previousPort = self.httpPort
        
        logger.debug("🔧 设置服务器信息 - URL: \(server.url), HTTP端口: \(httpPort)")
        logger.debug("🔄 更新前: 服务器 \(previousServer), 端口: \(previousPort)")
        
        self.clashServer = server
        self.httpPort = httpPort
        
        // 如果端口为0或空，尝试从服务器配置中读取
        if httpPort.isEmpty || httpPort == "0" {
            logger.debug("⚠️ 注意: HTTP端口为空或为0，这可能导致代理测试失败")
            // 在这里可以添加获取实际端口的代码
        }
    }
    
    // 测试代理是否可用
    private func testProxyAvailability() async -> Bool {
        guard let server = clashServer, !httpPort.isEmpty, Int(httpPort) ?? 0 > 0 else {
            logger.debug("❌ 代理测试失败: 服务器或端口设置无效")
            logger.debug("⚠️ 当前服务器: \(clashServer?.url ?? "未设置")")
            logger.debug("⚠️ 当前HTTP端口: \(httpPort)")
            return false
        }
        
        // 确保URL格式正确
        let proxyHost = server.url.replacingOccurrences(of: "http://", with: "")
                                 .replacingOccurrences(of: "https://", with: "")
        let proxyPort = Int(httpPort) ?? 0
        logger.debug("🔍 测试代理可用性 - 主机: \(proxyHost), 端口: \(proxyPort)")
        
        // 创建配置了代理的URLSession
        let config = URLSessionConfiguration.ephemeral
        
        // 设置代理配置
        let proxyDict: [AnyHashable: Any] = [
            kCFNetworkProxiesHTTPEnable: true,
            kCFNetworkProxiesHTTPProxy: proxyHost,
            kCFNetworkProxiesHTTPPort: proxyPort,
            // 添加HTTPS代理配置
//            kCFNetworkProxiesHTTPSEnable: true,
//            kCFNetworkProxiesHTTPSProxy: proxyHost,
//            kCFNetworkProxiesHTTPSPort: proxyPort
        ]
        config.connectionProxyDictionary = proxyDict as? [String: Any]
        logger.debug("📝 完整代理设置: \(proxyDict)")
        
        // 其他重要配置
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = true
        
        let session = URLSession(configuration: config)
        
        // 测试多个网站
        let testUrls = [
            "http://www.baidu.com",
            "http://www.qq.com",
            "http://www.163.com",
            "http://www.ifeng.com"
        ]
        
        logger.debug("🔄 开始测试代理连接...")
        
        for testUrl in testUrls {
            do {
                logger.debug("🌐 尝试访问: \(testUrl)")
                var request = URLRequest(url: URL(string: testUrl)!)
                request.timeoutInterval = 8
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                
                let startTime = Date()
                let (_, response) = try await session.data(for: request)
                let duration = Date().timeIntervalSince(startTime)
                
                if let httpResponse = response as? HTTPURLResponse {
                    logger.debug("📊 [代理测试] 响应状态码: \(httpResponse.statusCode), 耗时: \(String(format: "%.2f", duration))秒")
                    if (200...299).contains(httpResponse.statusCode) {
                        logger.debug("✅ 代理测试成功!")
                        return true
                    }
                }
            } catch {
                logger.debug("❌ 尝试代理访问\(testUrl)失败: \(error.localizedDescription)")
            }
        }
        
        logger.debug("❌ 所有代理测试网站都失败，可能原因:")
        logger.debug("  - 代理端口\(proxyPort)可能不正确")
        logger.debug("  - 代理服务器\(proxyHost)可能未运行")
        logger.debug("  - 网络连接可能有问题")
        return false
    }
    
    // 一次测试所有网站
    func testAllConnectivity() {
        logger.debug("🔄 开始测试所有网站")
        Task { @MainActor in
            isTestingAll = true
            
            // 先将所有网站设置为"正在检测"状态
            for index in websites.indices {
                websites[index].isChecking = true
            }
            
            // 然后测试代理可用性
            logger.debug("🔍 测试代理可用性...")
            let proxyAvailable = await testProxyAvailability()
            isUsingProxy = proxyAvailable
            proxyTested = true
            logger.debug("📝 代理可用性测试结果: \(proxyAvailable ? "可用" : "不可用")")
            
            // 依次测试所有网站
            for index in websites.indices {
                logger.debug("🔄 测试网站 [\(index)]: \(websites[index].name)")
                await testSingleWebsite(index: index, useProxy: proxyAvailable)
            }
            
            isTestingAll = false
            logger.debug("✅ 所有网站测试完成")
        }
    }
    
    // 测试单个网站连通性
    func testConnectivity(for index: Int) {
        guard index < websites.count else {
            logger.error("❌ 无效的网站索引: \(index)")
            return
        }
        
        logger.debug("🔄 开始测试网站: \(websites[index].name)")
        Task { @MainActor in
            // 设置当前网站为正在检测状态
            websites[index].isChecking = true
            websites[index].error = nil
            
            // 先测试代理可用性
            logger.debug("🔍 测试代理可用性...")
            let proxyAvailable = await testProxyAvailability()
            isUsingProxy = proxyAvailable
            logger.debug("📝 代理可用性测试结果: \(proxyAvailable ? "可用" : "不可用")")
            
            // 测试网站连通性
            await testSingleWebsite(index: index, useProxy: proxyAvailable)
        }
    }
    
    // 测试单个网站的实际逻辑
    private func testSingleWebsite(index: Int, useProxy: Bool) async {
        guard index < websites.count else {
            logger.debug("❌ 测试单个网站时索引无效: \(index)")
            return
        }
        
        let website = websites[index]
        logger.debug("🔄 测试网站: \(website.name), URL: \(website.url), 使用代理: \(useProxy)")
        
        guard let url = URL(string: website.url) else {
            logger.debug("❌ 无效的URL: \(website.url)")
            await MainActor.run {
                websites[index].isChecking = false
                websites[index].isConnected = false
                websites[index].error = "无效的URL"
                websites[index].usedProxy = false
            }
            return
        }
        
        do {
            var session: URLSession
            
            if useProxy, let server = clashServer, !httpPort.isEmpty, Int(httpPort) ?? 0 > 0 {
                // 创建配置了代理的URLSession
                let config = URLSessionConfiguration.ephemeral
                // 确保URL格式正确
                let proxyHost = server.url.replacingOccurrences(of: "http://", with: "")
                                         .replacingOccurrences(of: "https://", with: "")
                let proxyPort = Int(httpPort) ?? 0
                
                let proxyDict: [AnyHashable: Any] = [
                    kCFNetworkProxiesHTTPEnable: true,
                    kCFNetworkProxiesHTTPProxy: proxyHost,
                    kCFNetworkProxiesHTTPPort: proxyPort
                ]
                config.connectionProxyDictionary = proxyDict as? [String: Any]
                session = URLSession(configuration: config)
                logger.debug("📝 使用代理配置: 主机: \(proxyHost), 端口: \(proxyPort)")
            } else {
                // 使用普通URLSession
                session = URLSession.shared
                logger.debug("📝 使用直接连接")
            }
            
            // 创建请求并设置超时
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            logger.debug("🔄 发送请求到: \(url), 超时: 5秒")
            
            // 执行请求
            let startTime = Date()
            let (_, response) = try await session.data(for: request)
            let duration = Date().timeIntervalSince(startTime)
            logger.debug("⏱️ 请求耗时: \(String(format: "%.2f", duration))秒")
            
            // 检查响应状态
            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                logger.debug("📊 HTTP响应状态码: \(statusCode)")
                
                if (200...299).contains(statusCode) {
                    await MainActor.run {
                        websites[index].isChecking = false
                        websites[index].isConnected = true
                        websites[index].error = nil
                        websites[index].usedProxy = useProxy
                    }
                    logger.debug("✅ 连接成功: \(website.name)")
                } else {
                    throw NSError(domain: "HTTPError", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP错误: \(statusCode)"])
                }
            } else {
                logger.debug("❓ 未收到HTTP响应")
                throw NSError(domain: "HTTPError", code: 0, userInfo: [NSLocalizedDescriptionKey: "未收到HTTP响应"])
            }
        } catch {
            logger.debug("❌ 连接失败: \(website.name), 错误: \(error.localizedDescription)")
            await MainActor.run {
                websites[index].isChecking = false
                websites[index].isConnected = false
                websites[index].error = error.localizedDescription
                websites[index].usedProxy = useProxy
            }
        }
    }
    
    // 加载网站可见性设置和顺序设置
    func loadWebsiteVisibility() {
        logger.debug("🔄 加载网站可见性设置")
        // 获取可见性设置
        var websiteVisibility: [String: Bool] = [:]
        if let savedVisibility = try? JSONDecoder().decode([String: Bool].self, from: connectivityWebsiteVisibilityData) {
            websiteVisibility = savedVisibility
            logger.debug("📝 读取到可见性设置: \(websiteVisibility)")
        } else {
            // 默认所有网站都可见
            for website in defaultWebsites {
                websiteVisibility[website.name] = true
            }
            logger.debug("📝 使用默认可见性设置")
        }
        
        // 获取顺序设置
        var websiteOrder: [UUID] = []
        if let savedOrder = try? JSONDecoder().decode([UUID].self, from: connectivityWebsiteOrderData) {
            websiteOrder = savedOrder
            logger.debug("📝 读取到顺序设置: \(websiteOrder)")
        } else {
            // 默认使用原始顺序
            websiteOrder = defaultWebsites.map { $0.id }
            logger.debug("📝 使用默认顺序设置")
        }
        
        // 根据顺序和可见性设置网站列表
        let baseWebsites = defaultWebsites.map { website in
            if let fixedId = fixedWebsiteIds[website.name] {
                return WebsiteStatus(id: fixedId, name: website.name, url: website.url, icon: website.icon)
            }
            return website
        }
        
        // 先按顺序排列
        var orderedWebsites: [WebsiteStatus] = []
        
        // 添加所有在顺序列表中的网站
        for id in websiteOrder {
            if let website = baseWebsites.first(where: { $0.id == id }) {
                // 只添加可见的网站
                if websiteVisibility[website.name] ?? true {
                    orderedWebsites.append(website)
                    logger.debug("📋 添加有序网站: \(website.name)")
                }
            }
        }
        
        // 添加不在顺序列表中但应该可见的网站
        for website in baseWebsites {
            if !websiteOrder.contains(website.id) && (websiteVisibility[website.name] ?? true) {
                orderedWebsites.append(website)
                logger.debug("📋 添加额外可见网站: \(website.name)")
            }
        }
        
        logger.debug("✅ 最终加载的网站数量: \(orderedWebsites.count)")
        
        // 更新网站列表，保持连接状态
        DispatchQueue.main.async {
            let oldWebsites = self.websites
            // 保持已有的连接状态
            self.websites = orderedWebsites.map { newSite in
                if let oldSite = oldWebsites.first(where: { $0.id == newSite.id }) {
                    let updatedSite = newSite
                    updatedSite.isConnected = oldSite.isConnected
                    updatedSite.isChecking = oldSite.isChecking
                    updatedSite.error = oldSite.error
                    updatedSite.usedProxy = oldSite.usedProxy
                    return updatedSite
                }
                return newSite
            }
            logger.debug("✅ 网站列表更新完成")
        }
    }
    
    // 重置所有网站状态为初始状态（未检测状态）
    func resetWebsiteStatus() {
        logger.debug("🔄 重置所有网站状态")
        for website in websites {
            website.isChecking = false
            website.isConnected = false
            website.error = nil
            website.usedProxy = false
        }
        logger.debug("✅ 网站状态重置完成")
    }
    
    // 保存的设置
    @AppStorage("connectivityWebsiteVisibility") private var connectivityWebsiteVisibilityData: Data = Data()
    @AppStorage("connectivityWebsiteOrder") private var connectivityWebsiteOrderData: Data = Data()
    @AppStorage("connectivityTimeout") private var connectivityTimeout: Double = 10.0
    
    // 添加代理信息诊断方法
    func getProxyDiagnostics() -> String {
        guard let server = clashServer else {
            return "未设置服务器信息"
        }
        
        var info = """
        === 代理配置 ===
        服务器: \(server.url)
        端口: \(httpPort.isEmpty ? "未设置" : httpPort)
        """
        
        // 添加其他诊断信息
        if let port = Int(httpPort), port <= 0 {
            info += "\n⚠️ 端口必须大于0"
        }
        
        return info
    }
    
    // 添加到ConnectivityViewModel中
    func manuallyCheckPort() {
        logger.debug("🔍 手动检查代理配置")
        logger.debug("🔧 检查前状态:")
        logger.debug("  - clashServer: \(clashServer?.url ?? "未设置")")
        logger.debug("  - httpPort: \(httpPort)")
        
        guard let server = clashServer else { 
            logger.debug("❌ 服务器未设置")
            return 
        }
        
        // 尝试从服务器获取HTTP端口
        Task {
            logger.debug("🔄 开始获取服务器配置...")
            // 模拟从服务器获取配置
            // 这里是演示，您需要实际实现一个方法从服务器获取HTTP端口
            
            logger.debug("🔧 重新设置代理信息")
            // 重新设置服务器信息
            self.setupWithServer(server, httpPort: self.httpPort)
            logger.debug("📝 重设后的代理信息:")
            logger.debug("  - 服务器: \(self.clashServer?.url ?? "未设置")")
            logger.debug("  - 端口: \(self.httpPort)")
            
            // 测试连接
            await MainActor.run {
                self.testAllConnectivity()
            }
        }
    }
} 
