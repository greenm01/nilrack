import std/atomics
import ../types/plugin_runtime_values

proc callbackMask(flag: PluginHostCallbackFlag): uint32 =
  1'u32 shl ord(flag).uint32

proc initPluginHostCallbackFlags*(callbacks: var PluginHostCallbackFlags) =
  callbacks.bits.store(0'u32, moRelaxed)

proc markPluginHostCallback*(
    callbacks: var PluginHostCallbackFlags, flag: PluginHostCallbackFlag
) =
  discard callbacks.bits.fetchOr(callbackMask(flag), moRelease)

proc takePluginHostCallbackSnapshot*(
    callbacks: var PluginHostCallbackFlags
): PluginHostCallbackSnapshot =
  let bits = callbacks.bits.exchange(0'u32, moAcquireRelease)
  for flag in PluginHostCallbackFlag:
    if (bits and callbackMask(flag)) != 0:
      result.flags.incl(flag)
