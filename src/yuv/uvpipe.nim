import std/nativesockets

when defined(windows): import winlean else: import posix

import ./errors
import ./utils
import ./uvexport
import ./uvloop
import ./uvstream

type
  UVPipe* = ptr UVPipeObj
  UVPipeObj = object of UVStreamObj
    uv_pipe: uv_pipe_t

proc closePipe(c: Closeable) =
  proc closeCb(handle: ptr uv_handle_t) {.cdecl.} =
    let t = cast[UVPipe](uv_handle_get_data(handle))
    `=destroy`(t[])
    dealloc(t)

  uv_close(UVPipe(c).uv_pipe.addr, closeCb)

proc createUVPipe*(): UVPipe =
  result = allocObj[UVPipeObj](closePipe)
  uv_handle_set_data(result.uv_pipe.addr, result)
  setupStream(result, result.uv_pipe.addr)

  let loop = getUVLoop()
  let err = uv_pipe_init(loop.uv_loop.addr, result.uv_pipe.addr, 0)
  if err != 0:
    close(result)
    raiseUVError(UVErrorCode(err))

proc openPipe*(fd: uv_file): UVPipe =
  result = createUVPipe()

  let err = uv_pipe_open(result.uv_pipe.addr, fd)
  if err != 0:
    close(result)
    raiseUVError(UVErrorCode(err))

proc pipe*(): (UVPipe, UVPipe) =
  var fds: array[2, uv_file]
  var err = uv_pipe(fds, UV_NONBLOCK_PIPE.cint, UV_NONBLOCK_PIPE.cint)
  if err != 0:
    raiseUVError(UVErrorCode(err))

  result[0] = openPipe(fds[0])
  result[1] = openPipe(fds[1])
