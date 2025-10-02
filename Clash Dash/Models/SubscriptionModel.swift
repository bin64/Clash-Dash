import Foundation
import SwiftUI

// 订阅信息响应模型
struct SubInfoResponse: Codable {
    struct SubscriptionInfo: Codable {
        let surplus: String
        let total: String
        let dayLeft: Int
        let used: String
        let expire: String
        let percent: String
        
        enum CodingKeys: String, CodingKey {
            case surplus
            case total
            case dayLeft = "day_left"
            case used
            case expire
            case percent
        }
    }
    
    struct Provider: Codable {
        let subscriptionInfo: SubscriptionInfo
        let updatedAt: String
        
        enum CodingKeys: String, CodingKey {
            case subscriptionInfo = "subscription_info"
            case updatedAt = "updated_at"
        }
    }
    
    private let providers: [String: Provider]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var providers: [String: Provider] = [:]
        
        for key in container.allKeys {
            providers[key.stringValue] = try container.decode(Provider.self, forKey: key)
        }
        
        self.providers = providers
    }
    
    var allSubscriptions: [(name: String, provider: Provider)] {
        return providers.map { (name: $0.key, provider: $0.value) }
    }
    
    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?
        
        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }
        
        init?(intValue: Int) {
            return nil
        }
    }
}

// 代理提供者响应模型
struct ProxyProviderResponse: Codable {
    struct Provider: Codable {
        let vehicleType: String?
        let subscriptionInfo: SubscriptionInfo?
    }
    
    struct SubscriptionInfo: Codable {
        let Total: Int64
        let Upload: Int64
        let Download: Int64
        let Expire: TimeInterval
    }
    
    let providers: [String: Provider]
}

// HTTP 客户端协议
protocol HTTPClient {
    func login() async throws -> String
    func makeRequest(_ request: URLRequest) async throws -> (Data, URLResponse)
}

// 默认 HTTP 客户端实现
class DefaultHTTPClient: HTTPClient {
    private let server: ClashServer
    
    init(server: ClashServer) {
        self.server = server
    }
    
    func login() async throws -> String {
        let scheme = server.openWRTUseSSL ? "https" : "http"
        let baseURL = "\(scheme)://\(server.openWRTUrl ?? server.url):\(server.openWRTPort ?? server.port)"
        let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/auth")!
             
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let loginData = [
            "id": 1,
            "method": "login",
            "params": [server.openWRTUsername ?? "root", server.openWRTPassword ?? ""]
        ] as [String : Any]
        
        let loginBody = try JSONSerialization.data(withJSONObject: loginData)
        request.httpBody = loginBody
        
        let (data, _) = try await URLSession.secure.data(for: request)
        
        if let responseString = String(data: data, encoding: .utf8) {
            // 检查响应是否为空或无效
            if responseString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Login response is empty"])
            }
            
            // 尝试清理响应数据
            let cleanedResponse = responseString
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 如果清理后的响应不是以 { 开头，可能需要进一步处理
            if !cleanedResponse.hasPrefix("{") {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Login response is not a valid JSON object"])
            }
            
            // 尝试解析响应
            do {
                guard let cleanedData = cleanedResponse.data(using: .utf8) else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert cleaned response to data"])
                }
                
                struct LoginResponse: Codable {
                    let id: Int
                    let result: String
                    let error: String?
                }
                
                let response = try JSONDecoder().decode(LoginResponse.self, from: cleanedData)
                
                // 只有当 error 字段存在且不为 null 时才认为是错误
                if let error = response.error {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Login failed: \(error)"])
                }
                
                return response.result
                
            } catch {
                if let jsonError = error as? DecodingError {
                    switch jsonError {
                    case .dataCorrupted(let context):
                        LogManager.shared.error("Data corrupted: \(context)")
                    case .keyNotFound(let key, let context):
                        LogManager.shared.error("Key '\(key)' not found: \(context)")
                    case .typeMismatch(let type, let context):
                        LogManager.shared.error("Type '\(type)' mismatch: \(context)")
                    case .valueNotFound(let type, let context):
                        LogManager.shared.error("Value of type '\(type)' not found: \(context)")
                    @unknown default:
                        LogManager.shared.error("Unknown decoding error: \(jsonError)")
                    }
                }
                throw error
            }
        } else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not convert login response data to string"])
        }
    }
    
    func makeRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        return try await URLSession.secure.data(for: request)
    }
}

