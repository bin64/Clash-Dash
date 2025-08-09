import SwiftUI

struct RestartServiceView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ServerViewModel
    let server: ClashServer
    
    @State private var logs: [String] = []
    @State private var isRestarting = false
    @State private var error: Error?
    @State private var showConfirmation = true
    @State private var isRestartSuccessful = false
    
    init(viewModel: ServerViewModel, server: ClashServer) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.server = server
    }
    
    private func logColor(_ log: String) -> Color {
        if log.contains("警告") {
            return .orange
        } else if log.contains("错误") {
            return .red
        }else if log.contains("提示") {
            return .yellow
        } else if log.contains("成功") {
            return .green
        }
        return .secondary
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(logs.reversed(), id: \.self) { log in
                            Text(log)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(logColor(log))
                                .textSelection(.enabled)
                                .padding(.horizontal)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: logs) { _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(logs.first, anchor: .top)
                        }
                    }
                }
            }
            .navigationTitle("重启服务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    if isRestartSuccessful {
                        Label("重启成功", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .alert("确认重启", isPresented: $showConfirmation) {
            Button("取消", role: .cancel) {
                dismiss()
            }
            Button("确认重启", role: .destructive) {
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await restartService(package: server.luciPackage)
                }
            }
        } message: {
            Text("重启服务将导致：\n\n1. 所有当前连接会被中断\n2. 服务在重启期间不可用\n\n是否确认重启？")
        }
        .alert("错误", isPresented: .constant(error != nil)) {
            Button("确定") {
                error = nil
            }
        } message: {
            if let error = error {
                Text(error.localizedDescription)
            }
        }
    }
    
    private func restartService(package: LuCIPackage = .openClash) async {
        isRestarting = true
        isRestartSuccessful = false
        logs.removeAll()
        
        do {
            if package == .openClash {
                // 1. 先发送重启命令
                _ = try await viewModel.restartOpenClash(
                    server,
                    packageName: "openclash",
                    isSubscription: false
                )
                
                // 2. 开始轮询日志
                let scheme = server.openWRTUseSSL ? "https" : "http"
                guard let openWRTUrl = server.openWRTUrl else {
                    throw NetworkError.invalidURL
                }
                let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
                
                guard let username = server.openWRTUsername,
                      let password = server.openWRTPassword else {
                    throw NetworkError.unauthorized(message: "未设置 OpenWRT 用户名或密码")
                }
                
                // 获取认证令牌
                let token = try await viewModel.getAuthToken(server, username: username, password: password)
                
                // 3. 持续获取日志，直到服务完全启动或超时
                var retryCount = 0
                let maxRetries = 300 // 最多尝试300次，每次0.1秒
                
                while retryCount < maxRetries {
                    let random = Int.random(in: 1...1000000000)
                    guard let logURL = URL(string: "\(baseURL)/cgi-bin/luci/admin/services/openclash/startlog?\(random)") else {
                        throw NetworkError.invalidURL
                    }
                    
                    var logRequest = URLRequest(url: logURL)
                    logRequest.setValue("sysauth_http=\(token); sysauth_https=\(token); sysauth=\(token)", forHTTPHeaderField: "Cookie")
                    
                    // 对HTTPS连接始终使用支持自签名证书的会话
                    let session = server.openWRTUseSSL ? URLSession.secure : URLSession.shared
                    let (logData, _) = try await session.data(for: logRequest)
                    let logResponse = try JSONDecoder().decode(StartLogResponse.self, from: logData)
                    
                    if !logResponse.startlog.isEmpty {
                        let newLogs = logResponse.startlog
                            .components(separatedBy: "\n")
                            .filter { !$0.isEmpty }
                        
                        for log in newLogs {
                            if !logs.contains(log) {
                                withAnimation {
                                    logs.append(log)
                                }
                                
                                // 检查重启成功标记
                                if log.contains("第九步") || log.contains("第八步") || log.contains("启动成功") {
                                    // 等待2秒后标记成功
                                    try await Task.sleep(nanoseconds: 2_000_000_000)
                                    isRestartSuccessful = true
                                    isRestarting = false
                                    
                                    // 再等待1秒后关闭sheet
                                    try await Task.sleep(nanoseconds: 1_000_000_000)
                                    await MainActor.run {
                                        dismiss()
                                    }
                                    return
                                }
                            }
                        }
                    }
                    
                    retryCount += 1
                    try await Task.sleep(nanoseconds: 100_000_000) // 等待0.1秒
                }
                
                // 如果超时，添加提示信息
                withAnimation {
                    logs.append("获取日志超时，请自行检查服务状态")
                }
            } else {
                // mihomoTProxy
                // 1. 获取认证令牌
                guard let username = server.openWRTUsername,
                      let password = server.openWRTPassword else {
                    throw NetworkError.unauthorized(message: "未设置 OpenWRT 用户名或密码")
                }
                
                let token = try await viewModel.getAuthToken(server, username: username, password: password)
                
                let isNikki = try await viewModel.isUsingNikki(server, token: token)
                
                let packageName = isNikki ? "nikki" : "mihomo"
                
                // 2. 清理日志
                withAnimation {
                    
                    logs.append("🧹 清理 \(isNikki ? "Nikki" : "Mihomo") 运行日志...")
                }
                let clearLogCmd = "/usr/libexec/\(packageName)-call clear_log app"
                _ = try await makeUCIRequest(server, token: token, method: "sys", params: ["exec", [clearLogCmd]])
                
                // 3. 重启服务
                withAnimation {
                    logs.append("重启 \(isNikki ? "Nikki" : "Mihomo") 服务...")
                }
                let restartCmd = "/etc/init.d/\(packageName) restart"
                _ = try await makeUCIRequest(server, token: token, method: "sys", params: ["exec", [restartCmd]])
                
                // 4. 监控日志
                var seenLogs = Set<String>()
                var retryCount = 0
                let maxRetries = 300 // 最多尝试300次，每次0.1秒
                
                while retryCount < maxRetries {
                    // 获取应用日志
                    let getLogCmd = "cat /var/log/\(packageName)/app.log"
                    let logRequest = try await makeUCIRequest(server, token: token, method: "sys", params: ["exec", [getLogCmd]])
                    
                    if let result = logRequest["result"] as? String {
                        // 将日志按行分割并处理
                        let newLogs = result.components(separatedBy: "\n")
                            .filter { !$0.isEmpty }
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty && !seenLogs.contains($0) }
                        
                        // 处理每一行日志
                        for log in newLogs {
                            seenLogs.insert(log)
                            withAnimation {
                                logs.append(log)
                            }
                            
                            // 每条日志显示后等待 0.2 秒
                            try await Task.sleep(nanoseconds: 200_000_000)
                            
                            // 检查启动成功标记
                            if log.contains("[App] Start Successful") {
                                withAnimation {
                                    logs.append("\(isNikki ? "Nikki" : "Mihomo") 服务已完全启动")
                                }
                                isRestartSuccessful = true
                                isRestarting = false
                                
                                // 等待1秒后关闭sheet
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                                await MainActor.run {
                                    dismiss()
                                }
                                return
                            }
                        }
                    }
                    
                    retryCount += 1
                    try await Task.sleep(nanoseconds: 100_000_000) // 等待0.1秒
                }
                
                // 如果超时，添加提示信息
                withAnimation {
                    logs.append("获取日志超时，请自行检查服务状态")
                }
            }
            
        } catch {
            self.error = error
        }
        
        isRestarting = false
    }
    
    private func makeUCIRequest(_ server: ClashServer, token: String, method: String, params: [Any]) async throws -> [String: Any] {
        let scheme = server.openWRTUseSSL ? "https" : "http"
        guard let openWRTUrl = server.openWRTUrl else {
            throw NetworkError.invalidURL
        }
        let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
        
        guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/\(method)?auth=\(token)") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sysauth=\(token); sysauth_http=\(token); sysauth_https=\(token)", forHTTPHeaderField: "Cookie")
        
        let requestBody: [String: Any] = [
            "id": 1,
            "method": params[0],
            "params": params[1]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // 对HTTPS连接始终使用支持自签名证书的会话
        let session = server.openWRTUseSSL ? URLSession.secure : URLSession.shared
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.invalidResponse(message: "Invalid JSON response")
        }
        
        return jsonResponse
    }
}

