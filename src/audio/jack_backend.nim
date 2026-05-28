{.passL: "-ljack".}

import ../types/audio_values
import process_callback

const jackH = "jack/jack.h"
const jackLib = "libjack.so.0"

type
  JackClient {.importc: "jack_client_t", header: jackH.} = object
  JackPort {.importc: "jack_port_t", header: jackH.} = object
  JackStatusT {.importc: "jack_status_t", header: "jack/types.h".} = distinct cint
  JackProcessCallback = proc(nframes: uint32, arg: pointer): cint {.cdecl.}

proc jackClientOpen(
  name: cstring, options: cint, status: ptr JackStatusT
): ptr JackClient {.importc: "jack_client_open", header: jackH.}

proc jackClientClose(
  client: ptr JackClient
): cint {.importc: "jack_client_close", header: jackH.}

proc jackSetProcessCallback(
  client: ptr JackClient, cb: JackProcessCallback, arg: pointer
): cint {.importc: "jack_set_process_callback", header: jackH.}

proc jackPortRegister(
  client: ptr JackClient,
  portName: cstring,
  portType: cstring,
  flags: uint64,
  bufSize: uint64,
): ptr JackPort {.importc: "jack_port_register", header: jackH.}

proc jackActivate(
  client: ptr JackClient
): cint {.importc: "jack_activate", header: jackH.}

proc jackDeactivate(
  client: ptr JackClient
): cint {.importc: "jack_deactivate", header: jackH.}

proc jackGetSampleRate(
  client: ptr JackClient
): uint32 {.importc: "jack_get_sample_rate", header: jackH.}

proc jackGetBufferSize(
  client: ptr JackClient
): uint32 {.importc: "jack_get_buffer_size", header: jackH.}

const
  jackPortIsInput = 1'u64
  jackPortIsOutput = 2'u64
  jackDefaultAudioType = "32 bit float mono audio"

proc initJackBackend*(b: var JackBackend, clientName: string) =
  var status: JackStatusT
  let client = jackClientOpen(clientName.cstring, 0, status.addr)
  doAssert client != nil, "failed to open JACK client"
  b.client = cast[JackClientHandle](client)
  b.sampleRate = jackGetSampleRate(client)
  b.bufferSize = jackGetBufferSize(client)
  b.planSlot.initProcessPlanSlot()

  b.inPort1 = cast[JackPortHandle](jackPortRegister(
    client, "input_1", jackDefaultAudioType, jackPortIsInput, 0
  ))
  b.inPort2 = cast[JackPortHandle](jackPortRegister(
    client, "input_2", jackDefaultAudioType, jackPortIsInput, 0
  ))
  b.outPort1 = cast[JackPortHandle](jackPortRegister(
    client, "output_1", jackDefaultAudioType, jackPortIsOutput, 0
  ))
  b.outPort2 = cast[JackPortHandle](jackPortRegister(
    client, "output_2", jackDefaultAudioType, jackPortIsOutput, 0
  ))

  discard jackSetProcessCallback(client, jackProcess, b.addr)

proc activateJack*(b: var JackBackend) =
  let client = cast[ptr JackClient](b.client)
  doAssert jackActivate(client) == 0, "failed to activate JACK client"

proc publishJackProcessPlan*(
    b: var JackBackend, plan: ptr ProcessPlan
): ptr ProcessPlan =
  b.planSlot.publishProcessPlan(plan)

proc deactivateJack*(b: var JackBackend) =
  if pointer(b.client) != nil:
    discard jackDeactivate(cast[ptr JackClient](b.client))

proc shutdownJackBackend*(b: var JackBackend) =
  if pointer(b.client) != nil:
    discard jackClientClose(cast[ptr JackClient](b.client))
    b.client = cast[JackClientHandle](nil)
