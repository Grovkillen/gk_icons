# frozen_string_literal: true
# Revision: 0.00.003
# Depends on: gk_gui_stuff required (the icon library is drawn on its library primitive; gk_gui_stuff loads before
# gk_icons); optional gk_records, gk_compat, gk_fields, gk_core_stuff (icons in text), gk_scenarios.

require_relative 'extensions/gk_icons/core'
require_relative 'extensions/gk_icons/text'   # Icons in text, the library, the picker
require_relative 'extensions/gk_icons/library' # The icon library on GK GUI Stuff's library: sorts, per page, columns
require_relative 'extensions/gk_icons/packs' # Icon packs, folders outside the plugin, found by themselves
require_relative 'extensions/gk_icons/recipes' # Recipes for common packs, shown on the Packs tab
require_relative 'extensions/gk_icons/history' # The icons' history in records
require_relative 'extensions/gk_icons/measure' # What an icon draws, measured when its pack is read
require_relative 'extensions/gk_icons/store' # The packs in the database, states, sprites
require_relative 'extensions/gk_icons/patches' # The helper in every view, icons in core's formatted text
# The core patches (patches.rb), applied here and again on every reload
GkIcons::Patches.apply!
# Every change of the icons is an event in records (GkIcons::History): states chosen, groups made and changed,
# members in and out, readings that changed something.

Redmine::Plugin.register :gk_icons do
  name        'GK Icons'
  author      'Jimmy Westberg'
  description 'One syntax for external icon packs in wiki text, issues and other plugins'
  version     '1.02.000'
  requires_redmine version_or_higher: '6.0.0'

  settings default: { 'disabled_where_used' => 'shown', 'missing_where_used' => 'shown' }, partial: 'settings/gk_icons_settings'

  menu :admin_menu, :gk_icons_library, { controller: 'gk_icons', action: 'library' },
       caption: :label_gk_icons_library, icon: 'swatch', plugin: 'gk_icons', html: { class: 'icon' }
  # The way in for every signed-in person, an administrator too, while icons.library_for_users is on
  menu :account_menu, :gk_icons_library, { controller: 'gk_icons', action: 'library' },
       caption: :label_gk_icons_library, before: :my_account,
       if: proc { User.current.logged? && GkIcons.feature?('icons.library_for_users') }
end

# The hook gives the client the same icons as the helper
Redmine::Hook.add_listener(GkIcons::Hooks) unless Redmine::Hook.listeners.any?(GkIcons::Hooks)

# Once every plugin is in
Rails.configuration.after_initialize do
  GkIcons::History.register_records! # Records loads after icons
  # Declared functions in records' register, off for a new installation; records loads after icons
  if defined?(::GkRecords::Features) && ::GkRecords::Features.respond_to?(:register)
    ::GkRecords::Features.register('icons.library_for_users', plugin: :gk_icons,
                                                               label: :label_gk_feature_icons_library_for_users,
                                                               help: :text_gk_feature_icons_library_for_users)
    ::GkRecords::Features.register('icons.editor_insert', plugin: :gk_icons,
                                                           label: :label_gk_feature_icons_editor_insert,
                                                           help: :text_gk_feature_icons_editor_insert)
  end
  # Icons in text is an appearance setting in records' register (group Text and links), off for a new installation; a
  # function before, so the page says it moved
  if defined?(::GkRecords::AppearanceSettings)
    ::GkRecords::AppearanceSettings.register(GkIcons::IN_TEXT, plugin: :gk_icons, group: :text, moved_from: :features, anonymous: true,
                                                                preview: 'gk_icons_appearance/previews/in_text',
                                                                label: :label_gk_icons_appearance_in_text, help: :text_gk_icons_appearance_in_text)
  end
end
# Icons in text (icons.in_text) is an appearance setting, off by default; the library for every signed-in person
# (icons.library_for_users) and the button Insert icon in the editor's toolbar (icons.editor_insert) are declared
# functions, off by default.
# The places where an administrator writes a reason, declared in records once every plugin has loaded, required by
# default. A group's reason is asked only when its state changes.
Rails.configuration.after_initialize do
  if defined?(::GkRecords::Reasons)
    ::GkRecords::Reasons.register('icons.choose', plugin: :gk_icons, label: :label_gk_reason_icons_choose, default: :required, admin: true)
    ::GkRecords::Reasons.register('icons.group_state', plugin: :gk_icons, label: :label_gk_reason_icons_group_state, default: :required, admin: true)
    ::GkRecords::Reasons.register('icons.text_fit', plugin: :gk_icons, label: :label_gk_reason_icons_text_fit, default: :required, admin: true)
  end
end

# The names in other languages are gk_fields' (Translations), like every other name an administrator sets; off where
# they are written. After every plugin is in, so that the order plugins load in does not matter.
Rails.configuration.after_initialize do
  if defined?(GkFields::Translations) && GkFields::Translations.respond_to?(:register_type)
    GkFields::Translations.register_type('GkIconsGroup', attrs: %w[name description], label: -> { I18n.t(:label_gk_icons_groups) },
                                         records: -> { GkIconsGroup.order(:id) }, off_controllers: %w[gk_icons])
  end
end
# registrations.yml read through records' one reader: a label the file names that no locale has is written to the
# log at start
Rails.configuration.after_initialize { ::GkRecords::Registrations.check!(:gk_icons) if defined?(::GkRecords::Registrations) }
