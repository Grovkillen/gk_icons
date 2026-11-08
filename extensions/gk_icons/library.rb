# frozen_string_literal: true

module GkIcons
  # The icon library's page (the Icons tab) on GK GUI Stuff's library as data (gk_gui_stuff_library): the choices of
  # Sortera, the choices of Per sida and the columns of Lista. Plain Ruby, so that it can be tried without Rails.
  # Sortera: by name A to Z, Z to A, and the server's order (Redmine's, GK's, then each pack, each by name)
  LIBRARY_SORTS = %w[name_asc name_desc group].freeze
  # the library's own larger choices after core's per_page_options (core's setting is not changed)
  LIBRARY_PER_PAGE = [250, 500].freeze

  # core's per page choices and the library's own, whole numbers above nought, each once, in order
  def self.library_per_page(core_options)
    (Array(core_options).map(&:to_i) | LIBRARY_PER_PAGE).select(&:positive?).sort
  end

  # Lista's columns: [key, the heading's locale key, the locale key a screen reader hears for a heading that stands
  # empty]; the icon's heading stands empty and is heard as Ikon, the state is for an administrator
  def self.library_columns(admin)
    [['picture', nil, :label_gk_icons_column_icon], ['name', :field_name], ['group', :text_gk_icons_js_pack]] + (admin ? [['state', :text_gk_icons_js_state]] : [])
  end
end
