import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/pair

pub type Outcome(value) {
  Finished(value)
  TimedOut
}

/// What the pool reports as it works, for callers that want to show progress.
///
/// `Waiting` means nothing happened for a whole poll interval — it is what
/// drives an animation between real events.
pub type Event(value) {
  Started(index: Int)
  Settled(index: Int, outcome: Outcome(value))
  Waiting
}

// Everything that stays fixed for the duration of a run, so the collect loop
// keeps a readable signature.
type Runner(a, b, s) {
  Runner(
    replies: Subject(#(Int, Outcome(b))),
    timeout: fn(a) -> Int,
    run: fn(a) -> b,
    poll: Int,
    on_event: fn(s, Event(b)) -> s,
  )
}

/// Run `items` with at most `limit` in flight. Outcomes come back in the order
/// the items were given, whatever order they finished in.
pub fn exec(
  items: List(a),
  limit limit: Int,
  timeout timeout: fn(a) -> Int,
  run run: fn(a) -> b,
) -> List(Outcome(b)) {
  exec_observed(
    items,
    limit:,
    timeout:,
    run:,
    poll: 0,
    state: Nil,
    on: fn(state, _event) { state },
  )
  |> pair.first
}

/// `exec`, plus a fold over the run's events.
///
/// `on_event` runs on the collecting process, so it can own display state with
/// no locking at all: it is handed the current state and returns the next one.
/// `poll` is how often, in milliseconds, to emit `Waiting` when nothing else
/// has happened; 0 waits indefinitely and so never emits it.
pub fn exec_observed(
  items: List(a),
  limit limit: Int,
  timeout timeout: fn(a) -> Int,
  run run: fn(a) -> b,
  poll poll: Int,
  state state: s,
  on on_event: fn(s, Event(b)) -> s,
) -> #(List(Outcome(b)), s) {
  let runner =
    Runner(replies: process.new_subject(), timeout:, run:, poll:, on_event:)

  let indexed = list.index_map(items, fn(item, index) { #(index, item) })
  let #(running, queued) = list.split(indexed, at: int.max(limit, 1))

  let state =
    list.fold(running, state, fn(state, job) {
      start(runner, job)
      on_event(state, Started(job.0))
    })

  collect(runner, queued, list.length(indexed), [], state)
}

fn start(runner: Runner(a, b, s), job: #(Int, a)) -> Nil {
  let #(index, item) = job
  process.spawn(fn() {
    let done = process.new_subject()
    let worker =
      process.spawn_unlinked(fn() { process.send(done, runner.run(item)) })
    let outcome = case process.receive(done, within: runner.timeout(item)) {
      Ok(value) -> Finished(value)
      Error(Nil) -> {
        process.kill(worker)
        TimedOut
      }
    }
    process.send(runner.replies, #(index, outcome))
  })
  Nil
}

fn collect(
  runner: Runner(a, b, s),
  queued: List(#(Int, a)),
  remaining: Int,
  finished: List(#(Int, Outcome(b))),
  state: s,
) -> #(List(Outcome(b)), s) {
  case remaining {
    0 -> #(
      finished
        |> list.sort(fn(left, right) { int.compare(left.0, right.0) })
        |> list.map(pair.second),
      state,
    )
    _ ->
      case await(runner) {
        Error(Nil) ->
          collect(
            runner,
            queued,
            remaining,
            finished,
            runner.on_event(state, Waiting),
          )
        Ok(reply) -> {
          let #(index, outcome) = reply
          let state = runner.on_event(state, Settled(index, outcome))

          // A slot just freed up, so pull the next job in.
          let #(queued, state) = case queued {
            [] -> #([], state)
            [next, ..rest] -> {
              start(runner, next)
              #(rest, runner.on_event(state, Started(next.0)))
            }
          }

          collect(runner, queued, remaining - 1, [reply, ..finished], state)
        }
      }
  }
}

fn await(runner: Runner(a, b, s)) -> Result(#(Int, Outcome(b)), Nil) {
  case runner.poll {
    poll if poll <= 0 -> Ok(process.receive_forever(runner.replies))
    poll -> process.receive(runner.replies, within: poll)
  }
}
