import std/unittest

import ../src/systems/action_log
import ../src/types/ui_values

suite "action log":
  test "records committed user actions only":
    var log: ActionLog

    check not log.recordCommittedAction(
      Msg(kind: msgPointerMotion, motionX: 1, motionY: 2)
    )
    check not log.recordCommittedAction(
      Msg(kind: msgResize, resizeW: 640, resizeH: 480)
    )
    check log.recordCommittedAction(Msg(kind: msgCommand))

    check log.count == 1
    check log.latestAction().generation == 1
    check log.latestAction().msg.kind == msgCommand

  test "bounded log overwrites oldest entries":
    var log: ActionLog

    for i in 0 ..< MaxActionLogEntries + 1:
      check log.recordCommittedAction(Msg(kind: msgCommand))

    check log.count == MaxActionLogEntries.uint32
    check log.nextGeneration == (MaxActionLogEntries + 1).uint64
    check log.overflowed
    check log.latestAction().generation == (MaxActionLogEntries + 1).uint64
