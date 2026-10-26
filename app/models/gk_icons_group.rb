# frozen_string_literal: true

# A group of icons across the packs, the instance's own: active or disabled with a reason. Its members are icon
# references (GkIconsGroupMember). A disabled group is not offered; its icons are as their own state says.
class GkIconsGroup < ApplicationRecord
  self.table_name = 'gk_icons_groups'

  has_many :members, -> { order(:position, :id) }, class_name: 'GkIconsGroupMember', foreign_key: :group_id, inverse_of: :group

  validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z0-9][a-z0-9_-]{0,59}\z/ }
  validates :name, presence: true

  def state = chosen == 'disabled' ? 'disabled' : 'active'
end
