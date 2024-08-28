import std/macros

import uv

import ../common

macro defineAToB(F, T: typedesc): untyped =
  let name = newIdentNode("\1intern_" & (repr F) & (repr T))
  result = quote:
    converter `name`*(tp: ptr `F`): ptr `T` =
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
template getLoop*(p: ptr uv_loop_t): auto =
  cast[Loop](uv_loop_get_data(p))

template getLoop*(p: ptr uv_handle_t): auto =
  block:
    let loop = uv_handle_get_loop(p)
    cast[Loop](uv_loop_get_data(loop))

#
proc closeCb*[T](h: Handle) =
  proc closeCb(handle: ptr uv_handle_t) {.cdecl.} =
    let t = cast[T](uv_handle_get_data(handle))
    reset(t[])
    dealloc(t)

  uv_close(h.uv_handle, closeCb)
