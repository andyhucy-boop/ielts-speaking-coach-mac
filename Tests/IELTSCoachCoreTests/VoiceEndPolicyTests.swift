import XCTest
@testable import IELTSCoachCore

final class VoiceEndPolicyTests: XCTestCase {
    func testDoesNotFinalizeWhileVoiceActive() {
        let state = VoiceEndPolicy.advance(
            previous: VoiceEndState(), voiceActive: true, busy: false)
        XCTAssertFalse(state.shouldFinalize)
    }

    func testFinalizesAfterThreeInactiveTicksOnceSeenActive() {
        var state = VoiceEndPolicy.advance(
            previous: VoiceEndState(), voiceActive: true, busy: false)
        XCTAssertTrue(state.seenActive)

        for _ in 0..<3 {
            state = VoiceEndPolicy.advance(previous: state, voiceActive: false, busy: false)
        }
        XCTAssertTrue(state.shouldFinalize)
        XCTAssertEqual(state.reason, "voice-indicator-gone")
        XCTAssertEqual(state.inactiveTicks, 3)
    }

    func testDebounceResetsInactiveTicksWhenVoiceReturnsBrieflyActive() {
        var state = VoiceEndPolicy.advance(
            previous: VoiceEndState(), voiceActive: true, busy: false)

        // Two inactive ticks, then voice becomes active again — should reset the debounce.
        state = VoiceEndPolicy.advance(previous: state, voiceActive: false, busy: false)
        state = VoiceEndPolicy.advance(previous: state, voiceActive: false, busy: false)
        XCTAssertEqual(state.inactiveTicks, 2)

        state = VoiceEndPolicy.advance(previous: state, voiceActive: true, busy: false)
        XCTAssertEqual(state.inactiveTicks, 0)
        XCTAssertFalse(state.shouldFinalize)
    }

    func testBusySuppressesFinalizationUntilCleared() {
        var state = VoiceEndPolicy.advance(
            previous: VoiceEndState(), voiceActive: true, busy: false)
        XCTAssertTrue(state.seenActive)

        // While busy, ticks must not accumulate and finalize must stay suppressed,
        // no matter how many polls happen.
        for _ in 0..<5 {
            state = VoiceEndPolicy.advance(previous: state, voiceActive: false, busy: true)
        }
        XCTAssertFalse(state.shouldFinalize, "busy 应当抑制 finalize")
        XCTAssertEqual(state.inactiveTicks, 0, "busy 期间去抖计数不应累积")

        // Once busy clears, the debounce accumulates normally toward finalize.
        for _ in 0..<3 {
            state = VoiceEndPolicy.advance(previous: state, voiceActive: false, busy: false)
        }
        XCTAssertTrue(state.shouldFinalize, "busy 清除后应能正常判定 finalize")
        XCTAssertEqual(state.reason, "voice-indicator-gone")
    }

    func testNeverFinalizesWhenVoiceWasNeverSeenActive() {
        var state = VoiceEndState()
        for _ in 0..<8 {
            state = VoiceEndPolicy.advance(previous: state, voiceActive: false, busy: false)
        }
        XCTAssertFalse(state.shouldFinalize)
        XCTAssertFalse(state.seenActive)
        XCTAssertEqual(state.inactiveTicks, 0)
    }
}
