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

  ConnectAddrEnv = object of Cont[cint]
    request: uv_connect_t

  UnionSockAddrObj {.union.} = object
    sockAddr: Sockaddr
    sockAddr4: Sockaddr_in
    sockAddr6: Sockaddr_in6
    storage: Sockaddr_storage

proc closeTcp(c: Closeable) =
  proc closeCb(handle: ptr uv_handle_t) {.cdecl.} =
    let t = cast[UVTcp](uv_handle_get_data(handle))
    `=destroy`(t[])
    dealloc(t)

  uv_close(UVTcp(c).uv_tcp.addr, closeCb)

proc createUVTcp*(): UVTcp =
  result = allocObj[UVTcpObj](closeTcp)
  uv_handle_set_data(result.uv_tcp.addr, result)
  setupUVStream(result, result.uv_tcp.addr, createUVTcp)

  let loop = getUVLoop()
  let err = uv_tcp_init(loop.uv_loop.addr, result.uv_tcp.addr)
  if err != 0:
    close(result)
    raiseUVError(UVErrorCode(err))

proc createUVTcp*(fd: SocketHandle): UVTcp =
  result = allocObj[UVTcpObj](closeTcp)
  uv_handle_set_data(result.uv_tcp.addr, result)
  setupUVStream(result, result.uv_tcp.addr, createUVTcp)

  let loop = getUVLoop()
  var err = uv_tcp_init(loop.uv_loop.addr, result.uv_tcp.addr)
  if err != 0:
    close(result)
    raiseUVError(UVErrorCode(err))
    return

  err = uv_tcp_open(result.uv_tcp.addr, fd)
  if err != 0:
    close(result)
    raiseUVError(UVErrorCode(err))
    return

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

proc connectAddr*(t: UVTcp, `addr`: ptr SockAddr) {.async.} =
  let err = await connectAddrImpl(t, `addr`)
  if err != 0:
    raiseUVError(UVErrorCode(err))

proc connectAddr*(t: UVTcp, address: string, port: Port,
    domain: Domain = AF_INET) {.async.} =
  let res = await dns.getAddrInfo(address, port)
  defer:
    dns.freeAddrInfo(res)

  var err = UV_EHOSTUNREACH.cint
  for ai in res.items:
    if domain != AF_UNSPEC and domain.toInt != ai.ai_family:
      continue

    err = await connectAddrImpl(t, ai.ai_addr)
    if err != 0:
      continue
    return

  raiseUVError(UVErrorCode(err))

proc bindAddr*(t: UVTcp, `addr`: ptr SockAddr) {.async.} =
  let err = uv_tcp_bind(t.uv_tcp.addr, `addr`, 0)
  if err != 0:
    raiseUVError(UVErrorCode(err))

proc bindAddr*(t: UVTcp, address: string, port: Port,
    domain: Domain = AF_INET) {.async.} =
  let res = await dns.getAddrInfo(address, port, domain, flags = AI_PASSIVE)
  defer:
    dns.freeAddrInfo(res)

  var err = UV_UNKNOWN.cint
  for ai in res.items:
    err = uv_tcp_bind(t.uv_tcp.addr, ai.ai_addr, 0)
    if err != 0:
      continue
    return

  raiseUVError(UVErrorCode(err))

proc getAddrImpl(`addr`: UnionSockAddrObj): (string, Port) {.inline.} =
  var port: uint16
  var source: pointer

  let af = `addr`.sockAddr.sa_family.cint
  case af:
  of AF_INET.toInt:
    port = `addr`.sockAddr4.sin_port
    source = `addr`.sockAddr4.sin_addr.s_addr.addr
  of AF_INET6.toInt:
    port = `addr`.sockAddr6.sin6_port
    source = `addr`.sockAddr6.sin6_addr.s6_addr.addr
  else:
    raiseUVError(UV_EAFNOSUPPORT)

  var buffer: array[46, char]
  let err = uv_inet_ntop(af, source, buffer[0].addr, sizeof(buffer).csize_t)
  if err != 0:
    raiseUVError(UVErrorCode(err))

  result[0] = $cast[cstring](buffer[0].addr)
  result[1] = Port(port)

proc getLocalAddr*(t: UVTcp): (string, Port) =
  var `addr`: UnionSockAddrObj
  var size = sizeof(`addr`).cint

  let err = uv_tcp_getsockname(t.uv_tcp.addr, `addr`.sockAddr.addr, size.addr)
  if err != 0:
    raiseUVError(UVErrorCode(err))
    return

  getAddrImpl(`addr`)

proc getLocalAddr*(t: UVTcp, `addr`: ptr Sockaddr, size: int) =
  var size = size.cint
  let err = uv_tcp_getsockname(t.uv_tcp.addr, `addr`, size.addr)
  if err != 0:
    raiseUVError(UVErrorCode(err))

proc getPeerAddr*(t: UVTcp): (string, Port) =
  var `addr`: UnionSockAddrObj
  var size = sizeof(`addr`).cint

  let err = uv_tcp_getpeername(t.uv_tcp.addr, `addr`.sockAddr.addr, size.addr)
  if err != 0:
    raiseUVError(UVErrorCode(err))
    return

  getAddrImpl(`addr`)

proc getPeerAddr*(t: UVTcp, `addr`: ptr Sockaddr, size: int) =
  var size = size.cint
  let err = uv_tcp_getpeername(t.uv_tcp.addr, `addr`, size.addr)
  if err != 0:
    raiseUVError(UVErrorCode(err))
