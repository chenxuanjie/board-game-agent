# Web 端 AI 本地代理

浏览器直接请求某些 OpenAI 兼容接口时，会先发送 CORS `OPTIONS` 预检。若上游服务没有允许浏览器来源，Flutter Web 即使在 Android/Windows 上可以正常请求，浏览器仍然会被拦截。

本项目提供一个只绑定本机回环地址的 Python 代理，用于本地 Web 验证：代理为页面补充 CORS 响应，并把 `/v1/models` 与 `/v1/chat/completions` 转发到上游。API Key 仍由应用发送到本机代理，代理不会记录 Key 或请求正文。

## 启动

先构建 Web：

```powershell
flutter build web --release --source-maps
```

停止当前占用 8081 端口的 Flutter 静态服务器后，启动代理和静态文件服务：

```powershell
python scripts/web_preview_server.py `
  --port=8081 `
  --upstream=https://www.loomex.top/v1 `
  --directory=build/web
```

然后打开 `http://127.0.0.1:8081/`，在“AI 接口配置”中选择“自定义 OpenAI 兼容接口”，将接口地址设置为：

```text
http://127.0.0.1:8081/v1
```

模型仍然必须通过“刷新模型列表”从 `/models` 获取，随后才能发送文本问题。

## 注意

- 代理默认只监听 `127.0.0.1`，仅用于本机开发调试，不应部署到公网。
- 生产 Web 应用应使用同源后端网关，并在服务端保存上游 API Key；不要把真实 Key 固化进 Flutter Web 构建产物。
- 如果上游服务端修复 CORS，Web 可以直接使用上游 URL，无需该代理。
