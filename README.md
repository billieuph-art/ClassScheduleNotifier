# ClassScheduleNotifier

一个面向 iPhone / Apple Watch / 灵动岛的 SwiftUI 课程提醒应用，支持：

- 课表导入（CSV / **截图 OCR** / 手动录入）
- 上课前 20 分钟本地通知
- **Live Activities 实时状态**（已包含 Widget Extension，可在模拟器显示）
- Apple Watch 课程展示与倒计时
- 今天和本周课程视图

## 最近改进（2026-11）

- **图片导入**：使用 Vision OCR 支持中文课表截图识别。
- **实时活动**：新增 `ClassScheduleNotifierWidget` Extension，支持锁屏 + 灵动岛显示。
- **通知权限**：设置页「开启通知权限」按钮已修复。
- 课程列表每行有播放按钮，可直接启动实时活动（方便模拟器测试）。

## 在 Xcode 模拟器中运行

1. 安装 XcodeGen：`brew install xcodegen`
2. 在项目根目录执行：`xcodegen generate`
3. 打开生成的 `ClassScheduleNotifier.xcodeproj`
4. 选择 iPhone 模拟器（iOS 17+）
5. 运行主 Target `ClassScheduleNotifier`
6. 添加课程后，点击课程行右侧的播放按钮，即可在模拟器的锁屏/灵动岛看到实时活动

GitHub Actions 也会自动在 macos-15 上执行模拟器构建验证。

## 目录结构

- `ClassScheduleNotifier/` — 主 App
- `ClassScheduleNotifierWidget/` — Live Activity Widget Extension
- `project.yml` — XcodeGen 配置

## 开发环境

- Xcode 15+
- iOS 17.0+
- Swift 5.9+
