import SwiftUI

struct ClientTagView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let viewModel: ConnectionsViewModel
    @ObservedObject var tagViewModel: ClientTagViewModel
    @State private var searchText = ""
    @State private var showingManualAddSheet = false
    @State private var manualIP = ""
    
    // 紧凑筛选
    enum TagFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case saved = "标签"
        case active = "活跃"
        case offline = "离线"
        var id: String { rawValue }
    }
    @State private var selectedFilter: TagFilter = .all
    
    private var uniqueActiveConnections: [ClashConnection] {
        let activeConnections = viewModel.connections.filter { $0.isAlive }
        var uniqueIPs: Set<String> = []
        var uniqueConnections: [ClashConnection] = []
        
        for connection in activeConnections {
            let ip = connection.metadata.sourceIP
            if uniqueIPs.insert(ip).inserted {
                uniqueConnections.append(connection)
            }
        }
        
        // 按IP地址排序
        return uniqueConnections.sorted { $0.metadata.sourceIP < $1.metadata.sourceIP }
    }
    
    private var taggedActiveIPs: Set<String> {
        Set(tagViewModel.tags.map { $0.ip })
    }
    
    private var offlineTaggedConnections: [ClientTag] {
        // 返回已有标签但当前不在活跃连接中的设备
        let activeIPs = Set(uniqueActiveConnections.map { $0.metadata.sourceIP })
        return tagViewModel.tags.filter { !activeIPs.contains($0.ip) }
            .sorted { $0.ip < $1.ip } // 按IP排序
    }
    
    private var filteredTags: [ClientTag] {
        if searchText.isEmpty {
            return tagViewModel.tags.sorted { $0.ip < $1.ip } // 按IP排序
        }
        return tagViewModel.tags.filter { 
            $0.name.localizedCaseInsensitiveContains(searchText) || 
            $0.ip.localizedCaseInsensitiveContains(searchText) 
        }.sorted { $0.ip < $1.ip } // 按IP排序
    }
    
    private var filteredConnections: [ClashConnection] {
        if searchText.isEmpty {
            return uniqueActiveConnections
        }
        return uniqueActiveConnections.filter { 
            $0.metadata.sourceIP.localizedCaseInsensitiveContains(searchText) ||
            ($0.metadata.process ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var filteredOfflineConnections: [ClientTag] {
        if searchText.isEmpty {
            return offlineTaggedConnections
        }
        return offlineTaggedConnections.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.ip.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 筛选器（分段控件）
                Section {
                    Picker("筛选", selection: $selectedFilter) {
                        ForEach(TagFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                
                // 已保存标签
                if (selectedFilter == .all || selectedFilter == .saved), !filteredTags.isEmpty {
                    Section {
                        ForEach(filteredTags) { tag in
                            ClientTagRow(tag: tag) {
                                tagViewModel.editTag(tag)
                            } onDelete: {
                                tagViewModel.removeTag(tag)
                            }
                        }
                    } header: {
                        ClientTagSectionHeader(title: "已保存标签", count: filteredTags.count, systemImage: "tag.fill")
                    }
                }
                
                // 活跃连接
                if (selectedFilter == .all || selectedFilter == .active), !filteredConnections.isEmpty {
                    Section {
                        ForEach(filteredConnections) { connection in
                            ActiveConnectionRow(connection: connection) {
                                tagViewModel.showAddTagSheet(for: connection.metadata.sourceIP)
                            }
                        }
                    } header: {
                        ClientTagSectionHeader(title: "活跃连接", count: filteredConnections.count, systemImage: "network")
                    }
                }
                
                // 离线设备
                if (selectedFilter == .all || selectedFilter == .offline), !filteredOfflineConnections.isEmpty {
                    Section {
                        ForEach(filteredOfflineConnections) { tag in
                            OfflineDeviceRow(tag: tag) {
                                tagViewModel.editTag(tag)
                            }
                        }
                    } header: {
                        ClientTagSectionHeader(title: "离线设备", count: filteredOfflineConnections.count, systemImage: "wifi.slash")
                    }
                }
                
                // 空态
                if filteredTags.isEmpty && filteredConnections.isEmpty && filteredOfflineConnections.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("未找到匹配结果")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("客户端标签")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索标签或IP")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingManualAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $tagViewModel.showingSheet) {
                if let editingTag = tagViewModel.editingTag {
                    TagSheet(tag: editingTag, viewModel: tagViewModel, mode: .edit)
                } else if let ip = tagViewModel.selectedIP {
                    TagSheet(ip: ip, viewModel: tagViewModel, mode: .add)
                }
            }
            .sheet(isPresented: $showingManualAddSheet) {
                manualAddSheet
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索标签或IP", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
    
    private var savedTagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("已保存标签", systemImage: "tag.fill")
                    .font(.headline)
                Spacer()
                Text("\(filteredTags.count)个")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            LazyVStack(spacing: 8) {
                ForEach(filteredTags) { tag in
                    TagCard(tag: tag, viewModel: tagViewModel)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
    }
    
    private var activeConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("活跃连接", systemImage: "network")
                    .font(.headline)
                Spacer()
                Text("\(filteredConnections.count)个")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            LazyVStack(spacing: 8) {
                ForEach(filteredConnections) { connection in
                    ActiveConnectionCard(connection: connection, viewModel: tagViewModel)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
    }
    
    private var offlineConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("离线设备", systemImage: "wifi.slash")
                    .font(.headline)
                Spacer()
                Text("\(filteredOfflineConnections.count)个")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            LazyVStack(spacing: 8) {
                ForEach(filteredOfflineConnections) { tag in
                    OfflineDeviceCard(tag: tag, viewModel: tagViewModel)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
    }
    
    private var addManualTagButton: some View {
        Button {
            showingManualAddSheet = true
        } label: {
            HStack {
                Spacer()
                Label("手动添加标签", systemImage: "plus.circle")
                    .font(.system(.body, design: .rounded).weight(.medium))
                Spacer()
            }
            .padding()
            .background(Color.accentColor.opacity(0.1))
            .foregroundColor(.accentColor)
            .cornerRadius(10)
        }
    }
    
    private var manualAddSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP地址", text: $manualIP)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("手动添加IP地址")
                } footer: {
                    Text("输入任意设备的IP地址以添加标签，无需该设备当前处于连接状态")
                }
            }
            .navigationTitle("添加IP地址")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        manualIP = ""
                        showingManualAddSheet = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("下一步") {
                        if !manualIP.isEmpty {
                            tagViewModel.showAddTagSheet(for: manualIP)
                            manualIP = ""
                            showingManualAddSheet = false
                        }
                    }
                    .disabled(manualIP.isEmpty)
                    .fontWeight(.medium)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("未找到匹配结果")
                .font(.headline)
            Text("尝试使用其他关键词搜索")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}

// 离线设备卡片
struct OfflineDeviceCard: View {
    let tag: ClientTag
    @ObservedObject var viewModel: ClientTagViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            offlineIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .font(.system(.headline, design: .rounded))
                Text(tag.ip)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                viewModel.editTag(tag)
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private var offlineIcon: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.1))
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray)
        }
        .frame(width: 28, height: 28)
    }
}

struct TagCard: View {
    let tag: ClientTag
    @ObservedObject var viewModel: ClientTagViewModel
    @State private var offset: CGFloat = 0
    @State private var showingDeleteAlert = false
    @State private var isSwiped = false
    
    var body: some View {
        ZStack {
            // 背景按钮层
            HStack(spacing: 1) {
                Spacer()
                actionButtons
            }
            
            // 卡片内容
            cardContent
                .offset(x: offset)
                .gesture(swipeGesture)
        }
        .padding(.horizontal)
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("删除", role: .destructive) {
                withAnimation {
                    viewModel.removeTag(tag)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除\"\(tag.name)\"标签吗？")
        }
    }
    
    private var cardContent: some View {
        HStack(spacing: 12) {
            tagIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .font(.system(.headline, design: .rounded))
                Text(tag.ip)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.left")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .opacity(isSwiped ? 0 : 0.5)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
    }
    
    private var tagIcon: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.1))
            Image(systemName: "tag.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentColor)
        }
        .frame(width: 28, height: 28)
    }
    
    private var actionButtons: some View {
        HStack(spacing: 1) {
            Button {
                withAnimation(.spring()) {
                    offset = 0
                    isSwiped = false
                }
                viewModel.editTag(tag)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 50, height: 50)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
            }
            
            Button {
                showingDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 50, height: 50)
                    .background(Color.red)
                    .foregroundColor(.white)
            }
        }
        .cornerRadius(10)
        .opacity(isSwiped ? 1 : 0)
    }
    
    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard value.translation.width < 0 else { return }
                withAnimation(.interactiveSpring()) {
                    offset = max(value.translation.width, -100)
                    isSwiped = offset < -30
                }
            }
            .onEnded { value in
                withAnimation(.spring()) {
                    if value.translation.width < -50 {
                        offset = -100
                        isSwiped = true
                    } else {
                        offset = 0
                        isSwiped = false
                    }
                }
            }
    }
}

