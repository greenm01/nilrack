import std/atomics
import ../types/audio_values

proc feedbackMask(flag: AudioFeedbackFlag): uint32 =
  1'u32 shl ord(flag).uint32

proc initAudioFeedbackFlags*(feedback: var AudioFeedbackFlags) =
  feedback.bits.store(0'u32, moRelaxed)

proc markAudioFeedback*(feedback: var AudioFeedbackFlags, flag: AudioFeedbackFlag) =
  discard feedback.bits.fetchOr(feedbackMask(flag), moRelease)

proc takeAudioFeedbackSnapshot*(
    feedback: var AudioFeedbackFlags
): AudioFeedbackSnapshot =
  let bits = feedback.bits.exchange(0'u32, moAcquireRelease)
  for flag in AudioFeedbackFlag:
    if (bits and feedbackMask(flag)) != 0:
      result.flags.incl(flag)
