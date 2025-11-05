import SwiftUI

struct AddServerHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6).opacity(0.5)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 基本说明
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("基本说明")
                                .font(.headline)
                        }
                        
                        Text("添加的是外部控制器的连接信息，地址一般为运行代理服务应用的设备的地址。")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)


                    // OpenWrt 插件安装
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .foregroundColor(.orange)
                            Text("OpenWrt 插件安装")
                                .font(.headline)
                        }
                        
                        Text("如果添加 OpenWrt 控制时提示 404 没有安装对应的插件，请先登录 OpenWrt 或登录终端查找并安装对应的插件：")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("luci-mod-rpc luci-lib-ipkg luci-compat")
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(cardBackground)
                            .cornerRadius(8)
                            .contextMenu {
                                Button(action: {
                                    UIPasteboard.general.string = "luci-mod-rpc luci-lib-ipkg luci-compat"
                                    HapticManager.shared.notification(.success)
                                }) {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                            }
                        
                        Text("并重启 uhttpd")
                            .foregroundColor(.secondary)
                        
                        Text("如果您使用的是 opkg 包管理器，可登录 OpenWrt 终端后运行下列命令进行安装：")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("opkg update")
                                .font(.system(.body, design: .monospaced))
                                .padding(.vertical, 4)
                                .contextMenu {
                                    Button(action: {
                                        UIPasteboard.general.string = "opkg update"
                                        HapticManager.shared.notification(.success)
                                    }) {
                                        Label("复制", systemImage: "doc.on.doc")
                                    }
                                }
                            
                            Text("opkg install luci-mod-rpc luci-lib-ipkg luci-compat")
                                .font(.system(.body, design: .monospaced))
                                .padding(.vertical, 4)
                                .contextMenu {
                                    Button(action: {
                                        UIPasteboard.general.string = "opkg install luci-mod-rpc luci-lib-ipkg luci-compat"
                                        HapticManager.shared.notification(.success)
                                    }) {
                                        Label("复制", systemImage: "doc.on.doc")
                                    }
                                }
                            
                            Text("/etc/init.d/uhttpd restart")
                                .font(.system(.body, design: .monospaced))
                                .padding(.vertical, 4)
                                .contextMenu {
                                    Button(action: {
                                        UIPasteboard.general.string = "/etc/init.d/uhttpd restart"
                                        HapticManager.shared.notification(.success)
                                    }) {
                                        Label("复制", systemImage: "doc.on.doc")
                                    }
                                }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBackground)
                        .cornerRadius(8)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    
                    // MihomoTProxy 说明
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundColor(.blue)
                            Text("Nikki")
                                .font(.headline)
                        }
                        
                        Text("如果使用的是 Nikki（原 MihomoTProxy），外部控制器的端口和密钥信息可以在以下位置查看：")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("Nikki → 混入配置 → 外部控制配置")
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(cardBackground)
                            .cornerRadius(8)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    
                    // OpenClash 说明
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundColor(.blue)
                            Text("OpenClash")
                                .font(.headline)
                        }
                        
                        Text("如果使用的是 OpenClash，外部控制器的信息显示在 OpenClash 运行状态页面：")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("• 控制面板登录 IP")
                            Text("• 控制面板登录端口")
                            Text("• 控制面板登录密钥（如果未设置则可以留空）")
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBackground)
                        .cornerRadius(8)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    
                    // Sing-Box 说明
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundColor(.blue)
                            Text("Sing-Box")
                                .font(.headline)
                        }
                        
                        Text("如果使用的是 Sing-Box，外部控制的信息在所使用的配置文件中可以找到（external-controller）")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    
                    // 故障排除
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("故障排除")
                                .font(.headline)
                        }
                        
                        Text("如果添加失败，请检查以下内容：")
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("1. 确认地址和端口是否正确")
                            Text("2. 检查设备是否在同一网络")
                            Text("3. 查看运行日志以获取详细错误信息")
                            Text("4. 如果使用域名访问，确保已启用 HTTPS")
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardBackground)
                        .cornerRadius(8)
                    }
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    
                    
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

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ServerViewModel
    
    @State private var name = ""
    @State private var url = ""
    @State private var port = ""
    @State private var secret = ""
    @State private var useSSL = false
    @State private var showingHelp = false
    
    // 添加错误处理相关状态
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    // Surge device name 相关状态
    @State private var showDeviceNameDialog = false
    @State private var detectedDeviceName = ""
    @State private var detectedSurgeVersion: String? = nil
    @State private var detectedSurgeBuild: String? = nil
    
    // OpenWRT 相关状态
    @State private var isOpenWRT = false
    @State private var openWRTUrl = ""
    @State private var openWRTPort = ""
    @State private var openWRTUseSSL = false
    @State private var openWRTUsername = ""
    @State private var openWRTPassword = ""
    @State private var luciPackage: LuCIPackage = .openClash

    // Surge 相关状态
    @State private var isSurge = false
    
    // 添加密码显示控制状态
    @State private var isSecretVisible = false
    @State private var isPasswordVisible = false
    
    // 添加焦点状态
    @FocusState private var focusedField: Field?
    
    private enum Field {
        case openWRTUrl
        case other
    }
    
    private func checkIfHostname(_ urlString: String) -> Bool {
        let ipPattern = "^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$"
        let ipPredicate = NSPredicate(format: "SELF MATCHES %@", ipPattern)
        let trimmedUrl = urlString.trimmingCharacters(in: .whitespaces)
        return !ipPredicate.evaluate(with: trimmedUrl) && !trimmedUrl.isEmpty
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
                    TextField(isSurge ? "Surge 地址" : "控制器地址", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField(isSurge ? "Surge 端口" : "控制器端口", text: $port)
                        .keyboardType(.numberPad)
                    HStack(spacing: 8) {
                        if isSecretVisible {
                            TextField(isSurge ? "Surge API Key" : "控制器密钥（可选）", text: $secret)
                                .textInputAutocapitalization(.never)
                                .textContentType(.password)
                        } else {
                            SecureField(isSurge ? "Surge API Key" : "控制器密钥（可选）", text: $secret)
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
                            Text(isSurge ? "Surge 使用 HTTPS" : "使用 HTTPS")
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
                            if newValue {
                                isSurge = false
                            }
                        }

                    Toggle("添加 Surge 控制", isOn: $isSurge)
                        .onChange(of: isSurge) { newValue in
                            HapticManager.shared.impact(.light)
                            if newValue {
                                isOpenWRT = false
                            }
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
                                Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
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
                    if isSurge {
                        Text("添加 Surge 控制后，可以直接在 App 中对 Surge 进行连接监控、策略管理等操作")
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
            .navigationTitle("添加控制器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        Task {
                            isLoading = true
                            do {
                                if isOpenWRT {
                                    // 创建 OpenWRT 服务器
                                    let cleanHost = openWRTUrl.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
                                    var server = ClashServer(
                                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                        url: cleanHost,
                                        port: "",
                                        secret: "",
                                        status: .unknown,
                                        version: nil,
                                        clashUseSSL: false,
                                        source: .openWRT
                                    )
                                    
                                    // 设置 OpenWRT 相关信息
                                    server.openWRTUrl = cleanHost
                                    server.openWRTUsername = openWRTUsername
                                    server.openWRTPassword = openWRTPassword
                                    server.openWRTPort = openWRTPort
                                    server.openWRTUseSSL = openWRTUseSSL
                                    server.luciPackage = luciPackage
                                    
                                    // 设置外部控制器信息
                                    server.url = url
                                    server.port = port
                                    server.secret = secret
                                    server.clashUseSSL = useSSL
                                    
                                    // 验证 OpenWRT 服务器
                                    _ = try await viewModel.validateOpenWRTServer(server, username: openWRTUsername, password: openWRTPassword)
                                    
                                    // 验证成功后添加服务器
                                    viewModel.addServer(server)
                                    await MainActor.run {
                                        dismiss()
                                    }
                                } else if isSurge {
                                    // 创建 Surge 服务器
                                    let cleanHost = url.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
                                    var server = ClashServer(
                                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                        url: cleanHost,
                                        port: port,
                                        secret: "",
                                        status: .unknown,
                                        version: nil,
                                        clashUseSSL: false,
                                        source: .surge
                                    )

                                    // 设置 Surge 相关信息 (直接使用上面的字段)
                                    server.surgeKey = secret  // API key 来自 secret 字段
                                    server.surgeUseSSL = useSSL  // HTTPS 设置来自 useSSL 字段

                                    // 验证 Surge 服务器
                                    let (success, deviceName, surgeVersion, surgeBuild) = try await viewModel.validateSurgeServer(server)
                                    if !success {
                                        throw NetworkError.invalidResponse(message: "Surge 服务器验证失败")
                                    }

                                    // 更新服务器的版本信息
                                    server.surgeVersion = surgeVersion
                                    server.surgeBuild = surgeBuild

                                    // 检查是否有设备名称，如果有且与当前名称不同，就询问用户是否使用
                                    if let deviceName = deviceName, !deviceName.isEmpty, deviceName != name.trimmingCharacters(in: .whitespacesAndNewlines) {
                                        await MainActor.run {
                                            isLoading = false // 停止加载状态，允许用户与 Alert 交互
                                            detectedDeviceName = deviceName
                                            detectedSurgeVersion = surgeVersion
                                            detectedSurgeBuild = surgeBuild
                                            showDeviceNameDialog = true
                                        }
                                        return // 等待用户确认后再添加服务器
                                    }

                                    // 验证成功后添加服务器
                                    viewModel.addServer(server)
                                    await MainActor.run {
                                        dismiss()
                                    }
                                } else {
                                    // 创建普通服务器
                                    let server = ClashServer(
                                        name: name,
                                        url: url,
                                        port: port,
                                        secret: secret,
                                        clashUseSSL: useSSL
                                    )
                                    viewModel.addServer(server)
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
                    .disabled(url.isEmpty || port.isEmpty || (isOpenWRT && (openWRTUrl.isEmpty || openWRTPort.isEmpty || openWRTUsername.isEmpty || openWRTPassword.isEmpty)) || (isSurge && secret.isEmpty))
                }
            }
            .sheet(isPresented: $showingHelp) {
                AddServerHelpView()
            }
            .alert("检测到设备名称", isPresented: $showDeviceNameDialog) {
                Button("使用") {
                    isLoading = true // 开始处理
                    name = detectedDeviceName
                    // 继续添加服务器（使用新的名称）
                    Task {
                        do {
                            let cleanHost = url.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
                            var server = ClashServer(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                url: cleanHost,
                                port: port,
                                secret: "",
                                status: .unknown,
                                version: nil,
                                clashUseSSL: false,
                                source: .surge
                            )

                            server.surgeKey = secret
                            server.surgeUseSSL = useSSL
                            server.surgeVersion = detectedSurgeVersion
                            server.surgeBuild = detectedSurgeBuild

                            viewModel.addServer(server)
                            await MainActor.run {
                                dismiss()
                            }
                        }
                    }
                }
                Button("保持当前") {
                    isLoading = true // 开始处理
                    // 继续添加服务器（使用原有名称）
                    Task {
                        do {
                            let cleanHost = url.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
                            var server = ClashServer(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                url: cleanHost,
                                port: port,
                                secret: "",
                                status: .unknown,
                                version: nil,
                                clashUseSSL: false,
                                source: .surge
                            )

                            server.surgeKey = secret
                            server.surgeUseSSL = useSSL
                            server.surgeVersion = detectedSurgeVersion
                            server.surgeBuild = detectedSurgeBuild

                            viewModel.addServer(server)
                            await MainActor.run {
                                dismiss()
                            }
                        }
                    }
                }
            } message: {
                Text("检测到 Surge 设备名称：\"\(detectedDeviceName)\"\n\n是否将其用作控制器名称？")
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
