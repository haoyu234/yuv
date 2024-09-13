import yasync

import ./errors
import ./utils
import ./uvexport
import ./uvloop

type
  FsOpEnv[T] = object of Cont[T]
    request: uv_fs_t

proc completeVoidCb(request: ptr uv_fs_t) {.cdecl.} =
  let env = cast[ptr FsOpEnv[void]](uv_req_get_data(request))
  let err = cast[int](uv_fs_get_result(request))
  defer:
    uv_fs_req_cleanup(request)

  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

  completeSoon(env)

proc unlink*(path: string, env: ptr FsOpEnv[void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_unlink(
    loop.uv_loop.addr, env.request.addr, path.cstring, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc mkdir*(path: string, mode: int, env: ptr FsOpEnv[void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_mkdir(
    loop.uv_loop.addr, env.request.addr, path.cstring, mode.cint, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc mkdtemp*(prefix: string, env: ptr FsOpEnv[string]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  proc completePathCb(request: ptr uv_fs_t) {.cdecl.} =
    let env = cast[ptr FsOpEnv[string]](uv_req_get_data(request))
    let err = cast[int](uv_fs_get_result(request))
    defer:
      uv_fs_req_cleanup(request)

    if err < 0:
      failSoon(env, createUVError(UVErrorCode(err)))
      return

    var path = $uv_fs_get_path(request)
    completeSoon(env, move path)

  let tpl = prefix & "XXXXXX"
  let loop = getUVLoop()
  let err = uv_fs_mkdtemp(
    loop.uv_loop.addr, env.request.addr, tpl.cstring, completePathCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc rmdir*(path: string, env: ptr FsOpEnv[void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_rmdir(
    loop.uv_loop.addr, env.request.addr, path.cstring, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc completeStatCb(request: ptr uv_fs_t) {.cdecl.} =
  let env = cast[ptr FsOpEnv[uv_stat_t]](uv_req_get_data(request))
  let err = cast[int](uv_fs_get_result(request))
  uv_fs_req_cleanup(request)

  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

  let uv_stat = uv_fs_get_statbuf(request)[]
  completeSoon(env, uv_stat)

proc completeStatFsCb(request: ptr uv_fs_t) {.cdecl.} =
  let env = cast[ptr FsOpEnv[uv_statfs_t]](uv_req_get_data(request))
  let err = cast[int](uv_fs_get_result(request))
  defer:
    uv_fs_req_cleanup(request)

  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

  let uv_statfs = cast[ptr uv_statfs_t](uv_fs_get_ptr(request))[]
  completeSoon(env, uv_statfs)

proc stat*(path: string, env: ptr FsOpEnv[uv_stat_t]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_stat(
    loop.uv_loop.addr, env.request.addr, path.cstring, completeStatCb)
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc fstat*(file: uv_file, env: ptr FsOpEnv[uv_stat_t]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_fstat(
    loop.uv_loop.addr, env.request.addr, file, completeStatCb)
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc lstat*(path: string, env: ptr FsOpEnv[uv_stat_t]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_lstat(
    loop.uv_loop.addr, env.request.addr, path.cstring, completeStatCb)
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc statfs*(path: string, env: ptr FsOpEnv[uv_statfs_t]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_statfs(
    loop.uv_loop.addr, env.request.addr, path.cstring, completeStatFsCb)
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc rename*(path, newPath: string, env: ptr FsOpEnv[void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_rename(
    loop.uv_loop.addr, env.request.addr, path.cstring, newPath.cstring, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc fsync*(file: uv_file, env: ptr FsOpEnv[void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_fsync(
    loop.uv_loop.addr, env.request.addr, file, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc fdatasync*(file: uv_file, env: ptr FsOpEnv[void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_fdatasync(
    loop.uv_loop.addr, env.request.addr, file, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc ftruncate*(file: uv_file, offset: int64, env: ptr FsOpEnv[
    void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_ftruncate(
    loop.uv_loop.addr, env.request.addr, file, offset, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc access*(path: string, mode: int, env: ptr FsOpEnv[int]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  proc completeResultCb(request: ptr uv_fs_t) {.cdecl.} =
    let env = cast[ptr FsOpEnv[int]](uv_req_get_data(request))
    let err = cast[int](uv_fs_get_result(request))
    defer:
      uv_fs_req_cleanup(request)

    completeSoon(env, err)

  let loop = getUVLoop()
  let err = uv_fs_access(
    loop.uv_loop.addr, env.request.addr, path.cstring, mode.cint, completeResultCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc chmod*(path: string, mode: int, env: ptr FsOpEnv[void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_chmod(
    loop.uv_loop.addr, env.request.addr, path.cstring, mode.cint, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc fchmod*(file: uv_file, mode: int, env: ptr FsOpEnv[void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_fchmod(
    loop.uv_loop.addr, env.request.addr, file, mode.cint, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc chown*(path: string, uid: uv_uid_t, gid: uv_gid_t, env: ptr FsOpEnv[
    void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_chown(
    loop.uv_loop.addr, env.request.addr, path.cstring, uid, gid, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc fchown*(file: uv_file, uid: uv_uid_t, gid: uv_gid_t, env: ptr FsOpEnv[
    void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_fchown(
    loop.uv_loop.addr, env.request.addr, file, uid, gid, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc lchown*(path: string, uid: uv_uid_t, gid: uv_gid_t, env: ptr FsOpEnv[
    void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_lchown(
    loop.uv_loop.addr, env.request.addr, path.cstring, uid, gid, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc link*(path, newPath: string, env: ptr FsOpEnv[void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_link(
    loop.uv_loop.addr, env.request.addr, path.cstring, newPath.cstring, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc symlink*(path, newPath: string, flags: int, env: ptr FsOpEnv[
    void]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_symlink(
    loop.uv_loop.addr, env.request.addr, path.cstring, newPath.cstring,
    flags.cint, completeVoidCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc completeStringCb(request: ptr uv_fs_t) {.cdecl.} =
  let env = cast[ptr FsOpEnv[string]](uv_req_get_data(request))
  let err = cast[int](uv_fs_get_result(request))
  defer:
    uv_fs_req_cleanup(request)

  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

  let p = cast[cstring](uv_fs_get_ptr(request))
  completeSoon(env, $p)

proc readlink*(path: string, env: ptr FsOpEnv[string]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_readlink(
    loop.uv_loop.addr, env.request.addr, path.cstring, completeStringCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return

proc realpath*(path: string, env: ptr FsOpEnv[string]) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)

  let loop = getUVLoop()
  let err = uv_fs_realpath(
    loop.uv_loop.addr, env.request.addr, path.cstring, completeStringCb
  )
  if err < 0:
    failSoon(env, createUVError(UVErrorCode(err)))
    return
