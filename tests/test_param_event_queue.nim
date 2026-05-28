import std/unittest

import ../src/audio/[callback_diagnostics, param_event_queue]
import ../src/systems/graph_process_plan
import ../src/types/[audio_values, core]

suite "plugin param event queue":
  test "pops only events valid for current process plan":
    var backend: JackBackend
    var plan: ProcessPlan
    var event: PluginParamEvent
    backend.diagnostics.initAudioCallbackDiagnostics()
    check plan.addPluginTarget(PluginId(1))
    check plan.addParamTarget(PluginId(1), ParamId(10))

    check backend.enqueuePluginParamValue(PluginId(2), ParamId(10), 0.25)
    check backend.enqueuePluginParamValue(PluginId(1), ParamId(10), 0.75)

    check backend.popValidatedPluginParamEvent(addr plan, event)
    check event.pluginId == PluginId(1)
    check event.paramId == ParamId(10)
    check event.normalizedValue == 0.75

    let diagnostics = backend.diagnostics.loadAudioCallbackDiagnostics()
    check diagnostics.diagnosticCount(adkStaleEvent) == 1

  test "reports queue overflow without growing storage":
    var backend: JackBackend
    backend.diagnostics.initAudioCallbackDiagnostics()

    for i in 0 ..< MaxPluginParamEvents - 1:
      check backend.enqueuePluginParamValue(PluginId(1), ParamId(i.uint32 + 1), 0.5)

    check not backend.enqueuePluginParamValue(PluginId(1), ParamId(9999), 0.5)

    let diagnostics = backend.diagnostics.loadAudioCallbackDiagnostics()
    check diagnostics.diagnosticCount(adkQueueFull) == 1
