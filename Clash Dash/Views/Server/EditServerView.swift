import SwiftUI

struct EditServerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ServerViewModel
    let server: ClashServer
    
    @State private var name: String
    @State private var url: String
    @State private var port: String
    @State private var secret: String
    @State private var useSSL: Bool
    @State private var showingHelp = false
    
    // 添加错误处理相关状态
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // OpenWRT 相关状态
    @State private var isOpenWRT: Bool
    @State private var openWRTUrl: String
    @State private var openWRTPort: String
    @State private var openWRTUseSSL: Bool
    @State private var openWRTUsername: String
    @State private var openWRTPassword: String
    @State private var luciPackage: LuCIPackage
    
    // 添加密码显示控制状态
    @State private var isSecretVisible = false
    @State private var isPasswordVisible = false
    
    // 添加焦点状态
    @FocusState private var focusedField: Field?
    
    private enum Field {
        case openWRTUrl
        case other
    }
    
    // 添加触觉反馈生成器
    
    
    private func checkIfHostname(_ urlString: String) -> Bool {
        let ipPattern = "^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$"
        let ipPredicate = NSPredicate(format: "SELF MATCHES %@", ipPattern)
        let trimmedUrl = urlString.trimmingCharacters(in: .whitespaces)
        return !ipPredicate.evaluate(with: trimmedUrl) && !trimmedUrl.isEmpty
    }
    
    init(viewModel: ServerViewModel, server: ClashServer) {
        self.viewModel = viewModel
        self.server = server
        self._name = State(initialValue: server.name)
        self._url = State(initialValue: server.url)
        self._port = State(initialValue: server.port)
        self._secret = State(initialValue: server.secret)
        self._useSSL = State(initialValue: server.clashUseSSL)
        
        // 初始化 OpenWRT 相关状态
        self._isOpenWRT = State(initialValue: server.source == .openWRT)
        self._openWRTUrl = State(initialValue: server.openWRTUrl ?? "")
        self._openWRTPort = State(initialValue: server.openWRTPort ?? "")
        self._openWRTUseSSL = State(initialValue: server.openWRTUseSSL)
        self._openWRTUsername = State(initialValue: server.openWRTUsername ?? "")
        self._openWRTPassword = State(initialValue: server.openWRTPassword ?? "")
        self._luciPackage = State(initialValue: server.luciPackage)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称（可选）", text: $name)
                } header: {
                    Text("基本信息")
                }
                
                Section {
                    TextField("控制器地址", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("控制器端口", text: $port)
                        .keyboardType(.numberPad)
                    
                    HStack(spacing: 8) {
                        if isSecretVisible {
                            TextField("控制器密钥（可选）", text: $secret)
                                .textInputAutocapitalization(.never)
                                .textContentType(.password)
                        } else {
                            SecureField("控制器密钥（可选）", text: $secret)
                                .textInputAutocapitalization(.never)
                                .textContentType(.password)
                        }
                        
                        Button {
                            isSecretVisible.toggle()
                            HapticManager.shared.impact(.light)
                        } label: {
                            Image(systemName: isSecretVisible ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.secondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Toggle(isOn: $useSSL) {
                        Label {
                            Text("使用 HTTPS")
                        } icon: {
                            Image(systemName: "lock.fill")
                                .foregroundColor(useSSL ? .green : .secondary)
                        }
                    }
                } header: {
                    Text("外部控制器信息")
                } footer: {
                    VStack(alignment: .leading) {
                        Text("如果外部控制器启用了 HTTPS，请打开 HTTPS 开关")
                    }
                }
                
                Section {
                    Toggle("添加 OpenWRT 控制", isOn: $isOpenWRT)
                        .onChange(of: isOpenWRT) { newValue in
                            HapticManager.shared.impact(.light)
                        }
                    
                    if isOpenWRT {
                        TextField("OpenWRT地址", text: $openWRTUrl)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .openWRTUrl)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    if focusedField == .openWRTUrl {
                                        Button(url.isEmpty ? "" : "\(url)") {
                                            openWRTUrl = url
                                            HapticManager.shared.impact(.light)
                                        }
                                        .disabled(url.isEmpty)
                                        
                                        Spacer()
                                        
                                        Button("完成") {
                                            focusedField = nil
                                        }
                                    }
                                }
                            }
                        
                        // Toggle("与外部控制器相同地址", isOn: .init(
                        //     get: { openWRTUrl == url },
                        //     set: { if $0 { openWRTUrl = url } }
                        // ))
                        // .onChange(of: url) { newValue in
                        //     if openWRTUrl == url {
                        //         openWRTUrl = newValue
                        //     }
                        // }
                        
                        TextField("网页端口", text: $openWRTPort)
                            .keyboardType(.numberPad)
                        
                        TextField("用户名", text: $openWRTUsername)
                            .textContentType(.username)
                            .autocapitalization(.none)
                        
                        HStack(spacing: 8) {
                            if isPasswordVisible {
                                TextField("密码", text: $openWRTPassword)
                                    .textContentType(.password)
                                    .autocapitalization(.none)
                            } else {
                                SecureField("密码", text: $openWRTPassword)
                                    .textContentType(.password)
                            }
                            
                            Button {
                                isPasswordVisible.toggle()
                                HapticManager.shared.impact(.light)
                            } label: {
                                Image(systemName: isSecretVisible ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                        }

                        Toggle(isOn: $openWRTUseSSL) {
                            Label {
                                Text("使用 HTTPS")
                            } icon: {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(openWRTUseSSL ? .green : .secondary)
                            }
                        }
                        
                        Text("选择你使用的管理器")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        
                        Picker("", selection: $luciPackage) {
                            Text("OpenClash").tag(LuCIPackage.openClash)
                            Text("Nikki/MihomoTProxy").tag(LuCIPackage.mihomoTProxy)
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("高级")
                } footer: {
                    if isOpenWRT {
                        Text("添加 OpenWRT 控制后，可以直接在 App 中所选的管理器中进行订阅管理、切换配置、附加规则、重启服务等操作")
                    }
                }
                
                Section {
                    Button {
                        showingHelp = true
                    } label: {
                        HStack {
                            Image(systemName: "questionmark.circle")
                            Text("使用帮助")
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        viewModel.deleteServer(server)
                        dismiss()
                    } label: {
                        Text("删除控制器")
                    }
                }
            }
            .navigationTitle("编辑控制器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            isLoading = true
                            do {
                                if isOpenWRT {
                                    // 更新 OpenWRT 服务器
                                    let cleanHost = openWRTUrl.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
                                    var updatedServer = server
                                    updatedServer.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    // 更新 OpenWRT 相关信息
                                    updatedServer.openWRTUrl = cleanHost
                                    updatedServer.openWRTUsername = openWRTUsername
                                    updatedServer.openWRTPassword = openWRTPassword
                                    updatedServer.openWRTPort = openWRTPort
                                    updatedServer.openWRTUseSSL = openWRTUseSSL
                                    updatedServer.luciPackage = luciPackage
                                    updatedServer.source = .openWRT
                                    
                                    // 更新外部控制器信息
                                    updatedServer.url = url
                                    updatedServer.port = port
                                    updatedServer.secret = secret
                                    updatedServer.clashUseSSL = useSSL
                                    
                                    // 验证 OpenWRT 服务器
                                    _ = try await viewModel.validateOpenWRTServer(updatedServer, username: openWRTUsername, password: openWRTPassword)
                                    
                                    // 验证成功后更新服务器
                                    viewModel.updateServer(updatedServer)
                                    // 刷新控制器状态
                                    try? await viewModel.refreshServerStatus(for: updatedServer)
                                    await MainActor.run {
                                        dismiss()
                                    }
                                } else {
                                    // 更新普通服务器
                                    var updatedServer = server
                                    updatedServer.name = name
                                    updatedServer.url = url
                                    updatedServer.port = port
                                    updatedServer.secret = secret
                                    updatedServer.clashUseSSL = useSSL
                                    updatedServer.source = .clashController
                                    
                                    // 清除 OpenWRT 相关信息
                                    updatedServer.openWRTUrl = nil
                                    updatedServer.openWRTUsername = nil
                                    updatedServer.openWRTPassword = nil
                                    updatedServer.openWRTPort = nil
                                    updatedServer.openWRTUseSSL = false
                                    
                                    viewModel.updateServer(updatedServer)
                                    // 刷新控制器状态
                                    try? await viewModel.refreshServerStatus(for: updatedServer)
                                    await MainActor.run {
                                        dismiss()
                                    }
                                }
                            } catch {
                                await MainActor.run {
                                    if let networkError = error as? NetworkError {
                                        errorMessage = networkError.localizedDescription
                                    } else {
                                        errorMessage = error.localizedDescription
                                    }
                                    showError = true
                                    isLoading = false
                                }
                            }
                            await MainActor.run {
                                if !showError {
                                    isLoading = false
                                }
                            }
                        }
                    }
                    .disabled(url.isEmpty || port.isEmpty || (isOpenWRT && (openWRTUrl.isEmpty || openWRTPort.isEmpty || openWRTUsername.isEmpty || openWRTPassword.isEmpty)))
                }
            }
            .sheet(isPresented: $showingHelp) {
                AddServerHelpView()
            }
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .disabled(isLoading)
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
        }
    }
} 
