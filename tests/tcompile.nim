import unittest

import yuv

test "compile":
  proc amain() {.async.} =
    let n = time()

    for i in 0 .. 5:
      await sleep(100)

    let diff = time() - n
    check diff < 1000

  waitFor amain()
