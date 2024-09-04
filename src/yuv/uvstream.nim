import std/deques

import yasync

import ./buf
import ./errors
import ./stream
import ./utils
import ./uvexport
import ./uvloop

type
  WriteBufEnv = object of Cont[int]
    uv_write: uv_write_t
    written: int

  ReadBufEnv = object of Cont[int]
    uv_buf: uv_buf_t

  ReadJob = object
    buf: Buf
    env: ptr ReadBufEnv

  AcceptEnv[T] = object of Cont[T]

  StreamType = enum
    StreamNone
    StreamClient
    StreamServer

  StreamUnionObj = object
    case tp: StreamType
    of StreamClient:
      readJobQueue: Deque[ReadJob]
    of StreamServer:
      acceptEnvQueue: Deque[ptr AcceptEnv[UVStream]]
    else:
      discard

  UVStream* = ptr UVStreamObj
  UVStreamObj* = object of Stream
    unionObj: StreamUnionObj
    createStreamCb: CreateStreamCb

  CreateStreamCb = proc(): UVStream {.nimcall.}

template `+`(p: pointer, s: int): pointer =
  cast[pointer](cast[uint](p) + cast[uint](s))

proc ensureStreamType(stream: UVStream, tp: StreamType) {.inline.} =
  if stream.unionObj.tp != tp:
    if stream.unionObj.tp == StreamNone:
      stream.unionObj = StreamUnionObj(tp: tp)
      return

    assert false

proc writeCb(uv_write: ptr uv_write_t, status: cint) {.cdecl.} =
  let env = cast[ptr WriteBufEnv](uv_req_get_data(uv_write))
  if status < 0:
    failSoon(env, createUVError(UVErrorCode(status)))
  else:
    inc env.written, status.int
    completeSoon(env, env.written)

proc writeSomeCb(
    stream: Stream, buf: openArray[Buf], env: ptr WriteBufEnv
) {.asyncRaw.} =
  if buf.len <= 0:
    completeSoon(env, 0)
    return

  var uv_bufs: UVBufs
  let stream = UVStream(stream)

  setupBufs(uv_bufs, buf)
  uv_req_set_data(env.uv_write.addr, env)

  let r = uv_try_write(stream.uv_stream, uv_bufs.uv_bufs[0].addr, uv_bufs.nbufs.cuint)
  if r == uv_bufs.size.cint:
    completeSoon(env, uv_bufs.size.int)
    return

  var nbufs = 0
  if r > 0:
    var written = r.int
    env.written = written

    for idx in 0 ..< buf.len:
      let size = buf[idx].len
      if written >= size:
        dec written, size
        continue

      if written <= 0:
        uv_bufs.uv_bufs[nbufs] = uv_buf_init(buf[idx], size.cuint)
      else:
        uv_bufs.uv_bufs[nbufs] = uv_buf_init(buf[idx] + written, (size - written).cuint)
        written = 0

      inc nbufs

  let err = uv_write(
    env.uv_write.addr, stream.uv_stream, uv_bufs.uv_bufs[0].addr, nbufs.cuint, writeCb
  )
  if err != 0:
    failSoon(env, createUVError(UVErrorCode(err)))

proc allocCb(
    uv_handle: ptr uv_handle_t, suggested_size: csize_t, uv_buf: ptr uv_buf_t
) {.cdecl.} =
  let stream = cast[UVStream](uv_handle_get_data(uv_handle))

  let j = stream.unionObj.readJobQueue.peekFirst().addr
  uv_buf[] = uv_buf_init(j.buf, j.buf.len.cuint)

proc readCb(
    uv_stream: ptr uv_stream_t, nread: csize_t, uv_buf: ptr uv_buf_t
) {.cdecl.} =
  let nread = cast[int](nread)
  if nread == 0:
    return

  var hasError = false
  let stream = cast[UVStream](uv_handle_get_data(uv_stream))

  defer:
    if hasError or stream.unionObj.readJobQueue.len <= 0:
      discard uv_read_stop(uv_stream)

  if nread > 0:
    let j = stream.unionObj.readJobQueue.popFirst()
    completeSoon(j.env, nread.int)
    return

  if nread == UV_EOF.int:
    let j = stream.unionObj.readJobQueue.popFirst()
    completeSoon(j.env, 0)
    return

  hasError = true

  let exc = createUVError(UVErrorCode(nread))
  while stream.unionObj.readJobQueue.len > 0:
    let j = stream.unionObj.readJobQueue.popFirst()
    failSoon(j.env, exc)

proc enqueueReadJob(stream: UVStream, j: ReadJob): cint {.inline.} =
  if uv_is_active(stream.uv_stream) != 0:
    stream.unionObj.readJobQueue.addLast(j)
    return

  ensureStreamType(stream, StreamClient)

  result = uv_read_start(stream.uv_stream, allocCb, cast[uv_read_cb](readCb))
  if result != 0:
    return

  stream.unionObj.readJobQueue.addLast(j)

proc readSomeCb(stream: Stream, buf: openArray[Buf], env: ptr ReadBufEnv) {.asyncRaw.} =
  if buf.len <= 0:
    completeSoon(env, 0)
    return

  let stream = UVStream(stream)
  let j = ReadJob(env: env, buf: buf[0])

  let err = enqueueReadJob(stream, j)
  if err != 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc connectionCb(uv_stream: ptr uv_stream_t, status: cint) {.cdecl.} =
  let stream = cast[UVStream](uv_handle_get_data(uv_stream))

  if status == 0:
    if stream.unionObj.acceptEnvQueue.len > 0:
      var newStream: UVStream
      let env = stream.unionObj.acceptEnvQueue.popFirst()

      try:
        newStream = stream.createStreamCb()
      except Exception as e:
        failSoon(env, e)
        return

      let err = uv_accept(uv_stream, newStream.uv_stream)
      if err != 0:
        failSoon(env, createUVError(UVErrorCode(err)))
        return

      completeSoon(env, newStream)
    return

  let exp = createUVError(UVErrorCode(status))
  while stream.unionObj.acceptEnvQueue.len > 0:
    let env = stream.unionObj.acceptEnvQueue.popFirst()
    failSoon(env, exp)

proc accept*[T: UVStream](stream: T, env: ptr AcceptEnv[T]) {.asyncRaw.} =
  while true:
    if uv_is_active(stream.uv_stream) != 0:
      break

    ensureStreamType(stream, StreamServer)
    let err = uv_listen(stream.uv_stream, 511, connectionCb)
    if err != 0:
      failSoon(env, createUVError(UVErrorCode(err)))
      return
    break

  let env = cast[ptr AcceptEnv[UVStream]](env)
  stream.unionObj.acceptEnvQueue.addLast(env)

proc setupUVStream*[T: UVStream](
    stream: T, uv_stream: ptr uv_stream_t, createStreamCb: proc(): T {.nimcall.}
) {.inline.} =
  stream.uv_stream = uv_stream
  stream.readSomeCb = readSomeCb
  stream.writeSomeCb = writeSomeCb
  stream.createStreamCb = cast[CreateStreamCb](createStreamCb)
