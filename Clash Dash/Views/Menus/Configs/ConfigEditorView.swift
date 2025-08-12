import SwiftUI

struct ConfigEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ServerViewModel
    let server: ClashServer
    let configName: String
    let configFilename: String
    let isEnabled: Bool
    let isSubscription: Bool

    @State private var configContent: String = ""
    @State private var isLoading = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showingSaveAlert = false
    @State private var isSaving = false
    @State private var showingRestartAlert = false
    @State private var isRestarting = false
    @State private var startupLogs: [String] = []
    @State private var validationStatus: ValidationStatus = .unknown
    @State private var validationMessage: String = ""
    
    enum ValidationStatus {
        case unknown, validating, valid, invalid, warning
        
        var color: Color {
            switch self {
            case .unknown, .validating:
                return .secondary
            case .valid:
                return .green
            case .invalid:
                return .red
            case .warning:
                return .orange
            }
        }
        
        var icon: String {
            switch self {
            case .unknown:
                return "questionmark.circle"
            case .validating:
                return "clock.circle"
            case .valid:
                return "checkmark.circle"
            case .invalid:
                return "xmark.circle"
            case .warning:
                return "exclamationmark.triangle"
            }
        }
    }
    
    var onConfigSaved: (() -> Void)?
    
    private func logColor(_ log: String) -> Color {
        if log.contains("警告") {
            return .orange
        } else if log.contains("错误") {
            return .red
        } else if log.contains("成功") {
            return .green
        }
        return .secondary
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    YAMLTextView(
                        text: $configContent,
                        font: .monospacedSystemFont(ofSize: 14, weight: .regular)
                    )
                    .padding(.horizontal, 8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // 点击空白区域收回键盘
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle(configName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        // 验证状态指示器
                        HStack(spacing: 4) {
                            Image(systemName: validationStatus.icon)
                                .foregroundColor(validationStatus.color)
                                .font(.caption)
                            
                            if validationStatus == .validating {
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                        }
                        .onTapGesture {
                            if !validationMessage.isEmpty {
                                errorMessage = validationMessage
                                showError = true
                            }
                        }
                        
                        Button("保存") {
                            if validationStatus == .invalid {
                                errorMessage = "配置文件包含错误，请修正后再保存\n\n\(validationMessage)"
                                showError = true
                            } else {
                                showingSaveAlert = true
                            }
                        }
                        .disabled(isSaving || validationStatus == .validating)
                    }
                }
            }
        }
        .task {
            await loadConfigContent()
        }
        .onChange(of: configContent) { newValue in
            // 内容改变时进行验证，使用防抖动
            Task {
                await validateConfig(newValue)
            }
        }
        .alert("保存配置", isPresented: $showingSaveAlert) {
            Button("取消", role: .cancel) { }
            Button("保存", role: .destructive) {
                Task {
                    await saveConfig()
                }
            }
        } message: {
            Text(isEnabled ? 
                 "保存修改后的配置会重启 Clash 服务，这会导致已有连接中断。是否继续？" : 
                 "确定要保存修改后的配置吗？这将覆盖原有配置文件。")
        }
        .sheet(isPresented: $isRestarting) {
            LogDisplayView(
                logs: startupLogs,
                title: "正在重启 Clash 服务..."
            )
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func loadConfigContent() async {
        do {
            configContent = try await viewModel.fetchConfigContent(
                server,
                configFilename: configFilename,
                packageName: server.luciPackage == .openClash ? "openclash" : "mihomoTProxy",
                isSubscription: isSubscription
            )
            isLoading = false
            // 加载完成后验证配置
            await validateConfig(configContent)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
        }
    }
    
    @MainActor
    private func validateConfig(_ content: String) async {
        // 如果内容为空，设置为未知状态
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationStatus = .unknown
            validationMessage = ""
            return
        }
        
        // 设置验证中状态
        validationStatus = .validating
        validationMessage = ""
        
        // 在后台线程进行验证
        let result = await Task.detached {
            return YAMLValidator.validateClashConfig(content)
        }.value
        
        // 更新验证状态
        if result.isValid {
            if let error = result.error {
                // 有警告信息
                validationStatus = .warning
                validationMessage = error
            } else {
                // 完全有效
                validationStatus = .valid
                validationMessage = "配置文件格式正确"
            }
        } else {
            // 有错误
            validationStatus = .invalid
            validationMessage = result.error ?? "配置文件格式错误"
        }
    }
    
    private func saveConfig() async {
        isSaving = true
        defer { isSaving = false }
        
        do {
            try await viewModel.saveConfigContent(
                server,
                configFilename: configFilename,
                content: configContent,
                packageName: server.luciPackage == .openClash ? "openclash" : "mihomoTProxy",
                isSubscription: isSubscription
            )
            
            if isEnabled {
                isRestarting = true
                startupLogs.removeAll()
                
                do {
                    let logStream = try await viewModel.restartOpenClash(
                        server,
                        packageName: server.luciPackage == .openClash ? "openclash" : "mihomoTProxy",
                        isSubscription: isSubscription
                    )
                    
                    for try await log in logStream {
                        await MainActor.run {
                            startupLogs.append(log)
                        }
                    }
                    
                    await MainActor.run {
                        isRestarting = false
                        onConfigSaved?()
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        isRestarting = false
                        errorMessage = "重启失败: \(error.localizedDescription)"
                        showError = true
                    }
                }
            } else {
                onConfigSaved?()
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
} 
