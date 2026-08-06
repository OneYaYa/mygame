# Blindspot Relay 分发安全说明

`build_windows_release.ps1 -EmbedApiCredential` 会把项目 `.env` 中的模型配置
打进 `BlindspotRelayServer.exe`，以满足玩家解压即用在线 AI 的需求。

这只适合小范围、可信玩家测试。桌面程序中的任何密钥最终都可能被提取，
因此不要把含个人或高额度 API Key 的构建公开上传。公开发行前应改用托管代理：

- 密钥只保存在你控制的服务器；
- 玩家通过有鉴权、TLS、限流和配额的公网端点访问；
- 对账单设置额度与异常告警；
- 为发行构建使用可随时轮换的独立项目密钥。

不加 `-EmbedApiCredential` 时，发行包不会内置 `.env`；游戏依然能以本地 NPC
模式完整游玩，也可以在入口 EXE 同级或 `_runtime` 目录放置 `.env` 来启用在线 AI。