// Clash 客户端协议
protocol ClashClient {
    func getCurrentConfig() async throws -> String?
    func getSubscriptionInfo(config: String) async throws -> [String: SubscriptionCardInfo]?
    func getProxyProvider() async throws -> [String: SubscriptionCardInfo]?
}

// OpenClash 客户端实现
class OpenClashClient: ClashClient {
    private let httpClient: HTTPClient
    private let server: ClashServer
    private var token: String?
    
    init(server: ClashServer, httpClient: HTTPClient) {
        self.server = server
        self.httpClient = httpClient
    }
    
    func getCurrentConfig() async throws -> String? {
        if token == nil {
            token = try await httpClient.login()
        }
        
        let scheme = server.openWRTUseSSL ? "https" : "http"
        let baseURL = "\(scheme)://\(server.openWRTUrl ?? server.url):\(server.openWRTPort ?? server.port)"
        let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sysauth=\(token!);sysauth_http=\(token!)", forHTTPHeaderField: "Cookie")
        
        let requestData = [
            "method": "exec",
            "params": ["uci get openclash.config.config_path"]
        ] as [String : Any]
        
        let body = try JSONSerialization.data(withJSONObject: requestData)
        request.httpBody = body
        
        let (data, response) = try await httpClient.makeRequest(request)
        
        if let httpResponse = response as? HTTPURLResponse {
            LogManager.shared.info("Config response status code: \(httpResponse.statusCode)")
            LogManager.shared.info("Config response headers: \(httpResponse.allHeaderFields)")
        }
        
        if let responseString = String(data: data, encoding: .utf8) {
            LogManager.shared.info("Config response: \(responseString)")
            
            // 尝试清理响应数据
            let cleanedResponse = responseString
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            do {
                guard let cleanedData = cleanedResponse.data(using: .utf8) else {
                    LogManager.shared.error("Failed to convert cleaned config response to data")
                    return nil
                }
                
                struct Response: Codable {
                    let result: String
                }
                
                let response = try JSONDecoder().decode(Response.self, from: cleanedData)
                let config = response.result
                    .replacingOccurrences(of: "/etc/openclash/config/", with: "")
                    .replacingOccurrences(of: ".yaml", with: "")
                    .replacingOccurrences(of: ".yml", with: "")
                    .replacingOccurrences(of: "\n", with: "")
                
                LogManager.shared.info("Parsed config: \(config)")
                return config
                
            } catch {
                LogManager.shared.error("Error decoding config response: \(error)")
                if let jsonError = error as? DecodingError {
                    switch jsonError {
                    case .dataCorrupted(let context):
                        LogManager.shared.error("Data corrupted: \(context)")
                    case .keyNotFound(let key, let context):
                        LogManager.shared.error("Key '\(key)' not found: \(context)")
                    case .typeMismatch(let type, let context):
                        LogManager.shared.error("Type '\(type)' mismatch: \(context)")
                    case .valueNotFound(let type, let context):
                        LogManager.shared.error("Value of type '\(type)' not found: \(context)")
                    @unknown default:
                        LogManager.shared.error("Unknown decoding error: \(jsonError)")
                    }
                }
                throw error
            }
        } else {
            LogManager.shared.error("Could not convert config response data to string")
            return nil
        }
    }
    
    struct OpenClashConfigResponse: Codable {
        let config: String
    }
    
