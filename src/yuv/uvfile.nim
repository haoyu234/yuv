import yasync

import ./buf
import ./errors
import ./stream
import ./utils
import ./uvexport
import ./uvloop

type
  UVFile = ptr UVFileObj
  UVFileObj = object of Stream
    request: uv_fs_t

  FileOpEnv[T] = object of Cont[T]
    request: uv_fs_t
    file: UVFile

proc closeFile(c: Closeable) =
  proc closeCb(request: ptr uv_fs_t) {.cdecl.} =
    let f = cast[UVFile](uv_req_get_data(request))
    let err = uv_fs_get_result(request)
    uv_fs_req_cleanup(request)

    if err < 0:
      return

    `=destroy`(f[])
    dealloc(f)

  let f = UVFile(c)
  if f.uv_file.cint != 0:
    let loop = getUVLoop()
    let err = uv_fs_close(loop.uv_loop.addr, f.request.addr, f.uv_file, closeCb)
    if err != 0:
      echo UVErrorCode(err)

proc streamCb[T: static bool](
    stream: Stream, buf: openArray[Buf], env: ptr FileOpEnv[int]
) {.asyncRaw.} =
  if buf.len <= 0:
    completeSoon(env, 0)
    return

  let loop = getUVLoop()

  var uv_bufs: UVBufs
  let stream = UVFile(stream)

  setupBufs(uv_bufs, buf)
  uv_req_set_data(env.request.addr, env)

  proc completeCb(request: ptr uv_fs_t) {.cdecl.} =
    let env = cast[ptr FileOpEnv[int]](uv_req_get_data(request))
    let err = cast[int](uv_fs_get_result(request))
    uv_fs_req_cleanup(request)

    if err < 0:
      failSoon(env, createUVError(UVErrorCode(err)))
      return

    completeSoon(env, err.int)

  when T:
    let err = uv_fs_read(
      loop.uv_loop.addr,
      env.request.addr,
      stream.uv_file,
      uv_bufs.uv_bufs[0].addr,
      uv_bufs.nbufs.cuint,
      0,
      completeCb,
    )
  else:
    let err = uv_fs_write(
      loop.uv_loop.addr,
      env.request.addr,
      stream.uv_file,
      uv_bufs.uv_bufs[0].addr,
      uv_bufs.nbufs.cuint,
      0,
      completeCb,
    )

  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc setupStream(stream: Stream) =
  stream.readSomeCb = streamCb[true]
  stream.writeSomeCb = streamCb[false]

proc createUVFile(): UVFile =
  result = allocObj[UVFileObj](closeFile)
  uv_req_set_data(result.request.addr, result)
  setupStream(result)

proc openCb(request: ptr uv_fs_t) {.cdecl.} =
  let result = uv_fs_get_result(request)
  uv_fs_req_cleanup(request)

  let env = cast[ptr FileOpEnv[UVFile]](uv_req_get_data(request))
  if result < 0:
    failSoon(env, createUVError(UVErrorCode(result)))
    return

  let f = createUVFile()
  f.uv_file = result.uv_file

  completeSoon(env, f)

proc openFile*(fd: uv_file): UVFile =
  result = createUVFile()
  result.uv_file = fd

proc openFile*(
    path: string, flags: int, mode: int, env: ptr FileOpEnv[UVFile]
) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_open(
    loop.uv_loop.addr, env.request.addr, path.cstring, flags.cint, mode.cint, openCb
  )
  if err != 0:
    failSoon(env, createUVError(UVErrorCode(err)))
