import Foundation

// 使用生产 TrafficLogic（由 run_tests.sh 一并编译），禁止双份拷贝

@main
struct TrafficLogicTestRunner {
    static func main() {
        var failed = 0
        func expect(_ cond: Bool, _ msg: String) {
            if cond {
                print("  PASS \(msg)")
            } else {
                print("  FAIL \(msg)")
                failed += 1
            }
        }

        print("== 接口选择 ==")
        expect(
            TrafficLogic.resolveCountedInterface(selected: "en1", primaryHint: "en0", wifiBSD: "en0", activeEnInterfaces: ["en0", "en1"]) == "en1",
            "手动选择优先"
        )
        expect(
            TrafficLogic.resolveCountedInterface(selected: "", primaryHint: "en0", wifiBSD: "en0", activeEnInterfaces: ["en0", "en2"]) == "en0",
            "自动用 primaryHint"
        )
        expect(
            TrafficLogic.resolveCountedInterface(selected: "", primaryHint: nil, wifiBSD: "en0", activeEnInterfaces: ["en2", "en0"]) == "en0",
            "primary 空时优先 Wi‑Fi BSD"
        )
        expect(
            TrafficLogic.resolveCountedInterface(selected: "", primaryHint: nil, wifiBSD: nil, activeEnInterfaces: ["en2", "en5"]) == "en2",
            "否则取第一个活跃 en*"
        )
        expect(
            TrafficLogic.resolveCountedInterface(selected: "", primaryHint: nil, wifiBSD: nil, activeEnInterfaces: []) == nil,
            "无候选返回 nil"
        )
        let one = TrafficLogic.resolveCountedInterface(selected: "", primaryHint: nil, wifiBSD: nil, activeEnInterfaces: ["en0", "en1", "en2"])
        expect(one == "en0", "自动模式只返回单接口而非全加")

        print("== 首样本丢弃 ==")
        expect(TrafficLogic.shouldDiscardFirstSample(isReady: false) == true, "未就绪丢弃")
        expect(TrafficLogic.shouldDiscardFirstSample(isReady: true) == false, "已就绪不丢弃")

        print("== 休眠长间隔 ==")
        expect(TrafficLogic.shouldDiscardSpeedForLongInterval(31) == true, ">30s 丢速率")
        expect(TrafficLogic.shouldDiscardSpeedForLongInterval(30) == false, "30s 边界不丢")
        expect(TrafficLogic.shouldDiscardSpeedForLongInterval(2) == false, "正常间隔不丢")
        expect(TrafficLogic.shouldIgnoreShortInterval(0.01) == true, "过短忽略")
        expect(TrafficLogic.shouldIgnoreShortInterval(1.0) == false, "正常不忽略")

        print("== 跨日归档 ==")
        expect(TrafficLogic.shouldArchiveForNewDay(lastResetDate: "2026-11-04", today: "2026-11-05") == true, "日期变化需归档")
        expect(TrafficLogic.shouldArchiveForNewDay(lastResetDate: "2026-11-05", today: "2026-11-05") == false, "同日不归档")
        expect(TrafficLogic.shouldArchiveForNewDay(lastResetDate: nil, today: "2026-11-05") == false, "无上次日期不归档")

        print("== 增量/速度 ==")
        expect(TrafficLogic.delta(current: 100, previous: 40) == 60, "正常增量")
        expect(TrafficLogic.delta(current: 10, previous: 40) == 0, "回绕归零")
        expect(TrafficLogic.delta(current: 10, previous: nil) == 0, "无基线零增量")
        expect(abs(TrafficLogic.speed(bytes: 2048, interval: 2.0) - 1024.0) < 0.001, "速度计算")

        if failed == 0 {
            print("\nALL TESTS PASSED")
            exit(0)
        } else {
            print("\n\(failed) TEST(S) FAILED")
            exit(1)
        }
    }
}
