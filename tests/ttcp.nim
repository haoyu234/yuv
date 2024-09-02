# import unittest

# import std/nativesockets

# import yuv

# test "tcp":
#   proc amain() {.async.} =
#     let t = allocTcp()
#     # await t.connectAddr("www.baidu.com", Port(80))
#     await t.connectAddr("localhost", Port(1996))
#     let n = await t.writeSome("123".toBuf)
#     echo n

#   waitFor amain()
