import Foundation
import Yams

/// YAML 验证和解析工具类
class YAMLValidator {
    
    /// 验证 YAML 字符串是否有效
    /// - Parameter yamlString: 要验证的 YAML 字符串
    /// - Returns: 验证结果，包含是否有效和错误信息
    static func validate(_ yamlString: String) -> (isValid: Bool, error: String?) {
        do {
            // 尝试解析 YAML 字符串
            _ = try Yams.load(yaml: yamlString)
            return (true, nil)
        } catch let error {
            let errorMessage = formatYAMLError(error)
            return (false, errorMessage)
        }
    }
    
    /// 解析 YAML 字符串为字典
    /// - Parameter yamlString: 要解析的 YAML 字符串
    /// - Returns: 解析后的字典，失败时返回 nil
    static func parse(_ yamlString: String) -> [String: Any]? {
        do {
            if let result = try Yams.load(yaml: yamlString) as? [String: Any] {
                return result
            }
            return nil
        } catch {
            return nil
        }
    }
    
    /// 将字典转换为 YAML 字符串
    /// - Parameter dictionary: 要转换的字典
    /// - Returns: YAML 字符串，失败时返回 nil
    static func stringify(_ dictionary: [String: Any]) -> String? {
        do {
            return try Yams.dump(object: dictionary)
        } catch {
            return nil
        }
    }
    
    /// 格式化 YAML 错误信息
    /// - Parameter error: YAML 解析错误
    /// - Returns: 格式化后的错误信息
    private static func formatYAMLError(_ error: Error) -> String {
        if let yamlError = error as? YamlError {
            switch yamlError {
            case .parser(let context, let problem, let mark, _):
                var errorMessage = "YAML 解析错误"
                if let context = context {
                    errorMessage += "：\(context)"
                }
                errorMessage += " - \(problem)"
                errorMessage += " (行 \(mark.line + 1), 列 \(mark.column + 1))"
                return errorMessage
                
            case .scanner(let context, let problem, let mark, _):
                var errorMessage = "YAML 扫描错误"
                if let context = context {
                    errorMessage += "：\(context)"
                }
                errorMessage += " - \(problem)"
                errorMessage += " (行 \(mark.line + 1), 列 \(mark.column + 1))"
                return errorMessage
                
            case .composer(let context, let problem, let mark, _):
                var errorMessage = "YAML 组合错误"
                if let context = context {
                    errorMessage += "：\(context)"
                }
                errorMessage += " - \(problem)"
                errorMessage += " (行 \(mark.line + 1), 列 \(mark.column + 1))"
                return errorMessage
                
            case .representer(let problem):
                var errorMessage = "YAML 表示错误"
                errorMessage += " - \(problem)"
                return errorMessage
                
            default:
                return "YAML 错误：\(error.localizedDescription)"
            }
        }
        
        return "YAML 错误：\(error.localizedDescription)"
    }
    
    /// 验证 Clash 配置文件的基本结构
    /// - Parameter yamlString: Clash 配置 YAML 字符串
    /// - Returns: 验证结果和错误信息
    static func validateClashConfig(_ yamlString: String) -> (isValid: Bool, error: String?) {
        // 首先验证 YAML 语法
        let (isValidYAML, yamlError) = validate(yamlString)
        if !isValidYAML {
            return (false, yamlError)
        }
        
        // 解析为字典进行结构验证
        guard let config = parse(yamlString) else {
            return (false, "无法解析 YAML 配置")
        }
        
        // 验证 Clash 配置的基本字段
        var warnings: [String] = []
        
        // 检查基本字段
        if config["port"] == nil {
            warnings.append("缺少 port 字段")
        }
        
        if config["socks-port"] == nil {
            warnings.append("缺少 socks-port 字段")
        }
        
        // 检查代理相关字段
        if config["proxies"] == nil && config["proxy-providers"] == nil {
            warnings.append("缺少 proxies 或 proxy-providers 字段")
        }
        
        // 检查规则字段
        if config["rules"] == nil {
            warnings.append("缺少 rules 字段")
        }
        
        if !warnings.isEmpty {
            return (true, "配置可能存在问题：\n" + warnings.joined(separator: "\n"))
        }
        
        return (true, nil)
    }
}
