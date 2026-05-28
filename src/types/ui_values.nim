import core
import diagnostic_values

type
  InputTargetEntry* = object
    id*: InputTargetId
    x*, y*, w*, h*: float32

  InputTargetList* = object
    entries*: seq[InputTargetEntry]

  MsgKind* = enum
    msgNoop
    msgPointerMotion
    msgPointerButton
    msgPointerScroll
    msgKeyPress
    msgKeyRelease
    msgResize
    msgFrameCallback
    msgAudioSnapshot
    msgPluginScanResult
    msgPluginLoaded
    msgPluginUnloaded
    msgCommand

  Msg* = object
    case kind*: MsgKind
    of msgPointerMotion:
      motionX*, motionY*: float32
    of msgPointerButton:
      btnButton*: uint32
      btnPressed*: bool
      btnX*, btnY*: float32
    of msgPointerScroll:
      scrollAxis*: uint32
      scrollValue*: float32
    of msgKeyPress, msgKeyRelease:
      keyCode*: uint32
    of msgResize:
      resizeW*, resizeH*: int32
    of msgAudioSnapshot:
      diagnostics*: RuntimeDiagnosticsSnapshot
    else:
      discard
