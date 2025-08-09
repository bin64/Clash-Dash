import Foundation
import SwiftUI

private let logger = LogManager.shared

struct WiFiBinding: Codable, Identifiable, Equatable {
    let id: UUID
    var ssid: String
    var serverIds: [String]
    
    init(id: UUID = UUID(), ssid: String, serverIds: [String]) {
        self.id = id
        self.ssid = ssid
        self.serverIds = serverIds
    }
    
    static func == (lhs: WiFiBinding, rhs: WiFiBinding) -> Bool {
        lhs.id == rhs.id && lhs.ssid == rhs.ssid && lhs.serverIds == rhs.serverIds
    }
}

class WiFiBindingManager: ObservableObject {
    @Published var bindings: [WiFiBinding] = []
    @Published var defaultServerIds: Set<String> = []
    private let defaults = UserDefaults.standard
    private let storageKey = "wifi_bindings"
    private let enableKey = "enableWiFiBinding"
    private let defaultServersKey = "default_servers"
    private var notificationObserver: NSObjectProtocol?
    
    var isEnabled: Bool {
        get { defaults.bool(forKey: enableKey) }
    }
    
    init() {
        logger.debug("初始化 WiFiBindingManager")
        if isEnabled {
            loadBindings()
            loadDefaultServers()
        } else {
            logger.info("Wi-Fi 绑定功能未启用，跳过加载绑定数据")
        }
        
        // 添加通知监听
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("WiFiBindingsUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            logger.debug("收到 WiFi 绑定更新通知")
            guard let self = self else { return }
            if self.isEnabled {
                self.loadBindings()
                self.loadDefaultServers()
                self.objectWillChange.send()
            }
        }
    }
    
    deinit {
        // 移除通知监听
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // 解析并加载所有已保存的控制器信息（兼容新旧存储键）
    private func loadAllServers() -> [ClashServer] {
        if let data = defaults.data(forKey: "servers"),
           let servers = try? JSONDecoder().decode([ClashServer].self, from: data) {
            return servers
        }
        if let data = defaults.data(forKey: "SavedClashServers"),
           let servers = try? JSONDecoder().decode([ClashServer].self, from: data) {
            return servers
        }
        return []
    }
    
    // 将控制器 ID 列表转换为可读的控制器详情字符串
    private func describeServers(_ serverIds: [String]) -> String {
        let allServers = loadAllServers()
        if allServers.isEmpty { return serverIds.joined(separator: ", ") }
        let idSet = Set(serverIds)
        let matched = allServers.filter { idSet.contains($0.id.uuidString) }
        if matched.isEmpty { return serverIds.joined(separator: ", ") }
        return matched.map { server in
            let address: String
            if server.source == .clashController {
                address = "\(server.url):\(server.port)"
            } else {
                let host = server.openWRTUrl ?? server.url
                let port = server.openWRTPort ?? server.port
                address = "\(host):\(port)"
            }
            return "\(server.displayName) [\(address)]"
        }.joined(separator: ", ")
    }
    
    private func loadBindings() {
        if let data = defaults.data(forKey: storageKey),
           let bindings = try? JSONDecoder().decode([WiFiBinding].self, from: data) {
            self.bindings = bindings
            logger.info("从 UserDefaults 加载绑定: \(bindings.count) 个")
            for binding in bindings {
                logger.debug("   - SSID: \(binding.ssid), 控制器: \(describeServers(binding.serverIds))")
            }
        } else {
            logger.warning("无法从 UserDefaults 加载 Wi-Fi 绑定数据")
        }
    }
    
    private func saveBindings() {
        if !isEnabled {
            logger.warning("Wi-Fi 绑定功能未启用，跳过保存绑定数据")
            return
        }
        
        if let data = try? JSONEncoder().encode(bindings) {
            defaults.set(data, forKey: storageKey)
            logger.info("保存 Wi-Fi 绑定到 UserDefaults: \(bindings.count) 个")
            for binding in bindings {
                logger.debug("   - SSID: \(binding.ssid), 控制器: \(describeServers(binding.serverIds))")
            }
        } else {
            logger.error("保存 Wi-Fi 绑定失败")
        }
    }
    
    func addBinding(_ binding: WiFiBinding) {
        if !isEnabled {
            logger.warning("Wi-Fi 绑定功能未启用，无法添加绑定")
            return
        }
        
        logger.info("添加新的 Wi-Fi 绑定: SSID=\(binding.ssid), 控制器=\(describeServers(binding.serverIds))")
        bindings.append(binding)
        saveBindings()
        objectWillChange.send()
        logger.debug("绑定添加完成，当前总数: \(bindings.count)")
    }
    
    func updateBinding(_ binding: WiFiBinding) {
        if !isEnabled {
            logger.warning("Wi-Fi 绑定功能未启用，无法更新绑定")
            return
        }
        
        logger.info("更新 Wi-Fi 绑定: SSID=\(binding.ssid), 控制器=\(describeServers(binding.serverIds))")
        if let index = bindings.firstIndex(where: { $0.id == binding.id }) {
            var newBindings = bindings
            newBindings[index] = binding
            bindings = newBindings
            saveBindings()
            objectWillChange.send()
            logger.debug("绑定更新完成，当前总数: \(bindings.count)")
        } else {
            logger.error("未找到要更新的绑定: \(binding.id)")
        }
    }
    
    func removeBinding(_ binding: WiFiBinding) {
        if !isEnabled {
            logger.warning("Wi-Fi 绑定功能未启用，无法删除绑定")
            return
        }
        
        logger.info("删除 Wi-Fi 绑定: SSID=\(binding.ssid)")
        bindings.removeAll { $0.id == binding.id }
        saveBindings()
        objectWillChange.send()
        logger.debug("绑定删除完成，当前总数: \(bindings.count)")
    }
    
    private func loadDefaultServers() {
        if let data = defaults.stringArray(forKey: defaultServersKey) {
            defaultServerIds = Set(data)
            logger.debug("加载默认控制器列表: \(data.count) 个")
        }
    }
    
    private func saveDefaultServers() {
        defaults.set(Array(defaultServerIds), forKey: defaultServersKey)
        logger.debug("保存默认控制器列表: \(defaultServerIds.count) 个")
    }
    
    func updateDefaultServers(_ serverIds: Set<String>) {
        defaultServerIds = serverIds
        saveDefaultServers()
        objectWillChange.send()
        logger.info("更新默认控制器列表: \(serverIds.count) 个")
    }
    
    func onEnableChange() {
        if isEnabled {
            logger.info("Wi-Fi 绑定功能已启用，加载绑定数据")
            loadBindings()
            loadDefaultServers()
        } else {
            logger.info("Wi-Fi 绑定功能已禁用，清空绑定数据")
            bindings.removeAll()
            defaultServerIds.removeAll()
            objectWillChange.send()
        }
    }
}