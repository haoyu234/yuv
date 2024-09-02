import yasync

import ./buf
import ./utils
import ./uvexport

type
  Stream* = ptr StreamObj
  StreamObj* = object of CloseableObj
    uv_file*: uv_file
    uv_stream*: ptr uv_stream_t
    readSomeCb*:
      proc(stream: Stream, buf: openArray[Buf]): Future[int] {.raises: [], nimcall.}
    writeSomeCb*:
      proc(stream: Stream, buf: openArray[Buf]): Future[int] {.raises: [], nimcall.}

template toOpenArray(p: ptr Buf, n: int): openArray[Buf] =
  let p2 = cast[ptr UncheckedArray[Buf]](p)
  toOpenArray(p2, 0, n - 1)

proc readSome*(stream: Stream, buf: Buf): Future[int] =
  stream.readSomeCb(stream, toOpenArray(buf.addr, 1))

proc readSome*(stream: Stream, buf: openArray[Buf]): Future[int] =
  stream.readSomeCb(stream, buf)

proc writeSome*(stream: Stream, buf: Buf): Future[int] =
  stream.writeSomeCb(stream, toOpenArray(buf.addr, 1))

proc writeSome*(stream: Stream, buf: openArray[Buf]): Future[int] =
  stream.writeSomeCb(stream, buf)
