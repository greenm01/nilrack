import std/atomics
import core

type
  AudioIoMode* = enum
    aimBypass
    aimMonoLeftToStereo
    aimStereo

  AudioBlockProcessProc* = proc(
    runtime: pointer, in1, in2, out1, out2: pointer, nframes: uint32, mode: AudioIoMode
  ): bool

  AudioProcessEntry* = object
    nodeId*: NodeId
    pluginId*: PluginId
    runtime*: pointer
    processBlock*: AudioBlockProcessProc
    ioMode*: AudioIoMode
    active*: bool

  ProcessPlan* = object
    nodeOrder*: seq[NodeId]
    entryCount*: uint32
    entries*: array[4, AudioProcessEntry]

  JackClientHandle* = distinct pointer
  JackPortHandle* = distinct pointer

  JackBackend* = object
    client*: JackClientHandle
    inPort1*: JackPortHandle
    inPort2*: JackPortHandle
    outPort1*: JackPortHandle
    outPort2*: JackPortHandle
    sampleRate*: uint32
    bufferSize*: uint32
    processPlan*: ptr ProcessPlan

  MeterSnapshot* = object
    levels*: array[4, float32]

  RtQueue*[T; N: static int] = object
    data*: array[N, T]
    head*: Atomic[int]
    tail*: Atomic[int]
