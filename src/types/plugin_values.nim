import model

type
  PluginPortDescriptor* = object
    index*: uint32
    externalId*: uint32
    name*: string
    kind*: PortKind
    direction*: PortDirection
    channelCount*: uint32
    isMain*: bool
    portType*: string

  PluginParamDescriptor* = object
    index*: uint32
    externalId*: uint32
    name*: string
    modulePath*: string
    minVal*: float64
    maxVal*: float64
    defaultVal*: float64
    currentVal*: float64
    displayText*: string
    stepped*: bool
    hidden*: bool
    readonly*: bool
    bypass*: bool
    automatable*: bool

  PluginDescriptor* = object
    api*: PluginApi
    path*: string
    uri*: string
    name*: string
    vendor*: string
    version*: string
    description*: string
    ports*: seq[PluginPortDescriptor]
    params*: seq[PluginParamDescriptor]
    hasState*: bool

  ScanResult* = object
    descriptor*: PluginDescriptor
    failed*: bool
    errorMsg*: string
