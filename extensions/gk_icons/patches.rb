# frozen_string_literal: true

module GkIcons
  # Core patches. Each states what it assumes of core:
  # * No patch on textilizable: the codes in formatted text (wiki pages, descriptions, notes) are replaced in the runs
  #   of text GK Core Stuff's formatting_processors hands, where GkIcons::Text::Processor is registered as this
  #   plugin's text processor (text.rb). Without GK Core Stuff the codes stay as written.
  # * GkIcons::Helper in ActionView::Base: every view class inherits from it, so gk_icon and gk_icons_assets also
  #   answer in views core draws (the plugin's settings page); every name in the module carries the gk_ prefix.
  # Applied directly from init.rb, which Redmine runs inside to_prepare at start and again after every reload in
  # development mode; each guarded against a second inclusion.
  module Patches
    module_function

    def apply!
      ActionView::Base.include(GkIcons::Helper) unless ActionView::Base.include?(GkIcons::Helper)
      # icons in formatted text, through GK Core Stuff's pass; again on a reload replaces
      ::GkCoreStuff::FormattingProcessors.register(:gk_icons, text: GkIcons::Text::Processor) if defined?(::GkCoreStuff::FormattingProcessors)
    end
  end
end
