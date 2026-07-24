//// A bounded parallel map on plain BEAM processes. Each JVM pack is a
//// separate OS process.

import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/pair

/// Run `run` over every item with at most `limit` items in flight at once.
/// Results are returned in input order.
pub fn map(items: List(a), limit limit: Int, run run: fn(a) -> b) -> List(b) {
  let replies = process.new_subject()
  let indexed = list.index_map(items, fn(item, index) { #(index, item) })
  let #(running, queued) = list.split(indexed, at: int.max(limit, 1))
  list.each(running, start(replies, _, run))
  collect(replies, queued, run, list.length(indexed), [])
}

fn start(replies: Subject(#(Int, b)), job: #(Int, a), run: fn(a) -> b) -> Nil {
  let #(index, item) = job
  process.spawn(fn() { process.send(replies, #(index, run(item))) })
  Nil
}

fn collect(
  replies: Subject(#(Int, b)),
  queued: List(#(Int, a)),
  run: fn(a) -> b,
  remaining: Int,
  finished: List(#(Int, b)),
) -> List(b) {
  case remaining {
    0 ->
      finished
      |> list.sort(fn(left, right) { int.compare(left.0, right.0) })
      |> list.map(pair.second)
    _ -> {
      let reply = process.receive_forever(replies)
      let queued = case queued {
        [] -> []
        [next, ..rest] -> {
          start(replies, next, run)
          rest
        }
      }
      collect(replies, queued, run, remaining - 1, [reply, ..finished])
    }
  }
}
