import SwiftUI
import Foundation
import Yams

/// 基于 Yams 语法树的 YAML 语法高亮器
struct YAMLHighlighter {
    
    /// 语法元素类型
    enum SyntaxElementType {
        case key
        case value
        case comment
        case arrayIndicator
        case string
        case number
        case boolean
        case null
        case mainSection
    }
    
    /// 语法元素信息
    struct SyntaxElement {
        let type: SyntaxElementType
        let range: NSRange
        let text: String
    }
    
    /// 使用 Yams 进行基于语法树的语法高亮
    /// - Parameter yamlText: 完整的 YAML 文本
    /// - Returns: 语法元素数组
    static func analyzeSyntax(_ yamlText: String) -> [SyntaxElement] {
        var elements: [SyntaxElement] = []
        let lines = yamlText.components(separatedBy: .newlines)
        var currentPosition = 0
        
        // 主要节点列表（Clash 配置的顶级节点）
        let mainSections = ["proxies", "proxy-groups", "rules", "proxy-providers", "script", "dns", "hosts", "tun"]
        
        // 先分析注释
        for (_, line) in lines.enumerated() {
            let lineStart = currentPosition
            let lineLength = line.utf16.count
            
            // 处理注释
            if let commentStart = line.firstIndex(of: "#") {
                let commentOffset = commentStart.utf16Offset(in: line)
                let commentRange = NSRange(
                    location: lineStart + commentOffset,
                    length: lineLength - commentOffset
                )
                elements.append(SyntaxElement(
                    type: .comment,
                    range: commentRange,
                    text: String(line[commentStart...])
                ))
            }
            
            // 处理键值对
            if let colonIndex = line.firstIndex(of: ":") {
                let beforeColon = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let afterColon = String(line[line.index(after: colonIndex)...])
                
                if !beforeColon.isEmpty {
                    // 计算键的范围
                    let keyStart = line.firstIndex { !$0.isWhitespace } ?? line.startIndex
                    let keyOffset = keyStart.utf16Offset(in: line)
                    let keyLength = colonIndex.utf16Offset(in: line) - keyOffset
                    
                    let keyRange = NSRange(
                        location: lineStart + keyOffset,
                        length: keyLength
                    )
                    
                    // 判断是否为主要节点
                    let isMainSection = mainSections.contains(beforeColon)
                    
                    elements.append(SyntaxElement(
                        type: isMainSection ? .mainSection : .key,
                        range: keyRange,
                        text: beforeColon
                    ))
                    
                    // 处理值部分
                    let trimmedValue = afterColon.trimmingCharacters(in: .whitespaces)
                    if !trimmedValue.isEmpty && !trimmedValue.hasPrefix("#") {
                        let valueType = determineValueType(trimmedValue)
                        let valueStart = line.index(after: colonIndex)
                        let valueOffset = line[valueStart...].firstIndex { !$0.isWhitespace }?.utf16Offset(in: line) ?? (colonIndex.utf16Offset(in: line) + 1)
                        
                        let valueRange = NSRange(
                            location: lineStart + valueOffset,
                            length: trimmedValue.utf16.count
                        )
                        
                        elements.append(SyntaxElement(
                            type: valueType,
                            range: valueRange,
                            text: trimmedValue
                        ))
                    }
                }
            }
            
            // 处理数组指示符
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("-") {
                if let dashIndex = line.firstIndex(of: "-") {
                    let dashOffset = dashIndex.utf16Offset(in: line)
                    let dashRange = NSRange(
                        location: lineStart + dashOffset,
                        length: 1
                    )
                    elements.append(SyntaxElement(
                        type: .arrayIndicator,
                        range: dashRange,
                        text: "-"
                    ))
                }
            }
            
            currentPosition += lineLength + 1 // +1 for newline
        }
        
        return elements
    }
    
