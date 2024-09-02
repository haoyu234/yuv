import std/deques

import yasync

import ./buf
import ./errors
import ./stream
import ./utils
import ./uvexport
import ./uvloop

type
  ReadJob = object
    env: ptr ReadBufEnv
    buf: Buf

  WriteBufEnv = object of Cont[int]
    written: int
    uv_write: uv_write_t

  ReadBufEnv = object of Cont[int]
    uv_buf: uv_buf_t

  UVStream* = ptr UVStreamObj
  UVStreamObj* = object of Stream
    queuedJob: Deque[ReadJob]

template `+`(p: pointer, s: int): pointer =
  cast[pointer](cast[uint](p) + cast[uint](s))

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

  let j = stream.queuedJob.peekFirst().addr
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
    if hasError or stream.queuedJob.len <= 0:
      discard uv_read_stop(uv_stream)

  if nread > 0:
    let j = stream.queuedJob.popFirst()
    completeSoon(j.env, nread.int)
    return

  if nread == UV_EOF.int:
    let j = stream.queuedJob.popFirst()
    completeSoon(j.env, 0)
    return

  hasError = true

  let exc = createUVError(UVErrorCode(nread))
  while stream.queuedJob.len > 0:
    let j = stream.queuedJob.popFirst()
    failSoon(j.env, exc)

proc enqueueReadJob(stream: UVStream, r: ReadJob): cint {.inline.} =
  if uv_is_active(stream.uv_stream) != 0:
    stream.queuedJob.addLast(r)
    return

  let err = uv_read_start(stream.uv_stream, allocCb, cast[uv_read_cb](readCb))
  if err == 0:
    stream.queuedJob.addLast(r)
    return

  err

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

proc setupStream*(stream: UVStream, uv_stream: ptr uv_stream_t) =
  stream.uv_stream = uv_stream
  stream.readSomeCb = readSomeCb
  stream.writeSomeCb = writeSomeCb
