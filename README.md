# 快歌 · 嗅探 (KuaiGe)

一个 iOS 工具（TrollStore / 巨魔 可装）：粘贴「快歌 AI」等平台的**公开分享链接**，用内置浏览器打开页面，自动嗅探页面里加载的音频文件（含 `*.myqcloud.com` 这类 COS 远程链接），然后**复制链接**或**下载保存到本机 / 分享到文件 App**。

用途定位：保存你自己创作、且平台已通过官方分享链接公开的内容，供个人离线收听。

## 用法
1. 打开 App，点「粘贴」或手动粘贴分享链接（例如 `https://m.kuaigeai.cn/...`）。
2. 点「前往」加载页面。
3. 若页面需要点一下才播放，点一下播放，音频链接会被嗅探到。
4. 点右上角「音频(N)」打开列表，每条可：
   - **复制链接**：把真实音频/COS 地址复制到剪贴板。
   - **下载**：存到 App 沙盒 `Documents/Downloads`。
   - **分享**：把已下载的文件导出到「文件」App 或其他 App。

## 编译（GitHub Actions 云编译，无需 Mac）
本仓库自带 `.github/workflows/build.yml`：
- 推送（或手动 `workflow_dispatch`）后，GitHub macOS runner 会用 XcodeGen 生成工程、编译、用自签名证书注入 `KuaiGe.entitlements` 并打包成 `KuaiGe.ipa`。
- 在 Actions 页面下载 Artifact `KuaiGe.ipa`。

> Windows 无法编译 iOS App，必须走 Actions。

## 安装到手机（TrollStore / 巨魔）
1. 手机用 TrollStore 安装下载的 `KuaiGe.ipa`。
2. 打开即可使用。

## 目录结构
```
KuaiGe/
├── project.yml                 # XcodeGen 工程描述
├── KuaiGe.entitlements         # 签名授权（get-task-allow）
├── Resources/Info.plist        # 应用信息（含 ATS 放开）
├── Sources/KuaiGe/
│   ├── KuaiGeApp.swift         # @main 入口
│   ├── Models/SniffedMedia.swift
│   ├── Store/SniffStore.swift  # 嗅探结果容器
│   ├── Utils/
│   │   ├── SniffScript.swift        # 注入的 JS 嗅探脚本
│   │   ├── SniffMessageHandler.swift# JS -> 原生 桥接
│   │   └── DownloadManager.swift    # 下载/保存
│   └── Views/
│       ├── ContentView.swift   # 主界面（链接栏 + 浏览器）
│       ├── BrowserView.swift   # WKWebView 封装
│       └── SniffSheet.swift    # 嗅探结果列表
└── .github/workflows/build.yml # 云编译出 IPA
```

## 说明 / 局限
- 若音频是 HLS（`m3u8` 切片流），直接 `dataTask` 只能拿到播放列表文本，本工具不合并切片；这类情况用「复制链接」拿到地址后在桌面端处理。
- 仅作个人保存已授权/公开内容使用，不要用于批量抓取或再分发他人版权内容。
