when defined(linux):
  switch("define", "wgpu")
  switch("define", "wgvkWGSL")
  switch("define", "wayland")
  switch("define", "NoGLFW")
# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
