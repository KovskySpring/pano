import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/pair

pub type Outcome(value) {
  Finished(value)
  TimedOut
}

pub fn exec(
  items: List(a),
  limit limit: Int,
  timeout timeout: fn(a) -> Int,
  run run: fn(a) -> b,
) -> List(Outcome(b)) {
  let replies = process.new_subject()
  let indexed = list.index_map(items, fn(item, index) { #(index, item) })
  let #(running, queued) = list.split(indexed, at: int.max(limit, 1))
  list.each(running, start(replies, _, timeout, run))
  collect(replies, queued, timeout, run, list.length(indexed), [])
}

fn start(
  replies: Subject(#(Int, Outcome(b))),
  job: #(Int, a),
  timeout: fn(a) -> Int,
  run: fn(a) -> b,
) -> Nil {
  let #(index, item) = job
  process.spawn(fn() {
    let done = process.new_subject()
    let worker = process.spawn_unlinked(fn() { process.send(done, run(item)) })
    let outcome = case process.receive(done, within: timeout(item)) {
      Ok(value) -> Finished(value)
      Error(Nil) -> {
        process.kill(worker)
        TimedOut
      }
    }
    process.send(replies, #(index, outcome))
  })
  Nil
}

fn collect(
  replies: Subject(#(Int, Outcome(b))),
  queued: List(#(Int, a)),
  timeout: fn(a) -> Int,
  run: fn(a) -> b,
  remaining: Int,
  finished: List(#(Int, Outcome(b))),
) -> List(Outcome(b)) {
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
          start(replies, next, timeout, run)
          rest
        }
      }
      collect(replies, queued, timeout, run, remaining - 1, [reply, ..finished])
    }
  }
}
