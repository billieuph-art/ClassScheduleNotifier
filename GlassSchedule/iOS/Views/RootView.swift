import SwiftUI

struct RootView: View {
    @AppStorage("hasOnboarded", store: SharedSettings.defaults) private var hasOnboarded = false

    var body: some View {
        TabView {
            Tab("今天", systemImage: "sun.max") { TodayView() }
            Tab("课表", systemImage: "calendar") { WeekView() }
            Tab("复习资料", systemImage: "photo.stack") { MaterialsView() }
            Tab("设置", systemImage: "gearshape") { SettingsView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: Binding(get: { !hasOnboarded }, set: { if !$0 { hasOnboarded = true } })) {
            OnboardingView { hasOnboarded = true }
                .interactiveDismissDisabled()
        }
    }
}

struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var working = false

    var body: some View {
        ZStack {
            GlassBackground()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 64))
                    .padding(28)
                    .glassEffect(.regular.interactive(), in: .circle)
                Text("玻璃课表").font(.largeTitle.bold())
                GlassEffectContainer(spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        feature("doc.viewfinder", "截图或 PDF 一键导入课表", "Apple 智能自动识别课程、教室、节次")
                        feature("bell.badge", "上课前 20 分钟提醒", "实时活动在锁屏与灵动岛倒计时")
                        feature("photo.stack", "上课照片自动归档", "按专业与课程整理成复习资料")
                        feature("iphone.gen3", "锁屏实时活动", "上课倒计时显示在灵动岛")
                    }
                }
                Spacer()
                Button {
                    working = true
                    Task {
                        await NotificationScheduler.shared.requestAuthorization()
                        _ = await PhotoLibraryService.requestAccess()
                        working = false
                        onFinish()
                    }
                } label: {
                    Text(working ? "请稍候…" : "开始使用").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .disabled(working)
            }
            .padding(24)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).frame(width: 36)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
