import Foundation
import Combine
import SwiftUI  // 添加这行

@MainActor
class ConnectionsViewModel: ObservableObject, Sendable {
    @AppStorage("connectionRowStyle") var connectionRowStyle = ConnectionRowStyle.classic
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case paused
        case error(String)
        
        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected):
                return true
            case (.connecting, .connecting):
                return true
            case (.connected, .connected):
                return true
            case (.paused, .paused):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
        
        var message: String {
            switch self {
            case .disconnected:
                return "未连接到后端"
            case .connecting:
                return "正在连接后端..."
            case .connected:
                return "已连接到后端"
            case .paused:
                return "监控已暂停"
            case .error(let message):
                return message
            }
        }
        
        var showStatus: Bool {
            return true
        }
        
        var statusColor: Color {
            switch self {
            case .connected:
                return .green
            case .connecting, .paused:
                return .blue
            case .disconnected, .error:
                return .red
            }
        }
        
        var statusIcon: String {
            switch self {
            case .connected:
                return "checkmark.circle.fill"
            case .connecting:
                return "arrow.clockwise"
            case .paused:
                return "pause.circle.fill"
            case .disconnected, .error:
                return "exclamationmark.triangle.fill"
            }
        }
        
        var isConnecting: Bool {
            if case .connecting = self {
                return true
            }
            return false
        }
    }
    
    @Published var connections: [ClashConnection] = []
    @Published var totalUpload: Int = 0
    @Published var totalDownload: Int = 0
    @Published var connectionState: ConnectionState = .disconnected
    @Published var isMonitoring = false
    
    private var connectionsTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var server: ClashServer?
    
    private var previousConnections: [String: ClashConnection] = [:]
    private var reconnectTask: Task<Void, Never>?
    private var isReconnecting = false
    
    // 添加错误追踪
    private struct ErrorTracker {
        var count: Int = 0
        var firstErrorTime: Date?
        
        mutating func recordError() -> Bool {
            let now = Date()
            
            // 如果是第一个错误或者距离第一个错误超过5秒，重置计数
            if firstErrorTime == nil || now.timeIntervalSince(firstErrorTime!) > 5 {
                count = 1
                firstErrorTime = now
                return false
            }
            
            count += 1
            return count >= 3 // 返回是否达到阈值
        }
        
        mutating func reset() {
            count = 0
            firstErrorTime = nil
        }
    }
    
    private var errorTracker = ErrorTracker()
    
    private func log(_ message: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }
    
    func startMonitoring(server: ClashServer) {
        self.server = server
        isMonitoring = true

        switch server.source {
        case .surge:
            startSurgeConnectionsMonitoring()
        case .clashController, .openWRT:
            connectToConnections(server: server)
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        reconnectTask?.cancel()
        reconnectTask = nil
        connectionsTask?.cancel()
        connectionsTask = nil
        errorTracker.reset()

        // 停止 Surge 连接监控
        stopSurgeConnectionsMonitoring()

        updateConnectionState(.paused)
    }
    
    private func connectToConnections(server: ClashServer) {
        guard isMonitoring else { return }
        
        // 取消之前的重连任务
        reconnectTask?.cancel()
        reconnectTask = nil
        
        // 构建 WebSocket URL，支持 SSL
        let scheme = server.clashUseSSL ? "wss" : "ws"
        guard let url = URL(string: "\(scheme)://\(server.url):\(server.port)/connections") else {
            log("URL 构建失败")
            DispatchQueue.main.async { [weak self] in
                self?.connectionState = .error("URL 构建失败")
            }
            return 
        }
        
        // 先测试 HTTP 连接
        let httpScheme = server.clashUseSSL ? "https" : "http"
        var testRequest = URLRequest(url: URL(string: "\(httpScheme)://\(server.url):\(server.port)")!)
        if !server.secret.isEmpty {
            testRequest.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        }
        
        // 如果使用 SSL，添加额外的配置
        let sessionConfig = URLSessionConfiguration.default
        if server.clashUseSSL {
            sessionConfig.urlCache = nil // 禁用缓存
            sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            // 允许自签名证书
            sessionConfig.tlsMinimumSupportedProtocolVersion = .TLSv12
            sessionConfig.tlsMaximumSupportedProtocolVersion = .TLSv13
        }
        
        Task {
            do {
                let session = URLSession(configuration: sessionConfig)
                let (_, response) = try await session.data(for: testRequest)
                
                if let httpResponse = response as? HTTPURLResponse {
                    // log("HTTP 连接测试状态码: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode == 401 {
                        DispatchQueue.main.async { [weak self] in
                            self?.connectionState = .error("认证失败，请检查 Secret")
                        }
                        return
                    }
                }
                
                // 创建 WebSocket 请求
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                
                if !server.secret.isEmpty {
                    request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
                }
                
                // 取消现有连接
                connectionsTask?.cancel()
                connectionsTask = nil
                
                // 创建新连接
                let wsSession = URLSession(configuration: sessionConfig)
                let task = wsSession.webSocketTask(with: request)
                task.maximumMessageSize = 10 * 1024 * 1024 // 设置最大消息大小为 10MB
                connectionsTask = task
                
                // 设置消息处理
                task.resume()
                receiveConnectionsData()
                
            } catch {
                log("HTTP 连接测试失败: \(error.localizedDescription)")
                handleConnectionError(error)
            }
        }
    }
    
    private func handleConnectionError(_ error: Error) {
        log("连接错误：\(error.localizedDescription)")
        
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .error(error.localizedDescription)
        }
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .secureConnectionFailed:
                log("SSL/TLS 连接失败")
                DispatchQueue.main.async { [weak self] in
                    self?.connectionState = .error("SSL/TLS 连接失败，请检查证书配置")
                }
            case .serverCertificateUntrusted:
                log("服务器证书不受信任")
                DispatchQueue.main.async { [weak self] in
                    self?.connectionState = .error("服务器证书不受信任")
                }
            case .clientCertificateRejected:
                log("客户端证书被拒绝")
                DispatchQueue.main.async { [weak self] in
                    self?.connectionState = .error("客户端证书被拒绝")
                }
            default:
                break
            }
        }
    }
    
    private func receiveConnectionsData() {
        guard let task = connectionsTask, isMonitoring else { return }

        task.receive { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                guard self.isMonitoring else { return }

                switch result {
                case .success(let message):
                    // 成功接收消息时重置错误计数
                    self.errorTracker.reset()

                    switch message {
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            self.handleConnectionsMessage(data)
                        }
                    case .data(let data):
                        self.handleConnectionsMessage(data)
                    @unknown default:
                        break
                    }

                    // 继续接收下一条消息
                    self.receiveConnectionsData()

                case .failure(let error):
                    self.log("WebSocket 错误：\(error.localizedDescription)")

                    if self.errorTracker.recordError() {
                        self.connectionState = .error("连接失败，请检查网络或服务器状态")
                        self.stopMonitoring()
                    } else {
                        self.reconnect()
                    }
                }
            }
        }
    }
    
    private let maxHistoryCount = 200
    private var connectionHistory: [String: ClashConnection] = [:] // 用于存储历史记录
    
    private func updateConnectionState(_ newState: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 只有在以下情况才更新状态:
            // 1. 新状态是错误状态
            // 2. 当前不是错误状态
            // 3. 状态确实发生了变化
            if case .error = newState {
                self.connectionState = newState
            } else if case .error = self.connectionState {
                // 如果当前是错误状态，只有在明确要切换到其他状态时才更新
                if case .connecting = newState {
                    self.connectionState = newState
                }
            } else if self.connectionState != newState {
                self.connectionState = newState
            }
            
            // 记录状态变化
            // log("状态更新: \(self.connectionState.message)")
        }
    }
    
    private func handleConnectionsMessage(_ data: Data) {
        do {
            let response = try JSONDecoder().decode(ConnectionsResponse.self, from: data)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // 更新连接状态
                self.updateConnectionState(.connected)
                
                // 更新总流量
                self.totalUpload = response.uploadTotal
                self.totalDownload = response.downloadTotal
                
                // 更新设备缓存，只添加新设备
                for connection in response.connections {
                    let ip = connection.metadata.sourceIP
                    if !self.deviceCache.contains(ip) {
                        self.deviceCache.append(ip)
                    }
                }
                
                // 如果连接数组为空，不要清空现有连接，只更新活跃状态
                if response.connections.isEmpty {
                    // 将所有活跃连接标记为已断开
                    for (id, connection) in self.connectionHistory {
                        if connection.isAlive {
                            let closedConnection = ClashConnection(
                                id: connection.id,
                                metadata: connection.metadata,
                                upload: connection.upload,
                                download: connection.download,
                                start: connection.start,
                                chains: connection.chains,
                                rule: connection.rule,
                                rulePayload: connection.rulePayload,
                                downloadSpeed: 0,
                                uploadSpeed: 0,
                                isAlive: false,
                                endTime: Date()
                            )
                            self.connectionHistory[id] = closedConnection
                        }
                    }
                    
                    // 更新显示的连接列表
                    self.connections = Array(self.connectionHistory.values)
                        .sorted { $0.start > $1.start }
                    
                    // 只清空活跃连接记录
                    self.previousConnections = [:]
                    self.updateConnectionState(.connected)
                } else {
                    var hasChanges = false
                    let currentIds = Set(response.connections.map { $0.id })
                    
                    // 处理活跃连接
                    for connection in response.connections {
                        let downloadSpeed = Double(
                            connection.download - (self.previousConnections[connection.id]?.download ?? connection.download)
                        )
                        let uploadSpeed = Double(
                            connection.upload - (self.previousConnections[connection.id]?.upload ?? connection.upload)
                        )
                        
                        // 创建更新后的连接对象
                        let updatedConnection = ClashConnection(
                            id: connection.id,
                            metadata: connection.metadata,
                            upload: connection.upload,
                            download: connection.download,
                            start: connection.start,
                            chains: connection.chains,
                            rule: connection.rule,
                            rulePayload: connection.rulePayload,
                            downloadSpeed: max(0, downloadSpeed),
                            uploadSpeed: max(0, uploadSpeed),
                            isAlive: true
                        )
                        
                        // 检查是否需要更新
                        if let existingConnection = self.connectionHistory[connection.id] {
                            if existingConnection != updatedConnection {
                                hasChanges = true
                                self.connectionHistory[connection.id] = updatedConnection
                            }
                        } else {
                            hasChanges = true
                            self.connectionHistory[connection.id] = updatedConnection
                        }
                    }
                    
                    // 更新已断开连接的状态
                    for (id, connection) in self.connectionHistory {
                        if !currentIds.contains(id) && connection.isAlive {
                            // 创建已断开的连接副本
                            let closedConnection = ClashConnection(
                                id: connection.id,
                                metadata: connection.metadata,
                                upload: connection.upload,
                                download: connection.download,
                                start: connection.start,
                                chains: connection.chains,
                                rule: connection.rule,
                                rulePayload: connection.rulePayload,
                                downloadSpeed: 0,
                                uploadSpeed: 0,
                                isAlive: false,
                                endTime: Date()
                            )
                            hasChanges = true
                            self.connectionHistory[id] = closedConnection
                        }
                    }
                    
                    // 只在有变化时更新 UI
                    if hasChanges {
                        // 转换为数组并按开始时间倒序排序
                        var sortedConnections = Array(self.connectionHistory.values)
                        sortedConnections.sort { conn1, conn2 in
                            // 只按时间排序，不考虑连接状态
                            return conn1.start > conn2.start
                        }
                        
                        self.connections = sortedConnections
                    }
                    
                    // 更新上一次的连接数据，只保存活跃连接
                    self.previousConnections = Dictionary(
                        uniqueKeysWithValues: response.connections.map { ($0.id, $0) }
                    )
                }
            }
        } catch DecodingError.valueNotFound(_, _) {
            // 处理空连接的情况
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // 将所有活跃连接标记为已断开
                for (id, connection) in self.connectionHistory {
                    if connection.isAlive {
                        let closedConnection = ClashConnection(
                            id: connection.id,
                            metadata: connection.metadata,
                            upload: connection.upload,
                            download: connection.download,
                            start: connection.start,
                            chains: connection.chains,
                            rule: connection.rule,
                            rulePayload: connection.rulePayload,
                            downloadSpeed: 0,
                            uploadSpeed: 0,
                            isAlive: false,
                            endTime: Date()
                        )
                        self.connectionHistory[id] = closedConnection
                    }
                }
                
                // 更新显示的连接列表
                self.connections = Array(self.connectionHistory.values)
                    .sorted { $0.start > $1.start }
                
                // 只清空活跃连接记录
                self.previousConnections = [:]
                self.updateConnectionState(.connected)
            }
        } catch {
            log("解码错误：\(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .dataCorrupted(let context):
                    log("    数据损坏: \(context)")
                case .keyNotFound(let key, let context):
                    log("    找不到键: \(key), 上下文: \(context)")
                case .typeMismatch(let type, let context):
                    log("    类型不匹配: \(type), 上下文: \(context)")
                case .valueNotFound(let type, let context):
                    log("    值未找到: \(type), 上下文: \(context)")
                @unknown default:
                    log("    未知解码错误")
                }
            }
            self.updateConnectionState(.error("数据解析错误: \(error.localizedDescription)"))
        }
    }
    
    private func makeRequest(path: String, method: String = "GET") -> URLRequest? {
        guard let server = server else { return nil }

        let scheme: String
        let basePath: String

        switch server.source {
        case .surge:
            scheme = server.surgeUseSSL ? "https" : "http"
            basePath = path.hasPrefix("/") ? path : "/v1\(path.hasPrefix("/") ? "" : "/")\(path)"
        case .clashController, .openWRT:
            scheme = server.clashUseSSL ? "https" : "http"
            basePath = path
        }

        guard let url = URL(string: "\(scheme)://\(server.url):\(server.port)\(basePath)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        // 添加认证头
        switch server.source {
        case .surge:
            if let surgeKey = server.surgeKey, !surgeKey.isEmpty {
                request.setValue(surgeKey, forHTTPHeaderField: "x-key")
            }
        case .clashController, .openWRT:
            if !server.secret.isEmpty {
                request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
            }
        }

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return request
    }
    
    private func makeSession() -> URLSession {
        return URLSessionManager.shared.makeCustomSession()
    }
    
    func closeConnection(_ id: String) {
        guard let server = server else { return }

        let request: URLRequest?
        switch server.source {
        case .surge:
            // Surge 使用 POST /requests/kill
            guard var req = makeRequest(path: "requests/kill", method: "POST") else { return }
            let body = ["id": Int(id) ?? 0]
            req.httpBody = try? JSONEncoder().encode(body)
            request = req
        case .clashController, .openWRT:
            // Clash 使用 DELETE /connections/{id}
            request = makeRequest(path: "connections/\(id)", method: "DELETE")
        }

        guard let finalRequest = request else { return }

        Task {
            do {
                let (_, response) = try await makeSession().data(for: finalRequest)
                let success: Bool
                if let httpResponse = response as? HTTPURLResponse {
                    switch server.source {
                    case .surge:
                        success = (200...299).contains(httpResponse.statusCode)
                    case .clashController, .openWRT:
                        success = httpResponse.statusCode == 204
                    }
                } else {
                    success = false
                }

                if success {
                    await MainActor.run {
                        if let index = connections.firstIndex(where: { $0.id == id }) {
                            let updatedConnection = connections[index]
                            connections[index] = ClashConnection(
                                id: updatedConnection.id,
                                metadata: updatedConnection.metadata,
                                upload: updatedConnection.upload,
                                download: updatedConnection.download,
                                start: updatedConnection.start,
                                chains: updatedConnection.chains,
                                rule: updatedConnection.rule,
                                rulePayload: updatedConnection.rulePayload,
                                downloadSpeed: 0,
                                uploadSpeed: 0,
                                isAlive: false
                            )
                        }
                    }
                }
            } catch {
                log("关闭连接失败: \(error.localizedDescription)")
            }
        }
    }
    
    func closeAllConnections() {
        guard let server = server else { return }

        switch server.source {
        case .surge:
            // Surge 不支持批量关闭，需要逐个关闭
            let connectionIds = connections.map { $0.id }
            closeConnections(connectionIds)
        case .clashController, .openWRT:
            guard let request = makeRequest(path: "connections", method: "DELETE") else { return }

            Task {
                do {
                    let (_, response) = try await makeSession().data(for: request)
                    if let httpResponse = response as? HTTPURLResponse,
                       httpResponse.statusCode == 204 {
                        await MainActor.run {
                            // 清空所有连接相关的数据
                            connections.removeAll()
                            previousConnections.removeAll()
                        }
                    }
                } catch {
                    log("关闭所有连接失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 添加批量关闭连接的方法
    func closeConnections(_ connectionIds: [String]) {
        for id in connectionIds {
            closeConnection(id)
        }
    }
    
    func refresh() async {
        stopMonitoring()
        if let server = server {
            startMonitoring(server: server)
        }
    }
    
    private func reconnect() {
        guard !isReconnecting else { return }
        isReconnecting = true
        
        // 取消现有的重连任务
        reconnectTask?.cancel()
        
        // 创建新的重连任务
        reconnectTask = Task {
            // 等待1秒后重试
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.updateConnectionState(.connecting)
                self.isReconnecting = false
                
                if let server = self.server {
                    self.connectToConnections(server: server)
                }
            }
        }
    }
    
    private func handleWebSocketError(_ error: Error) {
        log("WebSocket 错误：\(error.localizedDescription)")
        
        if errorTracker.recordError() {
            DispatchQueue.main.async { [weak self] in
                if let urlError = error as? URLError, urlError.code == .secureConnectionFailed {
                    self?.connectionState = .error("SSL/TLS 连接失败，请检查证书配置")
                } else {
                    self?.connectionState = .error("连接失败，请检查网络或服务器状态")
                }
            }
            stopMonitoring()
        } else {
            reconnect()
        }
    }
    
    // 清理已关闭的连接
    func clearClosedConnections() {
        print("\n🧹 开始清理已断开连接")
        print("当前连接总数:", connections.count)
        print("历史连接数量:", previousConnections.count)
        
        // 获取要清理的连接ID
        let closedConnectionIds = connections.filter { !$0.isAlive }.map { $0.id }
        
        // 从当前连接列表中移除已断开的连接
        connections.removeAll { !$0.isAlive }
        
        // 从历史记录中也移除这些连接
        for id in closedConnectionIds {
            connectionHistory.removeValue(forKey: id)  // 修改这里：从 connectionHistory 中移除
            previousConnections.removeValue(forKey: id)  // 同时从 previousConnections 中移除
        }
        
        print("清理后连接数量:", connections.count)
        print("清理后历史连接数量:", previousConnections.count)
        print("清理完成")
        print("-------------------\n")
    }
    
    private func handleConnectionsUpdate(_ response: ConnectionsResponse) {
        Task { @MainActor in
            totalUpload = response.uploadTotal
            totalDownload = response.downloadTotal
            
            var updatedConnections: [ClashConnection] = []
            
            for connection in response.connections {
                if let previousConnection = previousConnections[connection.id] {
                    // 只有活跃的连接才会被添加到更新列表中
                    if connection.isAlive {
                        let updatedConnection = ClashConnection(
                            id: connection.id,
                            metadata: connection.metadata,
                            upload: connection.upload,
                            download: connection.download,
                            start: connection.start,
                            chains: connection.chains,
                            rule: connection.rule,
                            rulePayload: connection.rulePayload,
                            downloadSpeed: Double(connection.download - previousConnection.download),
                            uploadSpeed: Double(connection.upload - previousConnection.upload),
                            isAlive: connection.isAlive
                        )
                        updatedConnections.append(updatedConnection)
                    }
                } else if connection.isAlive {
                    // 新的活跃连接
                    let newConnection = ClashConnection(
                        id: connection.id,
                        metadata: connection.metadata,
                        upload: connection.upload,
                        download: connection.download,
                        start: connection.start,
                        chains: connection.chains,
                        rule: connection.rule,
                        rulePayload: connection.rulePayload,
                        downloadSpeed: 0,
                        uploadSpeed: 0,
                        isAlive: connection.isAlive
                    )
                    updatedConnections.append(newConnection)
                }
                
                // 只保存活跃连接的历史记录
                if connection.isAlive {
                    previousConnections[connection.id] = connection
                }
            }
            
            connections = updatedConnections
        }
    }
    
    func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else if let server = server {
            startMonitoring(server: server)
        }
    }
    
    // 修改设备缓存为有序数组，以保持设备顺序
    private(set) var deviceCache: [String] = []  // 存储所有出现过的设备IP，按出现顺序排列

    // MARK: - Surge Connections Support

    private var surgeConnectionsTimer: Timer?

    /// Surge 请求数据结构
    private struct SurgeRequestsData: Codable {
        let requests: [SurgeRequestItem]
    }

    /// Surge 请求项数据结构
    private struct SurgeRequestItem: Codable {
        let id: Int
        let remoteAddress: String?
        let remoteHost: String?
        let inMaxSpeed: Double
        let notes: [String]?
        let inCurrentSpeed: Double
        let failed: Bool
        let status: String
        let outCurrentSpeed: Double
        let completed: Bool
        let modified: Bool
        let sourcePort: Int
        let completedDate: Double?
        let outBytes: Double
        let sourceAddress: String
        let localAddress: String?
        let policyName: String
        let inBytes: Double
        let method: String
        let pid: Int
        let replica: Bool
        let rule: String
        let startDate: Double
        let setupCompletedDate: Double?
        let outMaxSpeed: Double
        let processPath: String?
        let URL: String
        let timingRecords: [SurgeTimingRecord]?

        // 额外的可选字段
        let local: Bool?
        let deviceName: String?
        let takeoverMode: Int?
        let pathForStatistics: String?
        let streamHasResponseBody: Bool?
        let engineIdentifier: Int?
        let rejected: Bool?
        let interface: String?
        let originalPolicyName: String?

        struct SurgeTimingRecord: Codable {
            let durationInMillisecond: Double
            let name: String
        }
    }

    /// 开始 Surge 连接监控
    private func startSurgeConnectionsMonitoring() {
        guard isMonitoring else { return }

        log("开始 Surge 连接监控")

        // 停止之前的定时器
        surgeConnectionsTimer?.invalidate()
        surgeConnectionsTimer = nil

        // 立即获取一次数据
        Task {
            await fetchSurgeConnectionsData()
        }

        // 设置定时器，每2秒获取一次数据
        surgeConnectionsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.fetchSurgeConnectionsData()
            }
        }

        updateConnectionState(.connected)
    }

    /// 获取 Surge 连接数据
    private func fetchSurgeConnectionsData() async {
        guard isMonitoring, let server = server, server.source == .surge else { return }

        guard let request = makeRequest(path: "requests/active") else {
            log("创建 Surge 连接请求失败")
            return
        }

        do {
            let (data, response) = try await makeSession().data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                // 打印 HTTP 错误响应
                if let responseString = String(data: data, encoding: .utf8) {
                    print("DEBUG: Surge API HTTP 错误响应:")
                    print("Status Code: \(httpResponse.statusCode)")
                    print("Response: \(responseString)")
                }
                throw URLError(.badServerResponse)
            }

            let surgeData = try JSONDecoder().decode(SurgeRequestsData.self, from: data)
            await handleSurgeConnectionsData(surgeData.requests)

        } catch {
            // 打印原始响应数据用于调试（如果是 JSON 解析错误）
            if let decodingError = error as? DecodingError {
                // 重新获取数据来打印（因为原始的 data 变量在 catch 块外）
                if let (errorData, _) = try? await makeSession().data(for: request),
                   let responseString = String(data: errorData, encoding: .utf8) {
                    print("DEBUG: Surge API JSON 解析失败，原始响应数据:")
                    print("DEBUG: 响应数据长度: \(errorData.count) bytes")
                    print("DEBUG: 解析错误详情: \(decodingError.localizedDescription)")

                    // 详细打印解码错误信息
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        print("DEBUG: 缺失的字段: '\(key.stringValue)'")
                        print("DEBUG: 错误路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                        if let lastPath = context.codingPath.last {
                            print("DEBUG: 问题出现在数组索引: \(lastPath)")
                        }
                        print("DEBUG: 原始响应前500字符: \(String(responseString.prefix(500)))")

                        // 尝试解析并显示问题请求的结构
                        if let data = responseString.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                           let requests = json["requests"] as? [[String: Any]] {
                            if let indexStr = context.codingPath.last?.stringValue,
                               let index = Int(indexStr.replacingOccurrences(of: "Index ", with: "")),
                               index < requests.count {
                                let problematicRequest = requests[index]
                                print("DEBUG: 问题请求的所有字段: \(problematicRequest.keys.sorted())")
                                print("DEBUG: 缺失字段 '\(key.stringValue)' 是否存在: \(problematicRequest[key.stringValue] != nil)")
                            }
                        }

                    case .typeMismatch(let type, let context):
                        print("DEBUG: 类型不匹配 - 期望类型: \(type), 实际路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .valueNotFound(let type, let context):
                        print("DEBUG: 值未找到 - 期望类型: \(type), 路径: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    case .dataCorrupted(let context):
                        print("DEBUG: 数据损坏: \(context)")
                    @unknown default:
                        print("DEBUG: 未知解码错误")
                    }

                    print("DEBUG: 完整原始响应:")
                    print(responseString)
                }
            } else {
                // 其他类型的错误
                print("DEBUG: Surge API 请求失败: \(error.localizedDescription)")
                // 如果是网络错误，也打印响应数据
                if let (errorData, _) = try? await makeSession().data(for: request),
                   let responseString = String(data: errorData, encoding: .utf8) {
                    print("DEBUG: 错误时的响应数据:")
                    print(responseString)
                }
            }

            log("获取 Surge 连接数据失败: \(error.localizedDescription)")
            handleConnectionError(error)
        }
    }

    /// 处理 Surge 连接数据
    private func handleSurgeConnectionsData(_ surgeRequests: [SurgeRequestItem]) async {
        await MainActor.run {
            var allConnections: [ClashConnection] = []
            var newDeviceCache: Set<String> = []

            // 获取当前活跃连接的ID集合
            let currentActiveIds = Set(surgeRequests.map { String($0.id) })

            // 1. 处理当前活跃的连接
            for request in surgeRequests {
                // 转换 Surge 请求为 Clash 连接格式
                let connection = convertSurgeRequestToClashConnection(request)
                allConnections.append(connection)

                // 添加到设备缓存
                newDeviceCache.insert(request.sourceAddress)
            }

            // 2. 保留所有之前已断开的连接（这些连接应该一直保留，直到手动清空）
            for (id, previousConnection) in previousConnections {
                if !previousConnection.isAlive {
                    // 这是一个已断开的连接，保留它
                    allConnections.append(previousConnection)
                } else if previousConnection.isAlive && !currentActiveIds.contains(id) {
                    // 这个连接在上一次是活跃的，但这次没有出现在活跃列表中
                    // 将其标记为已断开
                    log("连接 \(id) 已断开")
                    let disconnectedConnection = ClashConnection(
                        id: previousConnection.id,
                        metadata: previousConnection.metadata,
                        upload: previousConnection.upload,
                        download: previousConnection.download,
                        start: previousConnection.start,
                        chains: previousConnection.chains,
                        rule: previousConnection.rule,
                        rulePayload: previousConnection.rulePayload,
                        downloadSpeed: 0, // 已断开连接速度为0
                        uploadSpeed: 0,
                        isAlive: false,
                        endTime: Date() // 设置结束时间为当前时间
                    )
                    allConnections.append(disconnectedConnection)
                }
                // 如果连接仍然活跃，我们已经在上面添加了最新的版本
            }

            // 3. 更新连接列表（活跃连接在前，已断开连接在后）
            connections = allConnections.sorted { conn1, conn2 in
                if conn1.isAlive == conn2.isAlive {
                    // 同状态的按开始时间倒序（最新的在前）
                    return conn1.start > conn2.start
                } else {
                    // 活跃连接在前
                    return conn1.isAlive && !conn2.isAlive
                }
            }

            // 4. 更新设备缓存
            deviceCache = Array(newDeviceCache).sorted()

            // 5. 更新 previousConnections 用于下次比较
            // 保存所有当前连接的状态（活跃的和已断开的）
            var updatedPreviousConnections: [String: ClashConnection] = [:]
            for connection in allConnections {
                updatedPreviousConnections[connection.id] = connection
            }
            previousConnections = updatedPreviousConnections

            // 6. 更新连接状态
            updateConnectionState(.connected)

            objectWillChange.send()
        }
    }

    /// 将 Surge 请求转换为 Clash 连接格式
    private func convertSurgeRequestToClashConnection(_ request: SurgeRequestItem) -> ClashConnection {
        // Surge API 返回的时间戳是标准的 Unix 时间戳（从 1970-01-01 开始的秒数）
        let startDate = Date(timeIntervalSince1970: request.startDate)

        // 按优先级确定主机地址（只包含主机名，不包含端口）
        let host: String = {
            if let remoteHost = request.remoteHost, !remoteHost.isEmpty {
                // 如果 remoteHost 包含端口，提取主机名部分
                return extractHostFromRemoteAddress(remoteHost) ?? remoteHost
            } else if let urlHost = extractHostFromURL(request.URL), !urlHost.isEmpty {
                return urlHost
            } else if let remoteAddr = request.remoteAddress, !remoteAddr.isEmpty {
                return extractCleanIPAddress(remoteAddr)
            } else {
                return "unknown"
            }
        }()

        // 按优先级确定目标端口
        let destinationPort: String = {
            // 1. 从 URL 中提取端口
            if let url = URL(string: request.URL), let port = url.port {
                return String(port)
            }
            // 2. 从 remoteHost 中提取端口（如果 remoteHost 包含端口）
            if let remoteHost = request.remoteHost, let port = extractPortFromRemoteAddress(remoteHost) {
                return port
            }
            // 3. 从 remoteAddress 中提取端口
            if let remoteAddr = request.remoteAddress, let port = extractPortFromRemoteAddress(remoteAddr) {
                return port
            }
            // 4. 使用默认端口（HTTPS 的 443 或 HTTP 的 80）
            return request.URL.hasPrefix("https://") ? "443" : "80"
        }()

        // 创建连接元数据
        let metadata = ConnectionMetadata(
            network: request.method == "CONNECT" ? "TCP" : "TCP", // Surge 主要是 TCP 连接
            type: request.method,
            sourceIP: request.sourceAddress,
            destinationIP: extractCleanIPAddress(request.remoteAddress ?? ""),
            sourcePort: String(request.sourcePort),
            destinationPort: destinationPort,
            host: host,
            dnsMode: "normal",
            processPath: request.processPath,
            specialProxy: nil,
            sourceGeoIP: nil,
            destinationGeoIP: nil,
            sourceIPASN: nil,
            destinationIPASN: nil,
            inboundIP: nil,
            inboundPort: nil,
            inboundName: nil
        )

        // 创建 Clash 连接对象
        return ClashConnection(
            id: String(request.id),
            metadata: metadata,
            upload: Int(request.outBytes),
            download: Int(request.inBytes),
            start: startDate,
            chains: [request.policyName],
            rule: request.rule,
            rulePayload: "",
            downloadSpeed: request.inCurrentSpeed,
            uploadSpeed: request.outCurrentSpeed,
            isAlive: !request.completed && !request.failed
        )
    }

    /// 从远程地址中提取纯 IP 地址（去掉括号中的额外信息）
    private func extractCleanIPAddress(_ remoteAddress: String) -> String {
        // 首先提取主机部分（去掉端口）
        let hostPart = extractHostFromRemoteAddress(remoteAddress) ?? remoteAddress

        // 如果主机部分包含括号（如 "106.126.8.12 (Proxy)"），只保留 IP 地址部分
        if let parenthesisIndex = hostPart.firstIndex(of: "(") {
            let ipPart = hostPart[..<parenthesisIndex].trimmingCharacters(in: .whitespaces)
            return String(ipPart)
        }

        return hostPart
    }

    /// 从远程地址中提取主机部分
    private func extractHostFromRemoteAddress(_ remoteAddress: String) -> String? {
        // remoteAddress 格式可能是 "host:port" 或 "host"
        let components = remoteAddress.components(separatedBy: ":")
        return components.first
    }

    /// 从远程地址中提取端口部分
    private func extractPortFromRemoteAddress(_ remoteAddress: String) -> String? {
        // remoteAddress 格式可能是 "host:port" 或 "host"
        let components = remoteAddress.components(separatedBy: ":")
        return components.count > 1 ? components.last : nil
    }

    /// 从 URL 中提取主机名
    private func extractHostFromURL(_ url: String) -> String? {
        guard let url = URL(string: url) else { return nil }
        return url.host
    }

    /// 停止 Surge 连接监控
    private func stopSurgeConnectionsMonitoring() {
        surgeConnectionsTimer?.invalidate()
        surgeConnectionsTimer = nil
        // 清理上一次连接记录
        previousConnections.removeAll()
        updateConnectionState(.paused)
    }

    /// 暂停 Surge 连接监控
    func pauseSurgeConnectionsMonitoring() {
        surgeConnectionsTimer?.invalidate()
        surgeConnectionsTimer = nil
        updateConnectionState(.paused)
    }

    /// 恢复 Surge 连接监控
    func resumeSurgeConnectionsMonitoring() {
        if isMonitoring && server?.source == .surge {
            startSurgeConnectionsMonitoring()
        }
    }
} 
