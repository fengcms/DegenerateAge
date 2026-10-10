# 项目协作规则

- 开始修改前完整阅读 `docs/GDD.md`，它是首版需求基线。
- 每轮只实现一个可验收功能集合，说明涉及的文件与风险。P0/P1 已交付，下一阶段为 P2；不要一次实现整章。
- Core 规则、Data 配置、Persistence 存档模型与 SpriteKit / SwiftUI 分离。
- 随机规则使用可注入种子；业务规则变更需有有效验证。
- 使用占位资产；阶段功能必须实际运行，不能以截图代替可玩实现。
- 不为后期系统引入大型抽象、服务端或无关依赖。
- 系统 API 不确定时先验证最小样例。
- 完成后报告构建、检查、手动验收步骤与遗留风险。
- 本机只有 Command Line Tools：构建 `swift build`，规则检查 `swift run RuleChecks`，打包 `./scripts/build-app.sh`。
- 安装完整 Xcode 后将规则检查迁入 XCTest / Swift Testing；目前不要声称 `swift test` 已通过。
