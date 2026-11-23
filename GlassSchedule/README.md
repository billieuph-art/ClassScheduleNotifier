# 玻璃课表 GlassSchedule

iPhone + Apple Watch 课程表 App，基于 iOS 26 / watchOS 26 的最新框架：SwiftUI（液态玻璃 Liquid Glass）、SwiftData、Foundation Models（Apple 智能端侧大模型）、Vision、ActivityKit、App Intents、WidgetKit、WatchConnectivity。

## 功能

| 功能 | 实现 |
| --- | --- |
| 液态玻璃界面 | `glassEffect`、`GlassEffectContainer`、`.glass` / `.glassProminent` 按钮、iOS 26 TabView（滚动时收起） |
| 截图导入课表 | Vision `RecognizeTextRequest` 端侧 OCR（带坐标）→ Apple 智能 `@Generable` 结构化输出课程名、教室、教师、星期、第几节、时间、周次 |
| PDF / 文件导入 | PDF（文字层 + 逐页 OCR，扫描版也可）、图片、`.ics` 日历、CSV、TXT、HTML |
| 无 Apple 智能时 | 本地规则解析：网格课表（表头星期 × 左侧节次）与列表文字都能识别 |
| 上课前 20 分钟提醒 | 时效性通知（Time Sensitive），提醒时间可调 |
| 实时活动 | 锁屏 + 灵动岛倒计时、上课进度条；同时显示在 Apple Watch 智能叠放 |
| 照片自动归类 | 按拍摄时间匹配课程 → Vision 读取文字 → Apple 智能判断是否为板书/PPT 并生成标题、摘要、关键词 → 存入“照片”App 中「专业」文件夹 ›「课程 · 复习资料」相簿，并在“文件”App 中按 `复习资料/专业/课程/` 存副本和 `AI 复习笔记.md` |
| Siri / 快捷指令 | “今天有什么课”“开始下一节课倒计时”“整理上课照片” |
| 小组件 | 主屏幕、锁屏“下一节课”小组件 |
| Apple Watch | 今日/明日课程、下一节倒计时，离线缓存 |

所有识别都在本机完成，不上传任何数据。

## 环境要求

- 一台 Mac，安装 **Xcode 26** 或更新版本
- iPhone 需 iOS 26；Apple 智能需 iPhone 15 Pro 及以上并在设置中开启（不支持的设备会自动使用本地规则识别）
- Apple Watch 需 watchOS 26
- 上架 App Store 需要 [Apple Developer Program](https://developer.apple.com/programs/)（99 美元/年）

## 运行

```bash
brew install xcodegen
cd GlassSchedule
xcodegen generate        # 生成 GlassSchedule.xcodeproj
open GlassSchedule.xcodeproj
```

1. 全局把 `com.example.glassschedule` 替换成你自己的 Bundle ID 前缀，同时修改 `project.yml`、`Shared/Core/SharedSettings.swift`（App Group）和 `iOS/Services/BackgroundScheduler.swift`（后台任务 ID）。
2. 在 `project.yml` 的 `DEVELOPMENT_TEAM` 填入你的 Team ID（或在 Xcode 里给三个 target 选择 Team），然后重新运行 `xcodegen generate`。
3. 在 Xcode 的 Signing & Capabilities 中确认 App Group `group.<你的前缀>.glassschedule` 已在 iPhone App 与小组件中启用。
4. 连接 iPhone，选择 `GlassSchedule` scheme 运行；配对的 Apple Watch 会自动安装手表 App。

## 关于实时活动的自动开启

iOS 不允许 App 在完全没运行时自行开启实时活动（除非接入 APNs 服务器推送）。本 App 提供了以下几种方式：

- 打开 App 或后台刷新时，距上课不足 20 分钟会自动开启；
- 20 分钟提醒到达时点按“在灵动岛显示倒计时”；
- **完全自动**：在“快捷指令 > 自动化”中新建“特定时间”自动化（例如每个上课日 7:30），运行“开始下一节课的实时活动”，并关闭“运行前询问”。

如需服务器推送开启（push-to-start），可在 `LiveActivityManager` 中使用 `Activity.pushToStartTokenUpdates` 把 token 发给你的服务器。

## 发布到 App Store

1. 在 [App Store Connect](https://appstoreconnect.apple.com) 新建 App，Bundle ID 与工程一致，类别选“教育”。
2. Xcode 菜单 **Product › Archive**，完成后在 Organizer 中 **Distribute App › App Store Connect › Upload**。
3. 在 App Store Connect 中填写：
   - 截图：6.9 英寸 iPhone 与 Apple Watch 截图；
   - 隐私：工程已附带 `PrivacyInfo.xcprivacy`，“数据收集”选择“不收集数据”；
   - 审核备注：说明照片权限仅用于把上课期间拍摄的照片归类为复习资料，所有处理都在设备上完成；
   - 出口合规：已设置 `ITSAppUsesNonExemptEncryption = NO`。
4. 可先用 TestFlight 内测，再提交审核。
5. 图标：`iOS/Resources/Assets.xcassets/AppIcon.appiconset` 中有一张 1024×1024 占位图标；建议用 Xcode 26 自带的 **Icon Composer** 制作支持液态玻璃效果的分层图标后替换。

## 目录结构

```
project.yml                 XcodeGen 工程描述（iPhone App、小组件扩展、Watch App）
Shared/Core                 三个 target 共用：课程/节次/教学周计算、设置
Shared/Activity             实时活动数据结构（App + 小组件）
iOS/App                     App 入口、SwiftData 容器、统一刷新
iOS/Import                  OCR、Apple 智能课表解析、规则解析、ICS 解析
iOS/Photos                  照片匹配、Apple 智能摘要、相簿/文件归档
iOS/Services                通知、实时活动、后台任务、手表同步
iOS/Intents                 Siri 与快捷指令
iOS/Views                   液态玻璃界面
Widgets                     实时活动（锁屏/灵动岛/手表）与“下一节课”小组件
Watch                       Apple Watch App
```
