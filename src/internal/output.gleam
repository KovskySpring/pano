//// Emitting one packed atlas: the output filenames, and the copy of the
//// pages plus the Phaser multiatlas JSON out of a pack job's scratch
//// directory.
////
//// libGDX names its pages after the atlas with a 1-based suffix on every page
//// past the first (`ui.png`, `ui2.png`, `ui3.png`, …). pano renames them to a
//// uniform 0-based `<name>-<index>.png` on the way out, which is also what
//// the JSON references.

import filepath
import gleam/int
import gleam/list
import gleam/result
import internal/compat/gdx.{type Page}
import internal/compat/phaser
import internal/file_utils
import simplifile
import snag

/// The output filename for the `index`-th page of `name`, 0-based.
pub fn page_image_name(name: String, index: Int) -> String {
  name <> "-" <> int.to_string(index) <> ".png"
}

/// The output filename for the Phaser multiatlas descriptor of `name`.
pub fn json_name(name: String) -> String {
  name <> ".json"
}

/// Copy every packed page from `from` into `to` under pano's own naming, then
/// write the Phaser multiatlas JSON that indexes them. `scale` is the
/// variant's factor, recorded per texture.
///
/// `from` is the pack job's scratch directory, deleted once the job returns,
/// so anything not copied here is lost. `to` must already exist, and pages
/// left behind by an earlier run with more pages are not removed.
pub fn write(
  name: String,
  pages: List(Page),
  from pack_dir: String,
  to out_dir: String,
  scale scale: Float,
) -> snag.Result(Nil) {
  let named =
    list.index_map(pages, fn(page, index) {
      #(page_image_name(name, index), page)
    })

  use _ <- result.try(
    list.try_each(named, fn(entry) {
      let #(image, page) = entry
      let from = filepath.join(pack_dir, page.image)
      let to = filepath.join(out_dir, image)
      file_utils.context(
        simplifile.copy_file(at: from, to: to),
        while: "copying " <> from <> " to " <> to,
      )
    }),
  )

  let json = filepath.join(out_dir, json_name(name))
  file_utils.context(
    simplifile.write(json, phaser.encode(named, scale)),
    while: "writing " <> json,
  )
}
