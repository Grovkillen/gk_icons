# frozen_string_literal: true

# An icon in a group: the reference as it is written (fa/hammer, or a name of Redmine's or our own)
class GkIconsGroupMember < ApplicationRecord
  self.table_name = 'gk_icons_group_members'

  belongs_to :group, class_name: 'GkIconsGroup', inverse_of: :members

  validates :ref, presence: true, uniqueness: { scope: :group_id }
end
