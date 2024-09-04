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
  uvfs,
  uvloop,
  uvpipe,
  uvprocess,
  uvstream,
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
  uvfs,
  uvloop,
  uvpipe,
  uvprocess,
  uvstream,
  uvtcp,
]

exports [
  utils.close,
]

import yasync
export yasync
