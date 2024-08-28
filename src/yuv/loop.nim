import std/deques
import system/ansi_c

import uv
import yasync

import ./common
import ./intern/utils

type
  SchedJobType = enum
    Closure
    Callback

  SchedJob = object
    case kind: SchedJobType
    of Closure:
      closureCb: proc() {.gcsafe, raises: [], closure.}
    of Callback:
      env: pointer
      callbackCb: proc(env: pointer) {.gcsafe, raises: [], nimcall.}

  Loop* =
    ptr object
      closed: bool
      uv_loop*: uv_loop_t
      uv_idle: uv_idle_t
      queuedJob: Deque[SchedJob]

var defaultLoop {.threadvar.}: Loop

proc createLoop*(): Loop =
  result = cast[typeof(result)](alloc0(sizeof(result[])))

  var err = uv_loop_init(result.uv_loop.addr)
  if err != 0:
    dealloc(result)
    assert false, $uv_strerror(err)

  err = uv_idle_init(result.uv_loop.addr, result.uv_idle.addr)
  if err != 0:
    dealloc(result)
    assert false, $uv_strerror(err)

  uv_loop_set_data(result.uv_loop.addr, result)
  uv_handle_set_data(result.uv_idle.addr, result)

proc closeLoop*(loop: Loop) =
  loop.closed = true

  let err = uv_idle_stop(loop.uv_idle.addr)
  assert err == 0

  uv_close(loop.uv_idle.addr, nil)

  var closed = false

  for i in 0 .. 5:
    let err = uv_loop_close(loop.uv_loop.addr)
    if err == 0:
      closed = true
      break

    discard uv_run(loop.uv_loop.addr, UV_RUN_NOWAIT)

  when defined(debug):
    if not closed:
      uv_print_all_handles(loop.uv_loop.addr, cstdout)

  reset(loop[])
  dealloc(loop)

proc getLoop*(): Loop {.inline.} =
  if defaultLoop.isNil:
    defaultLoop = createLoop()
  defaultLoop

proc poll*(loop: Loop) {.inline.} =
  discard uv_run(loop.uv_loop.addr, UV_RUN_ONCE)

proc dump*(loop: Loop) {.inline.} =
  uv_print_all_handles(loop.uv_loop.addr, cstdout)

proc executeJob(j: ptr SchedJob) {.inline, stackTrace: off.} =
  case j.kind
  of Closure:
    j.closureCb()
  of Callback:
    j.callbackCb(j.env)

proc executeQueuedJob(p: ptr uv_idle_t) {.cdecl, stackTrace: off.} =
  let loop = getLoop(p)

  var count = 0
  while loop.queuedJob.len > 0 and count < 512:
    inc count
    let j = loop.queuedJob.popFirst
    executeJob(j.addr)

  if loop.queuedJob.len > 0:
    return

  let err = uv_idle_stop(p)
  if err != 0:
    assert false, $uv_strerror(err)

proc activeQueue(loop: Loop) {.inline.} =
  if uv_is_active(loop.uv_idle.addr) != 0:
    return

  let err = uv_idle_start(loop.uv_idle.addr, executeQueuedJob)
  if err != 0:
    raiseUVError(err)

template enqueueJob(j: SchedJob) =
  let loop = getLoop()
  if loop.closed:
    assert false

  loop.queuedJob.addLast(j)
  activeQueue(loop)

proc callSoon*(cb: proc() {.gcsafe, raises: [].}) {.inline.} =
  enqueueJob SchedJob(kind: Closure, closureCb: cb)

proc callSoon*(
    ctx: pointer, cb: proc(ctx: pointer) {.gcsafe, raises: [], nimcall.}
) {.inline.} =
  enqueueJob SchedJob(kind: Callback, env: ctx, callbackCb: cb)

proc completeSoon*(f: ptr Cont[void]) {.inline.} =
  callSoon f,
    proc(ctx: pointer) =
    let f = cast[ptr Cont[void]](ctx)
    f.complete()

proc completeSoon*[T](f: ptr Cont[T], v: T) {.inline.} =
  callSoon proc() =
    f.complete(v)

proc completeSoon*(f: Future[void]) {.inline.} =
  GC_ref(f)

  let p = cast[pointer](f)
  callSoon p,
    proc(ctx: pointer) =
    let f = cast[Future[void]](ctx)
    GC_unref(f)

    f.complete()

proc completeSoon*[T](f: Future[T], v: T) {.inline.} =
  callSoon proc() =
    f.complete(v)

proc failSoon*[T](f: ptr Cont[T], err: ref Exception) {.inline.} =
  callSoon proc() =
    f.fail(err)

template waitForButDontRead(f) =
  let loop = getLoop()
  while not f.finished:
    poll(loop)

template waitFor*[T](f: Future[T]): T =
  block:
    type Env = asyncCallEnvType(f)
    when Env is void:
      waitForButDontRead(f)
      f.read()
    else:
      if false:
        discard f
      var e: Env
      asyncLaunchWithEnv(e, f)
      waitForButDontRead(e)
      e.read()

#
uv_disable_stdio_inheritance()
