# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_icons_group_members.
# The groups' members. No seed data.
class CreateGkIconsGroupMembers < ActiveRecord::Migration[6.1]
  def change
    create_table "gk_icons_group_members" do |t|
      t.integer "group_id", null: false
      t.string "ref", limit: 250, null: false
      t.integer "position", default: 0, null: false
      t.integer "added_by_id"
      t.datetime "created_at", null: false, precision: 6
      t.datetime "updated_at", null: false, precision: 6
      t.index ["group_id", "ref"], name: "index_gk_icons_group_members_ref", unique: true
    end
  end
end
