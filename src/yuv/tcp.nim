import std/nativesockets except getAddrInfo, freeAddrInfo

import uv
import yasync

import ./common
import ./loop
import ./dns
import ./stream
import ./server
import ./intern/utils

type
  Tcp* = ptr object of StreamObj
    uv_tcp: uv_tcp_t

  TcpServer* =
    ptr object of StreamServerObj[Tcp]
      uv_tcp: uv_tcp_t

  ConnectAnyAddrEnv = object of Cont[void]
    request: uv_connect_t
    tcp: Tcp
    res: ptr AddrInfo
    closeOnError: bool

  ConnectAddrEnv = object of Cont[Tcp]
    request: uv_connect_t
    tcp: Tcp
    closeOnError: bool

proc createTcp(): Tcp =
  result = cast[typeof(result)](alloc0(sizeof(result[])))

  let loop = getLoop()
  let err = uv_tcp_init(loop.uv_loop.addr, result.uv_tcp.addr)
  if err != 0:
    dealloc(result)
    raiseUVError(err)

  result.closeCb = closeCb[Tcp]
  result.uv_handle = result.uv_tcp.addr

  uv_handle_set_data(result.uv_tcp.addr, result)

template connectAnyAddrImpl(env: ptr ConnectAnyAddrEnv) =
  while true:
    let ai = env.res
    env.res = ai.ai_next

    let err = uv_tcp_connect(env.request.addr, env.tcp.uv_tcp.addr, ai.ai_addr, connectAnyAddrCb)
    if err != 0:
      if not env.res.isNil:
        continue

      if env.closeOnError:
        close(env.tcp)

      failSoon(env, newUVError(err))
    break

proc connectAnyAddrCb(request: ptr uv_connect_t, status: cint) {.cdecl.} =
  let env = cast[ptr ConnectAnyAddrEnv](uv_req_get_data(request))
  if status == 0:
    completeSoon(env)
    return

  if env.res.isNil:
    if env.closeOnError:
      close(env.tcp)

    failSoon(env, newUVError(status))
  else:
    connectAnyAddrImpl(env)

proc connectAnyAddr(
    res: ptr AddrInfo, t: Tcp, closeOnError: bool, env: ptr ConnectAnyAddrEnv
) {.asyncRaw.} =
  env.res = res
  env.tcp = t
  env.closeOnError = closeOnError

  uv_req_set_data(env.request.addr, env)

  connectAnyAddrImpl(env)

proc connectTcp*(
  address: string, port: Port, domain: Domain = AF_INET): Tcp {.async.} =
  let res = await getAddrInfo(address, port, domain)
  defer:
    freeAddrInfo(res)

  result = createTcp()
  await connectAnyAddr(res, result, closeOnError = true)

proc connectAddrCb(request: ptr uv_connect_t, status: cint) {.cdecl.} =
  let env = cast[ptr ConnectAddrEnv](uv_req_get_data(request))
  if status == 0:
    completeSoon(env, env.tcp)
    return

  if env.closeOnError:
    env.tcp.close()

  failSoon(env, newUVError(status))

proc connectTcp*(address: ptr SockAddr,
    env: ptr ConnectAddrEnv) {.asyncRaw.} =
  let t = createTcp()

  env.tcp = t
  env.closeOnError = true

  uv_req_set_data(env.request.addr, env)

  let err = uv_tcp_connect(env.request.addr, t.uv_tcp.addr, address, connectAddrCb)
  if err != 0:
    t.close()
    failSoon(env, newUVError(err))

proc connectionCb(uv_stream: ptr uv_stream_t, pStream: ptr Tcp) =
  let stream = createTcp()

  let new_uv_stream = cast[ptr uv_stream_t](stream.uv_handle)
  let err = uv_accept(uv_stream, new_uv_stream)
  if err != 0:
    close(stream)
    raiseUVError(err)
    return

  pStream[] = stream

proc serveTcp*(address: string, port: Port): TcpServer =
  var storage: Sockaddr_storage

  var err = if ':' notin address:
    uv_ip4_addr(address.cstring, port.cint, cast[ptr Sockaddr_in](storage.addr))
  else:
    uv_ip6_addr(address.cstring, port.cint, cast[ptr Sockaddr_in6](storage.addr))

  if err != 0:
    raiseUVError(err)

  result = cast[typeof(result)](alloc0(sizeof(result[])))
  result.closeCb = closeCb[TcpServer]
  result.connectionCb = connectionCb
  result.uv_handle = result.uv_tcp.addr

  let loop = getLoop()
  err = uv_tcp_init(loop.uv_loop.addr, result.uv_tcp.addr)
  if err != 0:
    dealloc(result)
    raiseUVError(err)

  err = uv_tcp_bind(result.uv_tcp.addr, cast[ptr SockAddr](storage.addr), 0)
  if err != 0:
    close(result)
    raiseUVError(err)

  uv_handle_set_data(result.uv_tcp.addr, result)

proc socketPair*(): tuple[r: Tcp, w: Tcp] =
  var fds: array[2, uv_os_sock_t]
  var err = uv_socketpair(SOCK_STREAM.toInt, 0, fds, UV_NONBLOCK_PIPE.cint,
      UV_NONBLOCK_PIPE.cint)
  if err != 0:
    raiseUVError(err)

  result.r = createTcp()
  err = uv_tcp_open(result.r.uv_tcp.addr, fds[0])
  if err != 0:
    result.r.close()
    raiseUVError(err)

  result.w = createTcp()
  err = uv_tcp_open(result.w.uv_tcp.addr, fds[1])
  if err != 0:
    result.r.close()
    result.w.close()
    raiseUVError(err)
