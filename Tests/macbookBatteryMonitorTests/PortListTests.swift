import Foundation

struct PortListTests {
    /// lsof -F 的輸出：每個程式一段，同一個連接埠的 IPv4／IPv6 只列一次，依連接埠排序
    func testParse() {
        let text = """
        p300
        cexample-server
        u501
        f10
        n*:8080
        f11
        n*:8080
        p120
        cdevtool
        u501
        f7
        n127.0.0.1:3000
        f8
        n[::1]:3000
        f9
        n127.0.0.1:9229
        """
        XCTAssertEqual(PortList.parse(text), [
            PortList.Listener(pid: 120, command: "devtool", uid: 501, port: 3000, localOnly: true),
            PortList.Listener(pid: 300, command: "example-server", uid: 501, port: 8080, localOnly: false),
            PortList.Listener(pid: 120, command: "devtool", uid: 501, port: 9229, localOnly: true),
        ])
    }

    /// 壞掉或空的輸出不會當掉
    func testParseGarbage() {
        XCTAssertEqual(PortList.parse(""), [])
        XCTAssertEqual(PortList.parse("pabc\nnno-port\nn*:\n"), [])
    }

    /// 只能結束自己帳號的程式；不能結束 PID 1 以下、也不能結束自己
    func testCanTerminate() {
        XCTAssertTrue(PortList.canTerminate(pid: 300, uid: 501, myUID: 501, myPID: 999))
        XCTAssertTrue(!PortList.canTerminate(pid: 300, uid: 0, myUID: 501, myPID: 999))
        XCTAssertTrue(!PortList.canTerminate(pid: 999, uid: 501, myUID: 501, myPID: 999))
        XCTAssertTrue(!PortList.canTerminate(pid: 1, uid: 501, myUID: 501, myPID: 999))
        XCTAssertTrue(!PortList.canTerminate(pid: 0, uid: 501, myUID: 501, myPID: 999))
    }
}
