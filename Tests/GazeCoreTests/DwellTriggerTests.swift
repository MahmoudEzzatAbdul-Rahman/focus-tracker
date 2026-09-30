import Testing
@testable import GazeCore

@Suite("DwellTrigger")
struct DwellTriggerTests {
    @Test("fires once the target has been held for the delay")
    func firesAfterDelay() {
        var trigger = DwellTrigger(delay: 0.8)

        #expect(trigger.update(targetID: 1, now: 0) == nil)
        #expect(trigger.update(targetID: 1, now: 0.5) == nil)
        #expect(trigger.update(targetID: 1, now: 0.8) == 1)
    }

    @Test("fires only once per target")
    func firesOnce() {
        var trigger = DwellTrigger(delay: 0.5)
        _ = trigger.update(targetID: 1, now: 0)
        _ = trigger.update(targetID: 1, now: 0.6)

        #expect(trigger.update(targetID: 1, now: 2) == nil)
        #expect(trigger.update(targetID: 1, now: 10) == nil)
    }

    @Test("switching target restarts the countdown")
    func switchingRestarts() {
        var trigger = DwellTrigger(delay: 0.5)
        _ = trigger.update(targetID: 1, now: 0)

        #expect(trigger.update(targetID: 2, now: 0.4) == nil)
        #expect(trigger.update(targetID: 2, now: 0.8) == nil)
        #expect(trigger.update(targetID: 2, now: 0.9) == 2)
    }

    @Test("returning to a window after looking away fires again")
    func returningFiresAgain() {
        var trigger = DwellTrigger(delay: 0.5)
        _ = trigger.update(targetID: 1, now: 0)
        _ = trigger.update(targetID: 1, now: 0.5)
        _ = trigger.update(targetID: 2, now: 1)

        #expect(trigger.update(targetID: 1, now: 1.2) == nil)
        #expect(trigger.update(targetID: 1, now: 1.7) == 1)
    }

    @Test("no target never fires")
    func noTargetNeverFires() {
        var trigger = DwellTrigger(delay: 0)

        #expect(trigger.update(targetID: nil, now: 0) == nil)
        #expect(trigger.update(targetID: nil, now: 5) == nil)
    }

    @Test("reset makes the current target count down again")
    func resetRestarts() {
        var trigger = DwellTrigger(delay: 0.5)
        _ = trigger.update(targetID: 1, now: 0)
        _ = trigger.update(targetID: 1, now: 0.5)

        trigger.reset()

        #expect(trigger.update(targetID: 1, now: 1) == nil)
        #expect(trigger.update(targetID: 1, now: 1.5) == 1)
    }
}
