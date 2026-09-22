//// A multi-line spinner display: one row per job, redrawn in place on stderr.
////
//// ```gleam
//// let display =
////   rows.new()
////   |> rows.add("0", "ui.png")
////   |> rows.add("1", "characters.png")
////
//// let display = rows.set_status(display, "0", rows.Running) |> rows.render
//// // ...later, every ~80ms...
//// let display = rows.tick(display) |> rows.render
//// // ...at the end...
//// rows.finish(display)
//// ```

import gleam/int
import gleam/io
import gleam/list
import gleam/string

import gleam_community/ansi

/// Where a job is in its life. `note` on the row carries any detail.
pub type Status {
  Queued
  Running
  Done
  Failed
}

type Row {
  Row(id: String, label: String, status: Status, note: String)
}

pub opaque type Rows {
  Rows(
    rows: List(Row),
    frames: List(String),
    tick: Int,
    label_width: Int,
    drawn: Bool,
  )
}

// The spinner frames. Braille dots read well at small sizes and are a single
// column wide in every terminal font we care about.
const default_frames = [
  "\u{280B}", "\u{2819}", "\u{2839}", "\u{2838}", "\u{283C}", "\u{2834}",
  "\u{2826}", "\u{2827}", "\u{2807}", "\u{280F}",
]

const queued_glyph = "\u{00B7}"

const done_glyph = "\u{2713}"

const failed_glyph = "\u{2717}"

// Two spaces, matching the indent the rest of pano's output uses.
const indent = "  "

const indent_width = 2

// Columns between the label and the status detail.
const gap_width = 2

// Labels longer than this are ellipsised, so the rows stay aligned and a long
// pack name can never wrap a line.
const max_label_width = 32

// Fallback when the terminal size is unknown.
const fallback_width = 80

const clear_line = "\u{001b}[2K"

const line_start = "\r"

const hide_cursor = "\u{001b}[?25l"

const show_cursor = "\u{001b}[?25h"

fn cursor_up(n: Int) -> String {
  case n {
    0 -> ""
    _ -> "\u{001b}[" <> int.to_string(n) <> "A"
  }
}

/// Create an empty display.
pub fn new() -> Rows {
  Rows(rows: [], frames: default_frames, tick: 0, label_width: 0, drawn: False)
}

/// Replace the spinner frames.
pub fn with_frames(rows rows: Rows, frames frames: List(String)) -> Rows {
  case frames {
    [] -> rows
    _ -> Rows(..rows, frames:)
  }
}

/// Append a row. `id` addresses it later and must be unique; `label` is shown.
/// Rows are displayed in the order they were added.
pub fn add(rows rows: Rows, id id: String, label label: String) -> Rows {
  Rows(
    ..rows,
    rows: list.append(rows.rows, [Row(id:, label:, status: Queued, note: "")]),
    label_width: int.min(
      max_label_width,
      int.max(rows.label_width, string.length(label)),
    ),
  )
}

/// Set a row's status. Unknown ids are ignored.
pub fn set_status(
  rows rows: Rows,
  id id: String,
  status status: Status,
) -> Rows {
  update(rows, id, fn(row) { Row(..row, status:) })
}

/// Set the detail text shown after a row's status, e.g. "3 pages, 412 frames".
/// Pass "" to fall back to the status word. Unknown ids are ignored.
pub fn set_note(rows rows: Rows, id id: String, note note: String) -> Rows {
  update(rows, id, fn(row) { Row(..row, note:) })
}

fn update(rows: Rows, id: String, with: fn(Row) -> Row) -> Rows {
  Rows(
    ..rows,
    rows: list.map(rows.rows, fn(row) {
      case row.id == id {
        True -> with(row)
        False -> row
      }
    }),
  )
}

/// Advance the spinner animation by one frame.
pub fn tick(rows rows: Rows) -> Rows {
  Rows(..rows, tick: rows.tick + 1)
}

/// Repaint every row in place.
pub fn render(rows rows: Rows) -> Rows {
  let width = terminal_width()
  let body =
    rows.rows
    |> list.map(fn(row) {
      clear_line <> line_start <> render_row(rows, row, width) <> "\n"
    })
    |> string.concat

  // The first frame lands wherever the cursor already is; every frame after
  // that has to climb back over the one before it.
  let prefix = case rows.drawn {
    True -> cursor_up(list.length(rows.rows))
    False -> hide_cursor
  }

  io.print_error(prefix <> body)
  Rows(..rows, drawn: True)
}

/// Paint one last frame and give the cursor back. Call this once, at the end.
pub fn finish(rows rows: Rows) -> Nil {
  let _ = render(rows)
  io.print_error(show_cursor)
}

fn render_row(rows: Rows, row: Row, width: Int) -> String {
  let #(glyph, paint, fallback) = case row.status {
    Queued -> #(queued_glyph, ansi.grey, "queued")
    Running -> #(frame_at(rows.frames, rows.tick), ansi.cyan, "packing")
    Done -> #(done_glyph, ansi.green, "done")
    Failed -> #(failed_glyph, ansi.red, "failed")
  }

  let detail = case row.note {
    "" -> fallback
    note -> note
  }

  // Everything before the detail is fixed width, so what is left for the
  // detail is what keeps the line from wrapping. Truncate before colouring —
  // slicing a string that already holds escape sequences would cut one open.
  let used = indent_width + 1 + 1 + rows.label_width + gap_width
  let detail = truncate(detail, int.max(0, width - used))

  indent
  <> paint(glyph)
  <> " "
  <> pad_right(truncate(row.label, rows.label_width), rows.label_width)
  <> string.repeat(" ", gap_width)
  <> paint(detail)
}

fn frame_at(frames: List(String), tick: Int) -> String {
  let count = list.length(frames)
  case list.drop(frames, tick % count) {
    [frame, ..] -> frame
    [] -> queued_glyph
  }
}

fn pad_right(text: String, to width: Int) -> String {
  text <> string.repeat(" ", int.max(0, width - string.length(text)))
}

fn truncate(text: String, to width: Int) -> String {
  case width <= 0, string.length(text) <= width {
    True, _ -> ""
    _, True -> text
    _, False -> string.slice(text, 0, width - 1) <> "\u{2026}"
  }
}

fn terminal_width() -> Int {
  case terminal_columns() {
    Ok(columns) -> columns
    Error(Nil) -> fallback_width
  }
}

@external(erlang, "pano_ffi", "terminal_columns")
fn terminal_columns() -> Result(Int, Nil)
