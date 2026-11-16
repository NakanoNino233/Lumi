# Lumi Android

Lumi 的原生 Android 移植，使用 Kotlin、Jetpack Compose 和 Android 系统 API。iOS 工程位于仓库根目录；Android 的源码、构建和版本发布独立位于本目录。

**Android 8.0+ · 1.0.4-android · versionCode 5**

## 下载与安装

- [下载已签名的 Android 1.0.4 APK](https://github.com/NakanoNino233/Lumi/releases/download/android-v1.0.4/Lumi-Android-1.0.4.apk)
- [Android Release、源码压缩包和 SHA-256 校验](https://github.com/NakanoNino233/Lumi/releases/tag/android-v1.0.4)
- [返回项目首页 / iOS 版本](../README.md)

下载 APK 后打开安装，按系统提示允许浏览器或文件管理器安装应用。打开 App 后填写资料，或选择“先逛逛”；在“我的 → API 配置”填写自己的服务地址、模型和 API Key。安装包没有内置 API Key、模型额度或离线大模型。

此 APK 使用与此前 Android 版本一致的个人发布证书，可以覆盖安装同签名的旧版本。更新前建议导出备份。发布证书 SHA-256：

```text
aff211e5581401b561fcddc5e17533986f7ab901d1c36740dd2767743e2269d4
```

## 当前功能

| 功能 | Android 实现 |
| --- | --- |
| 私聊 | 流式回复、停止、重新生成、历史搜索、复制、分享、按会话保存文字草稿 |
| 图片 | 系统选择器、缩放后发送、全屏缩放预览；图片理解需要模型支持 |
| 语音 | Android 系统语音识别、TTS 手动与自动朗读 |
| 群聊 | 2–8 位好友依次回复，每位成员单独调用一次模型 |
| 角色 | 创建、编辑、置顶、搜索、删除、头像、兼容 schemaVersion 1 的 JSON 好友卡 |
| 记忆 | 添加、置顶、移除、中文词组与关键词检索、模型提取与更新 |
| 自动记忆 | 可选，每 8 次用户发送后调用模型，默认关闭 |
| 日记与关系 | 当日对话日记、好感与阶段、每天好感增长上限、纪念日 |
| 朋友圈 | 个人封面、动态时间线、点赞评论、好友独立动态与封面、手动生成好友动态和评论 |
| 模型配置 | 多配置，兼容 OpenAI Chat Completions 与 Anthropic Messages 协议 |
| 用量与外观 | 成功请求和实际报告的 Token、个人资料、浅色/深色/跟随系统 |
| 备份 | Android ZIP 完整备份、校验预览与替换恢复，不包含 API Key |
| iOS 迁移 | v1 备份中的好友、私聊文本、记忆、日记、纪念日、动态文本与资料 |

Android 版尚未移植 iOS 小组件、实时活动、主动问候与通知、天气/系统工具、技能市场和自定义表情包库。iOS 备份中的群聊、附件、表情、技能和工具记录尚不支持迁移。Android 自己创建的群聊和图片消息可以随 Android 备份完整恢复。

## 朋友圈与原版素材

朋友圈总页使用自己的昵称、头像和封面；点击封面即可选图，未设置时显示渐变。点击好友头像、昵称或资料中的“朋友圈”，进入该好友的独立动态页。大肥鱼的原版背景只用于大肥鱼页面，和个人封面分别保存。

原版 Logo、三个图标变体、大肥鱼头像、好友封面与十二张 CC0 几何表情位于 `app/src/main/res/drawable-nodpi/`。自适应启动图标位于 `res/drawable/` 和 `res/mipmap-anydpi-v26/`。18 份图片的来源与 SHA-256 记录在 [`ARTWORK_SOURCES.json`](app/src/main/assets/ARTWORK_SOURCES.json)。

## 数据与凭据

- 聊天和资料保存在应用私有目录，使用原子写入；网络请求发往用户自行配置的服务商。
- API Key 通过 Android Keystore 的 AES-GCM 密钥加密，保存在 `noBackupFilesDir`，不进入手动备份。
- 自动云备份与系统设备迁移已禁用；换机时请手动导出备份并重新填写密钥。
- 恢复前在应用私有目录保存 `before-restore.zip` 回滚副本。
- Release 要求 HTTPS，不向重定向地址转发凭据；Debug 仅为本地测试允许回环 HTTP。
- 压缩备份上限 50 MB，展开总量和资料读取上限 80 MB。
- 连接测试、聊天、记忆、日记与 AI 动态均可能产生模型服务商费用。

## 从源码构建

使用 Android Studio 打开 **`android/`** 目录，选择本机 Android SDK 和 Gradle JDK，然后执行 Sync。

| 环境 | 版本 |
| --- | --- |
| JDK | 25 |
| Android SDK | API 37；应用最低 API 26 |
| Android Gradle Plugin | 9.5.1 |
| Gradle Wrapper | 9.6.0 |
| Kotlin Compose 插件 | 2.2.10 |

无需 Xcode 或 iOS 工程。通过 Android Studio 设置 SDK，或在本机配置 `ANDROID_HOME` / `local.properties`；不要提交本机 SDK 路径。

macOS / Linux：

```bash
cd android
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest :app:lintDebug
```

Windows PowerShell（`JAVA_HOME` 指向 JDK 25）：

```powershell
cd android
.\gradlew.bat :app:assembleDebug
..\build-android.ps1 -Mode check
```

Debug 安装包位于 `app/build/outputs/apk/debug/app-debug.apk`。设备测试使用模拟服务，无需真实 API Key；请在独立测试设备上运行 `:app:connectedDebugAndroidTest`。

### 自行签名 Release

公开源码不包含发布私钥。Windows 可运行 `./prepare-signing.ps1` 生成自己的签名，再运行 `./build-android.ps1 -Mode release`。其他平台可使用 JDK 的 `keytool` 创建证书，并在 `.signing/keystore.properties` 中配置：

```properties
storeFile=.signing/lumi-android.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=lumi-android
keyPassword=YOUR_KEY_PASSWORD
```

然后运行 `./gradlew :app:assembleRelease`。没有签名配置时输出未签名 Release。请妥善保存自己的私钥；自行签名的 APK 无法直接覆盖使用本仓库发布证书签名的安装包。

## 1.0.4 更新与验证

本版修复重试丢失旧回复、编辑好友覆盖关系数据、后台生成与删除/恢复冲突等问题；增加页面过渡、工具栏动画、好友搜索、聊天草稿保留、回到最新消息和图片缩放预览。

- [修复和动画说明](AUDIT-1.0.4.md)
- [验证范围、结果与限制](VALIDATION.md)

## 许可与溯源

移植参考 iOS 提交 `91a3174a152620b358b887136f163ea624e4e6f3`。自有代码沿用 [PolyForm Noncommercial License 1.0.0](LICENSE)，属于非商业许可的源码可用项目；第三方代码与独立标注素材沿用原许可。

Required Notice: Copyright (c) 2026 NakanoNino233 and Lumi contributors

图标、头像与封面的权利独立于代码许可；见仓库的 [第三方与素材声明](../THIRD_PARTY_NOTICES.md)及随包保留的 [许可副本](app/src/main/assets/ANDROID_NOTICES.md)。
