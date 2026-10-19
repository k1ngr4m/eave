import XCTest
import PowerHelperProtocol
@testable import EavePowerHelper

final class PowerModeServiceTests: XCTestCase {
    func testWriteOnlySucceedsWhenTheReadbackConfirmsIt() {
        for observed in [true, false, nil] as [Bool?] {
            let service = PowerModeService(runner: FixedPmsetRunner(observed: observed))
            var replied = false
            service.setLowPowerMode(true) { value, error in
                replied = true
                XCTAssertEqual(error == nil, observed == true)
                if error == nil { XCTAssertTrue(value) }
            }
            XCTAssertTrue(replied)
        }
        XCTAssertNil(LowPowerModeCommand.parseEnabled(fromPmsetOutput: "lowpowermode unknown"))
        XCTAssertNil(LowPowerModeCommand.parseEnabled(fromPmsetOutput: "powermode 42"))
        XCTAssertEqual(LowPowerModeCommand.parseEnabled(fromPmsetOutput: "powermode 2"), false)
    }

    func testFailedWriteReturnsAnError() {
        let service = PowerModeService(runner: FixedPmsetRunner(observed: false, fails: true))
        service.setLowPowerMode(true) { _, error in XCTAssertNotNil(error) }
    }
}

private struct FixedPmsetRunner: PmsetRunning {
    let observed: Bool?
    var fails = false
    func setLowPowerMode(enabled: Bool) throws {
        if fails { throw PmsetError.nonZeroExit(1) }
    }
    func currentLowPowerMode() -> Bool? { observed }
}
