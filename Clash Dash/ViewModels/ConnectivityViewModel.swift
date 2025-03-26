import Foundation
import SwiftUI

private let logger = LogManager.shared

struct WebsiteStatus: Identifiable, Codable {
    let id: UUID
    let name: String
    let url: String
    let icon: String
    var isConnected: Bool = false
    var isChecking: Bool = false
    var error: String? = nil
    
    init(id: UUID = UUID(), name: String, url: String, icon: String, isConnected: Bool = false, isChecking: Bool = false, error: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.icon = icon
        self.isConnected = isConnected
        self.isChecking = isChecking
        self.error = error
    }
}

enum ConnectivityTestResult {
    case success
    case failure(String)
    case inProgress
}

class ConnectivityViewModel: ObservableObject {
    // 默认网站列表 - 固定不可更改的原始列表
    private let defaultWebsites = [
        WebsiteStatus(id: UUID(), name: "YouTube", url: "https://www.youtube.com", icon: "play.rectangle.fill"),
        WebsiteStatus(id: UUID(), name: "Google", url: "https://www.google.com", icon: "magnifyingglass"),
        WebsiteStatus(id: UUID(), name: "GitHub", url: "https://github.com", icon: "chevron.left.forwardslash.chevron.right"),
        WebsiteStatus(id: UUID(), name: "Apple", url: "https://www.apple.com", icon: "apple.logo")
    ]
    
    // 实际显示的网站列表
    @Published var websites: [WebsiteStatus] = []
    @Published var isTestingAll: Bool = false
    
    // 保存的设置
    @AppStorage("connectivityWebsiteVisibility") private var connectivityWebsiteVisibilityData: Data = Data()
    @AppStorage("connectivityWebsiteOrder") private var connectivityWebsiteOrderData: Data = Data()
    @AppStorage("connectivityTimeout") private var connectivityTimeout: Double = 10.0
    
    // 固定网站ID映射，确保ID稳定性
    private let fixedWebsiteIds: [String: UUID] = [
        "YouTube": UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        "Google": UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        "GitHub": UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        "Apple": UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    ]
    
    init() {
        // 初始化时使用固定ID替换默认生成的ID
        websites = defaultWebsites.map { website in
            if let fixedId = fixedWebsiteIds[website.name] {
                return WebsiteStatus(id: fixedId, name: website.name, url: website.url, icon: website.icon)
            }
            return website
        }
    }
    
    // 加载网站可见性设置和顺序设置
    func loadWebsiteVisibility() {
        // 获取可见性设置
        var websiteVisibility: [String: Bool] = [:]
        if let savedVisibility = try? JSONDecoder().decode([String: Bool].self, from: connectivityWebsiteVisibilityData) {
            websiteVisibility = savedVisibility
            logger.debug("读取到可见性设置: \(websiteVisibility)")
        } else {
            // 默认所有网站都可见
            for website in defaultWebsites {
                websiteVisibility[website.id.uuidString] = true
            }
            logger.debug("使用默认可见性设置")
        }
        
        // 获取顺序设置
        var websiteOrder: [UUID] = []
        if let savedOrder = try? JSONDecoder().decode([UUID].self, from: connectivityWebsiteOrderData) {
            websiteOrder = savedOrder
            logger.debug("读取到顺序设置: \(websiteOrder)")
        } else {
            // 默认使用原始顺序
            websiteOrder = defaultWebsites.map { $0.id }
            logger.debug("使用默认顺序设置")
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
                if websiteVisibility[id.uuidString] ?? true {
                    orderedWebsites.append(website)
                }
            }
        }
        
        // 添加不在顺序列表中但应该可见的网站
        for website in baseWebsites {
            if !websiteOrder.contains(website.id) && (websiteVisibility[website.id.uuidString] ?? true) {
                orderedWebsites.append(website)
            }
        }
        
        logger.debug("最终加载的网站数量: \(orderedWebsites.count)")
        
