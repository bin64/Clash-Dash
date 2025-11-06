import SwiftUI
import UIKit

struct DnsCacheView: View {
    let server: ClashServer
    @ObservedObject var monitor: NetworkMonitor
    @Environment(\.dismiss) private var dismiss
    @State private var isFlushing = false
    @State private var errorMessage: String?
    @State private var selectedTab = 0 // 0 for cache, 1 for local
    @State private var searchText = ""
    @Environment(\.colorScheme) private var colorScheme

    private var cardBackgroundColor: Color {
        colorScheme == .dark ?
            Color(.systemGray6).opacity(0.8) :
            Color(.systemBackground).opacity(0.9)
    }

    // 过滤后的 DNS 缓存数据
    private var filteredDnsCache: [SurgeDnsCacheItem] {
        guard let dnsData = monitor.dnsData else { return [] }
        if searchText.isEmpty {
            return dnsData.dnsCache
        }
        return dnsData.dnsCache.filter { item in
            item.domain.localizedCaseInsensitiveContains(searchText) ||
            item.data.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) ||
            item.server.localizedCaseInsensitiveContains(searchText)
        }
    }

    // 过滤后的本地 DNS 配置数据
    private var filteredLocalDns: [SurgeDnsLocalItem] {
        guard let dnsData = monitor.dnsData, let localItems = dnsData.local else { return [] }
        if searchText.isEmpty {
            return localItems
        }
        return localItems.filter { item in
            item.domain.localizedCaseInsensitiveContains(searchText) ||
            (item.data?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (item.server?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (item.source?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                if let error = errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("操作失败")
                            .font(.headline)
                            .padding(.top)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("重试") {
                            errorMessage = nil
                        }
                        .padding()
                    }
                } else if let dnsData = monitor.dnsData {
                    VStack {
                        // Tab selector
                        Picker("DNS 信息", selection: $selectedTab) {
                            Text("DNS 缓存 (\(filteredDnsCache.count))")
                                .tag(0)
                            Text("本地配置 (\(filteredLocalDns.count))")
                                .tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("搜索域名、服务器或数据...", text: $searchText)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            if !searchText.isEmpty {
                                Button(action: {
                                    searchText = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5).opacity(0.3))
                        .cornerRadius(10)
                        .padding(.horizontal)

                        ScrollView {
                            if selectedTab == 0 {
                                // DNS Cache
                                VStack(spacing: 12) {
                                    if filteredDnsCache.isEmpty && !searchText.isEmpty {
                                        Text("未找到匹配的 DNS 缓存条目")
                                            .foregroundColor(.secondary)
                                            .padding()
                                    } else {
                                        ForEach(Array(filteredDnsCache.enumerated()), id: \.offset) { index, item in
                                            DnsCacheItemView(item: item)
                                        }
                                    }
                                }
                                .padding()
                            } else {
                                // Local DNS
                                VStack(spacing: 12) {
                                    if filteredLocalDns.isEmpty {
                                        if searchText.isEmpty {
                                            Text("无本地 DNS 配置")
                                                .foregroundColor(.secondary)
                                                .padding()
                                        } else {
                                            Text("未找到匹配的本地 DNS 配置")
                                                .foregroundColor(.secondary)
                                                .padding()
                                        }
                                    } else {
                                        ForEach(Array(filteredLocalDns.enumerated()), id: \.offset) { index, item in
                                            DnsLocalItemView(item: item)
                                        }
                                    }
                                }
                                .padding()
                            }
                        }
                    }
                }
            }
            .navigationTitle("DNS 缓存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        flushDnsCache()
                    } label: {
                        if isFlushing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("清空缓存")
                                .foregroundColor(.red)
                        }
                    }
                    .disabled(isFlushing)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }


    private func flushDnsCache() {
        isFlushing = true
        errorMessage = nil

        Task {
            do {
                try await performDnsFlush()
                // 触发 NetworkMonitor 重新获取数据
                await MainActor.run {
                    // 清空本地数据，等待 NetworkMonitor 更新
                    self.isFlushing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "清空缓存失败: \(error.localizedDescription)"
                    self.isFlushing = false
                }
            }
        }
    }

    private func performDnsFlush() async throws {
        guard let baseURL = server.baseURL else {
            throw URLError(.badURL)
        }

        let flushURL = baseURL.appendingPathComponent("dns/flush")
        var request = URLRequest(url: flushURL)
        request.httpMethod = "POST"

        if let surgeKey = server.surgeKey, !surgeKey.isEmpty {
            request.setValue(surgeKey, forHTTPHeaderField: "x-key")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
    }
}

struct DnsCacheItemView: View {
    let item: SurgeDnsCacheItem
    @Environment(\.colorScheme) private var colorScheme
    @State private var copiedIP: String? = nil

    private var cardBackgroundColor: Color {
        colorScheme == .dark ?
            Color(.systemGray6).opacity(0.8) :
            Color(.systemBackground).opacity(0.9)
    }

    // 计算相对过期时间
    private var relativeExpiryTime: String {
        let expiryDate = Date(timeIntervalSince1970: item.expiresTime)
        let now = Date()
        let timeInterval = expiryDate.timeIntervalSince(now)

        if timeInterval <= 0 {
            return "已过期"
        }

        let seconds = Int(timeInterval)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        if days > 0 {
            return "\(days)天后过期"
        } else if hours > 0 {
            return "\(hours)小时后过期"
        } else if minutes > 0 {
            return "\(minutes)分钟后过期"
        } else {
            return "\(seconds)秒后过期"
        }
    }

    private var expiryColor: Color {
        let expiryDate = Date(timeIntervalSince1970: item.expiresTime)
        let now = Date()
        let timeInterval = expiryDate.timeIntervalSince(now)

        if timeInterval <= 0 {
            return .red
        } else if timeInterval < 300 { // 5分钟内
            return .orange
        } else {
            return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 头部区域 - 域名和响应时间
            HStack(alignment: .top) {
                Text(item.domain)
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1fms", item.timeCost * 1000))
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5).opacity(0.5))
                    .cornerRadius(4)
                }
            }

            // 服务器信息
            HStack(spacing: 8) {
                Label(item.server, systemImage: "server.rack")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text(relativeExpiryTime)
                    .font(.caption)
                    .foregroundColor(expiryColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(expiryColor.opacity(0.1))
                    .cornerRadius(4)
            }

            Divider()
                .opacity(0.5)

            // 解析结果
            VStack(alignment: .leading, spacing: 6) {
                Label("解析结果", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)

                LazyVGrid(columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ], alignment: .leading, spacing: 4) {
                    ForEach(item.data, id: \.self) { ip in
                        Text(ip)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(copiedIP == ip ? .green : .blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(copiedIP == ip ? Color.green.opacity(0.12) : Color.blue.opacity(0.08))
                            .cornerRadius(6)
                            .onTapGesture {
                                // 复制 IP 地址到剪贴板
                                UIPasteboard.general.string = ip
                                // 设置复制状态
                                copiedIP = ip
                                // 触觉反馈
                                HapticManager.shared.impact(.light)
                                // 2秒后清除状态
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedIP = nil
                                }
                            }
                    }
                }
            }

            // 解析路径
            if !item.path.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("解析路径", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)

                    Text(item.path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(6)
                }
            }

            // 日志信息
            if let logs = item.logs, !logs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("查询日志", systemImage: "doc.text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(logs.prefix(3), id: \.self) { log in
                            Text(log)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray6).opacity(0.2))
                                .cornerRadius(4)
                        }
                        if logs.count > 3 {
                            Text("... 还有 \(logs.count - 3) 条日志")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                                .italic()
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
    }
}

struct DnsLocalItemView: View {
    let item: SurgeDnsLocalItem
    @Environment(\.colorScheme) private var colorScheme

    private var cardBackgroundColor: Color {
        colorScheme == .dark ?
            Color(.systemGray6).opacity(0.8) :
            Color(.systemBackground).opacity(0.9)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 头部区域 - 域名
            VStack(alignment: .leading, spacing: 6) {
                Text(item.domain)
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                if let server = item.server {
                    Label(server, systemImage: "server.rack")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if item.data != nil || item.source != nil || item.comment != nil {
                Divider()
                    .opacity(0.5)
            }

            // 配置信息
            VStack(alignment: .leading, spacing: 8) {
                if let data = item.data {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("配置数据", systemImage: "doc.plaintext")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)

                        Text(data)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(6)
                    }
                }

                if let source = item.source {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("配置来源", systemImage: "folder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)

                        Text(source)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.systemGray6).opacity(0.3))
                            .cornerRadius(6)
                    }
                }

                if let comment = item.comment {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("备注信息", systemImage: "note.text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)

                        Text(comment)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray6).opacity(0.2))
                            .cornerRadius(6)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
    }
}
