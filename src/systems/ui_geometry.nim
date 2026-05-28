import ../state/engine
import ../types/core

const
  PluginBypassToggleW* = 30.0'f32
  PluginBypassToggleH* = 16.0'f32
  PluginBypassToggleRightPad* = 12.0'f32
  PluginBypassToggleTopPad* = 7.0'f32

proc pluginBypassToggleRect*(node: NodeData): Rect =
  let w = if node.w > 0.0'f32: node.w else: 320.0'f32
  Rect(
    x: node.x + w - PluginBypassToggleRightPad - PluginBypassToggleW,
    y: node.y + PluginBypassToggleTopPad,
    w: PluginBypassToggleW,
    h: PluginBypassToggleH,
  )
