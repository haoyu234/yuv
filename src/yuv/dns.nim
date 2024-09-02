import std/nativesockets

when defined(linux):
  import std/posix

import yasync

import ./errors
import ./utils
import ./uvexport
import ./uvloop

type GetAddrInfoEnv = object of Cont[ptr AddrInfo]
  request: uv_getaddrinfo_t

proc getAddrInfoCb(
    request: ptr uv_getaddrinfo_t, status: cint, res: ptr AddrInfo
) {.cdecl.} =
  let env = cast[ptr GetAddrInfoEnv](uv_req_get_data(request))
  if status != 0:
    failSoon(env, createUVError(UVErrorCode(status)))
  else:
    completeSoon(env, res)

proc getAddrInfo*(
    address: string,
    port: Port,
    domain: Domain = AF_INET,
    sockType: SockType = SOCK_STREAM,
    protocol: Protocol = IPPROTO_TCP,
    flags: cint = 0,
    env: ptr GetAddrInfoEnv,
) {.asyncRaw.} =
  var hints: AddrInfo
  hints.ai_family = toInt(domain)
  hints.ai_socktype = toInt(sockType)
  hints.ai_protocol = toInt(protocol)
  hints.ai_flags = flags

  # OpenBSD doesn't support AI_V4MAPPED and doesn't define the macro AI_V4MAPPED.
  # FreeBSD, Haiku don't support AI_V4MAPPED but defines the macro.
  # https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=198092
  # https://dev.haiku-os.org/ticket/14323

  when not defined(freebsd) and not defined(openbsd) and not defined(netbsd) and
      not defined(android) and not defined(haiku):
    if domain == AF_INET6:
      hints.ai_flags = flags or AI_V4MAPPED

  let socketPort =
    if sockType == SOCK_RAW:
      ""
    else:
      $port

  let loop = getUVLoop()

  uv_req_set_data(env.request.addr, env)

  let err = uv_getaddrinfo(
    loop.uv_loop.addr, env.request.addr, getAddrInfoCb, address.cstring,
    socketPort.cstring, hints.addr,
  )
  if err != 0:
    failSoon(env, createUVError(UVErrorCode(err)))

proc freeAddrInfo*(res: ptr AddrInfo) =
  uv_freeaddrinfo(res)
