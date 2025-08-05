@preconcurrency
import SwiftUI
import WebKit

struct LuCIWebView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: LuCIWebViewModel
    
    init(server: ClashServer) {
        _viewModel = StateObject(wrappedValue: LuCIWebViewModel(server: server))
    }
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("正在加载...")
            } else if let error = viewModel.error {
                VStack {
                    Text("加载失败")
                        .font(.headline)
                        .padding(.bottom, 4)
                    Text(error)
                        .foregroundColor(.secondary)
                }
            } else {
                WebView(url: viewModel.url, token: viewModel.token)
            }
        }
        .navigationTitle("网页访问")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") {
                    dismiss()
                }
            }
        }
        .task {
            await viewModel.loadWebView()
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    let token: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebView
        var cookieInjected = false
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // 处理 Cookie 消息
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 确保 Cookie 被正确设置
            let cookieScript = """
            document.cookie = 'sysauth=\(parent.token);path=/';
            document.cookie = 'sysauth_http=\(parent.token);path=/';
            """
            webView.evaluateJavaScript(cookieScript) { _, _ in }
            
            // 验证 Cookie
            webView.evaluateJavaScript("document.cookie") { _, _ in }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if !cookieInjected {
                syncCookies {
                    decisionHandler(.allow)
                }
                cookieInjected = true
            } else {
                decisionHandler(.allow)
            }
        }
        
        // 添加自签名证书支持
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                if let serverTrust = challenge.protectionSpace.serverTrust {
                    let credential = URLCredential(trust: serverTrust)
                    completionHandler(.useCredential, credential)
                    return
                }
            }
            completionHandler(.performDefaultHandling, nil)
        }
        
        private func syncCookies(completion: @escaping () -> Void) {
            let cookieStore = WKWebsiteDataStore.default().httpCookieStore
            let dispatchGroup = DispatchGroup()
            
            dispatchGroup.enter()
            cookieStore.getAllCookies { cookies in
                let group = DispatchGroup()
                cookies.forEach { cookie in
                    group.enter()
                    cookieStore.delete(cookie) {
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    dispatchGroup.leave()
                }
            }
            
            dispatchGroup.enter()
            let cookies = [
                createCookie(name: "sysauth", value: parent.token),
                createCookie(name: "sysauth_http", value: parent.token)
            ].compactMap { $0 }
            
            let group = DispatchGroup()
            cookies.forEach { cookie in
                group.enter()
                cookieStore.setCookie(cookie) {
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                dispatchGroup.leave()
            }
            
            dispatchGroup.notify(queue: .main) {
                completion()
            }
        }
        
        private func createCookie(name: String, value: String) -> HTTPCookie? {
            let properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: parent.url.host ?? "",
                .path: "/",
                .secure: "TRUE",
                .expires: Date().addingTimeInterval(3600)
            ]
            return HTTPCookie(properties: properties)
        }
    }
    
    func makeUIView(context: Context) -> WKWebView {
        // 创建新的非持久化数据存储
        let websiteDataStore = WKWebsiteDataStore.nonPersistent()
        
        // 配置 WKWebView
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        
        let controller = WKUserContentController()
        configuration.userContentController = controller
        
        // 预先注入 Cookie 设置脚本
        let cookieScript = WKUserScript(
            source: """
            function setCookie(name, value) {
                document.cookie = name + '=' + value + ';path=/';
            }
            setCookie('sysauth', '\(token)');
            setCookie('sysauth_http', '\(token)');
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        
        controller.addUserScript(cookieScript)
        controller.add(context.coordinator, name: "cookieHandler")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // 清理所有类型的网站数据
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) { }
        
        // 清理共享的 Cookie 存储
        HTTPCookieStorage.shared.removeCookies(since: Date(timeIntervalSince1970: 0))
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // 确保在发送请求前清理 Cookie
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            cookies.forEach { cookie in
                webView.configuration.websiteDataStore.httpCookieStore.delete(cookie)
            }
            
            // 在清理完成后发送请求
            var request = URLRequest(url: url)
            let cookieHeader = "sysauth=\(token); sysauth_http=\(token); sysauth_https=\(token)"
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.httpShouldHandleCookies = true
            
            webView.load(request)
        }
    }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        // 清理所有类型的网站数据
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) { }
        
        // 清理共享的 Cookie 存储
        HTTPCookieStorage.shared.removeCookies(since: Date(timeIntervalSince1970: 0))
        
        // 清理 WKWebView 的 Cookie
        uiView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            cookies.forEach { cookie in
                uiView.configuration.websiteDataStore.httpCookieStore.delete(cookie)
            }
        }
    }
}

class LuCIWebViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var error: String?
    @Published var url: URL!
    @Published var token: String = ""
    
    private let server: ClashServer
    private var serverViewModel: ServerViewModel?
    
    init(server: ClashServer) {
        self.server = server
    }
    
    @MainActor
    func loadWebView() async {
        isLoading = true
        error = nil
        
        do {
            // 在主线程初始化 ServerViewModel
            if serverViewModel == nil {
                serverViewModel = ServerViewModel()
            }
            
            guard let serverViewModel = serverViewModel else {
                throw NetworkError.invalidResponse(message: "无法初始化服务器视图模型")
            }
            
            // 获取认证 token
            guard let username = server.openWRTUsername,
                  let password = server.openWRTPassword else {
                throw NetworkError.unauthorized(message: "未设置 OpenWRT 用户名或密码")
            }
            
            token = try await serverViewModel.getAuthToken(server, username: username, password: password)
            
            // 构建 URL
            let scheme = server.openWRTUseSSL ? "https" : "http"
            guard let openWRTUrl = server.openWRTUrl else {
                throw NetworkError.invalidURL
            }
            let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
            
            let path: String
            if server.luciPackage == .openClash {
                path = "/cgi-bin/luci/admin/services/openclash/client"
            } else {
                // 判断是否使用 nikki
                let isNikki = try await serverViewModel.isUsingNikki(server, token: token)
                path = isNikki ? "/cgi-bin/luci/admin/services/nikki" : "/cgi-bin/luci/admin/services/mihomo"
            }
            
            guard let finalURL = URL(string: baseURL + path) else {
                throw NetworkError.invalidURL
            }
            
            print("🔐 Web 访问 URL: \(finalURL.absoluteString)")
            print("🔐 OpenWRT SSL设置: \(server.openWRTUseSSL)")
            
            url = finalURL
            isLoading = false
            
        } catch {
            isLoading = false
            if let networkError = error as? NetworkError {
                self.error = networkError.localizedDescription
            } else {
                self.error = error.localizedDescription
            }
        }
    }
} 
