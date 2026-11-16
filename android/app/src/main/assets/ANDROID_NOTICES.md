# Lumi Android 移植版

Required Notice: Copyright (c) 2026 NakanoNino233 and Lumi contributors

上游：https://github.com/NakanoNino233/Lumi
基于提交：91a3174a152620b358b887136f163ea624e4e6f3

本移植使用 Kotlin、Jetpack Compose 和 Android 平台 API 重写界面、网络、存储与系统集成，
参考上游的数据模型、角色卡、中文记忆关键词检索逻辑，并保留 DeepSeekDaughter、SafetyPrompt、
ReplyProtocol、DiaryPrompt、MemoryExtraction 文本资源。

Lumi 自有内容遵循随附 LICENSE（PolyForm Noncommercial License 1.0.0）。
角色参考内容的 MIT 声明保存在 nuwa-skill-LICENSE.txt；格式参考声明保存在 dsh-meme-LICENSE.txt。
上游 THIRD_PARTY_NOTICES.md 与 LICENSING.md 一并保留，供溯源查阅。

此本机个人 Android APK 保留上游应用图标及其三种变体、大肥鱼头像、默认朋友圈封面。
图片来源与 SHA-256 位于 ARTWORK_SOURCES.json；图片权利说明沿用 THIRD_PARTY_NOTICES.md。
图片权利独立于代码许可，未取得额外的图片商业使用或再分发授权。
十二张原创几何占位表情按 Lumi-Starter-Artwork.md 的 CC0 声明保留为图片资源；尚未实现自定义表情包库。
此 Android APK 未包含上游 ZIPFoundation 与 iOS 组件。

AndroidX、Jetpack Compose、Kotlin 与 kotlinx.coroutines 为各自作者维护的依赖，保留各自 Apache-2.0 许可。
此为非商业个人移植，并非上游作者发布的官方 Android 版本。
