import ../plugins/clap_host
import ../types/[audio_values, core, model, plugin_values]

proc mainAudioPort(
    descriptor: PluginDescriptor, direction: PortDirection
): PluginPortDescriptor =
  for port in descriptor.ports:
    if port.kind == pkAudio and port.direction == direction and port.isMain:
      return port
  for port in descriptor.ports:
    if port.kind == pkAudio and port.direction == direction:
      return port
  PluginPortDescriptor()

proc audioIoModeFor*(descriptor: PluginDescriptor): AudioIoMode =
  let input = mainAudioPort(descriptor, pdIn)
  let output = mainAudioPort(descriptor, pdOut)
  if input.channelCount == 1 and output.channelCount == 1:
    return aimMonoLeftToStereo
  if input.channelCount == 2 and output.channelCount == 2:
    return aimStereo
  aimBypass

proc buildSingleClapProcessPlan*(
    nodeId: NodeId,
    pluginId: PluginId,
    descriptor: PluginDescriptor,
    loaded: ClapLoadedPlugin,
): ProcessPlan =
  discard result.addPlanNode(nodeId)
  let mode = audioIoModeFor(descriptor)
  discard result.addProcessEntry(
    AudioProcessEntry(
      nodeId: nodeId,
      pluginId: pluginId,
      runtime: loaded.clapRuntimePointer(),
      processBlock: clapProcessAudioBlock,
      ioMode: mode,
      active: mode != aimBypass,
    )
  )
