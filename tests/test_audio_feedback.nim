import std/unittest

import ../src/audio/audio_feedback
import ../src/types/audio_values

suite "audio feedback flags":
  test "marks and clears one-shot feedback flags":
    var feedback: AudioFeedbackFlags
    feedback.initAudioFeedbackFlags()

    feedback.markAudioFeedback(affStaleEvent)
    feedback.markAudioFeedback(affQueueOverflow)

    let first = feedback.takeAudioFeedbackSnapshot()
    let second = feedback.takeAudioFeedbackSnapshot()

    check affStaleEvent in first.flags
    check affQueueOverflow in first.flags
    check affProcessError notin first.flags
    check second.flags == {}
