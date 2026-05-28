import wgpu_backend
import ../types/render_values

proc initRenderer*(
    r: var Renderer, display, wlSurface: pointer, width, height: uint32
) =
  r.backend.initWgpuBackend(display, wlSurface, width, height)

proc renderFrame*(r: var Renderer, drawList: NilDrawList) =
  r.backend.renderDrawList(drawList)

proc resizeRenderer*(r: var Renderer, width, height: uint32) =
  r.backend.resizeWgpuBackend(width, height)

proc shutdownRenderer*(r: var Renderer) =
  r.backend.shutdownWgpuBackend()
