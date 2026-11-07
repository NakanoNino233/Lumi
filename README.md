# Lumi

一个原生 iOS AI 好友与聊天应用。以绿色为主色，提供聊天、好友列表、朋友圈和个人资料。

[下载最新 IPA](https://github.com/NakanoNino233/Lumi/releases/latest) · [安装说明](Documentation/Installation.md) · [第三方声明](THIRD_PARTY_NOTICES.md)

## 功能

- 默认好友「大肥鱼」，支持编辑人设、头像、背景故事，以及添加、导入、导出自己的好友卡。
- 流式聊天、图片附件、语音输入、消息朗读、表情、群聊和聊天记录分享。
- 本地记忆、日记、纪念日、关系成长和可选主动问候。
- 首次进入填写个人资料卡；可在「我的」修改头像、名称、生日和星座。
- 朋友圈支持动态、评论、点赞、自定义封面和个性化标签，自己的头像随个人资料更新。
- API 配置提供 DeepSeek、ChatGPT、Claude 和自定义模板，地址、模型名称和能力开关均可修改。
- Token 用量统计、主题、深色模式、中英文、小组件、实时活动、备份与恢复。

模板中的模型名称需要与你的服务商账号实际可用模型一致。需要自行提供 API Key；本项目不提供模型额度。模型调用、自动记忆和连接测试可能产生服务商费用。

## 下载与安装

在 [Releases](https://github.com/NakanoNino233/Lumi/releases/latest) 下载 `Lumi-unsigned.ipa`；同页提供 SHA-256 校验文件。

**发布包未签名，需要用自己的签名工具签名后安装。** 最低系统为 iOS 17。包中包含 `LumiWidgets` 扩展；小组件与实时活动需要保留该扩展。

安装和续签请参阅 [安装说明](Documentation/Installation.md)。更新前建议在 App 内导出备份。

## 从源码运行

使用 Xcode 26 或更高版本打开 `Lumi.xcodeproj`，选择 `Lumi` scheme 和 iPhone 模拟器运行。项目使用 Swift 6、SwiftUI 和 SwiftData，ZIPFoundation 作为本地依赖随仓库提供。

真机运行时，在主程序和 `LumiWidgets` 的 Signing & Capabilities 中选择自己的开发团队，并按需要修改两个目标的 Bundle Identifier。

首次进入填写资料后，可以先浏览。要使用 AI 回复，在「我的 → 设置 → API 配置」填写服务商地址、模型和自己的 API Key，测试连接并保存。

在项目根目录生成未签名 IPA：

```bash
bash Distribution/build-unsigned.sh
```

输出位于 `Distribution/output/`。源码仓库忽略安装包、构建缓存、本机测试报告、用户配置与签名文件；IPA 通过 GitHub Release 发布。

## 数据与隐私

聊天、资料、记忆和偏好保存在本机，API Key 存在系统钥匙串中。聊天请求会将相应内容发送至你配置的服务商；自动记忆和日记也会使用相关历史。天气等可选功能需另行开启或授权。

备份包含个人资料和聊天内容，不含 API Key。请自行保管备份，并在提交问题或截图时隐藏私人信息。

## 测试与自动构建

在 Xcode 中使用 Product → Test。自动测试使用本地模拟响应，不需要真实模型 Key。

仓库提供「Build Lumi unsigned IPA」工作流，可在 Actions 中手动运行；推送 `v` 开头的标签时会构建并发布对应 Release。首次 `1.0.0` Release 使用本机验证的安装包。

模型回复效果、真机语音/触感、小组件展示及安装续签体验仍需在实际设备和服务商环境中验证。

## 许可与贡献

项目代码采用 [MIT License](LICENSE)。第三方依赖保留原许可证，详见 [第三方声明](THIRD_PARTY_NOTICES.md)。

应用图标、人物头像、朋友圈图片等用户提供的视觉素材不随代码授予 MIT 许可；它们的权利属于各自权利人。复用或再分发这些素材前，请自行取得授权或替换为自己的素材。

欢迎通过 Issues 反馈可复现的问题，或提交 Pull Request。请附系统版本、复现步骤及去除私人信息的截图。
