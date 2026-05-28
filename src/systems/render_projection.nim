import ../types/render_values
import ../state/engine
import ../render/draw_list
import ui_layout

proc project*(
    list: var NilDrawList,
    model: NilrackModel,
    width, height: float32,
    meterIn, meterOut: float32,
) =
  list.clear()
  list.layoutShell(width, height, meterIn, meterOut)
