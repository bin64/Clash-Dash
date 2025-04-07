import SwiftUI

struct ConnectivityCard: View {
    @ObservedObject var viewModel: ConnectivityViewModel
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var settingsViewModel: SettingsViewModel
    @State private var server: ClashServer?
    
    init(viewModel: ConnectivityViewModel, settingsViewModel: SettingsViewModel? = nil) {
        self.viewModel = viewModel
        self._settingsViewModel = ObservedObject(wrappedValue: settingsViewModel ?? SettingsViewModel())
    }
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("网站访问检测", systemImage: "globe.asia.australia.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
                
                Spacer()
                
                if viewModel.isUsingProxy {
                    Text("通过代理")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                } else if viewModel.proxyTested {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10))
                        Text("直接连接")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                    .onTapGesture {
                        viewModel.showProxyInfo = true
                    }
                }
                
                // 添加检查端口按钮
                Button(action: {
                    // 从服务器查询实际的HTTP端口
                    if let server = viewModel.clashServer {
                        print("🔍 尝试重新获取HTTP端口...")
                        // 这里假设您有一个方法可以专门获取HTTP端口
                        Task {
                            viewModel.manuallyCheckPort()
                        }
                    }
                }) 
                {
                    Image(systemName: "network")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
                .padding(.leading, 4)
                
                Button(action: {
                    // 重新设置服务器信息并刷新
                   
                    viewModel.testAllConnectivity()
                    HapticManager.shared.impact(.medium)
                }) {
                    HStack(spacing: 4) {
                        if viewModel.isTestingAll {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("全部检测")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(viewModel.isTestingAll)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(viewModel.websites.enumerated()), id: \.element.id) { index, website in
                    ConnectivityItem(
                        website: website,
                        onTap: {
                            viewModel.testConnectivity(for: index)
                            HapticManager.shared.impact(.light)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(cardBackgroundColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .alert("代理配置信息", isPresented: $viewModel.showProxyInfo) {
            Button("确定", role: .cancel) {
                viewModel.showProxyInfo = false
            }
        } message: {
            Text(viewModel.getProxyDiagnostics())
        }
        .onAppear {
            // 直接获取服务器引用
            if let serverFromEnv = viewModel.clashServer {
                server = serverFromEnv
                let httpPort = settingsViewModel.httpPort
                if !httpPort.isEmpty {
                    viewModel.setupWithServer(serverFromEnv, httpPort: httpPort)
                    print("⚙️ ConnectivityCard - 已重新设置服务器: \(serverFromEnv.url) 端口: \(httpPort)")
                }
            }
        }
    }
}

struct ConnectivityItem: View {
    let website: WebsiteStatus
    let onTap: () -> Void
    
    @State private var showError = false
    
    // 添加一个计算属性判断网站是否为未检测状态
    private var isUntested: Bool {
        // 未连接成功且没有错误信息，说明还未检测或者初始状态
        return !website.isConnected && website.error == nil && !website.isChecking
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: website.icon)
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                        
                        Text(website.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        // if website.usedProxy {
                        //     Image(systemName: "arrow.triangle.branch")
                        //         .font(.system(size: 10))
                        //         .foregroundColor(.blue)
                        // }
                    }
                    
                    if showError, let error = website.error {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                
                Spacer()
                
                if website.isChecking {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    // 未检测状态 - 既不是连接成功，也没有错误信息
                    if isUntested {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 18))
                    } else {
                        // 已检测状态 - 成功或失败
                        Image(systemName: website.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(website.isConnected ? .green : .red)
                            .font(.system(size: 18))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                website.isConnected ? Color.green.opacity(0.3) : 
                                (website.error != nil ? Color.red.opacity(0.3) : 
                                 (isUntested ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2))),
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if website.error != nil {
                    withAnimation {
                        showError.toggle()
                    }
                }
                onTap()
            }
            .onChange(of: website.error) { error in
                if error != nil {
                    withAnimation {
                        showError = true
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation {
                            showError = false
                        }
                    }
                } else {
                    withAnimation {
                        showError = false
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    let viewModel = ConnectivityViewModel()
    // 模拟一些测试数据
    viewModel.websites[0].isConnected = true
    viewModel.websites[1].isChecking = true
    viewModel.websites[2].error = "连接超时"
    
    return VStack {
        ConnectivityCard(viewModel: viewModel, settingsViewModel: SettingsViewModel())
    }
    .padding()
    .background(Color(.systemGroupedBackground))
} 
