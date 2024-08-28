import std/options
import std/deques
import std/posix

import uv
import yasync

import ./common
import ./loop
import ./stream
import ./intern/utils

type
  Process* = ptr ProcessObj
  ProcessObj* = object of HandleObj
    uv_process*: uv_process_t
    exitCode: Option[int64]
    queuedEnv: Deque[ptr ExitCodeEnv]

  ExitCodeEnv = object of Cont[int64]

  # Popen* = ref object
  #   process: Process
  #   stdin: Stream
  #   stdout: Stream
  #   stderr: Stream

proc addCString(result: var seq[cstring], s: string) =
  result.add(s.cstring)

proc addCString(result: var seq[cstring], ss: openArray[string]) =
  for s in ss:
    result.add(s.cstring)

  result.add(nil)

proc createProcess(): Process =
  result = cast[typeof(result)](alloc0(sizeof(result[])))
  result.closeCb = closeCb[Process]
  result.uv_handle = result.uv_process.addr

proc exitCb(param: ptr uv_process_t, exit_status: int64,
    term_signal: cint) {.cdecl.} =
  let p = cast[Process](uv_handle_get_data(param))

  var exitCode = exit_status
  if term_signal > 0:
    exitCode = - term_signal

  p.exitCode = some(exitCode)
  while p.queuedEnv.len > 0:
    let waitEnv = p.queuedEnv.popFirst()
    completeSoon(waitEnv, exitCode)

proc spawn*(executable: string, workdir: string = "",
  args: openArray[string] = @[], env: openArray[string] = @[],
  stdin: sink Stream = nil, stdout: sink Stream = nil,
      stderr: sink Stream = nil): Process =

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

  template setupStdioOpt(opt, s) =
    if s.isNil:
      opt.data.stream = nil
      opt.flags = UV_IGNORE
    else:
      let uv_stream = cast[ptr uv_stream_t](s.uv_handle)
      opt.data.stream = uv_stream
      opt.flags = UV_INHERIT_STREAM

  setupStdioOpt(stdio_opts[0], stdin)
  setupStdioOpt(stdio_opts[1], stdout)
  setupStdioOpt(stdio_opts[2], stderr)

  let loop = getLoop()
  result = createProcess()

  uv_handle_set_data(result.uv_process.addr, result)

  let err = uv_spawn(loop.uv_loop.addr, result.uv_process.addr, options.addr)
  if err != 0:
    result.close()
    raiseUVError(err)

proc exitCode*(p: Process, env: ptr ExitCodeEnv) {.asyncRaw.} =
  if p.exitCode.isSome:
    completeSoon(env, p.exitCode.get)
    return

  p.queuedEnv.addLast(env)

proc kill*(p: Process, sig: int) =
  assert sig > 0

  let err = uv_process_kill(p.uv_process.addr, sig.cint)
  if err != 0:
    raiseUVError(err)
