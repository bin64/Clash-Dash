import SwiftUI

struct OpenClashRulesView: View {
    let server: ClashServer
    @StateObject private var viewModel = ServerViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var rules: [OpenClashRule] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingAddSheet = false
    @State private var showError = false
    @State private var isUpdating = false
    @State private var isProcessing = false
    @State private var editingRule: OpenClashRule?
    @State private var isCustomRulesEnabled = false
    @State private var showingHelp = false
    @State private var parsingErrors: [String] = []
    @State private var isSortingMode = false
    @State private var versionError: String?
    private let versionService = VersionService()
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: 200)
                } else if let versionError = versionError {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                            .padding(.bottom, 10)
                        
                        Text("插件版本不支持")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text(versionError)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .padding(.top, 40)
                } else {
                    VStack {
                        if !parsingErrors.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("规则解析错误")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                    .padding(.bottom, 4)
                                
                                ForEach(parsingErrors, id: \.self) { error in
                                    Text(error)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .shadow(radius: 2)
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                        
                        if rules.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "text.badge.plus")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .padding(.bottom, 10)
                                
                                Text("没有规则")
                                    .font(.title2)
                                    .fontWeight(.medium)
                                
                                Text("点击添加按钮来添加一个新的规则")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .padding(.top, 40)
                        } else {
                            List {
                                ForEach(rules) { rule in
                                    HStack(spacing: 12) {
                                        // if isSortingMode {
                                        //     Image(systemName: "line.3.horizontal")
                                        //         .foregroundColor(.secondary)
                                        //         .font(.system(size: 14))
                                        // }
                                        
                                        // 左侧：目标
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 6) {
                                                if rule.error != nil {
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                        .foregroundColor(.orange)
                                                        .font(.system(size: 14))
                                                }
                                                
                                                Text(rule.error != nil ? rule.rawContent : rule.target)
                                                    .font(.system(.body, design: .monospaced))
                                                    .foregroundColor(rule.isEnabled ? (rule.error != nil ? .orange : .primary) : .secondary)
                                                    .lineLimit(1)
                                            }
                                            
                                            if let error = rule.error {
                                                Text(error.localizedDescription)
                                                    .font(.caption)
                                                    .foregroundColor(.orange)
                                                    .lineLimit(1)
                                            } else if let comment = rule.comment {
                                                Text(comment)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        // 右侧：类型和动作
                                        if rule.error == nil {
                                            VStack(alignment: .trailing, spacing: 4) {
                                                Text(rule.type)
                                                    .font(.caption)
                                                    .foregroundColor(typeColor(for: rule.type))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(typeColor(for: rule.type).opacity(0.12))
                                                    .cornerRadius(4)
                                                
                                                Text(rule.action)
                                                    .font(.caption)
                                                    .foregroundColor(.orange)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.orange.opacity(0.12))
                                                    .cornerRadius(4)
                                            }
                                        }
                                    }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                                    .opacity(rule.isEnabled ? 1 : 0.6)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if !isSortingMode {
                                            Button(role: .destructive) {
                                                Task {
                                                    await deleteRule(rule, package: server.luciPackage)
                                                }
                                            } label: {
                                                Text("删除")
                                            }
                                            
                                            Button {
                                                editingRule = rule
                                            } label: {
                                                Text("编辑")
                                            }
                                            .tint(.blue)
                                            
                                            if rule.error == nil {
                                                Button {
                                                    Task {
                                                        await toggleRule(rule, package: server.luciPackage)
                                                    }
                                                } label: {
                                                    Text(rule.isEnabled ? "禁用" : "启用")
                                                }
                                                .tint(rule.isEnabled ? .orange : .green)
                                            }
                                        }
                                    }
                                }
                                .onMove { from, to in
                                    rules.move(fromOffsets: from, toOffset: to)
                                    Task {
                                        if server.luciPackage == .openClash {
                                            try? await saveRules(package: server.luciPackage)
                                        } else {
                                            await reorderRules()
                                        }
                                    }
                                }
                            }
                            .listStyle(.insetGrouped)
                            .environment(\.editMode, .constant(isSortingMode ? .active : .inactive))
                            
                            if !isSortingMode {
                                Button {
                                    showingHelp = true
                                } label: {
                                    HStack {
                                        Image(systemName: "info.circle")
                                        Text("查看规则帮助")
                                    }
                                    .font(.system(.body))
                                    .foregroundColor(.blue)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .navigationTitle("附加规则")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            if isSortingMode {
                                Button("完成") {
                                    isSortingMode = false
                                }
                            } else {
                                Button("关闭", action: { dismiss() })
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack(spacing: 16) {
                                if !rules.isEmpty {
                                    Button {
                                        isSortingMode.toggle()
                                    } label: {
                                        Image(systemName: isSortingMode ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                                    }
                                }
                                
                                if !isSortingMode {
                                    Toggle("", isOn: $isCustomRulesEnabled)
                                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                                        .onChange(of: isCustomRulesEnabled) { newValue in
                                            Task {
                                                await toggleCustomRules(enabled: newValue, package: server.luciPackage)
                                            }
                                        }
                                    
                                    Button {
                                        showingAddSheet = true
                                    } label: {
                                        Image(systemName: "plus")
                                    }
                                }
                            }
                        }
                    }
                    .overlay {
                        if isUpdating {
                            ProgressView()
                                .scaleEffect(1.5)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(.systemBackground).opacity(0.8))
                        }
                    }
                }
            }
            .task {
                await loadRules(package: server.luciPackage)
            }
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) { }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                RuleEditView(server: server) { rule in
                    Task {
                        await addRule(rule, package: server.luciPackage)
                    }
                }
            }
            .sheet(item: $editingRule) { rule in
                RuleEditView(title: "编辑规则", rule: rule, server: server) { updatedRule in
                    Task {
                        await updateRule(updatedRule, package: server.luciPackage)
                    }
                }
            }
            .sheet(isPresented: $showingHelp) {
                OpenClashRulesHelpView()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private func loadRules(package: LuCIPackage = .openClash) async {
        isLoading = true
        parsingErrors.removeAll()
        versionError = nil
        defer { isLoading = false }
        
        guard let username = server.openWRTUsername,
              let password = server.openWRTPassword else {
            errorMessage = "未设置 OpenWRT 用户名或密码"
            showError = true
            return
        }
        
        do {
            let token = try await viewModel.getAuthToken(server, username: username, password: password)
            
            let scheme = server.openWRTUseSSL ? "https" : "http"
            guard let openWRTUrl = server.openWRTUrl else {
                throw NetworkError.invalidURL
            }
            let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
            
            // 如果不是 OpenClash，检查版本
            if package != .openClash {
                let versionInfo = try await versionService.getPluginVersion(
                    baseURL: baseURL,
                    token: token,
                    pluginType: .mihomoTProxy
                )
                
                // 检查是否是 Nikki 且版本号大于等于 v1.18.0
                if versionInfo.pluginName != "Nikki" || !isVersionGreaterOrEqual(versionInfo.version, "v1.18.0") {
                    versionError = "使用附加规则需要 Nikki 版本为 v1.18.0 或以上\n当前运行版本: \(versionInfo.version)"
                    return
                }
            }
            
            // 获取自定义规则启用状态
            guard let statusUrl = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
                errorMessage = "无效的服务器地址"
                showError = true
                return
            }
            
            var statusRequest = URLRequest(url: statusUrl)
            statusRequest.httpMethod = "POST"
            statusRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let statusPayload: [String: Any]
            if package == .openClash {
                statusPayload = [
                    "method": "exec",
                    "params": ["uci get openclash.config.enable_custom_clash_rules"]
                ]
            } else {
                statusPayload = [
                    "method": "exec",
                    "params": ["uci get nikki.mixin.rule"]
                ]
            }
            
            statusRequest.httpBody = try JSONSerialization.data(withJSONObject: statusPayload)
            
            let (statusData, _) = try await URLSession.secure.data(for: statusRequest)
            if let statusResponse = try? JSONDecoder().decode(OpenClashRuleResponse.self, from: statusData),
               let statusResult = statusResponse.result {
                let enabled = statusResult.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                await MainActor.run {
                    self.isCustomRulesEnabled = enabled
                }
            }
            
            // 获取规则内容
            guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
                errorMessage = "无效的服务器地址"
                showError = true
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let payload: [String: Any]
            if package == .openClash {
                payload = [
                    "method": "exec",
                    "params": ["cat /etc/openclash/custom/openclash_custom_rules.list"]
                ]
            } else {
                payload = [
                    "method": "exec",
                    "params": ["uci show nikki | grep '@rule'"]
                ]
            }
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, _) = try await URLSession.secure.data(for: request)
            let response = try JSONDecoder().decode(OpenClashRuleResponse.self, from: data)
            
            if let error = response.error {
                errorMessage = "服务器错误: \(error)"
                showError = true
                return
            }
            
            guard let result = response.result else {
                errorMessage = "服务器返回空结果"
                showError = true
                return
            }
            
            // 解析规则
            var parsedRules: [OpenClashRule] = []
            
            if package == .openClash {
                // OpenClash 规则解析逻辑
                var isInRulesSection = false
                var currentSection = ""
                var lineNumber = 0
                
                let lines = result.components(separatedBy: .newlines)
                for line in lines {
                    lineNumber += 1
                    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                    
                    // 检查 section 开始
                    if trimmedLine.hasSuffix(":") {
                        currentSection = trimmedLine.dropLast().trimmingCharacters(in: .whitespaces)
                        isInRulesSection = currentSection == "rules"
                        continue
                    }
                    
                    // 如果在 rules section 中且行以 - 开头（包括被注释的规则）
                    if isInRulesSection && (trimmedLine.hasPrefix("-") || trimmedLine.hasPrefix("##-")) {
                        do {
                            let rule = try OpenClashRule(from: trimmedLine, lineNumber: lineNumber)
                            parsedRules.append(rule)
                        } catch {
                            continue
                        }
                    }
                }
            } else {
                // Nikki 规则解析逻辑
                var ruleMap: [Int: [String: String]] = [:]
                
                let lines = result.components(separatedBy: .newlines)
                for line in lines {
                    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmedLine.isEmpty else { continue }
                    
                    let parts = trimmedLine.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    
                    let key = String(parts[0])
                    var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    if value.hasPrefix("'") && value.hasSuffix("'") {
                        value = String(value.dropFirst().dropLast())
                    }
                    
                    // 从 key 中提取规则索引
                    if let ruleIndexMatch = key.firstMatch(of: /@rule\[(\d+)\]/) {
                        let indexStr = String(ruleIndexMatch.1)
                        if let index = Int(indexStr) {
                            if ruleMap[index] == nil {
                                ruleMap[index] = [:]
                            }
                            
                            // 提取属性名
                            let propertyName = key.components(separatedBy: ".").last ?? ""
                            if !propertyName.contains("[") {
                                ruleMap[index]?[propertyName] = value
                            }
                        }
                    }
                }
                
                // 按索引排序并创建规则
                let sortedIndices = ruleMap.keys.sorted()
                for index in sortedIndices {
                    if let ruleDict = ruleMap[index],
                       let rule = createNikkiRule(from: ruleDict, index: index) {
                        parsedRules.append(rule)
                    }
                }
            }
            
            await MainActor.run {
                self.rules = parsedRules
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func createNikkiRule(from dict: [String: String], index: Int) -> OpenClashRule? {
        guard let type = dict["type"],
              let match = dict["match"],
              let node = dict["node"] else {
            return nil
        }
        
        let enabled = dict["enabled"] == "1"
        let comment = dict["comment"]  // comment 可能为 nil
        
        // 处理 no_resolve
        var action = node
        if dict["no_resolve"] == "1" && (type == "IP-CIDR" || type == "IP-CIDR6") {
            action += ",no-resolve"
        }
        
        let rawContent = "- \(type),\(match),\(action)"
        return OpenClashRule(
            target: match,
            type: type,
            action: action,
            isEnabled: enabled,
            comment: comment,  // 直接传递 nil 或字符串
            lineNumber: index + 1,
            rawContent: rawContent
            
        )
    }
    
    private func generateRulesContent(originalContent: String) -> String {
        var newContent = ""
        var isInRulesSection = false
        var hasFoundRulesSection = false
        var lineNumber = 0
        
        // 分行处理原始内容
        let lines = originalContent.components(separatedBy: .newlines)
        for line in lines {
            lineNumber += 1
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // 检查 section 开始
            if trimmedLine.hasSuffix(":") {
                let sectionName = trimmedLine.dropLast().trimmingCharacters(in: .whitespaces)
                if sectionName == "rules" {
                    isInRulesSection = true
                    hasFoundRulesSection = true
                    newContent += "rules:\n"
                    
                    // 添加新的规则
                    for rule in rules {
                        if rule.error != nil {
                            // 如果是错误的规则，使用原始内容
                            let prefix = rule.isEnabled ? "- " : "##- "
                            let cleanContent = rule.rawContent
                                .replacingOccurrences(of: "##- ", with: "")
                                .replacingOccurrences(of: "- ", with: "")
                            newContent += "\(prefix)\(cleanContent)\n"
                        } else {
                            // 如果是正确的规则，使用格式化内容
                            let prefix = rule.isEnabled ? "- " : "##- "
                            let comment = rule.comment.map { " #\($0)" } ?? ""
                            newContent += "\(prefix)\(rule.type),\(rule.target),\(rule.action)\(comment)\n"
                        }
                    }
                } else {
                    isInRulesSection = false
                    newContent += line + "\n"
                }
                continue
            }
            
            // 如果不在 rules section 中，保持原样
            if !isInRulesSection {
                newContent += line + "\n"
            }
        }
        
        // 如果文件中没有找到 rules section，在末尾添加
        if !hasFoundRulesSection {
            if !newContent.isEmpty && !newContent.hasSuffix("\n\n") {
                newContent += "\n"
            }
            newContent += "rules:\n"
            for rule in rules {
                if rule.error != nil {
                    // 如果是错误的规则，使用原始内容
                    let prefix = rule.isEnabled ? "- " : "##- "
                    let cleanContent = rule.rawContent
                        .replacingOccurrences(of: "##- ", with: "")
                        .replacingOccurrences(of: "- ", with: "")
                    newContent += "\(prefix)\(cleanContent)\n"
                } else {
                    // 如果是正确的规则，使用格式化内容
                    let prefix = rule.isEnabled ? "- " : "##- "
                    let comment = rule.comment.map { " #\($0)" } ?? ""
                    newContent += "\(prefix)\(rule.type),\(rule.target),\(rule.action)\(comment)\n"
                }
            }
        }
        
        return newContent
    }
    
    private func saveRules(package: LuCIPackage = .openClash) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        guard let username = server.openWRTUsername,
              let password = server.openWRTPassword else {
            throw NetworkError.unauthorized(message: "未设置 OpenWRT 用户名或密码")
        }
        
        let scheme = server.openWRTUseSSL ? "https" : "http"
        guard let openWRTUrl = server.openWRTUrl else {
            throw NetworkError.invalidURL
        }
        let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
        
        let token = try await viewModel.getAuthToken(server, username: username, password: password)
        
        guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
            throw NetworkError.invalidURL
        }
        
        // 首先读取当前文件内容
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let filePath: String
        if package == .openClash {
            filePath = "/etc/openclash/custom/openclash_custom_rules.list"
        } else {
            filePath = "/etc/mihomo/mixin.yaml"
        }
        
        let readCommand: [String: Any] = [
            "method": "exec",
            "params": ["cat \(filePath)"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: readCommand)
        let (readData, _) = try await URLSession.secure.data(for: request)
        let readResponse = try JSONDecoder().decode(OpenClashRuleResponse.self, from: readData)
        
        let originalContent = readResponse.result ?? ""
        let newContent = generateRulesContent(originalContent: originalContent)
        
        // 写入新内容
        let escapedContent = newContent.replacingOccurrences(of: "'", with: "'\\''")
        let writeCmd = "echo '\(escapedContent)' > \(filePath) 2>&1 && echo '写入成功' || echo '写入失败'"
        
        let writeCommand: [String: Any] = [
            "method": "exec",
            "params": [writeCmd]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: writeCommand)
        let (writeData, response) = try await URLSession.secure.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        if let writeResponse = try? JSONDecoder().decode(OpenClashRuleResponse.self, from: writeData),
           let writeResult = writeResponse.result {
            if writeResult.contains("写入失败") {
                throw NetworkError.serverError(500)
            }
        }
    }
    
    private func toggleRule(_ rule: OpenClashRule, package: LuCIPackage = .openClash) async {
        guard let username = server.openWRTUsername,
              let password = server.openWRTPassword else {
            errorMessage = "未设置 OpenWRT 用户名或密码"
            showError = true
            return
        }
        
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { 
            return 
        }
        
        let updatedRule = rule.toggled()
        let originalRule = rules[index]
        
        do {
            if package == .openClash {
                rules[index] = updatedRule
                try await saveRules(package: package)
            } else {
                let token = try await viewModel.getAuthToken(server, username: username, password: password)
                let scheme = server.openWRTUseSSL ? "https" : "http"
                guard let openWRTUrl = server.openWRTUrl else {
                    throw NetworkError.invalidURL
                }
                let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
                
                guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
                    throw NetworkError.invalidURL
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                // 使用 UCI 命令切换规则状态
                let toggleCommand = [
                    "uci set nikki.@rule[\(index)].enabled='\(updatedRule.isEnabled ? "1" : "0")'",
                    "uci commit nikki"
                ].joined(separator: " && ")
                
                let payload: [String: Any] = [
                    "method": "exec",
                    "params": [toggleCommand]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                
                let (_, response) = try await URLSession.secure.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    throw NetworkError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
                }
                
                // 更新本地规则状态
                rules[index] = updatedRule
            }
        } catch {
            // 恢复原始状态
            rules[index] = originalRule
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func deleteRule(_ rule: OpenClashRule, package: LuCIPackage = .openClash) async {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { 
            return 
        }
        
        let originalRules = rules
        
        do {
            if package == .openClash {
                rules.remove(at: index)
                try await saveRules(package: package)
            } else {
                guard let username = server.openWRTUsername,
                      let password = server.openWRTPassword else {
                    errorMessage = "未设置 OpenWRT 用户名或密码"
                    showError = true
                    return
                }
                
                let token = try await viewModel.getAuthToken(server, username: username, password: password)
                let scheme = server.openWRTUseSSL ? "https" : "http"
                guard let openWRTUrl = server.openWRTUrl else {
                    throw NetworkError.invalidURL
                }
                let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
                
                guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
                    throw NetworkError.invalidURL
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                // 使用 UCI 命令删除规则
                let deleteCommands = [
                    "uci delete nikki.@rule[\(index)]",
                    "uci commit nikki"
                ].joined(separator: " && ")
                
                let payload: [String: Any] = [
                    "method": "exec",
                    "params": [deleteCommands]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                
                let (_, response) = try await URLSession.secure.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    throw NetworkError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
                }
                
                // 重新加载规则列表
                await loadRules(package: package)
            }
        } catch {
            if package == .openClash {
                rules = originalRules
            }
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func typeColor(for type: String) -> Color {
        switch type {
        // 域名类规则
        case "DOMAIN":
            return .purple        // 纯紫色用于精确域名匹配
        case "DOMAIN-SUFFIX":
            return .indigo       // 靛蓝色用于域名后缀
        case "DOMAIN-KEYWORD":
            return .blue         // 蓝色用于域名关键字
        case "DOMAIN-REGEX":
            return .cyan         // 青色用于域名正则
        case "GEOSITE":
            return .mint         // 薄荷色用于地理域名
            
        // IP类规则
        case "IP-CIDR", "IP-CIDR6":
            return .orange       // 橙色用于IP CIDR
        case "IP-SUFFIX":
            return .yellow       // 黄色用于IP后缀
        case "IP-ASN":
            return .brown        // 棕色用于ASN
        case "GEOIP":
            return .green        // 绿色用于地理IP
            
        // 源IP类规则
        case "SRC-IP-CIDR":
            return .red         // 红色用于源IP CIDR
        case "SRC-IP-SUFFIX":
            return .pink        // 粉色用于源IP后缀
        case "SRC-IP-ASN":
            return .orange      // 橙色用于源IP ASN
        case "SRC-GEOIP":
            return .green       // 绿色用于源地理IP
            
        // 端口类规则
        case "DST-PORT":
            return .teal        // 青色用于目标端口
        case "SRC-PORT":
            return .mint        // 薄荷色用于源端口
            
        // 入站类规则
        case "IN-PORT":
            return .blue        // 蓝色用于入站端口
        case "IN-TYPE":
            return .indigo      // 靛蓝色用于入站类型
        case "IN-USER":
            return .purple      // 紫色用于入站用户
        case "IN-NAME":
            return .cyan        // 青色用于入站名称
            
        // 进程类规则
        case "PROCESS-PATH":
            return .brown       // 棕色用于进程路径
        case "PROCESS-PATH-REGEX":
            return .orange      // 橙色用于进程路径正则
        case "PROCESS-NAME":
            return .green       // 绿色用于进程名称
        case "PROCESS-NAME-REGEX":
            return .teal        // 青色用于进程名称正则
        case "UID":
            return .blue        // 蓝色用于用户ID
            
        // 网络类规则
        case "NETWORK":
            return .purple      // 紫色用于网络类型
        case "DSCP":
            return .indigo      // 靛蓝色用于DSCP
            
        // 规则集和逻辑规则
        case "RULE-SET":
            return .orange      // 橙色用于规则集
        case "AND":
            return .blue        // 蓝色用于逻辑与
        case "OR":
            return .green       // 绿色用于逻辑或
        case "NOT":
            return .red         // 红色用于逻辑非
        case "SUB-RULE":
            return .purple      // 紫色用于子规则
            
        default:
            return .secondary   // 默认颜色用于未知类型
        }
    }
    
    private func isVersionGreaterOrEqual(_ version: String, _ minVersion: String) -> Bool {
        let cleanVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "")
        let cleanMinVersion = minVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "")
        
        let versionComponents = cleanVersion.split(separator: ".")
        let minVersionComponents = cleanMinVersion.split(separator: ".")
        
        let maxLength = max(versionComponents.count, minVersionComponents.count)
        
        for i in 0..<maxLength {
            let v1 = i < versionComponents.count ? Int(versionComponents[i]) ?? 0 : 0
            let v2 = i < minVersionComponents.count ? Int(minVersionComponents[i]) ?? 0 : 0
            
            if v1 > v2 {
                return true
            } else if v1 < v2 {
                return false
            }
        }
        
        return true
    }
    
    private func addRule(_ rule: OpenClashRule, package: LuCIPackage = .openClash) async {
        guard let username = server.openWRTUsername,
              let password = server.openWRTPassword else {
            errorMessage = "未设置 OpenWRT 用户名或密码"
            showError = true
            return
        }
        
        do {
            let token = try await viewModel.getAuthToken(server, username: username, password: password)
            let scheme = server.openWRTUseSSL ? "https" : "http"
            guard let openWRTUrl = server.openWRTUrl else {
                throw NetworkError.invalidURL
            }
            let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
            
            guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
                throw NetworkError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            if package == .openClash {
                rules.insert(rule, at: 0)
                try await saveRules(package: package)
            } else {
                // 获取当前规则数量
                let countPayload: [String: Any] = [
                    "method": "exec",
                    "params": ["uci show nikki | grep -c '@rule\\[.*\\]=rule'"]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: countPayload)
                let (countData, _) = try await URLSession.secure.data(for: request)
                let countResponse = try JSONDecoder().decode(OpenClashRuleResponse.self, from: countData)
                guard let countStr = countResponse.result?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let count = Int(countStr) else {
                    throw NetworkError.invalidResponse(message: "无法获取规则数量")
                }
                
                // 使用 UCI 命令添加新规则
                let addCommands = [
                    "uci add nikki rule",
                    "uci set nikki.@rule[\(count)].type='\(rule.type)'",
                    "uci set nikki.@rule[\(count)].match='\(rule.target)'",
                    "uci set nikki.@rule[\(count)].node='\(rule.action.replacingOccurrences(of: ",no-resolve", with: ""))'",
                    "uci set nikki.@rule[\(count)].enabled='1'",
                    rule.comment.map { "uci set nikki.@rule[\(count)].comment='\($0)'" },
                    (rule.type == "IP-CIDR" || rule.type == "IP-CIDR6") && rule.action.hasSuffix(",no-resolve") ? "uci set nikki.@rule[\(count)].no_resolve='1'" : nil,
                    "uci commit nikki"
                ].compactMap { $0 }.joined(separator: " && ")
                
                let payload: [String: Any] = [
                    "method": "exec",
                    "params": [addCommands]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                
                let (_, response) = try await URLSession.secure.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    throw NetworkError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
                }
                
                // 重新加载规则列表
                await loadRules(package: package)
            }
        } catch {
            if package == .openClash {
                rules.removeFirst()
            }
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func updateRule(_ rule: OpenClashRule, package: LuCIPackage = .openClash) async {
        guard let username = server.openWRTUsername,
              let password = server.openWRTPassword else {
            errorMessage = "未设置 OpenWRT 用户名或密码"
            showError = true
            return
        }
        
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { 
            return 
        }
        let originalRule = rules[index]
        
        do {
            if package == .openClash {
                rules[index] = rule
                try await saveRules(package: package)
            } else {
                let token = try await viewModel.getAuthToken(server, username: username, password: password)
                let scheme = server.openWRTUseSSL ? "https" : "http"
                guard let openWRTUrl = server.openWRTUrl else {
                    throw NetworkError.invalidURL
                }
                let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
                
                guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
                    throw NetworkError.invalidURL
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                // 检查 no-resolve 的变化
                let originalHasNoResolve = originalRule.action.hasSuffix(",no-resolve")
                let newHasNoResolve = rule.action.hasSuffix(",no-resolve")
                let isNoResolveTypeRule = rule.type == "IP-CIDR" || rule.type == "IP-CIDR6"
                
                // 构建命令数组
                var commands = [
                    "uci set nikki.@rule[\(index)].type='\(rule.type)'",
                    "uci set nikki.@rule[\(index)].match='\(rule.target)'",
                    "uci set nikki.@rule[\(index)].node='\(rule.action.replacingOccurrences(of: ",no-resolve", with: ""))'",
                    "uci set nikki.@rule[\(index)].enabled='\(rule.isEnabled ? "1" : "0")'"
                ]
                
                // 处理 no-resolve
                if isNoResolveTypeRule {
                    if newHasNoResolve {
                        commands.append("uci set nikki.@rule[\(index)].no_resolve='1'")
                    } else if originalHasNoResolve {
                        commands.append("uci delete nikki.@rule[\(index)].no_resolve")
                    }
                }
                
                // 处理 comment
                if let newComment = rule.comment {
                    if originalRule.comment != newComment {
                        commands.append("uci set nikki.@rule[\(index)].comment='\(newComment)'")
                    }
                } else if originalRule.comment != nil {
                    commands.append("uci delete nikki.@rule[\(index)].comment")
                }
                
                // 添加提交命令
                commands.append("uci commit nikki")
                
                let updateCommands = commands.joined(separator: " && ")
                
                let payload: [String: Any] = [
                    "method": "exec",
                    "params": [updateCommands]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                
                let (_, response) = try await URLSession.secure.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    throw NetworkError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
                }
                
                // 重新加载规则列表
                await loadRules(package: package)
            }
        } catch {
            if package == .openClash {
                rules[index] = originalRule
            }
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func toggleCustomRules(enabled: Bool, package: LuCIPackage = .openClash) async {
        isProcessing = true
        defer { isProcessing = false }
        
        guard let username = server.openWRTUsername,
              let password = server.openWRTPassword else {
            errorMessage = "未设置 OpenWRT 用户名或密码"
            showError = true
            return
        }
        
        do {
            let token = try await viewModel.getAuthToken(server, username: username, password: password)
            let scheme = server.openWRTUseSSL ? "https" : "http"
            guard let openWRTUrl = server.openWRTUrl else {
                throw NetworkError.invalidURL
            }
            let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
            
            guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
                throw NetworkError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // 设置启用状态
            let setCmd: String
            let payload: [String: Any]
            if package == .openClash {  
                setCmd = "uci set openclash.config.enable_custom_clash_rules='\(enabled ? "1" : "0")' && uci commit openclash"
            } else {
                setCmd = "uci set nikki.mixin.rule='\(enabled ? "1" : "0")' && uci commit nikki"
            }
            
            payload = [
                "method": "exec",
                "params": [setCmd]
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (_, response) = try await URLSession.secure.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw NetworkError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            // 恢复UI状态
            await MainActor.run {
                self.isCustomRulesEnabled = !enabled
            }
        }
    }
    
    private func reorderRules() async {
        guard let username = server.openWRTUsername,
              let password = server.openWRTPassword else {
            errorMessage = "未设置 OpenWRT 用户名或密码"
            showError = true
            return
        }
        
        do {
            let token = try await viewModel.getAuthToken(server, username: username, password: password)
            let scheme = server.openWRTUseSSL ? "https" : "http"
            guard let openWRTUrl = server.openWRTUrl else {
                throw NetworkError.invalidURL
            }
            let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
            
            guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
                throw NetworkError.invalidURL
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // 1. 获取当前规则数量
            let countPayload: [String: Any] = [
                "method": "exec",
                "params": ["uci show nikki | grep -c '@rule\\[.*\\]=rule'"]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: countPayload)
            let (countData, _) = try await URLSession.secure.data(for: request)
            let countResponse = try JSONDecoder().decode(OpenClashRuleResponse.self, from: countData)
            guard let countStr = countResponse.result?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let count = Int(countStr) else {
                throw NetworkError.invalidResponse(message: "无法获取规则数量")
            }
            
            // 2. 构建重排序命令
            var commands: [String] = []
            
            // 先删除所有规则
            for _ in 0..<count {
                commands.append("uci delete nikki.@rule[\(0)]")
            }
            
            // 按新顺序添加规则
            for (index, rule) in rules.enumerated() {
                commands.append("uci add nikki rule")
                commands.append("uci set nikki.@rule[\(index)].type='\(rule.type)'")
                commands.append("uci set nikki.@rule[\(index)].match='\(rule.target)'")
                commands.append("uci set nikki.@rule[\(index)].node='\(rule.action.replacingOccurrences(of: ",no-resolve", with: ""))'")
                commands.append("uci set nikki.@rule[\(index)].enabled='\(rule.isEnabled ? "1" : "0")'")
                
                if let comment = rule.comment {
                    commands.append("uci set nikki.@rule[\(index)].comment='\(comment)'")
                }
                
                if (rule.type == "IP-CIDR" || rule.type == "IP-CIDR6") && rule.action.hasSuffix(",no-resolve") {
                    commands.append("uci set nikki.@rule[\(index)].no_resolve='1'")
                }
            }
            
            // 提交更改
            commands.append("uci commit nikki")
            
            let reorderCommand = commands.joined(separator: " && ")
            
            let payload: [String: Any] = [
                "method": "exec",
                "params": [reorderCommand]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (_, response) = try await URLSession.secure.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw NetworkError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            // 重新加载规则列表
            await loadRules(package: .mihomoTProxy)
        }
    }
}

struct OpenClashRuleResponse: Codable {
    let result: String?
    let error: String?
}

struct OpenWRTAuthResponse: Codable {
    let id: Int?
    let result: String?
    let error: String?
}

struct RuleRowView: View {
    let rule: OpenClashRule
    let onToggle: () async -> Void
    let onEdit: () -> Void
    let onDelete: () async -> Void
    
    private var typeColor: Color {
        switch rule.type {
        case "DOMAIN":
            return .purple        // 纯紫色用于精确域名匹配
        case "DOMAIN-SUFFIX":
            return .indigo       // 靛蓝色用于域名后缀
        case "DOMAIN-KEYWORD":
            return .blue         // 蓝色用于域名关键字
        case "PROCESS-NAME":
            return .green        // 绿色用于进程名
        case "IP-CIDR":
            return .orange       // 橙色用于目标IP
        case "SRC-IP-CIDR":
            return .cyan          // XX用于源IP
        case "DST-PORT":
            return .teal         // 青色用于目标端口
        case "SRC-PORT":
            return .mint         // 薄荷色用于源端口
        default:
            return .secondary
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 左侧：目标
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.target)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(rule.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                
                if let comment = rule.comment {
                    Text(comment)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 右侧：类型和动作
            VStack(alignment: .trailing, spacing: 4) {
                Text(rule.type)
                    .font(.caption)
                    .foregroundColor(typeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.12))
                    .cornerRadius(4)
                
                Text(rule.action)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(rule.isEnabled ? 1 : 0.6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task {
                    await onDelete()
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
            
            Button {
                onEdit()
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.blue)
            
            Button {
                Task {
                    await onToggle()
                }
            } label: {
                Label(rule.isEnabled ? "禁用" : "启用", 
                      systemImage: rule.isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
            }
            .tint(rule.isEnabled ? .green : .orange)
        }
    }
}
