# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_icons_packs.
# The icon packs. No seed data.
# The first migration's down runs last at redmine:plugins:migrate NAME=gk_icons VERSION=0: it also takes away the
# plugin's row in core's settings. The plugin keeps nothing in a person's preferences.
class CreateGkIconsPacks < ActiveRecord::Migration[6.1]
  def up
    create_table "gk_icons_packs" do |t|
      t.string "key", limit: 40, null: false
      t.string "name"
      t.string "license"
      t.string "version"
      t.text "attribution"
      t.boolean "mono", default: true, null: false
      t.string "default_variant", limit: 60, default: "", null: false
      t.text "aliases"
      t.string "root", limit: 1000
      t.boolean "on_disk", default: true, null: false
      t.string "chosen", limit: 20, default: "active", null: false
      t.text "reason"
      t.integer "changed_by_id"
      t.datetime "changed_at", precision: nil
      t.datetime "created_at", null: false, precision: 6
      t.datetime "updated_at", null: false, precision: 6
      t.index ["key"], name: "index_gk_icons_packs_on_key", unique: true
    end
  end

  def down
    drop_table "gk_icons_packs"
    Setting.where(name: 'plugin_gk_icons').delete_all
  end
end
