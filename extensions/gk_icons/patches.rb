# frozen_string_literal: true

module GkIcons
  # Core patches. Each states what it assumes of core:
  # * ApplicationHelper#textilizable (GkIcons::Text::HelperPatch, text.rb): core's textilizable gives the finished HTML
  #   of every formatted text (wiki pages, descriptions, notes); the codes are replaced in that HTML, after it.
  # * GkIcons::Helper in ActionView::Base: every view class inherits from it, so gk_icon and gk_icons_assets also
  #   answer in views core draws (the plugin's settings page); every name in the module carries the gk_ prefix.
  # Applied at once and again on every reload (to_prepare), each guarded against a second inclusion.
  module Patches
    module_function

    def apply!
      ActionView::Base.include(GkIcons::Helper) unless ActionView::Base.include?(GkIcons::Helper)
      ApplicationHelper.prepend(GkIcons::Text::HelperPatch) unless ApplicationHelper.ancestors.include?(GkIcons::Text::HelperPatch)
    end
  end
end

Rails.application.config.to_prepare { GkIcons::Patches.apply! }
GkIcons::Patches.apply!
