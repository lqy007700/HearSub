# HearSub

适用于 macOS 的实时双语字幕工具。

HearSub 常驻菜单栏，可以监听麦克风或 Mac 音频，并在当前使用的应用上方显示简洁的双行字幕条。它适合会议、通话、直播、视频、网课，以及任何“听一种语言、读另一种语言”的场景。

[English README](README.md) · [Releases](https://github.com/lqy007700/HearSub/releases)

## 功能概览

- 支持从麦克风或 macOS 系统音频捕获声音。
- 使用 Apple SpeechAnalyzer / SpeechTranscriber 进行语音转写。
- 通过悬浮字幕条显示实时字幕，不打断当前工作流。
- 可选择只显示原文、只显示译文，或同时显示两行字幕。
- 支持同时选择多个输入源，并为每个输入源单独设置原文语言和字幕语言。
- 通过 OpenAI 兼容的 Chat Completions 接口进行翻译。
- 在选择 Apple Translation 时，可准备 Apple 本地翻译资源。
- 使用 Silero VAD 和 ONNX Runtime 检测语音边界，减少字幕提交时的噪声和误切分。
- 保留字幕记录，并支持导出 transcript 文本。
- 在支持的 macOS 版本上，可用 Apple Intelligence 对字幕记录进行摘要。
- 提供菜单栏快捷控制、高级设置、登录时启动和 Sparkle 自动更新。

## 当前语言支持

输入语言刻意限制为 Apple SpeechAnalyzer / SpeechTranscriber 路径支持的语言：

- 英语
- 简体中文
- 粤语
- 西班牙语
- 德语
- 日语
- 法语
- 意大利语
- 韩语
- 葡萄牙语

字幕输出语言包含常用界面语言，例如英语、简体中文、西班牙语、德语、日语、法语、韩语、阿拉伯语、葡萄牙语和俄语。实际翻译质量和覆盖范围取决于你配置的翻译后端。

## 翻译后端

HearSub 默认使用 OpenAI 兼容的翻译后端。请在 **设置 -> 翻译** 中配置：

- Base URL，例如 `https://api.openai.com/v1` 或其他兼容端点。
- API key。
- 模型名称。

设置窗口里可以拉取模型列表，也可以测试连接。使用该后端时，字幕文本会发送到你自己配置的接口。

## 隐私说明

- HearSub 没有内置分析、遥测、账号系统或项目自有云后端。
- 音频捕获和语音识别通过 Apple 的 macOS API 在本机完成。
- Silero VAD 模型通过 ONNX Runtime 在本机运行。
- 当使用 OpenAI 兼容翻译后端时，字幕文本会发送到你配置的翻译服务。
- 字幕记录和应用设置保存在本机 HearSub 应用支持目录中。

## 系统要求

- 当前 SpeechAnalyzer / SpeechTranscriber 转写路径需要 macOS 26 或更新版本。
- 系统音频捕获需要 macOS 15 或更新版本。
- 使用麦克风输入时需要授予麦克风权限。
- 捕获 Mac 音频时需要授予音频捕获权限。
- 实时翻译字幕需要可用的 OpenAI 兼容翻译接口。
- 从源码构建需要完整安装 Xcode。

部分功能会根据 macOS 版本启用：

- 字幕记录摘要需要 macOS 26 或更新版本。
- Apple 本地翻译是否可用，取决于语言对和系统中已安装的语言资源。

## 从源码构建

```bash
git clone git@github.com:lqy007700/HearSub.git
cd HearSub
open HearSub.xcodeproj
```

也可以用终端构建：

```bash
xcodebuild -project HearSub.xcodeproj -scheme HearSub -configuration Debug build
```

项目通过 Xcode 工程使用 Swift Package Manager 依赖。构建 macOS app 需要完整 Xcode 工具链，仅安装 Command Line Tools 不够。

## 项目结构

```text
Sources/HearSubApp/        macOS app 源码
Tests/HearSubTests/        设置、本地化、语言目录和字幕启发式逻辑的单元测试
Assets.xcassets/           应用图标资源
Config/Info.plist          应用元数据、权限说明和 Sparkle appcast 配置
docs/                      GitHub Pages 静态站点
scripts/release.sh         版本号和 GitHub Release 辅助脚本
```

## 发布

带 tag 的版本由 GitHub Actions release workflow 构建。发布产物是压缩后的 `.app` 包，并附带 Sparkle appcast。

## 许可证

MIT
