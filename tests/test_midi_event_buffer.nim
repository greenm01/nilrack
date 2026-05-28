import std/unittest

import ../src/audio/midi_event_buffer
import ../src/types/[audio_values, core]

proc midi(
    portId: PortId, sampleOffset: uint32, status, data1, data2: uint8
): PluginMidiEvent =
  PluginMidiEvent(
    portId: portId,
    sampleOffset: sampleOffset,
    byteCount: 3,
    bytes: [status, data1, data2],
  )

suite "midi event buffer":
  test "inserts events by sample offset":
    var buffer: MidiEventBuffer

    check buffer.insertMidiEventSorted(midi(PortId(1), 32, 0x90, 60, 100))
    check buffer.insertMidiEventSorted(midi(PortId(1), 0, 0x90, 61, 100))
    check buffer.insertMidiEventSorted(midi(PortId(1), 16, 0x80, 60, 0))

    check buffer.count == 3
    check buffer.events[0].sampleOffset == 0
    check buffer.events[1].sampleOffset == 16
    check buffer.events[2].sampleOffset == 32

  test "merges source buffers by sample offset":
    var a: MidiEventBuffer
    var b: MidiEventBuffer

    check a.insertMidiEventSorted(midi(PortId(1), 20, 0x90, 60, 100))
    check a.insertMidiEventSorted(midi(PortId(1), 40, 0x80, 60, 0))
    check b.insertMidiEventSorted(midi(PortId(2), 10, 0x90, 64, 100))
    check b.insertMidiEventSorted(midi(PortId(2), 30, 0x80, 64, 0))

    check a.mergeMidiEventsBySampleOffset(b)

    check a.count == 4
    check a.events[0].sampleOffset == 10
    check a.events[1].sampleOffset == 20
    check a.events[2].sampleOffset == 30
    check a.events[3].sampleOffset == 40

  test "reports overflow without growing storage":
    var buffer: MidiEventBuffer

    for i in 0 ..< MaxMidiEvents:
      check buffer.insertMidiEventSorted(midi(PortId(1), i.uint32, 0x90, 60, 100))

    check not buffer.insertMidiEventSorted(midi(PortId(1), 999, 0x80, 60, 0))
    check buffer.overflowed
    check buffer.count == MaxMidiEvents.uint32

  test "clears buffer storage and overflow flag":
    var buffer: MidiEventBuffer
    check buffer.insertMidiEventSorted(midi(PortId(1), 0, 0x90, 60, 100))
    buffer.overflowed = true

    buffer.clearMidiEventBuffer()

    check buffer.count == 0
    check not buffer.overflowed
