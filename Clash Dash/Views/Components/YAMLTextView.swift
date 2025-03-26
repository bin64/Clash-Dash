import SwiftUI
import UIKit

struct YAMLTextView: UIViewRepresentable {
    @Binding var text: String
    let font: UIFont
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.backgroundColor = .clear
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        // 显式启用中文输入法支持
        textView.inputView = nil
        textView.inputAccessoryView = nil
        textView.keyboardType = .default
        textView.layoutManager.allowsNonContiguousLayout = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        
        // 初始设置文本和高亮
        textView.text = text
        highlightSyntax(textView)
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // 只在非组合文本状态下更新文本和高亮
        if uiView.text != text && !context.coordinator.isUpdatingText && !context.coordinator.isComposingText {
            let selectedRange = uiView.selectedRange
            uiView.text = text
            highlightSyntax(uiView)
            uiView.selectedRange = selectedRange
        }
    }
    
    private func highlightSyntax(_ textView: UITextView) {
        // 如果有标记文本（正在输入中文），不执行高亮
        if textView.markedTextRange != nil {
            return
        }
        
        let attributedText = NSMutableAttributedString(string: textView.text)
        let wholeRange = NSRange(location: 0, length: textView.text.utf16.count)
        let selectedRange = textView.selectedRange
        
        // 设置基本字体和颜色
        attributedText.addAttribute(.font, value: font, range: wholeRange)
        attributedText.addAttribute(.foregroundColor, value: UIColor.label, range: wholeRange)
        
        // 使用正则表达式进行语法高亮
        do {
            // 主要 YAML 关键字（使用蓝色和粗体）
            let mainKeywords = ["proxies:", "proxy-groups:", "rules:", "proxy-providers:", "script:"]
            for keyword in mainKeywords {
                let pattern = "^\\s*\(keyword)"
                let regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
                regex.enumerateMatches(in: textView.text, range: wholeRange) { match, _, _ in
                    if let range = match?.range {
                        attributedText.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
                        attributedText.addAttribute(.font,value: UIFont.boldSystemFont(ofSize: font.pointSize), range: range)
                    }
                }
            }
            
            // 注释（使用绿色）
            let commentPattern = "#.*$"
            let commentRegex = try NSRegularExpression(pattern: commentPattern, options: .anchorsMatchLines)
            commentRegex.enumerateMatches(in: textView.text, range: wholeRange) { match, _, _ in
                if let range = match?.range {
                    attributedText.addAttribute(.foregroundColor, value: UIColor.systemGreen, range: range)
                    attributedText.addAttribute(.font, value: UIFont.italicSystemFont(ofSize: font.pointSize), range: range)
                }
            }
            
            // 键值对中的键（使用紫色）
            let keyPattern = "^\\s*([\\w-]+):"
            let keyRegex = try NSRegularExpression(pattern: keyPattern, options: .anchorsMatchLines)
            keyRegex.enumerateMatches(in: textView.text, range: wholeRange) { match, _, _ in
                if let range = match?.range(at: 1) {
                    attributedText.addAttribute(.foregroundColor, value: UIColor.systemPurple, range: range)
                }
            }
            
            // 数组项的破折号（使用橙色）
            let dashPattern = "^\\s*-\\s"
            let dashRegex = try NSRegularExpression(pattern: dashPattern, options: .anchorsMatchLines)
            dashRegex.enumerateMatches(in: textView.text, range: wholeRange) { match, _, _ in
                if let range = match?.range {
                    attributedText.addAttribute(.foregroundColor, value: UIColor.systemOrange, range: range)
                }
            }
            
            // URL（使用蓝色和下划线）
            // let urlPattern = "(https?://[\\w\\d\\-\\.]+\\.[\\w\\d\\-\\./\\?\\=\\&\\%\\+\\#]+)"
            // let urlRegex = try NSRegularExpression(pattern: urlPattern, options: [])
            // urlRegex.enumerateMatches(in: textView.text, range: wholeRange) { match, _, _ in
            //     if let range = match?.range {
            //         attributedText.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
            //         attributedText.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            //     }
            // }
            
            // 布尔值（使用红色）
            let boolPattern = "\\s(true|false)\\s"
            let boolRegex = try NSRegularExpression(pattern: boolPattern, options: [])
            boolRegex.enumerateMatches(in: textView.text, range: wholeRange) { match, _, _ in
                if let range = match?.range(at: 1) {
                    attributedText.addAttribute(.foregroundColor, value: UIColor.systemRed, range: range)
                    attributedText.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: font.pointSize), range: range)
                }
            }
            
            // 数字（使用蓝绿色）
            let numberPattern = "\\s(\\d+)\\s"
            let numberRegex = try NSRegularExpression(pattern: numberPattern, options: [])
            numberRegex.enumerateMatches(in: textView.text, range: wholeRange) { match, _, _ in
                if let range = match?.range(at: 1) {
                    attributedText.addAttribute(.foregroundColor, value: UIColor.systemTeal, range: range)
                }
            }
        } catch {
            print("Regex error: \(error)")
        }
        
        textView.attributedText = attributedText
        textView.selectedRange = selectedRange
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: YAMLTextView
        var isUpdatingText = false
        var isComposingText = false
        
        init(_ parent: YAMLTextView) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            // 检查是否在中文输入过程中
            isComposingText = textView.markedTextRange != nil
            
            // 只有在非中文输入过程中才更新文本和高亮
            if !isComposingText {
                isUpdatingText = true
                parent.text = textView.text
                parent.highlightSyntax(textView)
                isUpdatingText = false
            } else {
                // 在中文输入过程中，只更新文本，不执行高亮
                isUpdatingText = true
                parent.text = textView.text
                isUpdatingText = false
            }
        }
        
        // 处理输入法组合文本
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // 当用户点击输入法候选词时，text会包含完整的候选词
            return true
        }
        
        // 输入法编辑中时调用
        func textViewDidBeginEditing(_ textView: UITextView) {
            // 确保输入视图可用
            if textView.inputView != nil {
                textView.inputView = nil
                textView.reloadInputViews()
            }
        }
        
        // 处理中文输入法的组合状态
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            return true
        }
        
        // 标记中文输入法正在组合文本
        func textViewDidChangeSelection(_ textView: UITextView) {
            let markedTextRange = textView.markedTextRange
            isComposingText = markedTextRange != nil
        }
    }
} 