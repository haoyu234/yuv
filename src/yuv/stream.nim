import std/deques

import uv
import yasync

import ./common
import ./loop
import ./buf
import ./intern/utils

type
  ReadJob = object
    env: ptr ReadBufEnv
    buf: Buf

  WriteBufEnv = object of Cont[int]
    written: int
    uv_write: uv_write_t

  ReadBufEnv = object of Cont[int]
    uv_buf: uv_buf_t

  Stream* = ptr StreamObj
  StreamObj* = object of HandleObj
    queuedJob: Deque[ReadJob]

template `+`(p: pointer, s: int): pointer =
  cast[pointer](cast[uint](p) + cast[uint](s))

proc writeCb(uv_write: ptr uv_write_t, status: cint) {.cdecl.} =
  let env = cast[ptr WriteBufEnv](uv_req_get_data(uv_write))
  if status < 0:
    failSoon(env, newUVError(status))
  else:
    inc env.written, status.int
    completeSoon(env, env.written)

proc writeSome*(stream: Stream, nBufs: int, vecBuf: ptr Buf,
    env: ptr WriteBufEnv) {.asyncRaw.} =
  var uv_bufs: array[32, uv_buf_t]
  let vecBuf = cast[ptr UncheckedArray[Buf]](vecBuf)

  uv_req_set_data(env.uv_write.addr, env)

  var size = 0
  var uv_nbufs = 0

  for idx in 0..<min(nBufs, 32):
    inc uv_nbufs
    inc size, vecBuf[idx].len
    uv_bufs[idx] = uv_buf_init(vecBuf[idx], vecBuf[idx].len.cuint)

  let uv_stream = cast[ptr uv_stream_t](stream.uv_handle)
  let r = uv_try_write(uv_stream, uv_bufs[0].addr, uv_nbufs.cuint)
  if r == size.cint:
    completeSoon(env, size.int)
    return

  if r > 0:
    var written = r.int
    env.written = written

    uv_nbufs = 0

    for idx in 0..<nBufs:
      let size = vecBuf[idx].len
      if written >= size:
        dec written, size
        continue

      if written <= 0:
        uv_bufs[uv_nbufs] = uv_buf_init(vecBuf[idx], size.cuint)
      else:
        uv_bufs[uv_nbufs] = uv_buf_init(vecBuf[idx] + written, (size -
            written).cuint)
        written = 0

      inc uv_nbufs

  let err = uv_write(env.uv_write.addr, uv_stream, uv_bufs[0].addr,
      uv_nbufs.cuint, writeCb)
  if err != 0:
    failSoon(env, newUVError(err))

proc allocCb(
    uv_handle: ptr uv_handle_t,
    suggested_size: csize_t, uv_buf: ptr uv_buf_t) {.cdecl.} =
  let stream = cast[Stream](uv_handle_get_data(uv_handle))

  let j = stream.queuedJob.peekFirst().addr
  uv_buf[] = uv_buf_init(j.buf, j.buf.len.cuint)

proc readCb(
    uv_stream: ptr uv_stream_t, nread: csize_t,
        uv_buf: ptr uv_buf_t) {.cdecl.} =
  let nread = cast[int](nread)
  if nread == 0:
    return

  var hasError = false
  let stream = cast[Stream](uv_handle_get_data(uv_stream))

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

  let exc = newUVError(nread.cint)
  while stream.queuedJob.len > 0:
    let j = stream.queuedJob.popFirst()
    failSoon(j.env, exc)

proc enqueueReadJob(stream: Stream, r: ReadJob): cint {.inline.} =
  if uv_is_active(cast[ptr uv_stream_t](stream.uv_handle)) != 0:
    stream.queuedJob.addLast(r)
    return

  let err = uv_read_start(cast[ptr uv_stream_t](stream.uv_handle), allocCb,
      cast[uv_read_cb](readCb))
  if err == 0:
    stream.queuedJob.addLast(r)
    return

  err

proc readSome*(
    stream: Stream, buf: Buf, env: ptr ReadBufEnv) {.asyncRaw.} =
  let j = ReadJob(env: env, buf: buf)

  let err = enqueueReadJob(stream, j)
  if err != 0:
    failSoon(env, newUVError(err))
    return

proc writeSome*(stream: Stream, buf: Buf): Future[int] =
  writeSome(stream, 1, buf.addr)

proc writeSome*(stream: Stream, bufs: openArray[Buf]): Future[int] =
  writeSome(stream, bufs.len, bufs[0].addr)