    func getSubscriptionInfo(config: String) async throws -> [String: SubscriptionCardInfo]? {
        if token == nil {
            token = try await httpClient.login()
        }
        
        guard !config.isEmpty else {
            return try await getProxyProvider()
        }
        
        let scheme = server.openWRTUseSSL ? "https" : "http"
        let baseURL = "\(scheme)://\(server.openWRTUrl ?? server.url):\(server.openWRTPort ?? server.port)"
        let randomNumber = String(Int.random(in: 1000000000000...9999999999999))
        let url = URL(string: "\(baseURL)/cgi-bin/luci/admin/services/openclash/sub_info_get")!
        
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [
            URLQueryItem(name: randomNumber, value: "null"),
            URLQueryItem(name: "filename", value: config)
        ]
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.setValue("sysauth=\(token!);sysauth_http=\(token!)", forHTTPHeaderField: "Cookie")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await httpClient.makeRequest(request)
        
        if let httpResponse = response as? HTTPURLResponse {
            LogManager.shared.info("订阅信息 - 响应状态码: \(httpResponse.statusCode)")
            LogManager.shared.info("订阅信息 - 响应头: \(httpResponse.allHeaderFields)")
        }
        
        if let responseString = String(data: data, encoding: .utf8) {
            LogManager.shared.info("订阅信息 - 接收到的响应: \(responseString)")
            
            // 尝试清理响应数据
            let cleanedResponse = responseString
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 尝试解析响应
            do {
                guard let cleanedData = cleanedResponse.data(using: .utf8) else {
                    LogManager.shared.error("订阅信息 - 无法将清理响应转换为数据")
                    return try await getProxyProvider()
                }
                
                struct Response: Codable {
                    let subInfo: String
                    let surplus: String
                    let total: String
                    let dayLeft: Int?
                    let used: String
                    let expire: String?
                    let percent: String
                    
                    enum CodingKeys: String, CodingKey {
                        case subInfo = "sub_info"
                        case surplus, total, dayLeft = "day_left", used, expire, percent
                    }
                    
                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        subInfo = try container.decode(String.self, forKey: .subInfo)
                        surplus = try container.decode(String.self, forKey: .surplus)
                        total = try container.decode(String.self, forKey: .total)
                        used = try container.decode(String.self, forKey: .used)
                        percent = try container.decode(String.self, forKey: .percent)
                        
                        // 处理 day_left 字段，可能是 Int 或者 String "null"
                        if let intValue = try? container.decode(Int.self, forKey: .dayLeft) {
                            dayLeft = intValue
                        } else if let stringValue = try? container.decode(String.self, forKey: .dayLeft), stringValue != "null" {
                            dayLeft = Int(stringValue)
                        } else {
                            dayLeft = nil
                        }
                        
                        // 处理 expire 字段，可能是 String 或者 String "null"
                        if let stringValue = try? container.decode(String.self, forKey: .expire), stringValue != "null" {
                            expire = stringValue
                        } else {
                            expire = nil
                        }
                    }
                }
                
                let response = try JSONDecoder().decode(Response.self, from: cleanedData)
                
                if response.subInfo == "Successful" {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    
                    var expireDate: Date? = nil
                    if let expireString = response.expire {
                        expireDate = dateFormatter.date(from: expireString)
                        if expireDate == nil {
                            LogManager.shared.warning("订阅信息 - 无法解析到期日期: \(expireString)")
                        }
                    }
                    
                    return [
                        config: SubscriptionCardInfo(
                            name: config,
                            expiryDate: expireDate,
                            lastUpdateTime: Date(),
                            usedTraffic: parseTrafficString(response.used),
                            totalTraffic: parseTrafficString(response.total)
                        )
                    ]
                }

                
                return try await getProxyProvider()
                
            } catch {
                LogManager.shared.error("订阅信息 - 错误解码清理响应: \(error)")
                if let jsonError = error as? DecodingError {
                    switch jsonError {
                    case .dataCorrupted(let context):
                        LogManager.shared.error("订阅信息 - 数据损坏: \(context)")
                    case .keyNotFound(let key, let context):
                        LogManager.shared.error("订阅信息 - 键未找到: \(key) - \(context)")
                    case .typeMismatch(let type, let context):
                        LogManager.shared.error("订阅信息 - 类型不匹配: \(type) - \(context)")
                    case .valueNotFound(let type, let context):
                        LogManager.shared.error("订阅信息 - 值未找到: \(type) - \(context)")
                    @unknown default:
                        LogManager.shared.error("订阅信息 - 未知解码错误: \(jsonError)")
                    }
                }
                return try await getProxyProvider()
            }
        } else {
            LogManager.shared.error("订阅信息 - 无法将响应数据转换为字符串")
            return try await getProxyProvider()
        }
    }
    
    func getProxyProvider() async throws -> [String: SubscriptionCardInfo]? {
        let scheme = server.clashUseSSL ? "https" : "http"
        let baseURL = "\(scheme)://\(server.url):\(server.port)"
        let url = URL(string: "\(baseURL)/providers/proxies")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, _) = try await httpClient.makeRequest(request)
        let response = try JSONDecoder().decode(ProxyProviderResponse.self, from: data)
        
        var result: [String: SubscriptionCardInfo] = [:]

        LogManager.shared.info("订阅信息 - 代理提供者信息: \(response)")
        for (name, provider) in response.providers {
            if let vehicleType = provider.vehicleType,
               ["HTTP", "FILE"].contains(vehicleType.uppercased()),
               let subInfo = provider.subscriptionInfo,
               subInfo.isValid {
                
                let total = Double(subInfo.Total)
                let upload = Double(subInfo.Upload)
                let download = Double(subInfo.Download)
                let used = (upload.isFinite && download.isFinite) ? upload + download : 0
                
                let expireDate = Date(timeIntervalSince1970: subInfo.Expire)
                
                // 当 total 或 expireDate 不为0时才添加订阅信息
                if (total > 0 || subInfo.Expire > 0) && used.isFinite {
                    result[name] = SubscriptionCardInfo(
                        name: name,
                        expiryDate: expireDate,
                        lastUpdateTime: Date(),
                        usedTraffic: used,
                        totalTraffic: total
                    )
                }
            }
        }
        
        return result
    }
    
    private func parseTrafficString(_ traffic: String) -> Double {
        let components = traffic.split(separator: " ")
        guard components.count == 2,
              let value = Double(components[0]) else {
            return 0
        }
        
        let unit = String(components[1]).uppercased()
        switch unit {
        case "TB":
            return value * 1024 * 1024 * 1024 * 1024
        case "GB":
            return value * 1024 * 1024 * 1024
        case "MB":
            return value * 1024 * 1024
        case "KB":
            return value * 1024
        default:
            return value
        }
    }
}

