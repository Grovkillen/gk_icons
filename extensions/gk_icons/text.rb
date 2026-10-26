# frozen_string_literal: true

# gk_icons in text: an icon is written :pack/name: in wiki text, descriptions and notes (:fa/hammer:,
# :flags/se:), and :gk/name: for core's icons and the plugin's own (:gk/status-done:). Replaced after the
# formatter has made its HTML, in text only: never inside code, pre, a form field or a link's address. An
# unknown pack or name is left as it was written.
module GkIcons
  module Text
    REF = %r{:([a-z0-9_-]+)/([a-z0-9_.+-]+):}i
    SKIP = %w[pre code textarea script style].freeze
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

    def apply(html, view)
      return html unless html.is_a?(String) && html.include?(':') && html.match?(REF)

      doc = Nokogiri::HTML::DocumentFragment.parse(html)
      changed = false
      doc.traverse do |node|
        next unless node.text? && node.content.match?(REF)
        next if node.ancestors.any? { |a| SKIP.include?(a.name) }

        before = changed
        changed = false
        out = ERB::Util.html_escape(node.content).to_str.gsub(REF) do |whole|
          pack = Regexp.last_match(1).downcase
          name = Regexp.last_match(2).downcase
          ref = pack == 'gk' ? name : "#{pack}/#{name}"
          next whole unless GkIcons.exists?(ref)

          changed = true
          # the size follows the text's font and what the icon draws (the stylesheet); 16 stays as the attributes' fallback
          view.gk_icon_in_text(ref, whole.delete(':'))
        end
        node.replace(Nokogiri::HTML::DocumentFragment.parse(out)) if changed
        changed ||= before
      end
      changed ? doc.to_html.html_safe : html
    rescue StandardError => e
      Rails.logger.warn("[gk_icons] text not read for icons: #{e.class}: #{e.message}")
      html
    end

    # Core's textilizable gives the HTML for every formatted text; ours runs after it
    module HelperPatch
      # A declared function, off for a new installation
      def textilizable(*args)
        html = super
        GkIcons.feature?('icons.in_text') ? GkIcons::Text.apply(html, self) : html
      end
    end
  end
end
