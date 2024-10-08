import yasync

import ./errors
import ./utils
import ./uvexport
import ./uvloop

type SleepEnv = object of Cont[void]
  uv_timer: uv_timer_t

proc time*(): uint64 =
  let loop = getUVLoop()
  uv_now(loop.uv_loop.addr)

proc sleep*(ms: uint64, env: ptr SleepEnv) {.asyncRaw.} =
  let loop = getUVLoop()
  var err = uv_timer_init(loop.uv_loop.addr, env.uv_timer.addr)
  if err != 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

  uv_handle_set_data(env.uv_timer.addr, env)

  proc closeCb(handle: ptr uv_handle_t) {.cdecl.} =
    let env = cast[ptr SleepEnv](uv_handle_get_data(handle))
    completeSoon(env)

  proc sleepCb(handle: ptr uv_timer_t) {.cdecl.} =
    uv_close(handle, closeCb)

  err = uv_timer_start(env.uv_timer.addr, sleepCb, ms, 0)
  if err != 0:
    uv_close(env.uv_timer.addr, nil)
    failSoon(env, createUVError(UVErrorCode(err)))
    return
