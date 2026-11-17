# frozen_string_literal: true

module GkIcons
  # The gate to GK GUI Stuff, which icons requires (IDENTITY.yml). The gate asks GK GUI Stuff itself: an older GK GUI
  # Stuff than the lowest base version does not open it, and neither does one whose own gate is closed. A candidate
  # of the required base version opens it. Without it icons does
  # nothing: no helper in the views, no icons in text, no client on the pages, no library, no menus, no pages and no
  # API (the icon files, the names, the packs), no functions, reason places, appearance setting, translations or
  # history in records, no scenario steps. The settings page says the first thing that is not met (GK GUI Stuff is
  # missing, too old, or installed but not active) in one line of core's own form (<p class="warning">) beside the
  # About box; the migrations run all the same, so nothing is lost when GK GUI Stuff
  # comes in. The extension files are still loaded, so another plugin that asks defined?(::GkIcons) and then
  # GkIcons.exists?(name) hears that no icon is there, and draws its own fallback instead of failing.
  # The lowest base version the gate opens for; IDENTITY.yml requires the same base and a test holds the two together
  GUI_STUFF_MIN = '1.05.000'

  #   GkIcons.gui_closed -> nil when the gate is open; otherwise the first thing that is not met: :missing (no GK GUI
  #   Stuff), :old (it does not answer open?, or its base version is older than GUI_STUFF_MIN) or :inactive (its own
  #   gate is closed)
  def self.gui_closed
    return :missing unless defined?(::GkGuiStuff)
    return :old unless ::GkGuiStuff.respond_to?(:open?) && ::GkGuiStuff.respond_to?(:version_at_least?) &&
                       ::GkGuiStuff.version_at_least?(GUI_STUFF_MIN)
    return :inactive unless ::GkGuiStuff.open?

    nil
  rescue StandardError
    :missing
  end

  #   GkIcons.gui? -> true when gui_closed has nothing to say
  def self.gui? = gui_closed.nil?

  module Gate
    # The hook methods a view or controller listener answers (view_*, controller_*, model_*). Redmine asks a listener
    # respond_to?(hook) once and keeps the answer (Redmine::Hook.hook_listeners), so a closed gate keeps every hook of
    # the listener silent. A listener is registered as soon as its class is defined (Listener.inherited), so the gate is
    # in the listener and not only in init.rb.
    HOOK = /\A(view|controller|model)_/

    module Listener
      def respond_to?(name, include_all = false)
        return false if HOOK.match?(name.to_s) && !GkIcons.gui?

        super
      end
    end

    # The plugin's controller (the library, the icon files, the names and the REST API) is closed without GK GUI
    # Stuff: core's 404. A plain before_action, after the ones ApplicationController has (the session, the user, the
    # language), so that the 404 is drawn for the person and in the language of the request; before the controller's
    # own (require_login, require_admin)
    module Controller
      def self.included(base)
        base.before_action :gk_icons_gate
      end

      private

      def gk_icons_gate
        render_404 unless GkIcons.gui?
      end
    end
  end
end
