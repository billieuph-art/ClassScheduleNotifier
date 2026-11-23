# ClassScheduleNotifier

一个面向 iPhone / Apple Watch / 灵动岛的 SwiftUI 课程提醒应用，支持：

- 课表导入（CSV / **截图 OCR** / 手动录入）
- 上课前 20 分钟本地通知
- Live Activities 实时状态
- Apple Watch 课程展示与倒计时
- 今天和本周课程视图

## 最近改进（2026-11）

- **图片导入**：使用 Vision OCR 支持中文课表截图识别，尽量提取课程名、教师、教室、周数、时间。
- **实时活动**：改进为使用系统倒计时机制，减少频繁更新。
- **通知权限**：新增设置页，「开启通知权限」按钮会正确请求权限；若被拒绝则跳转系统设置。

## 目录结构

- App/
- Models/
- Services/
  - `ImportService.swift`（含 OCR）
  - `LiveActivityController.swift`
  - `NotificationScheduler.swift`
- Views/
  - `ContentView.swift`
  - `SettingsView.swift`
  - `CourseEditorView.swift`
  - `CourseRow.swift`

## 使用说明

### 图片导入

在主界面点击左上角菜单 → 「导入课表截图」，选择从相册中的课表图片。

识别依赖本机 Vision 框架，对清晰、对比度好的中文课表截图效果较好。复杂表格可能需要手动校对。

### 通知权限

进入设置（右上角齿轮）→ 「开启通知权限」。如果之前拒绝过，会自动打开系统设置。

### Live Activities

需要在 Xcode 中为 Target 开启 Live Activities Capability，并建议添加 Widget Extension 来定义实时活动的 UI。当前代码可以正确启动活动，但完整显示依赖扩展中的 ActivityConfiguration。

## 开发环境

- Xcode 15+
- iOS 17.0+
- Swift 5.9+

## 快速开始

1. 克隆仓库
2. 用 Xcode 打开
3. 确保已开启通知与 Live Activities 相关 Capability
4. 运行到设备或模拟器
