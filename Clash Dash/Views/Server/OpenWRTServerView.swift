import SwiftUI

private let logger = LogManager.shared

struct OpenWRTHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6).opacity(0.5)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 版本兼容性提示
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("版本兼容性")
                                .font(.headline)
                        }
                        
                        Text("目前支持 OpenWRT + OpenClash（v0.46.050）的组合，后续会添加更多支持")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    
                    // 依赖安装说明
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "shippingbox.fill")
                                .foregroundColor(.blue)
                            Text("安装依赖")
                                .font(.headline)
                        }
                        
                        Text("使用该方式前，请确认您的 OpenWRT 已安装以下软件包并重启 uhttpd：")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(["opkg update",
                                   "opkg install luci-mod-rpc luci-lib-ipkg luci-compat",
                                   "/etc/init.d/uhttpd restart"], id: \.self) { command in
                                HStack {
                                    Text(command)
                                        .font(.system(.body, design: .monospaced))
                                    
                                    Spacer()
                                }
                                .padding(10)
                                .background(cardBackground)
                                .cornerRadius(8)
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = command
                                    } label: {
                                        Label("复制命令", systemImage: "doc.on.doc")
                                    }
                                }
                                .onTapGesture {
                                    UIPasteboard.general.string = command
                                    // 添加触觉反馈
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.success)
                                }
                            }
                        }
                        
                        Text("注意：如果 OpenWRT 使用 APK 包管理器，请自行更改上面的命令运行")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    
                    // 域名访问说明
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.blue)
                            Text("域名访问设置")
                                .font(.headline)
                        }
                        
                        Text("如果使用域名访问，推荐启用 SSL，并在 OpenClash 的\"插件设置\" - \"外部控制\"中配置以下选项：")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsRow(number: 1, title: "管理页面公网域名", description: "设置为您的域名")
                            SettingsRow(number: 2, title: "管理页面映射端口", description: "通常设置为 443")
                            SettingsRow(number: 3, title: "管理页面公网SSL访问", description: "推荐启用")
                        }
                        
                        Text("请确保 OpenClash 配置的外部访问能够正常访问")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    
                    // 故障排除
                    
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("使用帮助")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// 设置项行视图
private struct SettingsRow: View {
    let number: Int
    let title: String
    let description: String?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 24, height: 24)
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct OpenWRTServerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ServerViewModel
    @State private var showingHelp = false
    
    var server: ClashServer? // 如果是编辑模式，这个值会被设置
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var useSSL: Bool = false
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage: String = ""
    @State private var isPasswordVisible = false  // 添加密码可见性状态
    @State private var luciPackage: LuCIPackage = .openClash // 添加 LuCI 软件包选择状态
    
    private var isEditMode: Bool { server != nil }
    
    init(viewModel: ServerViewModel, server: ClashServer? = nil) {
        self.viewModel = viewModel
        self.server = server
        
        if let server = server {
            _name = State(initialValue: server.name)
            _host = State(initialValue: server.openWRTUrl ?? "")
            _port = State(initialValue: server.openWRTPort ?? "")
            _useSSL = State(initialValue: server.openWRTUseSSL)
            _username = State(initialValue: server.openWRTUsername ?? "")
            _password = State(initialValue: server.openWRTPassword ?? "")
            _luciPackage = State(initialValue: server.luciPackage)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("OpenWRT 信息")) {
                    TextField("名称（可选）", text: $name)
                        .textContentType(.name)
                    
                    TextField("OpenWRT地址（192.168.1.1）", text: $host)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                    
                    TextField("网页端口（80）", text: $port)
                        .keyboardType(.numberPad)
                    
                    Toggle("使用 HTTPS", isOn: $useSSL)
                        .help("是否使用 HTTPS 访问 OpenWRT 管理页面")
                }
                
                Section(header: Text("登录信息")) {
                    TextField("用户名（root）", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                    
                    HStack {
                        if isPasswordVisible {
                            TextField("密码", text: $password)
                                .textContentType(.password)
                        } else {
                            SecureField("密码", text: $password)
                                .textContentType(.password)
                        }
                        
                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Picker("LuCI 软件包", selection: $luciPackage) {
                        Text("OpenClash").tag(LuCIPackage.openClash)
                        Text("Nikki").tag(LuCIPackage.mihomoTProxy)
                    }
                    .pickerStyle(.segmented)
                    
                    Text("请选择已安装的 LuCI 软件包")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isEditMode {
                    Section {
                        Button(role: .destructive) {
                            viewModel.deleteServer(server!)
                            dismiss()
                        } label: {
                            Text("删除控制器")
                        }
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
            }
            .navigationTitle(isEditMode ? "编辑控制器" : "添加 OpenWRT 控制器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditMode ? "保存" : "添加") {
                        print("saveServer")
                        // saveServer()
                    }
                    .disabled(!isValid)
                }
            }
            .disabled(isLoading)
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            .alert("错误", isPresented: $showError) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingHelp) {
                OpenWRTHelpView()
            }
        }
    }
    
    private var isValid: Bool {
        !host.isEmpty && !port.isEmpty &&
        !username.isEmpty && !password.isEmpty
    }
    
    private func isPrivateIP(_ ipString: String) -> Bool {
        // 检查是否是合法的 IP 地址
        guard ipString.matches(of: /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/).first != nil else {
            return false
        }
        
        let components = ipString.split(separator: ".")
        guard components.count == 4,
              let firstByte = UInt8(components[0]),
              let secondByte = UInt8(components[1]) else {
            return false
        }
        
        // 检查是否是内网 IP
        // 10.0.0.0/8
        if firstByte == 10 {
            return true
        }
        
        // 172.16.0.0/12
        if firstByte == 172 && (secondByte >= 16 && secondByte <= 31) {
            return true
        }
        
        // 192.168.0.0/16
        if firstByte == 192 && secondByte == 168 {
            return true
        }
        
        // 127.0.0.0/8 (本地回环)
        if firstByte == 127 {
            return true
        }
        
        return false
    }
    
    // private func saveServer() {
    //     isLoading = true
        
    //     Task {
    //         do {
    //             let cleanHost = host.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
                
    //             var testServer = ClashServer(
    //                 id: server?.id ?? UUID(),
    //                 name: name.trimmingCharacters(in: .whitespacesAndNewlines),
    //                 url: cleanHost,
    //                 port: "",
    //                 secret: "",
    //                 status: .unknown,
    //                 version: nil,
    //                 clashUseSSL: false,
    //                 source: .openWRT
    //             )
                
    //             // 设置 OpenWRT 相关信息
    //             testServer.openWRTUrl = cleanHost
    //             testServer.openWRTUsername = username
    //             testServer.openWRTPassword = password
    //             testServer.openWRTPort = port
    //             testServer.openWRTUseSSL = useSSL
    //             testServer.luciPackage = luciPackage
                
    //             // 验证连接并获取 Clash 信息
    //             let status = try await viewModel.validateOpenWRTServer(testServer, username: username, password: password)
                
    //             // 检查是否是内网 IP
    //             if !isPrivateIP(cleanHost) {
    //                 // 检查是否配置了外部控制
    //                 if let domain = status.dbForwardDomain,
    //                    let port = status.dbForwardPort,
    //                    let ssl = status.dbForwardSsl,
    //                    !domain.isEmpty && !port.isEmpty {
    //                     // 使用外部控制配置
    //                     testServer.url = domain
    //                     testServer.port = port
    //                     testServer.clashUseSSL = ssl == "1"
    //                     logger.log("外部控制器使用公网地址 \(domain) 和端口 \(port) 连接")
    //                 } else {
    //                     throw NetworkError.invalidResponse(message: "未在 OpenClash 中启用公网外部控制，请查看\"使用帮助\"")
    //                 }
    //             } else {
    //                 logger.log("外部控制器使用局域网地址 \(status.daip) 和端口 \(status.cnPort) 连接")
    //                 // 使用本地地址
    //                 testServer.url = status.daip
    //                 testServer.port = status.cnPort
    //             }
                
    //             // 设置密钥
    //             testServer.secret = status.dase ?? ""
                
    //             if isEditMode {
    //                 viewModel.updateServer(testServer)
    //             } else {
    //                 viewModel.addServer(testServer)
    //             }
                
    //             await MainActor.run {
    //                 dismiss()
    //             }
    //         } catch {
    //             await MainActor.run {
    //                 if let networkError = error as? NetworkError {
    //                     errorMessage = networkError.localizedDescription
    //                 } else {
    //                     errorMessage = error.localizedDescription
    //                 }
    //                 showError = true
    //                 isLoading = false
    //             }
    //         }
    //     }
    // }
} 
