import unittest

import std/nativesockets

import yuv

type DemoType = enum
  DemoTypeClient
  DemoTypeServer

const hello = "hello world!"

test "tcp":
  proc amain(tp: DemoType) {.async.} =
    let t = createUVTcp()
    defer:
      t.close()

    if tp == DemoTypeClient:
      await t.connectAddr("localhost", Port(1996))
      let n = await t.writeSome(hello.toBuf)
      check n == hello.len
      return

    await t.bindAddr("0.0.0.0", Port(1996))
    await t.listen(1024)

    let client = await t.accept()
    defer:
      client.close()

    var buf: array[32, byte]
    let n = await client.readSome(buf.toBuf)
    check n == hello.len

  let s = amain(DemoTypeServer)
  let c = amain(DemoTypeClient)

  waitFor s
  waitFor c
