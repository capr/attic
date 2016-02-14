---
tagline: unidirectional cdata ring buffers
---

## `local ringbuffer = require'ringbuffer'`

A cdata array ring buffer, which supports adding/removing elements in bulk.

Two actual data structures are implemented:

  * a Lua array buffer, which can hold arbitrary Lua values which can be
  added/removed one by one.

For both kinds of buffers:

  * data can only be added to the tail and removed from the head (FIFO).
  * the buffer is fixed-size and can grow on request.
  * can work with an external buffer or can allocate one internally.

> __NOTE:__ This module can be used with Lua 5.1 but cdatabuffer won't work.

## API

-------------------------------------------------------------- -----------------------------------------------------
__cdata buffers__
`rb.cbuffer(cb) -> cb`                                         create a cdata buffer
`cb:head(i) -> i`                                              normalized offset from head
`cb:tail(i) -> i`                                              normalized offset from tail
`cb:segments() -> i1, n1, i2, n2`                              offsets and sizes of buffer's occupied segments
`cb:free_segments() -> i1, n1, i2, n2`                         offsets and sizes of buffer's free segments
`cb:push(n[, data]) -> i1, n1, i2, n2`                         add data to tail, invoking cb:read()
`cb:pull(n[, data]) -> i1, n1, i2, n2`                         remove data from head, invoking cb:write()
`cb:checksize(n)`                                              grow the buffer to fit at least `n` more elements
`cb:alloc(n) -> cdata`                                         allocator (defaults to ffi.new)
`cb:read(n, dst, di, src, si)`                                 segment reader (defaults to ffi.copy)
`cb:write(n, dst, di, src, si)`                                segment writer (defaults to ffi.copy)
`cb.data -> cdata`                                             the buffer itself
__value buffers__
`rb.vbuffer(vb) -> vb`                                         create a buffer for arbitrary Lua values
`vb:head(i) -> i`                                              normalized offset from head
`vb:tail(i) -> i`                                              normalized offset from tail
`vb:push(v) -> i`                                              add value to tail
`vb:pull() -> v`                                               remove value from head
`vb:checksize(n)`                                              grow the buffer to fit at least `n` more elements
`vb.data -> t`                                                 the buffer itself (a Lua table)
__buffer state__
`b.start -> i`                                                 start index
`b.size -> n`                                                  capacity
`b.length -> n`                                                occupied size
-------------------------------------------------------------- -----------------------------------------------------

__API Notes:__

  * cdatabuffer indices start at 0.
  * valuebuffer indices start at 1.

## Cdata buffers

Cdata buffers apply the ring buffer algorithm to a cdata array.
When `push()` is called with a `data` arg, the `write()` method is called
once or twice with the segments to be written from `data` into the buffer.
When `pull()` is called with a `data` arg, the `read()` method is called once
or twice with the segments to be read from the buffer into `data`.

> __NOTE:__ A cdatabuffer doesn't have to manage an actual buffer. Instead,
it can be used to manage an external resource that the ring buffer logic
can be applied to. To do this pass `data = true` when creating a buffer
to avoid allocating an actual buffer. Call `push()` and `pull()` without
a `data` arg to avoid calls to `write()` and `read()` and use the buffer
state variables `start`, `length` and `size` as you want. Or, pass `true`
to the `data` arg in `push()` and `pull()` and override `read()`
and `write()` to do the actual moving of data.

### `rb.cbuffer(cb) -> cb`

  * cb is a table providing:
    * `size`: the size of the buffer.
    * `data` or `ctype`: the pre-allocated buffer, or the element type
    in which case a `ctype[size]` buffer will be allocated.
    * `start`, `length`: optional, if the buffer comes pre-filled.
    * `alloc`: optional custom allocator, for initial allocation and growing.

## Value buffers

Value buffers hold arbitrary Lua values (nils included) in a table.
For simplicity, values can only be added and removed one by one.

### `rb.vbuffer(vb) -> vb`

  * vb is a table providing:
    * `size`: the size of the buffer.
    * `data`, `start`, `length`: optional, if the buffer comes pre-filled.