// Mihomo 客户端实现
class MihomoClient: ClashClient {
    private let httpClient: HTTPClient
    private let server: ClashServer
    private var token: String?
    
    init(server: ClashServer, httpClient: HTTPClient) {
        self.server = server
        self.httpClient = httpClient
    }
    
    // 添加一个私有方法来获取包名
    private func getPackageName() async throws -> String {
        let serverViewModel = await ServerViewModel()
        let isNikki = try await serverViewModel.checkIsUsingNikki(server)
        return isNikki ? "nikki" : "mihomo"
    }
    
    func getCurrentConfig() async throws -> String? {
        if token == nil {
            token = try await httpClient.login()
        }
        
        let scheme = server.openWRTUseSSL ? "https" : "http"
        let baseURL = "\(scheme)://\(server.openWRTUrl ?? server.url):\(server.openWRTPort ?? server.port)"
        let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sysauth=\(token!);sysauth_http=\(token!)", forHTTPHeaderField: "Cookie")
        
        let packageName = try await getPackageName()
        let requestData = [
            "method": "exec",
            "params": ["uci get \(packageName).config.profile"]
        ] as [String : Any]
        
        let body = try JSONSerialization.data(withJSONObject: requestData)
        request.httpBody = body
        let (data, response) = try await httpClient.makeRequest(request)
        
        if let httpResponse = response as? HTTPURLResponse {
            LogManager.shared.info("订阅信息 - 响应状态码: \(httpResponse.statusCode)")
            LogManager.shared.info("订阅信息 - 响应头: \(httpResponse.allHeaderFields)")
        }
        
        if let responseString = String(data: data, encoding: .utf8) {
            LogManager.shared.info("订阅信息 - 响应: \(responseString)")
            
            // 尝试清理响应数据
            let cleanedResponse = responseString
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            do {
                guard let cleanedData = cleanedResponse.data(using: .utf8) else {
                    LogManager.shared.error("订阅信息 - 无法将清理响应转换为数据")
                    return nil
                }
                
                struct Response: Codable {
                    let result: String
                }
                
                let response = try JSONDecoder().decode(Response.self, from: cleanedData)
                let result = response.result
                    .replacingOccurrences(of: "\\u000a", with: "")
                    .replacingOccurrences(of: "\n", with: "")
                
                LogManager.shared.info("订阅信息 - 解析结果: \(result)")
                
                let parts = result.split(separator: ":")
                let config = parts.count > 1 && parts[0] == "subscription" ? String(parts[1]) : nil
                LogManager.shared.info("订阅信息 - 最终配置: \(config ?? "nil")")
                return config
                
            } catch {
                LogManager.shared.error("订阅信息 - 错误解码配置响应: \(error)")
                if let jsonError = error as? DecodingError {
                    switch jsonError {
                    case .dataCorrupted(let context):
                        LogManager.shared.error("订阅信息 - 数据损坏: \(context)")
                    case .keyNotFound(let key, let context):
                        LogManager.shared.error("订阅信息 - 键未找到: \(key) - \(context)")
                    case .typeMismatch(let type, let context):
                        LogManager.shared.error("订阅信息 - 类型不匹配: \(type) - \(context)")
                    case .valueNotFound(let type, let context):
                        LogManager.shared.error("订阅信息 - 值未找到: \(type) - \(context)")
                    @unknown default:
                        LogManager.shared.error("订阅信息 - 未知解码错误: \(jsonError)")
                    }
                }
                throw error
            }
        } else {
            LogManager.shared.error("订阅信息 - 无法将配置响应数据转换为字符串")
            return nil
        }
    }
    