        // 更新网站列表，保持连接状态
        DispatchQueue.main.async {
            let oldWebsites = self.websites
            // 保持已有的连接状态
            self.websites = orderedWebsites.map { newSite in
                if let oldSite = oldWebsites.first(where: { $0.id == newSite.id }) {
                    var updatedSite = newSite
                    updatedSite.isConnected = oldSite.isConnected
                    updatedSite.isChecking = oldSite.isChecking
                    updatedSite.error = oldSite.error
                    return updatedSite
                }
                return newSite
            }
        }
    }
    
    // 重置所有网站状态为初始状态（未检测状态）
    func resetWebsiteStatus() {
        for i in 0..<websites.count {
            websites[i].isChecking = false
            websites[i].isConnected = false
            websites[i].error = nil
        }
    }
    
    func testConnectivity(for index: Int) {
        guard index < websites.count else { return }
        
        websites[index].isChecking = true
        websites[index].isConnected = false
        websites[index].error = nil
        
        let websiteURL = websites[index].url
        
        Task {
            let result = await checkWebsite(url: websiteURL)
            
            DispatchQueue.main.async {
                self.websites[index].isChecking = false
                
                switch result {
                case .success:
                    self.websites[index].isConnected = true
                    HapticManager.shared.notification(.success)
                case .failure(let error):
                    self.websites[index].error = error
                    HapticManager.shared.notification(.error)
                case .inProgress:
                    break
                }
            }
        }
    }
    
    func testAllConnectivity() {
        isTestingAll = true
        
        // 重置所有状态
        for i in 0..<websites.count {
            websites[i].isChecking = true
            websites[i].isConnected = false
            websites[i].error = nil
        }
        
        let dispatchGroup = DispatchGroup()
        
        for i in 0..<websites.count {
            dispatchGroup.enter()
            
            let websiteURL = websites[i].url
            
            Task {
                let result = await checkWebsite(url: websiteURL)
                
                DispatchQueue.main.async {
                    self.websites[i].isChecking = false
                    
                    switch result {
                    case .success:
                        self.websites[i].isConnected = true
                    case .failure(let error):
                        self.websites[i].error = error
                    case .inProgress:
                        break
                    }
                    
                    dispatchGroup.leave()
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            self.isTestingAll = false
            HapticManager.shared.notification(.success)
        }
    }
    
    private func checkWebsite(url: String) async -> ConnectivityTestResult {
        guard let url = URL(string: url) else {
            return .failure("无效URL")
        }
        
        // 创建URL请求
        var request = URLRequest(url: url)
        request.timeoutInterval = connectivityTimeout
        
        do {
            // 使用普通的网络请求，不使用代理
            logger.debug("请求: \(url.absoluteString)")
            let (_, response) = try await URLSession.shared.data(for: request)
            return processResponse(url: url.absoluteString, response: response)
        } catch {
            return handleError(url: url.absoluteString, error: error)
        }
    }
    
    private func processResponse(url: String, response: URLResponse) -> ConnectivityTestResult {
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure("非HTTP响应")
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            logger.debug("连接成功：\(url)")
            return .success
        } else {
            let errorMsg = "HTTP状态码: \(httpResponse.statusCode)"
            logger.error("连接失败：\(url)，\(errorMsg)")
            return .failure(errorMsg)
        }
    }
    
    private func handleError(url: String, error: Error) -> ConnectivityTestResult {
        let nsError = error as NSError
        
        // 根据NSError.code返回更友好的错误信息
        let errorMessage: String
        switch nsError.code {
        case NSURLErrorTimedOut:
            errorMessage = "连接超时"
        case NSURLErrorCannotFindHost:
            errorMessage = "找不到主机"
        case NSURLErrorCannotConnectToHost:
            errorMessage = "无法连接到主机"
        case NSURLErrorDNSLookupFailed:
            errorMessage = "DNS查询失败"
        case NSURLErrorNetworkConnectionLost:
            errorMessage = "网络连接中断"
        case NSURLErrorNotConnectedToInternet:
            errorMessage = "无网络连接"
        case 310: // 处理错误代码310
            errorMessage = "网络受限"
        default:
            if nsError.domain == "kCFErrorDomainCFNetwork" && 
               nsError.userInfo["_kCFStreamErrorDomainKey"] as? Int == 4 &&
               nsError.userInfo["_kCFStreamErrorCodeKey"] as? Int == -2103 {
                errorMessage = "无法访问此网站"
            } else {
                errorMessage = error.localizedDescription
            }
        }
        
        logger.error("连接错误：\(url)，\(errorMessage) (代码: \(nsError.code)，域: \(nsError.domain))")
        return .failure(errorMessage)
    }
} 