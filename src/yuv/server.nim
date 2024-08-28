import std/deques

import uv
import yasync

import ./common
import ./loop

type
  StreamServer*[T] = ptr StreamServerObj[T]
  StreamServerObj*[T] = object of HandleObj
    queuedEnv: Deque[ptr AcceptEnv[T]]
    connectionCb*: proc (uv_stream: ptr uv_stream_t,
        pStream: ptr T) {.nimcall.}

  AcceptEnv[T] = object of Cont[T]

proc connectionCb[T](uv_stream: ptr uv_stream_t,
    status: cint) {.cdecl.} =
  let streamServer = cast[StreamServer[T]](uv_handle_get_data(uv_stream))

  if status == 0:
    let stream: T = nil
    let env = streamServer.queuedEnv.popFirst()

    {.push warning[BareExcept]: off.}
    try:
      streamServer.connectionCb(uv_stream, stream.addr)
    except Exception as e:
      failSoon(env, e)
      return
    {.pop.}

    completeSoon(env, stream)
    return

  let exp = newUVError(status)
  while streamServer.queuedEnv.len > 0:
    let env = streamServer.queuedEnv.popFirst()
    failSoon(env, exp)

proc accept*[T](streamServer: StreamServer[T],
    env: ptr AcceptEnv[T]) {.asyncRaw.} =
  if uv_is_active(streamServer.uv_handle) == 0:
    let uv_stream = cast[ptr uv_stream_t](streamServer.uv_handle)
    let err = uv_listen(uv_stream, 128, connectionCb[T])
    if err != 0:
      failSoon(env, newUVError(err))
      return

  streamServer.queuedEnv.addLast(env)
