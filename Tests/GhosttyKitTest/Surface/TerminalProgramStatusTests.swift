import Foundation
import GhosttyKit
@testable import GhosttyTerminal
import Testing

/// OSC 7501 (program status) reaches a `TerminalSurfaceProgramStatusDelegate`
/// through a live surface, and the support query is answered.
@MainActor
@Suite(.serialized)
struct TerminalProgramStatusTests {
    @Test
    func `the support query is answered with the accepted states and kinds`() async {
        let harness = await GhosttySurfaceHarness.make()
        defer { harness.tearDown() }

        // Straight to the session: the harness's `receive` clears the reply.
        harness.session.receive(Data("\u{1B}]7501;?\u{1B}\\".utf8))
        let reply = String(decoding: await harness.takeOutbound(), as: UTF8.self)

        #expect(reply.contains(
            "\u{1B}]7501;?:states=idle,working,done,blocked,error:kinds=permission,question,auth\u{1B}\\",
        ))
    }

    @Test
    func `reports reach the delegate in order`() async {
        let harness = await GhosttySurfaceHarness.make()
        defer { harness.tearDown() }
        let probe = ProgramStatusProbe()
        harness.coordinator.delegate = probe

        harness.receive("\u{1B}]7501;state=working:id=sync:progress=40\u{1B}\\")
        harness.receive("\u{1B}]7501;state=blocked:kind=permission\u{07}")
        harness.receive("\u{1B}]7501;state=blocked\u{1B}\\")
        harness.receive("\u{1B}]7501;state=done\u{1B}\\")
        harness.receive("\u{1B}]7501;state=clear\u{1B}\\")

        let expected: [ProgramStatusProbe.Event] = [
            .init(state: .working, percent: 40),
            .init(state: .blocked(.permission), percent: nil),
            .init(state: .blocked(nil), percent: nil),
            .init(state: .done, percent: nil),
            .init(state: .clear, percent: nil),
        ]
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(15)
        while probe.events.count < expected.count, clock.now < deadline {
            await LifecycleStress.drainMainQueue(turns: 1)
        }
        #expect(probe.events == expected)
        withExtendedLifetime(probe) {}
    }

    @Test
    func `the bridge maps the C report, with -1 as no kind and no percent`() {
        let bridge = TerminalCallbackBridge()
        let probe = ProgramStatusProbe()
        bridge.delegate = probe

        for (state, kind, progress) in [
            (GHOSTTY_PROGRAM_STATUS_STATE_BLOCKED, Int32(GHOSTTY_PROGRAM_STATUS_KIND_AUTH.rawValue), Int8(-1)),
            (GHOSTTY_PROGRAM_STATUS_STATE_BLOCKED, -1, 70),
            (GHOSTTY_PROGRAM_STATUS_STATE_ERROR, -1, -1),
        ] {
            var action = ghostty_action_s()
            action.tag = GHOSTTY_ACTION_PROGRAM_STATUS
            action.action.program_status = ghostty_action_program_status_s(state: state, kind: kind, progress: progress)
            bridge.handleAction(action)
        }

        #expect(probe.events == [
            .init(state: .blocked(.auth), percent: nil),
            .init(state: .blocked(nil), percent: 70),
            .init(state: .error, percent: nil),
        ])
    }
}

@MainActor
private final class ProgramStatusProbe: TerminalSurfaceProgramStatusDelegate {
    struct Event: Equatable {
        let state: TerminalProgramState
        let percent: Int?
    }

    var events: [Event] = []

    func terminalDidReportProgramStatus(state: TerminalProgramState, percent: Int?) {
        events.append(.init(state: state, percent: percent))
    }
}
