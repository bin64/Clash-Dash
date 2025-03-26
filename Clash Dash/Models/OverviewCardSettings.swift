import Foundation
import SwiftUI

enum OverviewCard: String, CaseIterable, Identifiable, Codable {
    case speed = "speed"
    case totalTraffic = "totalTraffic"
    case status = "status"
    case speedChart = "speedChart"
    case memoryChart = "memoryChart"
    case modeSwitch = "modeSwitch"
    case subscription = "subscription"
    case connectivity = "connectivity"
    
    var id: String { self.rawValue }
    
    var description: String {
        switch self {
        case .speed: return "实时速度"
        case .totalTraffic: return "总流量"
        case .status: return "状态信息"
        case .speedChart: return "速率图表"
        case .memoryChart: return "内存图表"
        case .modeSwitch: return "代理模式切换"
        case .subscription: return "订阅信息"
        case .connectivity: return "连通性检测"
        }
    }
    
    var icon: String {
        switch self {
        case .speed: return "speedometer"
        case .totalTraffic: return "arrow.up.arrow.down.circle"
        case .status: return "info.circle"
        case .speedChart: return "chart.line.uptrend.xyaxis"
        case .memoryChart: return "memorychip"
        case .modeSwitch: return "switch.2"
        case .subscription: return "doc.text.fill"
        case .connectivity: return "network"
        }
    }
}

class OverviewCardSettings: ObservableObject {
    @AppStorage("overviewCardOrder") private var orderData: Data = Data()
    @AppStorage("overviewCardVisibility") private var visibilityData: Data = Data()
    
    @Published var cardOrder: [OverviewCard]
    @Published var cardVisibility: [OverviewCard: Bool]
    
    init() {
        // 先初始化存储属性，确保所有卡片都在列表中
        cardOrder = OverviewCard.allCases
        cardVisibility = Dictionary(uniqueKeysWithValues: OverviewCard.allCases.map { card in
            return (card, true)
        })
        
        // 从 AppStorage 加载顺序数据
        if let savedOrder = try? JSONDecoder().decode([OverviewCard].self, from: orderData) {
            // 确保新添加的卡片也在列表中
            var newOrder = savedOrder
            for card in OverviewCard.allCases {
                if !newOrder.contains(card) {
                    newOrder.append(card)
                }
            }
            cardOrder = newOrder
            saveOrder() // 保存更新后的顺序
        }
        
        // 从 AppStorage 加载可见性数据
        if let savedVisibility = try? JSONDecoder().decode([String: Bool].self, from: visibilityData) {
            var newVisibility: [OverviewCard: Bool] = [:]
            for card in OverviewCard.allCases {
                // 如果是保存的数据中没有的新卡片，默认设置为显示
                newVisibility[card] = savedVisibility[card.rawValue] ?? true
            }
            cardVisibility = newVisibility
            saveVisibility() // 保存更新后的可见性设置
        }
    }
    
    func saveOrder() {
        if let encoded = try? JSONEncoder().encode(cardOrder) {
            orderData = encoded
        }
    }
    
    func saveVisibility() {
        let visibilityDict = Dictionary(uniqueKeysWithValues: cardVisibility.map { ($0.key.rawValue, $0.value) })
        if let encoded = try? JSONEncoder().encode(visibilityDict) {
            visibilityData = encoded
        }
    }
    
    func moveCard(from source: IndexSet, to destination: Int) {
        cardOrder.move(fromOffsets: source, toOffset: destination)
        saveOrder()
    }
    
    func toggleVisibility(for card: OverviewCard) {
        cardVisibility[card]?.toggle()
        saveVisibility()
    }
} 