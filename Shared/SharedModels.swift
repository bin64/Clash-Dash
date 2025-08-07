import Foundation

// MARK: - 共享的数据管理器
public class SharedDataManager {
    public static let shared = SharedDataManager()
    
    private let userDefaults: UserDefaults
    private let appGroupId = "group.ym.si.clashdash"
    
    private enum Keys {
        static func serverKey(_ serverAddress: String, _ key: String) -> String {
            return "\(serverAddress)_\(key)"
        }
        static let lastUpdateTime = "lastUpdateTime"
        static let secret = "secret"
        static let useSSL = "useSSL"
    }
    
    private init() {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            fatalError("无法访问 App Group")
        }
        self.userDefaults = userDefaults
    }
    
    public func saveClashStatus(
        serverAddress: String,
        serverName: String?,
        activeConnections: Int,
        uploadTotal: Int64,
        downloadTotal: Int64,
        memoryUsage: Double?,
        secret: String? = nil,
        useSSL: Bool = false
    ) {
        // // print("[SharedDataManager] Saving status:")
        // // print("[SharedDataManager] - Server address: \(serverAddress)")
        // // print("[SharedDataManager] - Server name: \(serverName ?? "nil")")
        // // print("[SharedDataManager] - Active connections: \(activeConnections)")
        // // print("[SharedDataManager] - Upload total: \(uploadTotal)")
        // // print("[SharedDataManager] - Download total: \(downloadTotal)")
        // // print("[SharedDataManager] - Memory usage: \(memoryUsage ?? 0)")
        // // print("[SharedDataManager] - Use SSL: \(useSSL)")
        // // print("[SharedDataManager] - Secret: \(secret != nil ? "provided" : "nil")")
        
        let cleanServerAddress = serverAddress.components(separatedBy: ":")[0]
        // // print("[SharedDataManager] - Clean server address: \(cleanServerAddress)")
        
        // 保存基本信息
        userDefaults.set(serverAddress, forKey: "\(serverAddress)_serverAddress")
        userDefaults.set(serverName, forKey: "\(serverAddress)_serverName")
        userDefaults.set(activeConnections, forKey: "\(serverAddress)_activeConnections")
        userDefaults.set(uploadTotal, forKey: "\(serverAddress)_uploadTotal")
        userDefaults.set(downloadTotal, forKey: "\(serverAddress)_downloadTotal")
        userDefaults.set(memoryUsage, forKey: "\(serverAddress)_memoryUsage")
        userDefaults.set(Date(), forKey: "\(serverAddress)_lastUpdateTime")
        userDefaults.set(useSSL, forKey: "\(serverAddress)_useSSL")
        
        if let secret = secret {
            // 1. 使用直接格式
            userDefaults.set(secret, forKey: "\(cleanServerAddress)_secret")
            // // print("[SharedDataManager] Secret saved with direct key")
            
            // 2. 使用带 app group 前缀的格式
            userDefaults.set(secret, forKey: "group.ym.si.clashdash_\(cleanServerAddress)_secret")
            // // print("[SharedDataManager] Secret saved with app group key")
            
            // 3. 使用 Keys.serverKey 格式
            userDefaults.set(secret, forKey: Keys.serverKey(cleanServerAddress, Keys.secret))
            // // print("[SharedDataManager] Secret saved with serverKey format")
            
            // 4. 使用完整地址格式（包含端口）
            userDefaults.set(secret, forKey: "\(serverAddress)_secret")
            // print("[SharedDataManager] Secret saved with full address key")
        }
        
        userDefaults.synchronize()
        // print("[SharedDataManager] Status saved successfully")
        
        // 验证保存的数据 (用于调试，当前已禁用)
        let _ = getClashStatus(for: serverAddress)
    }
    
    public func getClashStatus(for serverAddress: String? = nil) -> ClashStatus {
        // print("[SharedDataManager] Getting status")
        
        let targetAddress = serverAddress ?? findLastUpdatedServer() ?? "未连接"
        // print("[SharedDataManager] Target address: \(targetAddress)")
        
        let status = ClashStatus(
            serverAddress: userDefaults.string(forKey: "\(targetAddress)_serverAddress") ?? targetAddress,
            serverName: userDefaults.string(forKey: "\(targetAddress)_serverName"),
            activeConnections: userDefaults.integer(forKey: "\(targetAddress)_activeConnections"),
            uploadTotal: Int64(userDefaults.integer(forKey: "\(targetAddress)_uploadTotal")),
            downloadTotal: Int64(userDefaults.integer(forKey: "\(targetAddress)_downloadTotal")),
            memoryUsage: userDefaults.double(forKey: "\(targetAddress)_memoryUsage")
        )
        
        // print("[SharedDataManager] Retrieved status:")
        // print("[SharedDataManager] - Server address: \(status.serverAddress)")
        // print("[SharedDataManager] - Server name: \(status.serverName ?? "nil")")
        // print("[SharedDataManager] - Active connections: \(status.activeConnections)")
        // print("[SharedDataManager] - Upload total: \(status.uploadTotal)")
        // print("[SharedDataManager] - Download total: \(status.downloadTotal)")
        // print("[SharedDataManager] - Memory usage: \(status.memoryUsage ?? 0)")
        return status
    }
    
    public func getLastUpdateTime(for serverAddress: String) -> Date? {
        let lastUpdate = userDefaults.object(forKey: Keys.serverKey(serverAddress, Keys.lastUpdateTime)) as? Date
        // print("[SharedDataManager] Last update time for \(serverAddress): \(lastUpdate?.description ?? "nil")")
        return lastUpdate
    }
    
    public func getSecret(for serverAddress: String) -> String? {
        let cleanServerAddress = serverAddress.components(separatedBy: ":")[0]
        // print("[SharedDataManager] Getting secret for \(cleanServerAddress)")
        
        // 1. 尝试直接格式
        if let secret = userDefaults.string(forKey: "\(cleanServerAddress)_secret") {
            // print("[SharedDataManager] Found secret with direct key")
            return secret
        }
        
        // 2. 尝试带 app group 前缀的格式
        if let secret = userDefaults.string(forKey: "group.ym.si.clashdash_\(cleanServerAddress)_secret") {
            // print("[SharedDataManager] Found secret with app group key")
            return secret
        }
        
        // 3. 尝试使用完整地址格式（包含端口）
        if let secret = userDefaults.string(forKey: "\(serverAddress)_secret") {
            // print("[SharedDataManager] Found secret with full address key")
            return secret
        }
        
        // 4. 尝试使用 Keys.serverKey 格式
        if let secret = userDefaults.string(forKey: Keys.serverKey(cleanServerAddress, Keys.secret)) {
            // print("[SharedDataManager] Found secret with serverKey format")
            return secret
        }
        
        // 5. 尝试从 UserDefaults 中查找所有可能的 secret
        let allKeys = userDefaults.dictionaryRepresentation().keys
        for key in allKeys {
            if key.contains(cleanServerAddress) && key.hasSuffix("_secret") {
                if let secret = userDefaults.string(forKey: key) {
                    // print("[SharedDataManager] Found secret with key: \(key)")
                    return secret
                }
            }
        }
        
        // print("[SharedDataManager] Secret not found for \(serverAddress)")
        return nil
    }
    
    public func getUseSSL(for serverAddress: String) -> Bool {
        return userDefaults.bool(forKey: Keys.serverKey(serverAddress, Keys.useSSL))
    }
    
    public func findLastUpdatedServer() -> String? {
        let pattern = "_lastUpdateTime$"
        let allKeys = userDefaults.dictionaryRepresentation().keys
        var latestDate: Date?
        var latestServer: String?
        
        for key in allKeys {
            if key.range(of: pattern, options: .regularExpression) != nil {
                if let date = userDefaults.object(forKey: key) as? Date {
                    if latestDate == nil || date > latestDate! {
                        latestDate = date
                        latestServer = String(key.split(separator: "_")[0])
                    }
                }
            }
        }
        
        return latestServer
    }
}

