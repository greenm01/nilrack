import std/options

import ../state/engine
import action_log
import effect_queue
import param_mapping
import ui_hit_test

const MaxUpdateCommands* = 64

type
  UpdateCommandKind* = enum
    uckResize
    uckClose
    uckEnqueueParamValue
    uckPublishProcessPlan

  UpdateCommand* = object
    case kind*: UpdateCommandKind
    of uckResize:
      width*, height*: int32
    of uckEnqueueParamValue:
      pluginId*: PluginId
      paramId*: ParamId
      normalizedValue*: float64
    else:
      discard

  UpdateCommandQueue* = object
    count*: uint32
    entries*: array[MaxUpdateCommands, UpdateCommand]
    overflowed*: bool

proc pushUpdateCommand*(queue: var UpdateCommandQueue, command: UpdateCommand): bool =
  if queue.count >= MaxUpdateCommands.uint32:
    queue.overflowed = true
    return false
  queue.entries[queue.count.int] = command
  inc queue.count
  true

proc popUpdateCommand*(
    queue: var UpdateCommandQueue, command: var UpdateCommand
): bool =
  if queue.count == 0:
    return false
  command = queue.entries[0]
  let last = queue.count.int - 1
  for i in 0 ..< last:
    queue.entries[i] = queue.entries[i + 1]
  queue.entries[last] = UpdateCommand()
  dec queue.count
  true

proc dispatchMsg*(
    model: var NilrackModel,
    committedActions: var ActionLog,
    effects: var EffectQueue,
    commands: var UpdateCommandQueue,
    msg: Msg,
) =
  discard committedActions.recordCommittedAction(msg)
  discard effects.routeMsgEffects(msg)
  case msg.kind
  of msgResize:
    discard commands.pushUpdateCommand(
      UpdateCommand(kind: uckResize, width: msg.resizeW, height: msg.resizeH)
    )
  of msgKeyPress:
    if msg.keyCode == 1:
      discard commands.pushUpdateCommand(UpdateCommand(kind: uckClose))
  of msgPointerButton:
    if not msg.btnPressed:
      return
    let paramHit = model.paramSliderHitAt(msg.btnX, msg.btnY)
    if paramHit.isSome:
      let hit = paramHit.get
      model.paramSetNormalized(hit.paramId, hit.normalizedValue.float64)
      let param = model.paramData(hit.paramId)
      if param.isSome:
        let pluginId = model.pluginForNode(param.get.nodeId)
        if pluginId.isSome:
          discard commands.pushUpdateCommand(
            UpdateCommand(
              kind: uckEnqueueParamValue,
              pluginId: pluginId.get,
              paramId: hit.paramId,
              normalizedValue: hit.normalizedValue.float64,
            )
          )
    else:
      let bypassNode = model.bypassToggleAt(msg.btnX, msg.btnY)
      if bypassNode.isSome:
        model.nodeToggleBypass(bypassNode.get)
        discard effects.enqueueProcessPlanDirty(NullRackId)
        discard commands.pushUpdateCommand(UpdateCommand(kind: uckPublishProcessPlan))
  else:
    discard
