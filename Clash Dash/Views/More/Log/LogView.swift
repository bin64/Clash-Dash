import SwiftUI

struct LogView: View {
    let server: ClashServer
    @StateObject private var viewModel = LogViewModel()
    @State private var selectedLevel: LogLevel = .info
    
    var body: some View {
        VStack(spacing: 0) {
            // 日志级别选择器（仅 Clash 控制器显示）
            if server.source != .surge {
                VStack(spacing: 0) {
                    NavigationLink {
                        LogLevelSelectionView(
                            selectedLevel: $selectedLevel,
                            onLevelSelected: { level in
                                viewModel.setLogLevel(level.wsLevel)
                            }
                        )
                    } label: {
                        HStack {
                            Label {
                                Text("日志级别")
                                    .foregroundColor(.primary)
                            } icon: {
                                Image(systemName: "list.bullet.circle.fill")
                                    .foregroundColor(selectedLevel.color)
                            }
                            Spacer()
                            Text(selectedLevel.rawValue)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground))
            }
            
            // 日志列表
            ZStack {
                Color(.systemGroupedBackground)
                    .edgesIgnoringSafeArea(.bottom)
                
                if viewModel.logs.isEmpty && viewModel.isConnected {
                    EmptyStateView(
                        title: "暂无日志",
                        systemImage: "doc.text",
                        description: "正在等待日志..."
                    )
                    .transition(.opacity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.logs.reversed()) { log in
                                LogRow(log: log)
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal)
                        .animation(.easeOut(duration: 0.2), value: viewModel.logs)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .navigationTitle(server.source == .surge ? "系统事件" : "内核日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.toggleConnection(to: server)
                } label: {
                    Image(systemName: viewModel.isUserPaused ? "play.circle.fill" : "pause.circle.fill")
                        .foregroundColor(viewModel.isUserPaused ? .green : .blue)
                        .imageScale(.large)
                }
            }
        }
        .onAppear {
            viewModel.connect(to: server)
        }
        .onDisappear {
            viewModel.disconnect()
        }
    }
}

struct LogRow: View {
    let log: LogMessage
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 日志内容
            Text(log.payload)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            
            // 时间和级别指示器
            HStack(alignment: .center, spacing: 4) {
                Text(log.type.displayText)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(log.type.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(log.type.color.opacity(0.1))
                    .cornerRadius(4)
                
                Text(Self.timeFormatter.string(from: log.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Menu {
                    Button {
                        UIPasteboard.general.string = log.payload
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    
                    Button {
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                        let timeString = dateFormatter.string(from: log.timestamp)
                        UIPasteboard.general.string = "[\(timeString)] [\(log.type.displayText)] \(log.payload)"
                    } label: {
                        Label("复制（含时间）", systemImage: "document.badge.clock")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
        .contextMenu {
            Button {
                UIPasteboard.general.string = log.payload
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            
            Button {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let timeString = dateFormatter.string(from: log.timestamp)
                UIPasteboard.general.string = "[\(timeString)] [\(log.type.displayText)] \(log.payload)"
            } label: {
                Label("复制（含时间）", systemImage: "document.badge.clock")
            }
        }
    }
}

#Preview {
    NavigationView {
        LogView(server: ClashServer(name: "测试服务器", url: "10.1.1.2", port: "9090", secret: "123456"))
    }
} 