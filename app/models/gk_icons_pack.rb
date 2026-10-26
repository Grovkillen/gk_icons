# frozen_string_literal: true

# A pack as the instance has it: read from its folder, shown or not by an administrator's choice.
# The state is what the two say together (GkIcons::States): missing when the folder is gone, otherwise the choice.
class GkIconsPack < ApplicationRecord
  self.table_name = 'gk_icons_packs'

  include GkIcons::States

  validates :key, presence: true, uniqueness: true

  def alias_map
    JSON.parse(aliases.presence || '{}')
  rescue JSON::ParserError
    {}
  end
end
