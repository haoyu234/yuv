import unittest

import std/nativesockets

import yuv

const data = "hello world!"

template serverBody(listen) =
  let s = listen
  defer:
    close(s)

  let t = await s.accept()
  defer:
    close(t)

  var buf: array[128, byte]

  let writeBuf = buf.toBuf
  let readSize = await t.readSome(writeBuf)
  assert readSize > 0

  let writeSize = await t.writeSome(writeBuf[0..<readSize])
  assert writeSize == readSize

template clientBody(connect) =
  let t = connect
  defer:
    close(t)

  let writeSize = await t.writeSome(data.toBuf)
  assert writeSize == data.len

  var buf: array[128, byte]
  let readSize = await t.readSome(buf.toBuf)
  assert readSize == writeSize

template testBody(serverProc, clientProc) =
  let s = serverProc()
  let c = clientProc()

  waitFor s
  waitFor c

test "tcp":

  const address = "0.0.0.0"
  const port = Port(1996)

  proc serverProc() {.async.} =
    serverBody:
      serveTcp(address, port)

  proc clientProc() {.async.} =
    clientBody:
      await connectTcp(address, port)

  testBody serverProc, clientProc

test "pipe":

  const address = "\0/yuv.unix"

  proc serverProc() {.async.} =
    serverBody:
      servePipe(address)

  proc clientProc() {.async.} =
    clientBody:
      await connectPipe(address)

  testBody serverProc, clientProc
