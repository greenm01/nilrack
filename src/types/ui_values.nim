import core

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
    msgTextInput
    msgResize
    msgFrameCallback
    msgAudioSnapshot
    msgPluginScanResult
    msgPluginLoaded
    msgPluginUnloaded
    msgCommand

  Msg* = object
    kind*: MsgKind