struct ActiveConnectionCard: View {
    let connection: ClashConnection
    @ObservedObject var viewModel: ClientTagViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            connectionIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.metadata.sourceIP)
                    .font(.system(.headline, design: .monospaced))
                if let process = connection.metadata.process, !process.isEmpty {
                    Text(process)
                        .font(.system(.subheadline))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                viewModel.showAddTagSheet(for: connection.metadata.sourceIP)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private var connectionIcon: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.1))
            Image(systemName: "network")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.green)
        }
        .frame(width: 28, height: 28)
    }
}

struct TagSheet: View {
    enum Mode {
        case add
        case edit
    }
    
    let mode: Mode
    let ip: String
    @ObservedObject var viewModel: ClientTagViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var tagName: String
    @State private var ipText: String
    @FocusState private var isTextFieldFocused: Bool
    private let editingTagId: UUID?
    
    init(ip: String, viewModel: ClientTagViewModel, mode: Mode) {
        self.ip = ip
        self.viewModel = viewModel
        self.mode = mode
        _tagName = State(initialValue: "")
        _ipText = State(initialValue: ip)
        self.editingTagId = nil
    }
    
    init(tag: ClientTag, viewModel: ClientTagViewModel, mode: Mode) {
        self.ip = tag.ip
        self.viewModel = viewModel
        self.mode = mode
        _tagName = State(initialValue: tag.name)
        _ipText = State(initialValue: tag.ip)
        self.editingTagId = tag.id
    }
    
