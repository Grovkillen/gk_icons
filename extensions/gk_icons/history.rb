# frozen_string_literal: true

module GkIcons
  # The icons' history in records: an icon's or a pack's state chosen, a group made or changed, an icon put in or
  # taken out of a group, and a reading from disk that changed something. The events stand on the pack or the group
  # (records targets gk_icons_pack and gk_icons_group, seen by administrators), with who, when and the reason. The
  # columns chosen, reason, changed_by_id and changed_at hold the latest; records holds all.
  # Without records nothing is written and the icons work as before.
  module History
    KINDS = %w[icons_state_chosen icons_group_made icons_group_changed icons_member_added icons_member_removed icons_read icons_text_fit].freeze

    module_function

    def on? = defined?(::GkRecords::Events) && defined?(::GkRecords::Targets)

    def register_records!
      return unless on?

      admin = ->(_o, u) { u.admin? }
      none = ->(_o, _u) { false }
      lib = ->(_o) { Rails.application.routes.url_helpers.gk_icons_library_path }
      ::GkRecords::Targets.register('gk_icons_pack', model: 'GkIconsPack', visible: admin, editable: none, label: ->(p) { p.name.presence || p.key }, url: lib)
      ::GkRecords::Targets.register('gk_icons_group', model: 'GkIconsGroup', visible: admin, editable: none, label: ->(g) { g.name }, url: lib)
      KINDS.each { |k| ::GkRecords::Kinds.register_event(k, plugin: :gk_icons, label_key: "label_gk_icons_event_#{k}") }
    end

    def write(target, kind, details, reason: nil, user: ::User.current)
      return unless on? && target

      ::GkRecords::Events.write(target, kind, details: details, reason: reason.presence,
                                              user: user&.logged? ? user : nil, origin: user&.logged? ? 'human' : 'system')
    rescue StandardError => e
      Rails.logger.warn("[gk_icons] history not written (#{kind}): #{e.class}: #{e.message}")
    end
  end
end
