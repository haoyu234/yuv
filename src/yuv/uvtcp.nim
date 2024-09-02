import std/nativesockets

when defined(windows): import winlean else: import posix

import yasync

import ./common
import ./dns
import ./errors
import ./utils
import ./uvexport
import ./uvloop
import ./uvstream

type
  UVTcp* = ptr UVTcpObj
  UVTcpObj = object of UVStreamObj
    uv_tcp: uv_tcp_t
    domain: Domain

  ConnectAddrEnv = object of Cont[cint]
    request: uv_connect_t

proc closeTcp(c: Closeable) =
  proc closeCb(handle: ptr uv_handle_t) {.cdecl.} =
    let t = cast[UVTcp](uv_handle_get_data(handle))
    `=destroy`(t[])
    dealloc(t)

  uv_close(UVTcp(c).uv_tcp.addr, closeCb)

proc createUVTcp*(domain: Domain = AF_INET): UVTcp =
  result = allocObj[UVTcpObj](closeTcp)
  uv_handle_set_data(result.uv_tcp.addr, result)
  setupStream(result, result.uv_tcp.addr)

  let loop = getUVLoop()
  let err = uv_tcp_init(loop.uv_loop.addr, result.uv_tcp.addr)
  if err != 0:
    close(result)
    raiseUVError(UVErrorCode(err))

  result.domain = domain

proc requestCb(request: ptr uv_connect_t, status: cint) {.cdecl.} =
  let env = cast[ptr ConnectAddrEnv](uv_req_get_data(request))
  completeSoon(env, status)

proc connectAddrImpl(
    t: UVTcp, `addr`: ptr SockAddr, env: ptr ConnectAddrEnv
) {.asyncRaw.} =
  uv_req_set_data(env.request.addr, env)
  let err = uv_tcp_connect(env.request.addr, t.uv_tcp.addr, `addr`, requestCb)
  if err != 0:
    completeSoon(env, err)

proc connectAddr*(t: UVTcp, address: string, port: Port) {.async.} =
  let res = await dns.getAddrInfo(address, port)
  defer:
    dns.freeAddrInfo(res)

  var err = UV_EHOSTUNREACH.cint
  for ai in res.items:
    if t.domain != AF_UNSPEC and t.domain.toInt != ai.ai_family:
      continue

    err = await connectAddrImpl(t, ai.ai_addr)
    if err != 0:
      continue
    return

  raiseUVError(UVErrorCode(err))

proc bindAddr*(t: UVTcp, address: string, port: Port) {.async.} =
  let res = await dns.getAddrInfo(address, port, t.domain, flags = AI_PASSIVE)
  defer:
    dns.freeAddrInfo(res)

  var err = UV_UNKNOWN.cint
  for ai in res.items:
    err = uv_tcp_bind(t.uv_tcp.addr, ai.ai_addr, 0)
    if err != 0:
      continue
    return

  raiseUVError(UVErrorCode(err))
