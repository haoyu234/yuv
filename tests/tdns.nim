import unittest

import std/nativesockets except getAddrInfo, freeAddrInfo

import yuv

proc dumpRes(res: ptr AddrInfo) =
  var res = res
  while not res.isNil:
    res = res.ai_next

test "getAddrInfo":
  proc amain() {.async.} =
    let res = await getAddrInfo("baidu.com", Port(80))
    defer:
      freeAddrInfo(res)
    dumpRes(res)

  waitFor amain()