    struct MihomoConfigResponse: Codable {
        let result: String
    }
    
    struct MihomoSubscriptionData {
        let name: String
        let available: String
        let total: String
        let used: String
        let expire: String
        
        static func parse(from result: String) -> MihomoSubscriptionData? {
            var data: [String: String] = [:]
            let lines = result.split(separator: "\n")
            
            for line in lines {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0].split(separator: ".").last ?? "")
                    let value = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                    data[key] = value
                }
            }
            
            guard let name = data["name"],
                  let available = data["avaliable"],
                  let total = data["total"],
                  let used = data["used"],
                  let expire = data["expire"] else {
                return nil
            }
            
            return MihomoSubscriptionData(
                name: name,
                available: available,
                total: total,
                used: used,
                expire: expire
            )
        }
    }
    
    func getSubscriptionInfo(config: String) async throws -> [String: SubscriptionCardInfo]? {
        if token == nil {
            token = try await httpClient.login()
        }
        
        guard !config.isEmpty else {
            return try await getProxyProvider()
        }
        
        let scheme = server.openWRTUseSSL ? "https" : "http"
        let baseURL = "\(scheme)://\(server.openWRTUrl ?? server.url):\(server.openWRTPort ?? server.port)"
        let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sysauth=\(token!);sysauth_http=\(token!)", forHTTPHeaderField: "Cookie")
        
        // 检查是否使用 nikki
        let serverViewModel = await ServerViewModel()
        let isNikki = try await serverViewModel.checkIsUsingNikki(server)
        let packageName = isNikki ? "nikki" : "mihomo"
        
        let requestData = [
            "id": 1,
            "method": "exec",
            "params": ["uci show \(packageName).\(config)"]
        ] as [String : Any]
        
        let body = try JSONSerialization.data(withJSONObject: requestData)
        request.httpBody = body
        let (data, _) = try await httpClient.makeRequest(request)
        
        // 打印接收到的数据
        if let responseString = String(data: data, encoding: .utf8) {
            LogManager.shared.info("订阅信息 - 接收响应: \(responseString)")
        }
        
        // 尝试解析响应
        do {
            struct Response: Codable {
                let result: String
            }
            
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard let subscriptionData = MihomoSubscriptionData.parse(from: response.result) else {
                LogManager.shared.error("订阅信息 - 无法从结果解析订阅数据")
                return try await getProxyProvider()
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            
            guard let expireDate = dateFormatter.date(from: subscriptionData.expire) else {
                LogManager.shared.error("订阅信息 - 无法解析到期日期: \(subscriptionData.expire)")
                return try await getProxyProvider()
            }
            
            return [
                subscriptionData.name: SubscriptionCardInfo(
                    name: subscriptionData.name,
                    expiryDate: expireDate,
                    lastUpdateTime: Date(),
                    usedTraffic: parseTrafficString(subscriptionData.used),
                    totalTraffic: parseTrafficString(subscriptionData.total)
                )
            ]
        } catch {
            LogManager.shared.error("订阅信息 - 错误解码响应: \(error)")
            LogManager.shared.error("订阅信息 - 响应数据: \(String(data: data, encoding: .utf8) ?? "Unable to convert data to string")")
            throw error
        }
    }
    
    func getProxyProvider() async throws -> [String: SubscriptionCardInfo]? {
        let scheme = server.clashUseSSL ? "https" : "http"
        let baseURL = "\(scheme)://\(server.url):\(server.port)"
        let url = URL(string: "\(baseURL)/providers/proxies")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, _) = try await httpClient.makeRequest(request)
        let response = try JSONDecoder().decode(ProxyProviderResponse.self, from: data)
        
        var result: [String: SubscriptionCardInfo] = [:]
        
        for (name, provider) in response.providers {
            if let vehicleType = provider.vehicleType,
               ["HTTP", "FILE"].contains(vehicleType.uppercased()),
               let subInfo = provider.subscriptionInfo,
               subInfo.isValid {
                
                let total = Double(subInfo.Total)
                let upload = Double(subInfo.Upload)
                let download = Double(subInfo.Download)
                let used = (upload.isFinite && download.isFinite) ? upload + download : 0
                
                let expireDate = Date(timeIntervalSince1970: subInfo.Expire)

                LogManager.shared.info("订阅信息 - 订阅信息: \(name) - \(expireDate) - \(used) - \(total)")
                
                // 当 total 或 expireDate 不为0时才添加订阅信息
                if (total > 0 || subInfo.Expire > 0) && used.isFinite {
                    result[name] = SubscriptionCardInfo(
                        name: name,
                        expiryDate: expireDate,
                        lastUpdateTime: Date(),
                        usedTraffic: used,
                        totalTraffic: total
                    )
                }
            }
        }
        
        return result
    }
    
    private func parseTrafficString(_ traffic: String) -> Double {
        let components = traffic.split(separator: " ")
        guard components.count == 2,
              let value = Double(components[0]) else {
            return 0
        }
        
        let unit = String(components[1]).uppercased()
        switch unit {
        case "TB":
            return value * 1024 * 1024 * 1024 * 1024
        case "GB":
            return value * 1024 * 1024 * 1024
        case "MB":
            return value * 1024 * 1024
        case "KB":
            return value * 1024
        default:
            return value
        }
    }
}