    private var isSaveDisabled: Bool {
        tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        ipText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        viewModel.isIPInUse(ipText, excludingId: editingTagId)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("标签名称", text: $tagName)
                        .textInputAutocapitalization(.never)
                        .focused($isTextFieldFocused)
                    
                    TextField("IP地址", text: $ipText)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    if viewModel.isIPInUse(ipText, excludingId: editingTagId) {
                        Text("该 IP 已存在于标签中")
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                } header: {
                    Text(mode == .add ? "添加新标签" : "编辑标签")
                } footer: {
                    Text("为设备添加一个易记的标签名称，方便后续识别")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            }
            .navigationTitle(mode == .add ? "新建标签" : "编辑标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消", role: .cancel) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        viewModel.saveTag(name: tagName, ip: ipText)
                        dismiss()
                    }
                    .fontWeight(.medium)
                    .disabled(isSaveDisabled)
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }
}

// 标签数据模型
struct ClientTag: Identifiable, Codable {
    let id: UUID
    var name: String
    var ip: String
    
    init(id: UUID = UUID(), name: String, ip: String) {
        self.id = id
        self.name = name
        self.ip = ip
    }
}

// 标签管理 ViewModel
class ClientTagViewModel: ObservableObject {
    @Published var tags: [ClientTag] = []
    @Published var showingSheet = false
    @Published var selectedIP: String?
    @Published var editingTag: ClientTag?
    
    private let saveKey = "ClientTags"
    
    init() {
        loadTags()
    }
    
    func showAddTagSheet(for ip: String) {
        selectedIP = ip
        editingTag = nil
        showingSheet = true
    }
    
    func editTag(_ tag: ClientTag) {
        editingTag = tag
        selectedIP = nil
        showingSheet = true
    }
    
    func saveTag(name: String, ip: String) {
        if let editingTag = editingTag {
            // 编辑现有标签
            if let index = tags.firstIndex(where: { $0.id == editingTag.id }) {
                tags[index].name = name
                tags[index].ip = ip
            }
        } else {
            // 添加新标签
            if let existingIndex = tags.firstIndex(where: { $0.ip == ip }) {
                tags[existingIndex].name = name
            } else {
                let tag = ClientTag(name: name, ip: ip)
                tags.append(tag)
            }
        }
        saveTags()
        self.editingTag = nil
    }
    
    func removeTag(_ tag: ClientTag) {
        tags.removeAll { $0.id == tag.id }
        saveTags()
    }
    
    func hasTag(for ip: String) -> Bool {
        tags.contains { $0.ip == ip }
    }
    
    // 检查 IP 是否被占用（可排除某个正在编辑的标签）
    func isIPInUse(_ ip: String, excludingId: UUID?) -> Bool {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return tags.contains { tag in
            if let excludingId = excludingId { return tag.id != excludingId && tag.ip == trimmed }
            return tag.ip == trimmed
        }
    }
    
    private func saveTags() {
        if let encoded = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    func loadTags() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([ClientTag].self, from: data) {
            tags = decoded
        }
    }
}

//#pragma mark - 紧凑列表组件

struct ClientTagSectionHeader: View {
    let title: String
    let count: Int
    let systemImage: String
    
    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("\(count)个")
                .foregroundColor(.secondary)
        }
        .font(.subheadline)
    }
}

struct ClientTagRow: View {
    let tag: ClientTag
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.1))
                Image(systemName: "tag.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .font(.body)
                    .lineLimit(1)
                Text(tag.ip)
                    .font(.footnote.monospaced())
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: { Label("删除", systemImage: "trash") }
            Button { onEdit() } label: { Label("编辑", systemImage: "pencil") }
                .tint(.accentColor)
        }
    }
}

struct ActiveConnectionRow: View {
    let connection: ClashConnection
    let onAdd: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.opacity(0.12))
                Image(systemName: "network")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.green)
            }
            .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.metadata.sourceIP)
                    .font(.body.monospaced())
                    .lineLimit(1)
                if let process = connection.metadata.process, !process.isEmpty {
                    Text(process)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { onAdd() } label: { Label("添加", systemImage: "plus") }
                .tint(.blue)
        }
    }
}

struct OfflineDeviceRow: View {
    let tag: ClientTag
    let onEdit: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.gray.opacity(0.12))
                Image(systemName: "wifi.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .font(.body)
                    .lineLimit(1)
                Text(tag.ip)
                    .font(.footnote.monospaced())
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button { onEdit() } label: { Label("编辑", systemImage: "pencil") }
                .tint(.accentColor)
        }
    }
}

#Preview {
    ClientTagView(viewModel: ConnectionsViewModel(), tagViewModel: ClientTagViewModel())
} 
