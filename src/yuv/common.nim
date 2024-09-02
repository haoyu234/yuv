import std/nativesockets

import ./errors
import ./uvexport

iterator items*(res: ptr AddrInfo): ptr AddrInfo =
  var res = res
  while not res.isNil:
    yield res
    res = res.ai_next

proc `$`*(`addr`: ptr SockAddr): string =
  var source: pointer
  var buffer: array[46, char]

  let af = `addr`.sa_family.cint
  case af
  of AF_INET.toInt:
    source = cast[ptr Sockaddr_in](`addr`).sin_addr.s_addr.addr
  of AF_INET6.toInt:
    source = cast[ptr Sockaddr_in6](`addr`).sin6_addr.s6_addr.addr
  else:
    raiseUVError(UV_EAFNOSUPPORT)

  let err = uv_inet_ntop(af, source, buffer[0].addr, sizeof(buffer).csize_t)
  if err != 0:
    raiseUVError(UVErrorCode(err))

  $cast[cstring](buffer[0].addr)
