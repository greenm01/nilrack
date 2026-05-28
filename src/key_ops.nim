import std/hashes

import types/core
import types/model

proc `==`*(a, b: RackId): bool {.borrow.}
proc `==`*(a, b: NodeId): bool {.borrow.}
proc `==`*(a, b: CableId): bool {.borrow.}
proc `==`*(a, b: PortId): bool {.borrow.}
proc `==`*(a, b: ParamId): bool {.borrow.}
proc `==`*(a, b: PluginId): bool {.borrow.}
proc `==`*(a, b: PluginUiId): bool {.borrow.}
proc `==`*(a, b: AudioBackendId): bool {.borrow.}
proc `==`*(a, b: RenderSurfaceId): bool {.borrow.}
proc `==`*(a, b: TextureId): bool {.borrow.}
proc `==`*(a, b: InputTargetId): bool {.borrow.}

proc `<`*(a, b: RackId): bool {.borrow.}
proc `<`*(a, b: NodeId): bool {.borrow.}
proc `<`*(a, b: CableId): bool {.borrow.}
proc `<`*(a, b: PortId): bool {.borrow.}
proc `<`*(a, b: ParamId): bool {.borrow.}
proc `<`*(a, b: PluginId): bool {.borrow.}
proc `<`*(a, b: PluginUiId): bool {.borrow.}
proc `<`*(a, b: AudioBackendId): bool {.borrow.}
proc `<`*(a, b: RenderSurfaceId): bool {.borrow.}
proc `<`*(a, b: TextureId): bool {.borrow.}
proc `<`*(a, b: InputTargetId): bool {.borrow.}

proc `$`*(id: RackId): string {.borrow.}
proc `$`*(id: NodeId): string {.borrow.}
proc `$`*(id: CableId): string {.borrow.}
proc `$`*(id: PortId): string {.borrow.}
proc `$`*(id: ParamId): string {.borrow.}
proc `$`*(id: PluginId): string {.borrow.}
proc `$`*(id: PluginUiId): string {.borrow.}
proc `$`*(id: AudioBackendId): string {.borrow.}
proc `$`*(id: RenderSurfaceId): string {.borrow.}
proc `$`*(id: TextureId): string {.borrow.}
proc `$`*(id: InputTargetId): string {.borrow.}

proc hash*(id: RackId): Hash =
  hash(uint32(id))

proc hash*(id: NodeId): Hash =
  hash(uint32(id))

proc hash*(id: CableId): Hash =
  hash(uint32(id))

proc hash*(id: PortId): Hash =
  hash(uint32(id))

proc hash*(id: ParamId): Hash =
  hash(uint32(id))

proc hash*(id: PluginId): Hash =
  hash(uint32(id))

proc hash*(id: PluginUiId): Hash =
  hash(uint32(id))

proc hash*(id: AudioBackendId): Hash =
  hash(uint32(id))

proc hash*(id: RenderSurfaceId): Hash =
  hash(uint32(id))

proc hash*(id: TextureId): Hash =
  hash(uint32(id))

proc hash*(id: InputTargetId): Hash =
  hash(uint32(id))

proc `==`*(a, b: ExternalPortKey): bool =
  a.pluginId == b.pluginId and a.index == b.index

proc `==`*(a, b: ExternalParamKey): bool =
  a.pluginId == b.pluginId and a.index == b.index

proc hash*(k: ExternalPortKey): Hash =
  hash((uint32(k.pluginId), k.index))

proc hash*(k: ExternalParamKey): Hash =
  hash((uint32(k.pluginId), k.index))
