import std/atomics
import core

type
  ProcessPlan* = object
    nodeOrder*: seq[NodeId]

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

  MeterSnapshot* = object
    levels*: array[4, float32]

  RtQueue*[T; N: static int] = object
    data*: array[N, T]
    head*: Atomic[int]
    tail*: Atomic[int]
