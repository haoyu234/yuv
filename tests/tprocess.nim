import unittest

import std/paths
import std/strutils

import yuv

proc collectOutput(reader: Stream): string {.async.} =
  var idx = 0
  var offset = 0
  var bufferSize = 128
  var reserveSize = bufferSize div 3

  while true:
    if result.len - offset < reserveSize:
      result.setLen(offset + bufferSize)

      if idx < 6:
        inc idx
        bufferSize = bufferSize * 2
        reserveSize = reserveSize * 2

    let writeBuf = result.toBuf
    let n = await reader.readSome(writeBuf[offset ..< result.len])
    if n > 0:
      inc offset, n
      continue
    break

  result.setLen(offset)

proc getOutput(
    executable: string, cwd: string = "", args: seq[string] = @[]
): string {.async.} =
  var (reader, writer) = pipe()
  defer:
    reader.close()

    if not writer.isNil:
      writer.close()

  let p = spawn(executable, cwd, args, stdout = writer)
  defer:
    p.close()

  writer.close()
  writer = nil

  result = await collectOutput(reader)

  let exitCode = await p.exitCode
  check exitCode == 0

test "spawn":
  proc amain() {.async.} =
    let workDir = getCurrentDir().string
    let workDir2 = await getOutput("pwd", workDir)

    check workDir == workDir2.strip

  waitFor amain()
