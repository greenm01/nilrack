import ../types/ui_values

proc isCommittedUserAction*(msg: Msg): bool =
  case msg.kind
  of msgCommand, msgPluginLoaded, msgPluginUnloaded: true
  else: false

proc recordCommittedAction*(log: var ActionLog, msg: Msg): bool =
  if not msg.isCommittedUserAction():
    return false

  inc log.nextGeneration
  log.entries[log.writeIndex.int] =
    ActionLogEntry(generation: log.nextGeneration, msg: msg)
  log.writeIndex = (log.writeIndex + 1) mod MaxActionLogEntries.uint32
  if log.count < MaxActionLogEntries.uint32:
    inc log.count
  else:
    log.overflowed = true
  true

proc latestAction*(log: ActionLog): ActionLogEntry =
  if log.count == 0:
    return ActionLogEntry()
  let index =
    if log.writeIndex == 0:
      MaxActionLogEntries - 1
    else:
      log.writeIndex.int - 1
  log.entries[index]
