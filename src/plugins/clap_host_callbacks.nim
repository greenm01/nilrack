import std/atomics

import ../types/[core, plugin_runtime_values]
import clap_api
import host_callbacks
import plugin_event_thread_queue

type
  ClapHostRuntime* = object
    callbacks*: PluginHostCallbackFlags
    eventQueue*: PluginEventThreadQueue
    pluginId*: PluginId
    nextTimerId*: Atomic[uint32]
    fdSupport*: ClapHostPosixFdSupport
    timerSupport*: ClapHostTimerSupport

  ClapHostBox* = ref object
    runtime*: ClapHostRuntime
    host*: ClapHost

proc cstringEquals(value: cstring, expected: string): bool =
  if value.isNil:
    return false
  for i in 0 ..< expected.len:
    if value[i] != expected[i]:
      return false
  value[expected.len] == '\0'

proc hostRuntime(host: ptr ClapHost): ptr ClapHostRuntime =
  if host.isNil or host.hostData.isNil:
    return nil
  cast[ptr ClapHostRuntime](host.hostData)

proc hostGetExtension(host: ptr ClapHost, extensionId: cstring): pointer {.cdecl.} =
  let runtime = hostRuntime(host)
  if runtime.isNil:
    return nil
  if extensionId.cstringEquals(ClapExtPosixFdSupport):
    return addr runtime.fdSupport
  if extensionId.cstringEquals(ClapExtTimerSupport):
    return addr runtime.timerSupport
  nil

proc hostRequestRestart(host: ptr ClapHost) {.cdecl.} =
  let runtime = hostRuntime(host)
  if not runtime.isNil:
    runtime.callbacks.markPluginHostCallback(phcfRestart)

proc hostRequestProcess(host: ptr ClapHost) {.cdecl.} =
  let runtime = hostRuntime(host)
  if not runtime.isNil:
    runtime.callbacks.markPluginHostCallback(phcfProcess)

proc hostRequestCallback(host: ptr ClapHost) {.cdecl.} =
  let runtime = hostRuntime(host)
  if not runtime.isNil:
    runtime.callbacks.markPluginHostCallback(phcfCallback)

proc hostRegisterFd(host: ptr ClapHost, fd: cint, flags: uint32): bool {.cdecl.} =
  let runtime = hostRuntime(host)
  if runtime.isNil:
    return false
  runtime.eventQueue.enqueuePluginEventThreadEvent(
    PluginEventThreadEvent(
      kind: peteClapFdRegister, pluginId: runtime.pluginId, fd: fd.int32, fdFlags: flags
    )
  )

proc hostModifyFd(host: ptr ClapHost, fd: cint, flags: uint32): bool {.cdecl.} =
  let runtime = hostRuntime(host)
  if runtime.isNil:
    return false
  runtime.eventQueue.enqueuePluginEventThreadEvent(
    PluginEventThreadEvent(
      kind: peteClapFdModify, pluginId: runtime.pluginId, fd: fd.int32, fdFlags: flags
    )
  )

proc hostUnregisterFd(host: ptr ClapHost, fd: cint): bool {.cdecl.} =
  let runtime = hostRuntime(host)
  if runtime.isNil:
    return false
  runtime.eventQueue.enqueuePluginEventThreadEvent(
    PluginEventThreadEvent(
      kind: peteClapFdUnregister, pluginId: runtime.pluginId, fd: fd.int32
    )
  )

proc hostRegisterTimer(
    host: ptr ClapHost, periodMs: uint32, timerId: ptr ClapId
): bool {.cdecl.} =
  let runtime = hostRuntime(host)
  if runtime.isNil or timerId.isNil:
    return false
  let id = runtime.nextTimerId.fetchAdd(1'u32, moRelaxed) + 1'u32
  timerId[] = id
  runtime.eventQueue.enqueuePluginEventThreadEvent(
    PluginEventThreadEvent(
      kind: peteClapTimerRegister,
      pluginId: runtime.pluginId,
      timerId: id,
      periodMs: periodMs,
    )
  )

proc hostUnregisterTimer(host: ptr ClapHost, timerId: ClapId): bool {.cdecl.} =
  let runtime = hostRuntime(host)
  if runtime.isNil:
    return false
  runtime.eventQueue.enqueuePluginEventThreadEvent(
    PluginEventThreadEvent(
      kind: peteClapTimerUnregister, pluginId: runtime.pluginId, timerId: timerId
    )
  )

proc initClapHostRuntime*(runtime: var ClapHostRuntime) =
  runtime.callbacks.initPluginHostCallbackFlags()
  runtime.pluginId = NullPluginId
  runtime.nextTimerId.store(0'u32, moRelaxed)
  runtime.fdSupport = ClapHostPosixFdSupport(
    registerFd: hostRegisterFd, modifyFd: hostModifyFd, unregisterFd: hostUnregisterFd
  )
  runtime.timerSupport = ClapHostTimerSupport(
    registerTimer: hostRegisterTimer, unregisterTimer: hostUnregisterTimer
  )

proc newClapHostBox*(): ClapHostBox =
  result = ClapHostBox()
  result.runtime.initClapHostRuntime()
  result.host = ClapHost(
    clapVersion: clapVersion(),
    hostData: addr result.runtime,
    name: "nilrack",
    vendor: "niltempus",
    url: "",
    version: "0.1.0",
    getExtension: hostGetExtension,
    requestRestart: hostRequestRestart,
    requestProcess: hostRequestProcess,
    requestCallback: hostRequestCallback,
  )

proc bindClapHostPluginId*(hostBox: ClapHostBox, pluginId: PluginId) =
  if hostBox.isNil:
    return
  hostBox.runtime.pluginId = pluginId

proc popClapHostBoxEvent*(
    hostBox: ClapHostBox, event: var PluginEventThreadEvent
): bool =
  if hostBox.isNil:
    return false
  hostBox.runtime.eventQueue.dequeuePluginEventThreadEvent(event)
