import ../types/plugin_runtime_values
import ../audio/rt_queue

proc enqueuePluginEventThreadEvent*(
    queue: var PluginEventThreadQueue, event: PluginEventThreadEvent
): bool =
  queue.push(event)

proc dequeuePluginEventThreadEvent*(
    queue: var PluginEventThreadQueue, event: var PluginEventThreadEvent
): bool =
  queue.pop(event)
