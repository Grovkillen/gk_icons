# frozen_string_literal: true

# gk_icons in text: an icon is written :pack/name: in wiki text, descriptions and notes (:fa/hammer:,
# :flags/se:), and :gk/name: for core's icons and the plugin's own (:gk/status-done:). Replaced in the runs of text
# GK Core Stuff's pass (formatting_processors) hands after core has formatted the text, so never inside code, pre, a
# form field or a link's address; the plugin never reads the finished HTML itself. An unknown pack or name is left as
# it was written. Without GK Core Stuff the codes stay as written.
module GkIcons
  module Text
    REF = %r{:([a-z0-9_-]+)/([a-z0-9_.+-]+):}i
    # A drive path or a UNC path written with slashes, in a message (display_path)
    DISPLAY_PATH = %r{(?<![A-Za-z0-9])[A-Za-z]:/[^\s'"<>|]*|(?<![:/\w])//[^\s/'"<>|]+/[^\s'"<>|]*}

    module_function

    # A path built with its base's separator: a base written with backslashes (Windows, UNC) gives backslashes, any
    # other base slashes; a separator at the end of the base or inside a part is not doubled
    def join_path(base, *parts)
      b = base.to_s
      sep = b.include?('\\') ? '\\' : '/'
      [b.sub(%r{[\\/]+\z}, ''), *parts.flat_map { |p| p.to_s.split(%r{[\\/]+}) }.reject(&:empty?)].join(sep)
    end

    # A path, or a message with paths in it (from core, a gem or an exception), as the platform writes paths: with
    # backslashes on Windows. A drive path (C:/...) and a UNC path (//server/...) are rewritten; an address is not.
    def display_path(text)
      sep = File::ALT_SEPARATOR or return text.to_s

      text.to_s.gsub(DISPLAY_PATH) { |m| m.tr('/', sep) }
    end

    # One run of text as HTML with its codes as icons, or nil when it has none that exists. The run is plain text
    # (entities decoded); what is not a code is escaped.
    def replace(text, view)
      return nil unless text.is_a?(String) && text.include?(':') && text.match?(REF)

      changed = false
      out = ERB::Util.html_escape(text).to_str.gsub(REF) do |whole|
        pack = Regexp.last_match(1).downcase
        name = Regexp.last_match(2).downcase
        ref = pack == 'gk' ? name : "#{pack}/#{name}"
        next whole unless GkIcons.exists?(ref)

        changed = true
        # the size follows the text's font and what the icon draws (the stylesheet); 16 stays as the attributes' fallback
        view.gk_icon_in_text(ref, whole.delete(':'))
      end
      changed ? out.html_safe : nil
    end

    # The text processor in GK Core Stuff's formatting_processors, registered in patches.rb: every run of text outside
    # code, pre, a form field, a script and a style, also inside a link's text. An appearance setting, off for a new
    # installation.
    module Processor
      module_function

      def active?(_context) = GkIcons.appearance?(GkIcons::IN_TEXT)

      def call(run, context) = GkIcons::Text.replace(run.text, context.view)
    end
  end
end
