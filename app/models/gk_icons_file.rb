# frozen_string_literal: true

# One icon file as the instance has it: the file's content as read from its pack's folder, kept when the file is
# gone from disk. Never deleted (P1); the state says whether it is offered (GkIcons::States).
class GkIconsFile < ApplicationRecord
  self.table_name = 'gk_icons_files'

  include GkIcons::States

  validates :pack, :name, :ext, :sha256, presence: true

  scope :without_content, -> { select(column_names - ['content']) }

  def ref = "#{pack}/#{name}"
end
