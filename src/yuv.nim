import std/macros

import yuv/[
  buf,
  common,
  dns,
  errors,
  stream,
  timer,
  utils,
  uvfile,
  uvloop,
  uvpipe,
  uvprocess,
  uvtcp,
]

macro exports(l: untyped): untyped =
  result = newNimNode(nnkExportStmt)
  for p in l.children:
    result.add(p)

exports [
  buf,
  common,
  dns,
  errors,
  stream,
  timer,
  uvfile,
  uvloop,
  uvpipe,
  uvprocess,
  uvtcp,
]

exports [
  utils.close,
]

import yasync
export yasync
