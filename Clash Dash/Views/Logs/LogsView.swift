import SwiftUI

struct LogsView: View {
    @StateObject private var logManager = LogManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingClearConfirm = false
    
    var filteredLogs: [LogManager.LogEntry] {
        if searchText.isEmpty {
            return logManager.logs.reversed()
        }
        return logManager.logs.filter { $0.message.localizedCaseInsensitiveContains(searchText) }.reversed()
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(filteredLogs) { entry in
                        LogEntryView(entry: entry)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 28)
                .searchable(text: $searchText, prompt: "搜索日志")
                .overlay {
                    if logManager.logs.isEmpty {
                        EmptyStateView(
                            title: "暂无日志",
                            systemImage: "doc.text",
                            description: "运行日志将在此显示"
                        )
                    } else if !logManager.logs.isEmpty && filteredLogs.isEmpty {
                        EmptyStateView(
                            title: "未找到结果",
                            systemImage: "magnifyingglass",
                            description: "尝试其他搜索词"
                        )
                    }
                }
            }
            .navigationTitle("运行日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // ToolbarItem(placement: .cancellationAction) {
                //     Button("关闭") {
                //         dismiss()
                //     }
                // }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            showingClearConfirm = true
                        } label: {
                            Label("清空日志", systemImage: "trash")
                        }
                        
                        Button {
                            shareLog()
                        } label: {
                            Label("导出日志", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("确认清空", isPresented: $showingClearConfirm) {
                Button("取消", role: .cancel) { }
                Button("清空", role: .destructive) {
                    withAnimation {
                        logManager.clearLogs()
                    }
                }
            } message: {
                Text("确定要清空所有日志吗？此操作无法撤销。")
            }
        }
    }
    
    private func shareLog() {
        let logText = logManager.exportLogs()
        let av = UIActivityViewController(
            activityItems: [logText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            av.popoverPresentationController?.sourceView = window
            av.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            av.popoverPresentationController?.permittedArrowDirections = []
            rootViewController.present(av, animated: true)
        }
    }
}

struct LogEntryView: View {
    let entry: LogManager.LogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.levelInfo.0)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(entry.levelInfo.1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(entry.levelInfo.1.opacity(0.12))
                    .clipShape(Capsule())
                
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer(minLength: 0)
            }
            
            Text(entry.message)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.primary)
                .lineSpacing(2)
            
            // 来源信息：文件名:行 函数
            Text("\(entry.fileName.replacingOccurrences(of: ".swift", with: "")):\(entry.line) \(entry.function)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.message
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            
            Button {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let timeString = dateFormatter.string(from: entry.timestamp)
                UIPasteboard.general.string = "[\(timeString)] [\(entry.levelInfo.0)] \(entry.message)"
            } label: {
                Label("复制（含时间和级别）", systemImage: "info.square")
            }
        }
    }
}

#Preview {
    LogsView()
}