import unittest

import yuv

test "loop":
  proc amain() {.async.} =
    discard

  waitFor amain()

  let loop = getUVLoop()
  closeUVLoop(loop)
