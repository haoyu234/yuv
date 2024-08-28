import uv

type
  UVError* = object of CatchableError
    errorCode*: cint

  Handle* = ptr HandleObj
  HandleObj* = object of RootObj
    uv_handle*: ptr uv_handle_t
    closeCb*: CloseCb

  CloseCb = proc (s: ptr HandleObj) {.raises: [], nimcall.}

proc newUVError*(err: cint): ref UVError =
  (ref UVError)(errorCode: err, msg: $uv_strerror(err))

proc raiseUVError*(err: cint) =
  raise (ref UVError)(errorCode: err, msg: $uv_strerror(err))

proc close*(b: ptr HandleObj) =
  b.closeCb(b)
