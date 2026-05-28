import std/atomics
import ../types/audio_values

proc push*[T; N: static int](q: var RtQueue[T, N], item: T): bool =
  let t = q.tail.load(moRelaxed)
  let next = (t + 1) mod N
  if next == q.head.load(moAcquire):
    return false
  q.data[t] = item
  q.tail.store(next, moRelease)
  true

proc pop*[T; N: static int](q: var RtQueue[T, N], item: var T): bool =
  let h = q.head.load(moRelaxed)
  if h == q.tail.load(moAcquire):
    return false
  item = q.data[h]
  q.head.store((h + 1) mod N, moRelease)
  true
