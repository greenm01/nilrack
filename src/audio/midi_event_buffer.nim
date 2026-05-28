import ../types/audio_values

proc insertMidiEventSorted*(buffer: var MidiEventBuffer, event: PluginMidiEvent): bool =
  if buffer.count >= MaxMidiEvents.uint32:
    buffer.overflowed = true
    return false

  var insertAt = buffer.count.int
  while insertAt > 0 and buffer.events[insertAt - 1].sampleOffset > event.sampleOffset:
    buffer.events[insertAt] = buffer.events[insertAt - 1]
    dec insertAt

  buffer.events[insertAt] = event
  inc buffer.count
  true

proc mergeMidiEventsBySampleOffset*(
    dst: var MidiEventBuffer, src: MidiEventBuffer
): bool =
  result = true
  for i in 0 ..< src.count.int:
    if not dst.insertMidiEventSorted(src.events[i]):
      result = false

proc clearMidiEventBuffer*(buffer: var MidiEventBuffer) =
  for i in 0 ..< buffer.count.int:
    buffer.events[i] = PluginMidiEvent()
  buffer.count = 0
  buffer.overflowed = false
