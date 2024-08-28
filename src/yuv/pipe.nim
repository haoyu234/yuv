import std/nativesockets

import uv
import yasync

import ./common
import ./loop
import ./stream
import ./server
import ./intern/utils

type
  Pipe* = ptr object of StreamObj
    uv_pipe: uv_pipe_t

  ConnectEnv = object of Cont[Pipe]
    request: uv_connect_t
    pipe: Pipe
    closeOnError: bool

  PipeServer* =
    ptr object of StreamServerObj[Pipe]
      uv_pipe: uv_pipe_t

proc createPipe(): Pipe =
  result = cast[typeof(result)](alloc0(sizeof(result[])))

  let loop = getLoop()
  let err = uv_pipe_init(loop.uv_loop.addr, result.uv_pipe.addr, 0)
  if err != 0:
    dealloc(result)
    raiseUVError(err)

  result.closeCb = closeCb[Pipe]
  result.uv_handle = result.uv_pipe.addr

  uv_handle_set_data(result.uv_pipe.addr, result)

proc connectCb(request: ptr uv_connect_t, status: cint) {.cdecl.} =
  let env = cast[ptr ConnectEnv](uv_req_get_data(request))
  if status == 0:
    completeSoon(env, env.pipe)
    return

  if env.closeOnError:
    env.pipe.close()

  failSoon(env, newUVError(status))

proc connectPipe*(address: string, env: ptr ConnectEnv) {.asyncRaw.} =
  let u = createPipe()

  env.pipe = u
  env.closeOnError = true

  uv_req_set_data(env.request.addr, env)

  uv_pipe_connect2(env.request.addr, u.uv_pipe.addr, address[0].addr,
      address.len.csize_t, 0, connectCb)

proc connectionCb(uv_stream: ptr uv_stream_t, pStream: ptr Pipe) =
  let stream = createPipe()

  let new_uv_stream = cast[ptr uv_stream_t](stream.uv_handle)
  let err = uv_accept(uv_stream, new_uv_stream)
  if err != 0:
    close(stream)
    raiseUVError(err)
    return

  pStream[] = stream

proc servePipe*(address: string): PipeServer =
  result = cast[typeof(result)](alloc0(sizeof(result[])))
  result.closeCb = closeCb[PipeServer]
  result.connectionCb = connectionCb
  result.uv_handle = result.uv_pipe.addr

  let loop = getLoop()
  var err = uv_pipe_init(loop.uv_loop.addr, result.uv_pipe.addr, 0)
  if err != 0:
    dealloc(result)
    raiseUVError(err)

  err = uv_pipe_bind2(result.uv_pipe.addr, address[0].addr, address.len.csize_t, 0)
  if err != 0:
    close(result)
    raiseUVError(err)

  uv_handle_set_data(result.uv_pipe.addr, result)

proc pipe*(): tuple[r: Pipe, w: Pipe] =
  var fds: array[2, cint]
  var err = uv_pipe(fds, UV_NONBLOCK_PIPE.cint, UV_NONBLOCK_PIPE.cint)
  if err != 0:
    raiseUVError(err)

  result.r = createPipe()
  err = uv_pipe_open(result.r.uv_pipe.addr, fds[0])
  if err != 0:
    result.r.close()
    raiseUVError(err)

  result.w = createPipe()
  err = uv_pipe_open(result.w.uv_pipe.addr, fds[1])
  if err != 0:
    result.r.close()
    result.w.close()
    raiseUVError(err)
