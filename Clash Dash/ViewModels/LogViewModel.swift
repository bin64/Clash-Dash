import Foundation
import SwiftUI
import Network

private let logger = LogManager.shared

class LogViewModel: ObservableObject {
    @Published var logs: [LogMessage] = []
    @Published var isConnected = false
    @Published var isUserPaused = false
    private var logLevel: String = "info"
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var currentServer: ClashServer?
    private var isReconnecting = false
    private var connectionRetryCount = 0
    private let maxRetryCount = 5
    private var reconnectTask: Task<Void, Never>?
    
    // 添加日志缓冲队列
    private var logBuffer: [LogMessage] = []
    private var displayTimer: Timer?
    private let displayInterval: TimeInterval = 0.1 // 每条日志显示间隔
    
    // 添加网络状态监控
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    
    init() {
        setupNetworkMonitoring()
    }
    
    deinit {
        networkMonitor.cancel()
        stopDisplayTimer()
        webSocketTask?.cancel()
        webSocketTask = nil
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
                if self?.isNetworkAvailable == true && self?.isConnected == false {
                    if let server = self?.currentServer {
                        self?.connect(to: server)
                    }
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .background))
    }
    
    private func startDisplayTimer() {
        stopDisplayTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: displayInterval, repeats: true) { [weak self] _ in
            self?.displayNextLog()
        }
    }
    
    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }
    
    private func displayNextLog() {
        guard !logBuffer.isEmpty else {
            stopDisplayTimer()
            return
        }
        
        DispatchQueue.main.async {
            // 从缓冲区取出第一条日志
            let log = self.logBuffer.removeFirst()
            
            // 只保留最新的 1000 条日志
            if self.logs.count > 1000 {
                self.logs.removeFirst(self.logs.count - 1000)
            }
            
            // 添加新日志
            self.logs.append(log)
        }
    }
    
    // 添加设置日志级别的方法
    func setLogLevel(_ level: String) {
        guard self.logLevel != level else { return }
        self.logLevel = level
        // print("📝 切换实时日志级别到: \(level)")
        logger.info("切换实时日志级别到: \(level)")
        
        Task { @MainActor in
            // 先断开现有连接
            disconnect(clearLogs: false)
            // 等待短暂延迟确保连接完全关闭
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            // 重新连接
            if let server = self.currentServer {
                connect(to: server)
            }
        }
    }
    
    private func makeWebSocketRequest(server: ClashServer) -> URLRequest? {
        var components = URLComponents()
        components.scheme = server.clashUseSSL ? "wss" : "ws"
        components.host = server.url
        components.port = Int(server.port)
        components.path = "/logs"
        components.queryItems = [
            URLQueryItem(name: "token", value: server.secret),
            URLQueryItem(name: "level", value: logLevel)
        ]
        
        guard let url = components.url else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15 // 增加超时时间到 15 秒
        
        // WebSocket 必需的请求头
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
        request.setValue("permessage-deflate; client_max_window_bits", forHTTPHeaderField: "Sec-WebSocket-Extensions")
        request.setValue("HTTP/1.1", forHTTPHeaderField: "Version") // 添加HTTP版本头
        
        if !server.secret.isEmpty {
            request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        }
        
        return request
    }
    
    private func makeSession(server: ClashServer) -> URLSession {
        let config = URLSessionConfiguration.default
        if server.clashUseSSL {
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            config.tlsMinimumSupportedProtocolVersion = .TLSv12
            config.tlsMaximumSupportedProtocolVersion = .TLSv13
        }
        return URLSession(configuration: config)
    }
    
    func connect(to server: ClashServer) {
        // 取消现有的重连任务
        reconnectTask?.cancel()
        reconnectTask = nil
        
        // 如果是用户手动暂停的，不要连接
        if isUserPaused {
            return
        }
        
        // 如果已经连接到同一个服务器，不要重复连接
        if isConnected && currentServer?.id == server.id {
            return
        }
        
        // print("📡 开始连接到服务器: \(server.url):\(server.port)")
        logger.info("开始连接到服务器: \(server.url):\(server.port)")
        
        currentServer = server
        
        guard let request = makeWebSocketRequest(server: server) else {
            // print("无法创建 WebSocket 请求")
            logger.error("无法创建 WebSocket 请求")
            return
        }
        
        // 使用支持 SSL 的会话
        let session = makeSession(server: server)
        webSocketTask?.cancel()
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        DispatchQueue.main.async {
            self.isConnected = true
        }
        
        receiveLog()
    }
    
    private func handleWebSocketError(_ error: Error) {
        // 只在非取消错误时处理
        guard !error.isCancellationError else { return }
        
        // print("WebSocket 错误: \(error.localizedDescription)")
        logger.error("WebSocket 错误: \(error.localizedDescription)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 更新连接状态
            self.isConnected = false
            
            // 如果不是用户手动暂停，且未达到最大重试次数，则尝试重连
            if !self.isUserPaused {
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .secureConnectionFailed, .serverCertificateUntrusted:
                        // print("SSL/证书错误，停止重连")
                        logger.error("SSL/证书错误，停止重连")
                        self.connectionRetryCount = self.maxRetryCount
                    default:
                        if self.connectionRetryCount < self.maxRetryCount {
                            self.reconnect()
                        } else {
                            // print("达到最大重试次数，停止重连")
                            logger.warning("达到最大重试次数，停止重连")
                        }
                    }
                } else {
                    if self.connectionRetryCount < self.maxRetryCount {
                        self.reconnect()
                    } else {
                        // print("达到最大重试次数，停止重连")
                        logger.warning("达到最大重试次数，停止重连")
                    }
                }
            }
        }
    }
    
    private func receiveLog() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                DispatchQueue.main.async {
                    self.isConnected = true
                    // 只有在非重连状态下才重置重试计数
                    if !self.isReconnecting {
                        self.connectionRetryCount = 0
                    }
                }
                
                switch message {
                case .string(let text):
                    if text == "ping" {
                        self.receiveLog()
                        return
                    }
                    self.handleLog(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleLog(text)
                    }
                @unknown default:
                    break
                }
                self.receiveLog()
                
            case .failure(let error):
                self.handleWebSocketError(error)
            }
        }
    }
    
    private func handleLog(_ text: String) {
        guard let data = text.data(using: .utf8),
              let logMessage = try? JSONDecoder().decode(LogMessage.self, from: data) else {
            return
        }
        
        // 将新日志添加到缓冲区
        logBuffer.append(logMessage)
        
        // 如果定时器没有运行，启动定时器
        if displayTimer == nil {
            DispatchQueue.main.async {
                self.startDisplayTimer()
            }
        }
    }
    
    func disconnect(clearLogs: Bool = true) {
        // 取消重连任务
        reconnectTask?.cancel()
        reconnectTask = nil
        
        networkMonitor.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        stopDisplayTimer()
        logBuffer.removeAll()
        
        DispatchQueue.main.async {
            self.isConnected = false
            if clearLogs {
                self.logs.removeAll()
            }
        }
    }
    
    // 修改重连策略，使用指数退避
    private func getReconnectDelay() -> UInt64 {
        let baseDelay: UInt64 = 3_000_000_000 // 3秒
        let maxDelay: UInt64 = 30_000_000_000 // 30秒
        let delay = baseDelay * UInt64(min(pow(2.0, Double(connectionRetryCount - 1)), 10))
        return min(delay, maxDelay)
    }
    
    private func reconnect() {
        // 如果已经有重连任务在进行，不要创建新的
        guard reconnectTask == nil else { return }
        
        connectionRetryCount += 1
        
        // print("准备重新连接... (第 \(connectionRetryCount) 次重试)")
        logger.info("准备重新连接... (第 \(connectionRetryCount) 次重试)")
        
        reconnectTask = Task { [weak self] in
            guard let self = self else { return }
            
            self.isReconnecting = true
            
            // 使用指数退避延迟
            let delay = self.getReconnectDelay()
            // print("⏳ 等待 \(delay/1_000_000_000) 秒后重试...")
            logger.debug("等待 \(delay/1_000_000_000) 秒后重试...")
            
            try? await Task.sleep(nanoseconds: delay)
            
            // 检查任务是否被取消
            if Task.isCancelled {
                await MainActor.run {
                    self.isReconnecting = false
                    self.reconnectTask = nil
                }
                return
            }
            
            // 重连前再次检查状态
            if self.isUserPaused {
                await MainActor.run {
                    self.isReconnecting = false
                    self.reconnectTask = nil
                }
                return
            }
            
            await MainActor.run {
                if let server = self.currentServer {
                    self.connect(to: server)
                }
                self.isReconnecting = false
                self.reconnectTask = nil
            }
        }
    }
    
    // 修改用户手动暂停/继续方法
    func toggleConnection(to server: ClashServer) {
        isUserPaused.toggle()  // 直接切换用户暂停状态
        
        if isUserPaused {
            disconnect(clearLogs: false)
        } else {
            connectionRetryCount = 0  // 重置重试计数
            connect(to: server)
        }
    }
}

// 添加扩展来判断错误类型
extension Error {
    var isCancellationError: Bool {
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
            || self is CancellationError
    }
} 
