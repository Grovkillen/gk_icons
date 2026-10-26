# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_icons_groups.
# The groups of icons. No seed data.
class CreateGkIconsGroups < ActiveRecord::Migration[6.1]
  def change
    create_table "gk_icons_groups" do |t|
      t.string "key", limit: 60, null: false
      t.string "name", null: false
      t.text "description"
      t.integer "position", default: 0, null: false
      t.string "chosen", limit: 20, default: "active", null: false
      t.text "reason"
      t.integer "changed_by_id"
      t.datetime "changed_at", precision: nil
      t.datetime "created_at", null: false, precision: 6
      t.datetime "updated_at", null: false, precision: 6
      t.index ["key"], name: "index_gk_icons_groups_on_key", unique: true
    end
  end
end
