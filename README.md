# ClassScheduleNotifier

一个面向 iPhone / Apple Watch / 灵动岛的 SwiftUI 课程提醒应用原型，支持：

- 课表导入（CSV / ICS / 手动录入）
- 上课前 20 分钟本地通知
- Live Activities 实时状态
- Apple Watch 课程展示与倒计时
- 今天和本周课程视图

本仓库是一个可以直接导入 Xcode 的 SwiftUI 架构骨架，包含核心模型、导入逻辑、通知调度和 Apple 生态展示层代码。

## 目录结构

- App/
  - `ClassScheduleNotifierApp.swift`
- Models/
  - `Course.swift`
- Services/
  - `ScheduleStore.swift`
  - `ImportService.swift`
  - `NotificationScheduler.swift`
  - `LiveActivityController.swift`
  - `WatchSyncService.swift`
- Views/
  - `ContentView.swift`

## 功能说明

### 1. 课表导入

支持以下导入方式：

- `.csv` 文件导入
- `.ics` 日历文件导入
- 手动录入课程

可在 `ImportService.swift` 中扩展 HTML / 学校导出格式解析。

### 2. 提前 20 分钟提醒

`NotificationScheduler` 会在每次课程更新后重建通知，并在课程开始前 20 分钟触发系统本地通知。

### 3. 实时活动（Live Activities）

`LiveActivityController` 会在 iPhone 锁屏 / 灵动岛区域展示下一节课状态：

- 课程名
- 地点
- 倒计时
- 当前状态（即将开始 / 上课中 / 已结束）

### 4. Apple Watch 显示

`WatchSyncService` 负责同步下一节课信息到 Apple Watch，并在 watchOS 端展示课程状态与倒计时。

## 开发环境

- Xcode 15+
- iOS 17.0+
- watchOS 10.0+
- Swift 5.9+

## 快速开始

1. 在 GitHub 中克隆本仓库
2. 用 Xcode 打开项目目录
3. 新建一个 iOS + watchOS App Target
4. 将 `App/`、`Models/`、`Services/`、`Views/` 下的文件复制到新项目中
5. 配置通知权限和 Live Activities Capability
6. 运行到 iPhone / Apple Watch 模拟器

## 重点实现说明

- `Course` 数据模型：代表一节课
- `ScheduleStore`：本地存储 & 数据更新
- `ImportService`：负责解析 `.csv` / `.ics`
- `NotificationScheduler`：用于 20 分钟前通知
- `LiveActivityController`：用于灵动岛与锁屏显示
- `WatchSyncService`：用于 watchOS 实时同步

## 适合扩展的方向

- 支持学校官网导出格式解析
- 支持课程变更自动更新通知
- 支持 `WidgetKit` 小组件
- 支持课表周次切换
- 支持周末课程 / 节假日调课

## 备注

这是一个完整的工程思路与代码骨架，不依赖在线后端即可运行。如果你需要，我下一步可以继续把它扩展成：

- 完整可运行的 Xcode 项目结构
- Apple Watch target 代码
- Live Activities 扩展代码
- 真实 CSV / ICS 导入实现