// MARK: - 共享的数据模型
public struct ClashStatus {
    public let serverAddress: String
    public let serverName: String?
    public let activeConnections: Int
    public let uploadTotal: Int64
    public let downloadTotal: Int64
    public let memoryUsage: Double?
    
    public init(
        serverAddress: String,
        serverName: String?,
        activeConnections: Int,
        uploadTotal: Int64,
        downloadTotal: Int64,
        memoryUsage: Double?
    ) {
        self.serverAddress = serverAddress
        self.serverName = serverName
        self.activeConnections = activeConnections
        self.uploadTotal = uploadTotal
        self.downloadTotal = downloadTotal
        self.memoryUsage = memoryUsage
    }
}

// MARK: - 连接相关模型
public struct ConnectionMetadata: Codable {
    public let network: String
    public let type: String
    public let sourceIP: String
    public let destinationIP: String
    public let sourcePort: String
    public let destinationPort: String
    public let host: String
    public let dnsMode: String
    public let processPath: String
    public let specialProxy: String
    public let sourceGeoIP: String?
    public let destinationGeoIP: String?
    public let sourceIPASN: String?
    public let destinationIPASN: String?
    public let inboundIP: String?
    public let inboundPort: String?
    public let inboundName: String?
    public let inboundUser: String?
    public let uid: Int?
    public let process: String?
    public let specialRules: String?
    public let remoteDestination: String?
    public let dscp: Int?
    public let sniffHost: String?
    
