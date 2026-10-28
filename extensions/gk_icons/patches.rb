# frozen_string_literal: true

module GkIcons
  # Core patches. Each states what it assumes of core:
  # * ApplicationHelper#textilizable (GkIcons::Text::HelperPatch, text.rb): core's textilizable gives the finished HTML
  #   of every formatted text (wiki pages, descriptions, notes); the codes are replaced in that HTML, after it.
  # * GkIcons::Helper in ActionView::Base: every view class inherits from it, so gk_icon and gk_icons_assets also
  #   answer in views core draws (the plugin's settings page); every name in the module carries the gk_ prefix.
  # Applied directly from init.rb, which Redmine runs inside to_prepare at start and again after every reload in
  # development mode; each guarded against a second inclusion.
  module Patches
    module_function

    def apply!
      ActionView::Base.include(GkIcons::Helper) unless ActionView::Base.include?(GkIcons::Helper)
      ApplicationHelper.prepend(GkIcons::Text::HelperPatch) unless ApplicationHelper.ancestors.include?(GkIcons::Text::HelperPatch)
    end
  end
end
