import std/unittest

import ../src/audio/[audio_feedback, callback_diagnostics, param_event_queue]
import ../src/systems/graph_process_plan
import ../src/types/[audio_values, core]

suite "plugin param event queue":
  test "pops only events valid for current process plan":
    var backend: JackBackend
    var plan: ProcessPlan
    var event: PluginParamEvent
    backend.diagnostics.initAudioCallbackDiagnostics()
    backend.feedback.initAudioFeedbackFlags()
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
    check affStaleEvent in backend.feedback.takeAudioFeedbackSnapshot().flags

  test "reports queue overflow without growing storage":
    var backend: JackBackend
    backend.diagnostics.initAudioCallbackDiagnostics()
    backend.feedback.initAudioFeedbackFlags()

    for i in 0 ..< MaxPluginParamEvents - 1:
      check backend.enqueuePluginParamValue(PluginId(1), ParamId(i.uint32 + 1), 0.5)

    check not backend.enqueuePluginParamValue(PluginId(1), ParamId(9999), 0.5)

    let diagnostics = backend.diagnostics.loadAudioCallbackDiagnostics()
    check diagnostics.diagnosticCount(adkQueueFull) == 1
    check affQueueOverflow in backend.feedback.takeAudioFeedbackSnapshot().flags

  test "gesture begin overflow does not create active gesture state":
    var backend: JackBackend
    backend.diagnostics.initAudioCallbackDiagnostics()
    backend.feedback.initAudioFeedbackFlags()

    for i in 0 ..< MaxPluginParamEvents - 1:
      check backend.enqueuePluginParamValue(PluginId(1), ParamId(i.uint32 + 1), 0.5)

    check not backend.enqueuePluginParamGestureBegin(PluginId(1), ParamId(9999))
    check not backend.hasActivePluginParamGesture(PluginId(1), ParamId(9999))

  test "gesture end overflow clears active gesture state":
    var backend: JackBackend
    backend.diagnostics.initAudioCallbackDiagnostics()
    backend.feedback.initAudioFeedbackFlags()

    check backend.enqueuePluginParamGestureBegin(PluginId(1), ParamId(10))
    check backend.hasActivePluginParamGesture(PluginId(1), ParamId(10))

    for i in 0 ..< MaxPluginParamEvents - 2:
      check backend.enqueuePluginParamValue(PluginId(1), ParamId(i.uint32 + 1), 0.5)

    check not backend.enqueuePluginParamGestureEnd(PluginId(1), ParamId(10))
    check not backend.hasActivePluginParamGesture(PluginId(1), ParamId(10))
