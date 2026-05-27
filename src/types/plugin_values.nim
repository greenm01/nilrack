import model

type
  PluginDescriptor* = object
    api*: PluginApi
    path*: string
    uri*: string
    name*: string
    vendor*: string
    version*: string

  ScanResult* = object
    descriptor*: PluginDescriptor
    failed*: bool
    errorMsg*: string
