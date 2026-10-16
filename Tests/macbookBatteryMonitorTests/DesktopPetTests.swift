import Foundation

struct DesktopPetTests {
    /// 想像框：電量與狀態，有智慧充電時加一行排程
    func testThoughtShowsStateAndPlan() {
        var s = DesktopPetStatus(percent: 62, state: .charging)
        s.minutesToFull = 36
        s.limit = 80
        XCTAssertEqual(DesktopPetMessages.thought(s), "62%・充電中，36 分鐘後到 80%")
        s.limit = nil
        s.minutesToFull = 95
        XCTAssertEqual(DesktopPetMessages.thought(s), "62%・充電中，1 小時 35 分後充滿")
        var battery = DesktopPetStatus(percent: 78, state: .discharging)
        battery.minutesToEmpty = 445
        XCTAssertEqual(DesktopPetMessages.thought(battery), "78%・還能用 7 小時 25 分")
        battery.minutesToEmpty = nil
        XCTAssertEqual(DesktopPetMessages.thought(battery), "78%・使用電池中")
        var plan = DesktopPetStatus(percent: 80, state: .limitReached)
        plan.planTitle = "等待開始"
        plan.planDetail = "明天 5:54 開始充電，明天 7:30 前到 95%"
        XCTAssertEqual(DesktopPetMessages.thought(plan), "80%・已達充電上限，用變壓器供電\n等待開始：明天 5:54 開始充電，明天 7:30 前到 95%")
    }

    /// 點一下的對話：心情在第一句，之後是今天、健康度、耗電；沒有資料的那句不出現
    func testSayingsFollowMoodAndData() {
        var low = DesktopPetStatus(percent: 8, state: .discharging)
        XCTAssertEqual(DesktopPetMessages.sayings(low), ["快沒電了！拜託快接上電源"])
        low.percent = 18
        XCTAssertEqual(DesktopPetMessages.mood(low), "肚子有點餓，記得幫我充電")
        low.percent = 55
        XCTAssertEqual(DesktopPetMessages.mood(low), "陪你一起努力，還有 55%")
        var drainingOnAC = DesktopPetStatus(percent: 15, state: .pluggedIdle)
        drainingOnAC.drainingOnAC = true
        XCTAssertEqual(DesktopPetMessages.mood(drainingOnAC), "肚子有點餓，記得幫我充電")
        var full = DesktopPetStatus(percent: 95, state: .limitReached)
        full.usedToday = 14
        full.chargedToday = 3
        full.healthPercent = 92
        full.cycleCount = 212
        full.systemWatts = 6.5
        XCTAssertEqual(DesktopPetMessages.sayings(full), ["吃飽了，現在靠變壓器供電", "今天用掉 14%，補回 3%",
                                                         "電池健康度 92%，充過 212 次", "現在整台 Mac 用了 6.5 W"])
        var waiting = DesktopPetStatus(percent: 80, state: .limitReached)
        waiting.planWaiting = true
        waiting.planDetail = "5:54 開始充電，7:30 前到 95%"
        XCTAssertEqual(DesktopPetMessages.mood(waiting), "我先睡一下，5:54 開始充電，7:30 前到 95%")
        waiting.planReady = true
        XCTAssertEqual(DesktopPetMessages.mood(waiting), "準備好了，隨時可以出門！")
        XCTAssertEqual(DesktopPetMessages.mood(DesktopPetStatus(percent: 60, state: .charging)), "充電中，好溫暖～")
    }
}