    /// 确定值的类型
    private static func determineValueType(_ value: String) -> SyntaxElementType {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        
        // 布尔值
        if ["true", "false", "yes", "no", "on", "off"].contains(trimmed.lowercased()) {
            return .boolean
        }
        
        // null 值
        if ["null", "~"].contains(trimmed.lowercased()) {
            return .null
        }
        
        // 数字
        if Int(trimmed) != nil || Double(trimmed) != nil {
            return .number
        }
        
        // 字符串（包括带引号和不带引号的）
        return .string
    }
    
    /// 应用语法高亮到 NSMutableAttributedString
    /// - Parameters:
    ///   - attributedString: 要应用高亮的属性字符串
    ///   - elements: 语法元素数组
    ///   - font: 基础字体
    static func applySyntaxHighlighting(
        to attributedString: NSMutableAttributedString,
        elements: [SyntaxElement],
        font: UIFont
    ) {
        for element in elements {
            guard element.range.location >= 0 && 
                  element.range.location + element.range.length <= attributedString.length else {
                continue
            }
            
            switch element.type {
            case .mainSection:
                attributedString.addAttribute(.foregroundColor, 
                                            value: UIColor.systemBlue, 
                                            range: element.range)
                attributedString.addAttribute(.font, 
                                            value: UIFont.boldSystemFont(ofSize: font.pointSize), 
                                            range: element.range)
                
            case .key:
                attributedString.addAttribute(.foregroundColor, 
                                            value: UIColor.systemPurple, 
                                            range: element.range)
                
            case .value, .string:
                attributedString.addAttribute(.foregroundColor, 
                                            value: UIColor.label, 
                                            range: element.range)
                
            case .comment:
                attributedString.addAttribute(.foregroundColor, 
                                            value: UIColor.systemGreen, 
                                            range: element.range)
                attributedString.addAttribute(.font, 
                                            value: UIFont.italicSystemFont(ofSize: font.pointSize), 
                                            range: element.range)
                
            case .arrayIndicator:
                attributedString.addAttribute(.foregroundColor, 
                                            value: UIColor.systemOrange, 
                                            range: element.range)
                
            case .number:
                attributedString.addAttribute(.foregroundColor, 
                                            value: UIColor.systemTeal, 
                                            range: element.range)
                
            case .boolean:
                attributedString.addAttribute(.foregroundColor, 
                                            value: UIColor.systemRed, 
                                            range: element.range)
                attributedString.addAttribute(.font, 
                                            value: UIFont.boldSystemFont(ofSize: font.pointSize), 
                                            range: element.range)
                
            case .null:
                attributedString.addAttribute(.foregroundColor, 
                                            value: UIColor.systemGray, 
                                            range: element.range)
                attributedString.addAttribute(.font, 
                                            value: UIFont.italicSystemFont(ofSize: font.pointSize), 
                                            range: element.range)
            }
        }
    }
    
    // 保持原有的简单行高亮方法作为备用
    static func highlight(_ line: String) -> AttributedString {
        var attributedString = AttributedString(line)
        
        // 注释
        if line.trimmingCharacters(in: .whitespaces).starts(with: "#") {
            attributedString.foregroundColor = .green
            return attributedString
        }
        
        // 键值对中的键
        if let colonIndex = line.firstIndex(of: ":") {
            let keyRange = attributedString.startIndex..<attributedString.index(attributedString.startIndex, offsetByCharacters: colonIndex.utf16Offset(in: line))
            
            // 检查是否是缩进的键
            let leadingSpaces = line.prefix(while: { $0 == " " })
            let isIndented = !leadingSpaces.isEmpty
            
            if keyRange.lowerBound < keyRange.upperBound {
                attributedString[keyRange].foregroundColor = isIndented ? .red : .pink
            }
        }
        
        // 数组项的破折号
        if line.trimmingCharacters(in: .whitespaces).starts(with: "-") {
            if let dashRange = line.range(of: "-") {
                let start = attributedString.index(attributedString.startIndex, offsetByCharacters: dashRange.lowerBound.utf16Offset(in: line))
                let end = attributedString.index(attributedString.startIndex, offsetByCharacters: dashRange.upperBound.utf16Offset(in: line))
                if start < end {
                    attributedString[start..<end].foregroundColor = .red
                }
            }
        }
        
        return attributedString
    }
} 
