import SwiftUI

enum ServerSource: String, Codable {
    case clashController = "clash_controller"
    case openWRT = "openwrt"
    case surge = "surge"
}

enum LuCIPackage: String, Codable {
    case openClash = "openclash"
    case mihomoTProxy = "mihomo_tproxy"
}

struct ClashServer: Identifiable, Codable {
    let id: UUID
    var name: String
    var url: String
    var port: String
    var secret: String
    var status: ServerStatus
    var version: String?
    var clashUseSSL: Bool
    var errorMessage: String?
    var serverType: ServerType?
    var isQuickLaunch: Bool = false
    var source: ServerSource
    var openWRTUsername: String?
    var openWRTPassword: String?
    var openWRTPort: String?
    var openWRTUrl: String?
    var openWRTUseSSL: Bool = false
    var luciPackage: LuCIPackage = .openClash
    var surgeKey: String?
    var surgeUseSSL: Bool = false
    var surgeVersion: String?
    var surgeBuild: String?
    
    enum ServerType: String, Codable {
        case unknown = "Unknown"
        case meta = "Meta"
        case premium = "Premium"
        case singbox = "Sing-Box"
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, name, url, port, secret, status, version
        case useSSL // 旧版本的字段
        case clashUseSSL, openWRTUseSSL
        case errorMessage, serverType, isQuickLaunch, source
        case openWRTUsername, openWRTPassword, openWRTPort, openWRTUrl
        case luciPackage
        case surgeKey, surgeUseSSL, surgeVersion, surgeBuild
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 解码基本字段
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        port = try container.decode(String.self, forKey: .port)
        secret = try container.decode(String.self, forKey: .secret)
        status = try container.decode(ServerStatus.self, forKey: .status)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        serverType = try container.decodeIfPresent(ServerType.self, forKey: .serverType)
        isQuickLaunch = try container.decodeIfPresent(Bool.self, forKey: .isQuickLaunch) ?? false
        source = try container.decode(ServerSource.self, forKey: .source)
        openWRTUsername = try container.decodeIfPresent(String.self, forKey: .openWRTUsername)
        openWRTPassword = try container.decodeIfPresent(String.self, forKey: .openWRTPassword)
        openWRTPort = try container.decodeIfPresent(String.self, forKey: .openWRTPort)
        openWRTUrl = try container.decodeIfPresent(String.self, forKey: .openWRTUrl)
        luciPackage = try container.decodeIfPresent(LuCIPackage.self, forKey: .luciPackage) ?? .openClash
        surgeKey = try container.decodeIfPresent(String.self, forKey: .surgeKey)
        surgeUseSSL = try container.decodeIfPresent(Bool.self, forKey: .surgeUseSSL) ?? false
        
        // 处理 SSL 字段迁移
        if let oldUseSSL = try container.decodeIfPresent(Bool.self, forKey: .useSSL) {
            // 如果存在旧的 useSSL 字段，使用它的值
            clashUseSSL = oldUseSSL
            openWRTUseSSL = oldUseSSL
        } else {
            // 否则尝试读取新字段，如果不存在则使用默认值
            clashUseSSL = try container.decodeIfPresent(Bool.self, forKey: .clashUseSSL) ?? false
            openWRTUseSSL = try container.decodeIfPresent(Bool.self, forKey: .openWRTUseSSL) ?? false
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(port, forKey: .port)
        try container.encode(secret, forKey: .secret)
        try container.encode(status, forKey: .status)
        try container.encode(version, forKey: .version)
        try container.encode(clashUseSSL, forKey: .clashUseSSL)
        try container.encode(openWRTUseSSL, forKey: .openWRTUseSSL)
        try container.encode(errorMessage, forKey: .errorMessage)
        try container.encode(serverType, forKey: .serverType)
        try container.encode(isQuickLaunch, forKey: .isQuickLaunch)
        try container.encode(source, forKey: .source)
        try container.encode(openWRTUsername, forKey: .openWRTUsername)
        try container.encode(openWRTPassword, forKey: .openWRTPassword)
        try container.encode(openWRTPort, forKey: .openWRTPort)
        try container.encode(openWRTUrl, forKey: .openWRTUrl)
        try container.encode(luciPackage, forKey: .luciPackage)
        try container.encode(surgeKey, forKey: .surgeKey)
        try container.encode(surgeUseSSL, forKey: .surgeUseSSL)
    }
    
    init(id: UUID = UUID(), 
         name: String = "", 
         url: String = "", 
         port: String = "", 
         secret: String = "", 
         status: ServerStatus = .unknown, 
         version: String? = nil,
         clashUseSSL: Bool = false,
         source: ServerSource = .clashController,
         isQuickLaunch: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.port = port
        self.secret = secret
        self.status = status
        self.version = version
        self.clashUseSSL = clashUseSSL
        self.source = source
        self.isQuickLaunch = isQuickLaunch
    }
    
    var displayName: String {
        if name.isEmpty {
            switch source {
            case .clashController:
                return "\(url):\(port)"
            case .openWRT:
                return "\(openWRTUrl ?? url):\(openWRTPort ?? "")"
            case .surge:
                return "\(url):\(port)"
            }
        }
        return name
    }
    
    var baseURL: URL? {
        let cleanURL = url.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
        let scheme: String
        switch source {
        case .clashController:
            scheme = clashUseSSL ? "https" : "http"
        case .openWRT:
            scheme = openWRTUseSSL ? "https" : "http"
        case .surge:
            scheme = surgeUseSSL ? "https" : "http"
        }
        let path = source == .surge ? "/v1" : ""
        return URL(string: "\(scheme)://\(cleanURL):\(port)\(path)")
    }
    
    /// 专门用于 Clash API 请求的 URL
    var clashBaseURL: URL? {
        let cleanURL = url.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
        let scheme = clashUseSSL ? "https" : "http"
        return URL(string: "\(scheme)://\(cleanURL):\(port)")
    }
    
    var proxyProvidersURL: URL? {
        baseURL?.appendingPathComponent("providers/proxies")
    }
    
    func makeRequest(url: URL?) throws -> URLRequest {
        guard let url = url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)

        // 根据服务器类型设置不同的认证方式
        switch source {
        case .clashController, .openWRT:
            if !secret.isEmpty {
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            }
        case .surge:
            if let surgeKey = surgeKey, !surgeKey.isEmpty {
                request.setValue(surgeKey, forHTTPHeaderField: "x-key")
            }
        }

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        return request
    }
    
    static func handleNetworkError(_ error: Error) -> NetworkError {
        if let networkError = error as? NetworkError {
            return networkError
        } else if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout(message: "请求超时")
            case .notConnectedToInternet:
                return .invalidResponse(message: "网络未连接")
            case .cannotConnectToHost:
                return .invalidResponse(message: "无法连接到服务器")
            case .secureConnectionFailed:
                return .invalidResponse(message: "SSL/TLS 连接失败")
            case .serverCertificateUntrusted:
                return .invalidResponse(message: "证书不信任")
            default:
                return .invalidResponse(message: error.localizedDescription)
            }
        } else {
            return .invalidResponse(message: error.localizedDescription)
        }
    }
}

enum ServerStatus: String, Codable {
    case ok
    case unauthorized
    case error
    case unknown
    
    var color: Color {
        switch self {
        case .ok: return .green
        case .unauthorized: return .yellow
        case .error: return .red
        case .unknown: return .gray
        }
    }
    
    var text: String {
        switch self {
        case .ok: return "200 OK"
        case .unauthorized: return "401 Unauthorized"
        case .error: return "Error"
        case .unknown: return "Unknown"
        }
    }
} 