// 订阅信息管理器
@MainActor
class SubscriptionManager: ObservableObject, Sendable {
    @Published var subscriptions: [SubscriptionCardInfo] = []
    @Published var isLoading = false
    @Published var lastUpdateTime: Date?
    
    private let server: ClashServer
    private let httpClient: HTTPClient
    private var clashClient: ClashClient
    private let cache = SubscriptionCache.shared
    
    init(server: ClashServer) {
        self.server = server
        self.httpClient = DefaultHTTPClient(server: server)
        
        // 根据 luciPackage 选择对应的客户端
        switch server.luciPackage {
        case .mihomoTProxy:
            self.clashClient = MihomoClient(server: server, httpClient: httpClient)
            LogManager.shared.info("订阅信息 - 初始化 Mihomo 客户端")
        case .openClash:
            self.clashClient = OpenClashClient(server: server, httpClient: httpClient)
            LogManager.shared.info("订阅信息 - 初始化 OpenClash 客户端")
        }
        
        // 加载缓存的数据
        if let cached = cache.load(for: server) {
            self.subscriptions = cached
            self.lastUpdateTime = cache.getLastUpdateTime(for: server)
            LogManager.shared.info("订阅信息 - 从缓存加载了 \(cached.count) 个订阅信息")
        } else {
            LogManager.shared.info("订阅信息 - 没有找到缓存的订阅信息")
        }
    }
    
