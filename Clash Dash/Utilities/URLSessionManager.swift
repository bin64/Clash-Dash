import Foundation

class URLSessionManager: NSObject, URLSessionDelegate {
    static let shared = URLSessionManager()
    
    private override init() {
        super.init()
    }
    
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        if #available(iOS 15.0, *) {
            config.tlsMinimumSupportedProtocolVersion = .TLSv12
        }
        config.tlsMaximumSupportedProtocolVersion = .TLSv13
        
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let messages = [
            "收到证书验证请求",
            "认证方法: \(challenge.protectionSpace.authenticationMethod)",
            "主机: \(challenge.protectionSpace.host)",
            "端口: \(challenge.protectionSpace.port)",
            "协议: \(challenge.protectionSpace.protocol.map { $0 } ?? "unknown")"
        ]
        
        messages.forEach { message in
            Task { @MainActor in
                LogManager.shared.debug(message)
            }
        }
        
        // 无条件接受所有证书
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
                Task { @MainActor in
                    LogManager.shared.debug("已接受服务器证书（包括自签证书）")
                }
            } else {
                Task { @MainActor in
                    LogManager.shared.debug("无法获取服务器证书")
                }
                completionHandler(.performDefaultHandling, nil)
            }
        } else {
            Task { @MainActor in
                LogManager.shared.debug("默认处理证书验证")
            }
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    // 创建一个自定义的 URLSession
    func makeCustomSession(timeoutInterval: TimeInterval = 30) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        if #available(iOS 15.0, *) {
            config.tlsMinimumSupportedProtocolVersion = .TLSv12
        }
        config.tlsMaximumSupportedProtocolVersion = .TLSv13
        
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
} 