    public init(
        network: String,
        type: String,
        sourceIP: String,
        destinationIP: String,
        sourcePort: String,
        destinationPort: String,
        host: String,
        dnsMode: String,
        processPath: String,
        specialProxy: String,
        sourceGeoIP: String? = nil,
        destinationGeoIP: String? = nil,
        sourceIPASN: String? = nil,
        destinationIPASN: String? = nil,
        inboundIP: String? = nil,
        inboundPort: String? = nil,
        inboundName: String? = nil,
        inboundUser: String? = nil,
        uid: Int? = nil,
        process: String? = nil,
        specialRules: String? = nil,
        remoteDestination: String? = nil,
        dscp: Int? = nil,
        sniffHost: String? = nil
    ) {
        self.network = network
        self.type = type
        self.sourceIP = sourceIP
        self.destinationIP = destinationIP
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.host = host
        self.dnsMode = dnsMode
        self.processPath = processPath
        self.specialProxy = specialProxy
        self.sourceGeoIP = sourceGeoIP
        self.destinationGeoIP = destinationGeoIP
        self.sourceIPASN = sourceIPASN
        self.destinationIPASN = destinationIPASN
        self.inboundIP = inboundIP
        self.inboundPort = inboundPort
        self.inboundName = inboundName
        self.inboundUser = inboundUser
        self.uid = uid
        self.process = process
        self.specialRules = specialRules
        self.remoteDestination = remoteDestination
        self.dscp = dscp
        self.sniffHost = sniffHost
    }
}

// MARK: - 网络请求模型
public struct ConnectionsData: Codable {
    public let downloadTotal: Int
    public let uploadTotal: Int
    public let connections: [Connection]?
    public let memory: Int?
    
    public init(downloadTotal: Int, uploadTotal: Int, connections: [Connection]?, memory: Int?) {
        self.downloadTotal = downloadTotal
        self.uploadTotal = uploadTotal
        self.connections = connections
        self.memory = memory
    }
}

public struct Connection: Codable {
    public let id: String
    public let upload: Int
    public let download: Int
    
    public init(id: String, upload: Int, download: Int) {
        self.id = id
        self.upload = upload
        self.download = download
    }
}

public struct MemoryData: Codable {
    public let inuse: Int
    public let oslimit: Int
    
    public init(inuse: Int, oslimit: Int) {
        self.inuse = inuse
        self.oslimit = oslimit
    }
} 