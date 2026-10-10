import SwiftUI

struct GameRootView: View {
    @StateObject private var session = GameSession()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ZStack {
            if let scene = session.scene {
                GameViewport(scene: scene).ignoresSafeArea()
                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("守护者 · 等级 1").font(.headline)
                            Text("生命 \(session.snapshot?.hp ?? 100) / 100 · 法力 50 / 50")
                            ProgressView(value: Double(session.snapshot?.hp ?? 100), total: 100).tint(.green).frame(width: 220)
                            Text("已击败 \(session.snapshot?.kills ?? 0) 只野狼").font(.callout)
                            if session.debugVisible, let snapshot = session.snapshot {
                                Text("坐标 \(snapshot.position.column, specifier: "%.2f"), \(snapshot.position.row, specifier: "%.2f")")
                                Text("目标 \(snapshot.targetID ?? "无") · \(snapshot.targetPhase ?? "idle")")
                                Text("存活怪物 \(snapshot.enemyCount) · 路径节点 \(snapshot.pathNodes)")
                            }
                        }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            Text("测试营地 · 战斗试炼").font(.headline)
                            if let snapshot = session.snapshot, let name = snapshot.targetName {
                                Text("\(name) · HP \(snapshot.targetHP ?? 0)")
                            } else { Text("未选择目标").foregroundStyle(.secondary) }
                            Button("暂停 · Esc") { session.paused = true }
                        }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Spacer()
                    VStack(spacing: 6) {
                        Text(session.snapshot?.status ?? "").font(.headline)
                        Text("WASD 移动 · 点击野狼接近并斩击 · 按住空格持续普攻 · Esc 暂停").font(.callout)
                    }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }.padding(20).allowsHitTesting(!session.paused)
                if session.snapshot?.hp == 0 {
                    modal(title: "守护者倒下了", detail: "返回营地后恢复全部生命与法力。", button: "返回营地复活") { session.revive() }
                }
                if session.paused {
                    modal(title: "游戏已暂停", detail: "战斗和怪物刷新计时已停止。", button: "继续游戏") { session.paused = false }
                }
            } else {
                VStack { Text("配置加载失败").font(.title); Text(session.errorMessage ?? "未知错误").textSelection(.enabled) }.padding(32)
            }
        }
        .onChange(of: scenePhase) { _, phase in session.setActive(phase == .active) }
        .onAppear { session.setActive(scenePhase == .active) }
    }
    private func modal(title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(title).font(.title.bold())
                Text(detail)
                Button(button, action: action).buttonStyle(.borderedProminent)
            }.padding(36).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