    func fetchSubscriptionInfo(forceRefresh: Bool = false) async {
        // 如果不是强制刷新且已有缓存数据，直接返回
        if !forceRefresh && !subscriptions.isEmpty {
            LogManager.shared.info("订阅信息 - 使用现有缓存数据，跳过刷新")
            return
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        LogManager.shared.info("订阅信息 - 开始\(forceRefresh ? "强制" : "")刷新订阅信息")
        
        do {
            // 根据 ServerSource 决定获取订阅信息的方式
            if server.source == .openWRT {
                LogManager.shared.info("订阅信息 - 检测到 OpenWRT 源，尝试获取配置信息")
                // 对于 openWRT 源，使用原有的逻辑
                if let config = try await clashClient.getCurrentConfig() {
                    LogManager.shared.info("订阅信息 - 成功获取配置：\(config)")
                    if let subscriptionInfo = try await clashClient.getSubscriptionInfo(config: config) {
                        LogManager.shared.info("订阅信息 - 成功获取订阅信息，共 \(subscriptionInfo.count) 个")
                        // 保持现有订阅的顺序
                        var newSubscriptions: [SubscriptionCardInfo] = []
                        if !self.subscriptions.isEmpty {
                            // 如果已有订阅，按照现有顺序更新
                            for existingSub in self.subscriptions {
                                if let updatedSub = subscriptionInfo.values.first(where: { $0.name == existingSub.name }) {
                                    newSubscriptions.append(updatedSub)
                                }
                            }
                            // 添加新的订阅（如果有）
                            for newSub in subscriptionInfo.values {
                                if !newSubscriptions.contains(where: { $0.name == newSub.name }) {
                                    newSubscriptions.append(newSub)
                                }
                            }
                            LogManager.shared.info("订阅信息 - 更新现有订阅顺序，最终数量：\(newSubscriptions.count)")
                        } else {
                            // 如果是首次加载，按照名称排序
                            newSubscriptions = Array(subscriptionInfo.values).sorted { ($0.name ?? "") < ($1.name ?? "") }
                            LogManager.shared.info("订阅信息 - 首次加载订阅信息，按名称排序")
                        }
                        
                        let finalSubscriptions = newSubscriptions
                        DispatchQueue.main.async {
                            self.subscriptions = finalSubscriptions
                            self.lastUpdateTime = Date()
                            self.isLoading = false
                        }
                        // 保存到缓存
                        cache.save(subscriptions: newSubscriptions, for: server)
                        LogManager.shared.info("订阅信息 - 已更新并保存到缓存")
                        return
                    } else {
                        LogManager.shared.warning("订阅信息 - 无法获取订阅信息，尝试获取代理提供者信息")
                    }
                } else {
                    LogManager.shared.warning("订阅信息 - 无法获取配置信息，尝试获取代理提供者信息")
                }
            }
            
            // 对于其他源或者 openWRT 获取失败的情况，直接尝试获取代理提供者信息
            LogManager.shared.info("订阅信息 - 尝试获取代理提供者信息")
            if let proxyInfo = try await clashClient.getProxyProvider() {
                LogManager.shared.info("订阅信息 - 成功获取代理提供者信息，共 \(proxyInfo.count) 个")
                // 保持现有订阅的顺序
                var newSubscriptions: [SubscriptionCardInfo] = []
                if !self.subscriptions.isEmpty {
                    // 如果已有订阅，按照现有顺序更新
                    for existingSub in self.subscriptions {
                        if let updatedSub = proxyInfo.values.first(where: { $0.name == existingSub.name }) {
                            newSubscriptions.append(updatedSub)
                        }
                    }
                    // 添加新的订阅（如果有）
                    for newSub in proxyInfo.values {
                        if !newSubscriptions.contains(where: { $0.name == newSub.name }) {
                            newSubscriptions.append(newSub)
                        }
                    }
                    LogManager.shared.info("订阅信息 - 更新现有订阅顺序，最终数量：\(newSubscriptions.count)")
                } else {
                    // 如果是首次加载，按照名称排序
                    newSubscriptions = Array(proxyInfo.values).sorted { ($0.name ?? "") < ($1.name ?? "") }
                    LogManager.shared.info("订阅信息 - 首次加载代理提供者信息，按名称排序")
                }
                
                let finalSubscriptions = newSubscriptions
                DispatchQueue.main.async {
                    self.subscriptions = finalSubscriptions
                    self.lastUpdateTime = Date()
                    self.isLoading = false
                }
                // 保存到缓存
                cache.save(subscriptions: newSubscriptions, for: server)
                LogManager.shared.info("订阅信息 - 代理提供者信息已更新并保存到缓存")
            } else {
                LogManager.shared.warning("订阅信息 - 无法获取代理提供者信息")
            }
        } catch {
            LogManager.shared.error("订阅信息 - 获取订阅信息失败：\(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
    
    func refresh() async {
        LogManager.shared.info("订阅信息 - 手动刷新订阅信息")
        await fetchSubscriptionInfo(forceRefresh: true)
    }
    
    func clearCache() {
        LogManager.shared.info("订阅信息 - 清除订阅信息缓存")
        cache.clear(for: server)
        subscriptions = []
        lastUpdateTime = nil
    }
}

extension Double {
    func rounded(to places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

// 添加 SubscriptionInfo 的扩展，用于验证数据
extension ProxyProviderResponse.SubscriptionInfo {
    var isValid: Bool {
        // 验证流量数据是否有效
        let uploadValid = Upload >= 0 && !Double(Upload).isInfinite && !Double(Upload).isNaN
        let downloadValid = Download >= 0 && !Double(Download).isInfinite && !Double(Download).isNaN
        let totalValid = Total >= 0 && !Double(Total).isInfinite && !Double(Total).isNaN
        
        // 安全计算总使用量
        let upload = Double(Upload)
        let download = Double(Download)
        
        // 检查是否任一值接近或等于 Int64 最大值
        if upload >= Double(Int64.max) / 2 || download >= Double(Int64.max) / 2 {
            return false // 数值太大，认为无效
        }
        
        return uploadValid && downloadValid && totalValid
    }
} 
