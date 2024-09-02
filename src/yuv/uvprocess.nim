import std/deques
import std/options
import std/posix

import yasync

import ./errors
import ./stream
import ./utils
import ./uvexport
import ./uvloop

type
  UVProcess* = ptr UVProcessObj
  UVProcessObj* = object of CloseableObj
    uv_process*: uv_process_t
    exitCode: Option[int64]
    queuedEnv: Deque[ptr ExitCodeEnv]

  ExitCodeEnv = object of Cont[int64]

proc addCString(result: var seq[cstring], s: string) {.inline.} =
  result.add(s.cstring)

proc addCString(result: var seq[cstring], ss: openArray[string]) {.inline.} =
  for s in ss:
    result.add(s.cstring)

  result.add(nil)

proc closeProcess(c: Closeable) =
  proc closeCb(handle: ptr uv_handle_t) {.cdecl.} =
    let p = cast[UVProcess](uv_handle_get_data(handle))
    `=destroy`(p[])
    dealloc(p)

  uv_close(UVProcess(c).uv_process.addr, closeCb)

proc createProcess(): UVProcess =
  result = allocObj[UVProcessObj](closeProcess)
  uv_handle_set_data(result.uv_process.addr, result)

proc exitCb(param: ptr uv_process_t, exit_status: int64, term_signal: cint) {.cdecl.} =
  let p = cast[UVProcess](uv_handle_get_data(param))

  var exitCode = exit_status
  if term_signal > 0:
    exitCode = -term_signal

  p.exitCode = some(exitCode)
  while p.queuedEnv.len > 0:
    let waitEnv = p.queuedEnv.popFirst()
    completeSoon(waitEnv, exitCode)

proc setupStdioStream(opt: var uv_stdio_container_t, s: Stream) {.inline.} =
  if s.isNil:
    opt.data.fd = 0
    opt.data.stream = nil
    opt.flags = UV_IGNORE
    return

  if s.uv_stream.isNil:
    opt.data.fd = s.uv_file.cint
    opt.flags = UV_INHERIT_FD
    return

  opt.data.stream = s.uv_stream
  opt.flags = UV_INHERIT_STREAM

proc spawn*(
    executable: string,
    workdir: string = "",
    args: openArray[string] = @[],
    env: openArray[string] = @[],
    stdin: Stream = nil,
    stdout: Stream = nil,
    stderr: Stream = nil,
): UVProcess =
  var stdio_opts: array[3, uv_stdio_container_t]
  var options: uv_process_options_t

  var c_args, c_env: seq[cstring]

  addCString(c_args, executable)
  addCString(c_args, args)
  addCString(c_env, env)

  options.file = executable.cstring
  options.exit_cb = exitCb
  options.stdio_count = 3
  options.stdio = stdio_opts[0].addr
  options.cwd = nil
  options.env = c_env[0].addr
  options.args = c_args[0].addr
  options.flags = 0

  if workdir.len > 0:
    options.cwd = workdir.cstring

  setupStdioStream(stdio_opts[0], stdin)
  setupStdioStream(stdio_opts[1], stdout)
  setupStdioStream(stdio_opts[2], stderr)

  let loop = getUVLoop()
  result = createProcess()

  let err = uv_spawn(loop.uv_loop.addr, result.uv_process.addr, options.addr)
  if err != 0:
    result.close()
    raiseUVError(UVErrorCode(err))

proc exitCode*(p: UVProcess, env: ptr ExitCodeEnv) {.asyncRaw.} =
  if p.exitCode.isSome:
    completeSoon(env, p.exitCode.get)
    return

  p.queuedEnv.addLast(env)

proc kill*(p: UVProcess, sig: int) =
  assert sig > 0

  let err = uv_process_kill(p.uv_process.addr, sig.cint)
  if err != 0:
    raiseUVError(UVErrorCode(err))
