#!/bin/bash

# 日志函数
log() {
    local level="$1"
    local message="$2"
    case "$level" in
        "info")
            echo "🔍 $message"
            ;;
        "error")
            echo "$message"
            ;;
        "success")
            echo "$message"
            ;;
        "send")
            echo "📤 $message"
            ;;
        "receive")
            echo "$message"
            ;;
        *)
            echo "$message"
            ;;
    esac
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> clash_debug.log
}

# 发送请求并处理响应的函数
send_request() {
    local method="$1"
    local endpoint="$2"
    local description="$3"
    
    log "info" "正在获取$description..."
    
    local url="${protocol}://${host}:${port}${endpoint}"
    local response=$(curl -s -w "\n%{http_code}" \
        -X "$method" \
        -H "Authorization: Bearer $secret" \
        -H "Accept: */*" \
        -H "Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh-TW;q=0.7,zh;q=0.6" \
        -H "Cache-Control: no-cache" \
        -H "Connection: keep-alive" \
        -H "Content-Type: application/json" \
        -H "DNT: 1" \
        -H "Pragma: no-cache" \
        -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" \
        ${use_ssl:+--insecure} \
        "$url")
    
    local response_body=$(echo "$response" | head -n 1)
    local status_code=$(echo "$response" | tail -n 1)
    
    log "receive" "$description 响应状态码: $status_code"
    echo "$description 响应内容：" >> clash_debug.log
    echo "$response_body" | python3 -m json.tool 2>/dev/null >> clash_debug.log || echo "$response_body" >> clash_debug.log
    echo "----------------------------------------" >> clash_debug.log
    
    if [ "$status_code" = "200" ]; then
        log "success" "$description 请求成功"
    else
        log "error" "$description 请求失败"
    fi
}

# 清理之前的日志文件
> clash_debug.log

# 获取参数
read -p "请输入域名或IP地址: " host
read -p "请输入端口 (默认9090): " port
port=${port:-9090}
read -p "请输入连接密钥: " secret
read -p "是否启用 SSL (y/n): " ssl_option

# 设置协议
if [[ "$ssl_option" =~ ^[Yy]$ ]]; then
    protocol="https"
    use_ssl=1
else
    protocol="http"
    use_ssl=0
fi

log "info" "开始测试 Clash 控制器连接..."
log "info" "目标地址: ${protocol}://${host}:${port}"

# 1. 获取版本信息
send_request "GET" "/version" "版本信息"

# 2. 获取代理提供者信息
send_request "GET" "/providers/proxies" "代理提供者信息"

# 3. 获取代理信息
send_request "GET" "/proxies" "代理信息"

# 4. 获取规则信息
send_request "GET" "/rules" "规则信息"

# 5. 获取规则提供者信息
send_request "GET" "/providers/rules" "规则提供者信息"

# 6. 获取连接信息
send_request "GET" "/connections" "连接信息"

# 7. 获取配置信息
send_request "GET" "/configs" "配置信息"

log "success" "测试完成，详细日志已保存到 clash_debug.log" 
