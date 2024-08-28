{.experimental: "views".}

type
  Buf* = object
    len: int
    data: ptr UncheckedArray[byte]

  Byte = byte | char | int8 | uint8

template len*(s: Buf): int =
  s.len

proc toBuf*(data: pointer, len: int): Buf {.inline.} =
  result.len = len
  result.data = cast[ptr UncheckedArray[byte]](data)

proc toBuf*(data: ptr UncheckedArray[Byte], len: int): Buf {.inline.} =
  result.len = len
  result.data = cast[ptr UncheckedArray[byte]](data)

proc toBuf*(d: string): Buf {.inline.} =
  result.len = d.len
  result.data = cast[ptr UncheckedArray[byte]](d[0].addr)

proc toBuf*(d: openArray[Byte]): Buf {.inline.} =
  result.len = d.len
  result.data = cast[ptr UncheckedArray[byte]](d[0].addr)

proc toBuf*[S](d: array[S, Byte]): Buf {.inline.} =
  result.len = d.len
  result.data = cast[ptr UncheckedArray[byte]](d[0].addr)

template toOpenArray*(s: Buf): openArray[byte] =
  s.data.toOpenArray(0, s.len - 1)

proc toSeq*(s: Buf): seq[byte] {.inline.} =
  result.add(s.toOpenArray())

proc toUncheckedArray*[T](s: Buf): ptr UncheckedArray[T] {.inline.} =
  cast[ptr UncheckedArray[T]](cast[uint](s.data))

converter autoToPointer*(s: Buf): pointer =
  s.data

converter autoToOpenArray*(s: Buf): openArray[byte] =
  s.toOpenArray()

converter autoUncheckedArray*[T](s: Buf): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](cast[uint](s.data))

template `^^`*(s, i: untyped): untyped =
  (when i is BackwardsIndex: s.len - int(i) else: int(i))

template checkSliceOp(len, l, r: untyped) =
  let
    l2 = l
    r2 = r
    len2 = len

  if l2 > len2:
    raise newException(IndexDefect, formatErrorIndexBound(l2, len2))

  if r2 > len2:
    raise newException(IndexDefect, formatErrorIndexBound(r2, len2))

proc `[]`*[U, V: Ordinal](s: Buf, x: HSlice[U, V]): Buf =
  let a = s ^^ x.a
  let L = (s ^^ x.b) - a + 1

  checkSliceOp(s.len, a, a + L)

  result.len = L
  result.data = cast[ptr UncheckedArray[byte]](s.data[a].addr)

template equalsImpl(T, opIdx) {.dirty.} =
  proc `==`*(s: Buf, d: T): bool =
    result = false
    let data = s.data

    if s.len == d.len:
      for i in 0 .. s.len - 1:
        if data[i] == opIdx:
          continue

      result = true

  when not T is Buf:
    template `==`*(d: T, s: Buf): bool =
      `==`(s, d)

equalsImpl(Buf, d.data[i])
equalsImpl(seq[Byte], d[i])
equalsImpl(openArray[Byte], d[i])

proc `==`*[S](s: Buf, d: array[S, Byte]): bool =
  result = false
  let data = s.data
  let L = s.len

  if L == d.len:
    for i in 0 ..< L:
      if data[i] == d[i]:
        continue

    result = true

template `==`*[S](d: array[S, Byte], s: Buf): bool =
  `==`(s, d)

proc `$`*(s: Buf): string =
  let data = s.data
  let L = s.len

  result = newStringOfCap((L + 1) * 3)
  result.add("Buf[")

  let L2 = L - 1

  for i in 0 ..< L2:
    result.add($data[i])
    result.add(", ")

  result.add($data[L2])
  result.add(']')
