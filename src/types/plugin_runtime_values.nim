import std/atomics
import core
import audio_values

const
  MaxPluginEventThreadEvents* = 128
  MaxPluginRuntimes* = 64

type
  PluginHostCallbackFlag* = enum
    phcfRestart
    phcfProcess
    phcfCallback
    phcfLog
    phcfParam
    phcfFd
    phcfTimer
    phcfStateDirty

  PluginHostCallbackFlags* = object
    bits*: Atomic[uint32]

  PluginHostCallbackSnapshot* = object
    flags*: set[PluginHostCallbackFlag]

  PluginEventThreadEventKind* = enum
    peteClapFdRegister
    peteClapFdModify
    peteClapFdUnregister
    peteClapTimerRegister
    peteClapTimerUnregister

  PluginEventThreadEvent* = object
    kind*: PluginEventThreadEventKind
    pluginId*: PluginId
    fd*: int32
    fdFlags*: uint32
    timerId*: uint32
    periodMs*: uint32

  PluginEventThreadQueue* = RtQueue[PluginEventThreadEvent, MaxPluginEventThreadEvents]

  PluginRuntimeRef* = object
    pluginId*: PluginId
    runtime*: pointer
    ops*: pointer

  PluginRuntimeStore* = object
    count*: uint32
    runtimes*: array[MaxPluginRuntimes, PluginRuntimeRef]
    capacityExceeded*: bool
