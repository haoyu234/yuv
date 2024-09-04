import std/macros

import ./buf
import ./uvexport

const DEFAULT_UVBUFS_SIZE* = 32

type
  Closeable* = ptr CloseableObj
  CloseableObj* {.inheritable.} = object
    closeCb: CloseCb

  CloseCb = proc(s: Closeable) {.raises: [], nimcall.}

  UVBufs* = object
    size*: int
    nbufs*: int
    uv_bufs*: array[DEFAULT_UVBUFS_SIZE, uv_buf_t]

proc allocObj*[T: CloseableObj](closeCb: CloseCb): ptr T {.nodestroy.} =
  result = createU(T)
  result[] = default(T)
  result.closeCb = closeCb

proc close*(h: Closeable) =
  if h.isNil:
    return

  h.closeCb(h)

proc setupBufs*(b: var UVBufs, buf: openArray[Buf]) =
  for idx in 0 ..< min(buf.len, DEFAULT_UVBUFS_SIZE):
    inc b.nbufs
    inc b.size, buf[idx].len
    b.uv_bufs[idx] = uv_buf_init(buf[idx], buf[idx].len.cuint)

macro defineAToB(F, T: typedesc): untyped =
  let name = newIdentNode("intern_" & (repr F) & "_" & (repr T))
  result = quote:
    converter `name`*(tp: ptr `F`): ptr `T` {.inline.} =
      cast[ptr `T`](tp)

# handle
defineAToB(uv_async_t, uv_handle_t)
defineAToB(uv_check_t, uv_handle_t)
defineAToB(uv_fs_event_t, uv_handle_t)
defineAToB(uv_fs_poll_t, uv_handle_t)
defineAToB(uv_idle_t, uv_handle_t)
defineAToB(uv_pipe_t, uv_handle_t)
defineAToB(uv_poll_t, uv_handle_t)
defineAToB(uv_prepare_t, uv_handle_t)
defineAToB(uv_process_t, uv_handle_t)
defineAToB(uv_stream_t, uv_handle_t)
defineAToB(uv_tcp_t, uv_handle_t)
defineAToB(uv_timer_t, uv_handle_t)
defineAToB(uv_tty_t, uv_handle_t)
defineAToB(uv_udp_t, uv_handle_t)
defineAToB(uv_signal_t, uv_handle_t)

# request
defineAToB(uv_connect_t, uv_req_t)
defineAToB(uv_write_t, uv_req_t)
defineAToB(uv_shutdown_t, uv_req_t)
defineAToB(uv_udp_send_t, uv_req_t)
defineAToB(uv_fs_t, uv_req_t)
defineAToB(uv_work_t, uv_req_t)
defineAToB(uv_getaddrinfo_t, uv_req_t)
defineAToB(uv_getnameinfo_t, uv_req_t)

# stream
defineAToB(uv_pipe_t, uv_stream_t)
defineAToB(uv_tcp_t, uv_stream_t)
defineAToB(uv_tty_t, uv_stream_t)

#
template getUVLoop*(p: ptr uv_loop_t): auto =
  cast[UVLoop](uv_loop_get_data(p))

template getUVLoop*(p: ptr uv_handle_t): auto =
  block:
    let loop = uv_handle_get_loop(p)
    cast[UVLoop](uv_loop_get_data(loop))
