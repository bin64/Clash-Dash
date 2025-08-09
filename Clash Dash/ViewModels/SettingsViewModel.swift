import Foundation
// 在类的开头添加 LogManager
private let logger = LogManager.shared

class SettingsViewModel: ObservableObject {
    @Published var config: ClashConfig?
    @Published var mode: String = "rule"
    @Published var logLevel: String = "info"
    @Published var allowLan: Bool = true
    @Published var sniffing: Bool = false
    @Published var tunEnable: Bool = false
    @Published var tunDevice: String = ""
    @Published var tunStack: String = "gVisor"
    @Published var interfaceName: String = ""
    @Published var language: String = "zh-CN"
    @Published var tunAutoRoute: Bool = true
    @Published var tunAutoDetectInterface: Bool = true
    @Published var httpPort: String = "0"
    @Published var socksPort: String = "0"
    @Published var mixedPort: String = "0"
    @Published var redirPort: String = "0"
    @Published var tproxyPort: String = "0"
    @Published var tempHttpPort: String = "0"
    @Published var tempSocksPort: String = "0"
    @Published var tempMixedPort: String = "0"
    @Published var tempRedirPort: String = "0"
    @Published var tempTproxyPort: String = "0"
    
    private func makeRequest(path: String, server: ClashServer) -> URLRequest? {
        let scheme = server.clashUseSSL ? "https" : "http"
        // logger.debug("SSL设置: clashUseSSL = \(server.clashUseSSL)")
        // logger.debug("📡 使用协议: \(scheme)")
        
        guard let url = URL(string: "\(scheme)://\(server.url):\(server.port)/\(path)") else {
            logger.error("无效的 URL")
            return nil
        }
        
        // logger.debug("完整URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    func fetchConfig(server: ClashServer) {
        // logger.debug("开始获取配置...")
        guard let request = makeRequest(path: "configs", server: server) else { 
            logger.error("创建请求失败")
            return 
        }
        
        URLSession.secure.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                logger.error("请求错误: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                logger.debug("响应状态码: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                logger.error("没有收到数据")
                return 
            }
            
            if let config = try? JSONDecoder().decode(ClashConfig.self, from: data) {
                DispatchQueue.main.async {
                    self?.config = config
                    self?.updateUIFromConfig(config)
                    logger.info("配置更新成功")
                }
            } else {
                logger.error("解码配置失败")
            }
        }.resume()
    }
    
    private func updateUIFromConfig(_ config: ClashConfig) {
        self.mode = config.mode.lowercased()
        self.logLevel = config.logLevel
        self.allowLan = config.allowLan
        self.sniffing = config.sniffing ?? false
        
        if let tun = config.tun {
            self.tunEnable = tun.enable
            self.tunDevice = tun.device
            // logger.log("TUN Stack 原始值: \(tun.stack)")
            self.tunStack = tun.stack.lowercased()
            // logger.log("TUN Stack 转换后值: \(self.tunStack)")
            self.tunAutoRoute = tun.autoRoute
            self.tunAutoDetectInterface = tun.autoDetectInterface
        }
        
        if let interfaceName = config.interfaceName {
            self.interfaceName = interfaceName
        }
        
        self.httpPort = "\(config.port)"
        self.tempHttpPort = self.httpPort
        self.socksPort = "\(config.socksPort)"
        self.tempSocksPort = self.socksPort
        self.mixedPort = String(config.mixedPort ?? 0)
        self.tempMixedPort = self.mixedPort
        self.redirPort = String(config.redirPort)
        self.tempRedirPort = self.redirPort
        self.tproxyPort = String(config.tproxyPort ?? 0)
        self.tempTproxyPort = self.tproxyPort
    }
    
    func updateConfig(_ path: String, value: Any, server: ClashServer, completion: (() -> Void)? = nil) {
        guard var request = makeRequest(path: "configs", server: server) else { return }
        
        request.httpMethod = "PATCH"
        
        // 如果是模式更新，保存到 UserDefaults
        if path == "mode" {
            if let modeValue = value as? String {
                UserDefaults.standard.set(modeValue, forKey: "currentMode")
            }
        }
        
        // 构建嵌套的 payload 结构
        let payload: [String: Any]
        if path.contains(".") {
            let components = path.split(separator: ".")
            let lastKey = String(components.last!)
            let firstKey = String(components.first!)
            
            payload = [
                firstKey: [
                    lastKey: value
                ]
            ]
        } else {
            payload = [path: value]
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            if let bodyString = String(data: request.httpBody!, encoding: .utf8) {
                logger.debug("配置更新请求: \(bodyString)")
            }
        } catch {
            logger.error("配置更新失败: \(error.localizedDescription)")
            return
        }
        
        URLSession.secure.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 204 {
                    logger.info("配置更新成功：\(path) = \(value)")
                    DispatchQueue.main.async {
                        completion?()
                    }
                } else {
                    logger.error("配置更新失败：状态码 \(httpResponse.statusCode)")
                }
            }
            
            if let error = error {
                logger.error("配置更新错误：\(error.localizedDescription)")
            }
        }.resume()
    }
    
    // MARK: - Actions
    func reloadConfig(server: ClashServer) {
        let scheme = server.clashUseSSL ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(server.url):\(server.port)/configs?force=true") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        
        URLSession.secure.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                logger.info("配置重载成功")
                DispatchQueue.main.async {
                    HapticManager.shared.notification(.success)
                }
            } else if let error = error {
                logger.error("配置重载失败：\(error.localizedDescription)")
                DispatchQueue.main.async {
                    HapticManager.shared.notification(.error)
                }
            }
        }.resume()
    }
    
    func updateGeoDatabase(server: ClashServer) {
        let scheme = server.clashUseSSL ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(server.url):\(server.port)/configs/geo") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        
        URLSession.secure.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                logger.info("GEO 数据库更新成功")
                DispatchQueue.main.async {
                    HapticManager.shared.notification(.success)
                }
            } else if let error = error {
                logger.error("GEO 数据库更新失败：\(error.localizedDescription)")
                DispatchQueue.main.async {
                    HapticManager.shared.notification(.error)
                }
            }
        }.resume()
    }
    
    func clearFakeIP(server: ClashServer) {
        let scheme = server.clashUseSSL ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(server.url):\(server.port)/cache/fakeip/flush") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        
        URLSession.secure.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                logger.info("FakeIP 缓存清除成功")
                DispatchQueue.main.async {
                    HapticManager.shared.notification(.success)
                }
            } else if let error = error {
                logger.error("FakeIP 缓存清除失败：\(error.localizedDescription)")
                DispatchQueue.main.async {
                    HapticManager.shared.notification(.error)
                }
            }
        }.resume()
    }
    
    func restartCore(server: ClashServer) {
        let scheme = server.clashUseSSL ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(server.url):\(server.port)/restart") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        
        URLSession.secure.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                logger.info("核心重启成功")
                DispatchQueue.main.async {
                    HapticManager.shared.notification(.success)
                }
            } else if let error = error {
                logger.error("核心重启失败：\(error.localizedDescription)")
                DispatchQueue.main.async {
                    HapticManager.shared.notification(.error)
                }
            }
        }.resume()
    }
    
    func upgradeCore(server: ClashServer) {
        let scheme = server.clashUseSSL ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(server.url):\(server.port)/upgrade") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        
        URLSession.secure.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                logger.info("核心更新成功")
                DispatchQueue.main.async {
                    HapticManager.shared.notification(.success)
                }
            } else if let error = error {
                logger.error("核心更新失败：\(error.localizedDescription)")
                DispatchQueue.main.async {
                    HapticManager.shared.notification(.error)
                }
            }
        }.resume()
    }
    
    func validateAndUpdatePort(_ portString: String, configKey: String, server: ClashServer) -> Bool {
        guard let port = Int(portString),
              (0...65535).contains(port) else {
            DispatchQueue.main.async {
                HapticManager.shared.notification(.error)
            }
            return false
        }
        
        updateConfig(configKey, value: port, server: server)
        DispatchQueue.main.async {
            HapticManager.shared.notification(.success)
        }
        return true
    }
    
    func getCurrentMode(server: ClashServer, completion: @escaping (String) -> Void) {
        guard let request = makeRequest(path: "configs", server: server) else { return }
        
        URLSession.secure.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let config = try? JSONDecoder().decode(ClashConfig.self, from: data) else {
                return
            }
            
            DispatchQueue.main.async {
                completion(config.mode)
            }
        }.resume()
    }
} 
