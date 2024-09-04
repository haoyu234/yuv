import unittest

import yuv

test "fs":

  proc amain() {.async.} =
    echo await realpath(".")
    echo await stat(".")
    echo await lstat(".")
    echo await statfs(".")
    echo await mkdtemp("abc")
    echo await access(".", 1)

  waitFor amain()
