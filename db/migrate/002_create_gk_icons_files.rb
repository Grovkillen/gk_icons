# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_icons_files.
# The packs' files. No seed data.
class CreateGkIconsFiles < ActiveRecord::Migration[6.1]
  def change
    create_table "gk_icons_files" do |t|
      t.string "pack", limit: 40, null: false
      t.string "name", limit: 200, null: false
      t.string "variant", limit: 60, default: "", null: false
      t.string "ext", limit: 8, null: false
      t.binary "content", null: false
      t.string "sha256", limit: 64, null: false
      t.integer "bytes", null: false
      t.bigint "source_mtime"
      t.boolean "on_disk", default: true, null: false
      t.string "chosen", limit: 20, default: "active", null: false
      t.text "reason"
      t.integer "changed_by_id"
      t.datetime "changed_at", precision: nil
      t.datetime "created_at", null: false, precision: 6
      t.datetime "updated_at", null: false, precision: 6
      t.index ["pack", "name", "variant", "ext"], name: "index_gk_icons_files_ref", unique: true
      t.index ["pack", "updated_at"], name: "index_gk_icons_files_pack_time"
    end
  end
end
