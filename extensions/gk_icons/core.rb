# frozen_string_literal: true

# gk_icons: one way to an icon for every plugin. An icon core has is core's; an icon core lacks comes from this
# plugin's own sprite, built from the same source as core's (Tabler Icons, MIT, the release core's sprite is
# built from), so the two cannot be told apart on the page.
#   Ruby:  gk_icon('status-done')                 the svg, as core's sprite_icon gives it
#          gk_icon('copy', 'Copy')                with a label, as core's
#          GkIcons.exists?(name), GkIcons.names, GkIcons.url(name)   the last for stylesheets (mask-image)
#   JS:    GkIcons.svg('status-done')             an svg element; GkIcons.url(name)
# No plugin has a sprite of its own, and no plugin writes an icon as a character.
module GkIcons
  SYMBOL = %r{<symbol\b[^>]*\bid="icon--([a-z0-9-]+)"[^>]*>(.*?)</symbol>}m

  module_function

  def own_file = File.join(__dir__, '..', '..', 'assets', 'images', 'icons.svg')
  def core_file = Rails.root.join('app', 'assets', 'images', 'icons.svg').to_s

  # name => the symbol's inner markup, read once per file change
  def read(file)
    @read ||= {}
    stamp = File.exist?(file) ? File.mtime(file).to_i : 0
    cached = @read[file]
    return cached[1] if cached && cached[0] == stamp

    text = stamp.zero? ? '' : File.read(file, encoding: 'UTF-8')
    @read[file] = [stamp, text.scan(SYMBOL).to_h { |name, body| [name, body.strip] }]
    @read[file][1]
  end

  def own = read(own_file)
  def core = read(core_file)

  # :core, :own, :pack or nil. Core's wins: an icon core has is never drawn from here. A name with a slash is
  # a pack's icon (fa/hammer); packs are folders outside the plugin (packs.rb).
  # Without GK GUI Stuff no icon is there (gate.rb): another plugin that asks draws its own fallback.
  def source(name)
    return nil unless GkIcons.gui?

    n = name.to_s
    # A disabled or missing icon where it is already written as the settings say (shown by default; hidden is as
    # an unknown name)
    return ((Store.ready? ? Store.drawable?(n) : Packs.exists?(n)) ? :pack : nil) if n.include?('/')

    return :core if core.key?(n)

    own.key?(n) ? :own : nil
  end

  def exists?(name) = !source(name).nil?

  # A declared function in records' register; off until switched on, and off when records is not there
  def feature?(key) = defined?(::GkRecords::Features) ? ::GkRecords::Features.on?(key) : false

  # An appearance setting in records' register, for the person reading (optional lets each person switch it off);
  # off without records. Icons in text is one, also for someone not logged in.
  IN_TEXT = 'icons.in_text'
  def appearance?(key, user = ::User.current) = defined?(::GkRecords::AppearanceSettings) ? ::GkRecords::AppearanceSettings.on_for?(key, user) : false

  # Without GK GUI Stuff no names (gate.rb)
  def names = GkIcons.gui? ? (core.keys + own.keys).uniq.sort : []
  def all_names = GkIcons.gui? ? names + Packs.names : []

  # How a pack's icons sit in text, on top of what each icon draws (Measure: the drawing as high as the capitals, on
  # the baseline): scale (the height, 1 is the capitals' height, 0.5 to 2), shift (up when positive, in em, -0.5 to
  # 0.5) and gap (the space on each side, in em, 0 to 0.5). The administrator's values from the library's Packs tab
  # (the plugin's setting pack_text, Store.fit!), else the pack's pack.yml (text_scale, text_shift, text_gap), else
  # 1, 0 and TEXT_GAP.
  TEXT_RANGE = { 'scale' => [0.5, 2.0], 'shift' => [-0.5, 0.5], 'gap' => [0.0, 0.5] }.freeze
  # The space at an icon's sides when nothing else is set: about what a pack's own margin in its box gave before each
  # icon was cut to its drawing (Tabler's 2 of 24 at the height of the text)
  TEXT_GAP = 0.075

  # The pack's own values: its pack.yml, else the defaults ({ 'scale', 'shift', 'gap' } as floats in their ranges)
  def text_base(pack_key)
    meta = (pack_key.to_s.empty? ? nil : Packs.all[pack_key.to_s]&.meta) || {}
    { 'scale' => meta['text_scale'], 'shift' => meta['text_shift'], 'gap' => meta['text_gap'] }.to_h do |k, v|
      n = v.to_s.strip.empty? ? { 'scale' => 1.0, 'shift' => 0.0, 'gap' => TEXT_GAP }[k] : v.to_s.tr(',', '.').to_f
      n = 1.0 if k == 'scale' && !n.positive?
      [k, n.clamp(*TEXT_RANGE[k]).round(3)]
    end
  rescue StandardError
    { 'scale' => 1.0, 'shift' => 0.0, 'gap' => TEXT_GAP }
  end

  # [scale, shift, gap] as they are used: the administrator's values over the pack's own
  def text_fit(pack_key)
    base = text_base(pack_key)
    own = pack_key.to_s.empty? ? {} : (((Setting.plugin_gk_icons || {})['pack_text'] || {})[pack_key.to_s] || {})
    %w[scale shift gap].map do |k|
      v = own[k].to_s.strip
      v.empty? ? base[k] : v.tr(',', '.').to_f.clamp(*TEXT_RANGE[k]).round(3)
    end
  rescue StandardError
    [1.0, 0.0, TEXT_GAP]
  end

  # What an icon draws (Measure.fit): a pack's icon as the store measured it when it was read (or its file on disk
  # before the first reading), Redmine's and GK's own from their sprite's markup with core's stroke (document)
  def measure(name)
    n = name.to_s
    m = if !n.include?('/')
          (@measured ||= {})[[n, stamp]] ||= (doc = document(n)) ? Measure.svg(doc) : nil
        elsif Store.ready?
          Store.measure(n)
        else
          path, ext = Packs.file(n)
          path && File.file?(path) ? ((@measured ||= {})[[path, File.mtime(path).to_i, File.size(path)]] ||= Measure.file(File.binread(path), ext)) : nil
        end
    Measure.fit(m)
  rescue StandardError
    nil
  end

  # The style an icon in text gets, on the element around it (span.gk-icon-in-text, so that core's own svg gets it too):
  # what the icon draws (--gk-ar, --gk-k, --gk-b, --gk-l, --gk-r) and its pack's fit (--gk-scale, --gk-shift,
  # --gk-gap); the stylesheet (gk_icons_client.css, on every page) places the icon by them. Only what differs from the
  # stylesheet's defaults.
  def text_style(name)
    f = measure(name) || {}
    scale, shift, gap = text_fit(name.to_s.include?('/') ? name.to_s.split('/').first : '')
    vars = []
    vars << "--gk-ar: #{f[:ar]}" if f[:ar] && f[:ar] != 1.0
    vars << "--gk-k: #{f[:k]}" if f[:k] && f[:k] != 1.0
    %i[b l r].each { |k| vars << "--gk-#{k}: #{f[k]}" if f[k] && !f[k].zero? }
    vars << "--gk-scale: #{scale}" unless scale == 1.0
    vars << "--gk-shift: #{shift}em" unless shift.zero?
    vars << "--gk-gap: #{gap}em" unless gap == TEXT_GAP
    vars.empty? ? nil : vars.join('; ')
  end

  # The width over the height an icon in text is drawn at (its box), for the attributes' fallback size
  def text_ratio(name) = (measure(name) || {})[:ar] || 1.0

  # Drawn in the text's colour (a shape) or as it is (a picture with colours of its own: a flag, an emoji)
  def mono?(name)
    return true unless name.to_s.include?('/')

    if Store.ready?
      pk, = Store.find(name)
      return pk ? pk[:mono] : true
    end
    pack, = Packs.find(name)
    pack ? pack.mono : true
  end
  def markup(name) = core[name.to_s] || own[name.to_s]

  # The words of the script: its own (text_gk_icons_js_<word>), and core's where core has the word
  # (the library's own words, Kopierat, the page numbers, Per sida and the cross, are GK GUI Stuff's library's)
  JS_WORDS = %w[search all none no_match showing all_states state_active state_disabled state_missing missing_info missing_choose
                saved refreshing refreshed groups no_groups selected mark_title mark_disabled mark_missing only_disabled only_missing
                pack_off pack pack_change none_marked changed skipped choose_group in_text in_code state cannot_disable
                change_state choose_active choose_disabled unchanged ratio similar insert pack_or_group].freeze
  CORE_WORDS = { name: :field_name, cancel: :button_cancel, save: :button_save }.freeze

  def js_words
    JS_WORDS.to_h { |k| [k, ::I18n.t(:"text_gk_icons_js_#{k}")] }.merge(CORE_WORDS.transform_keys(&:to_s).transform_values { |k| ::I18n.t(k) })
  end

  # The stylesheet, the words (a JSON element the script reads, #gk-icons-texts) and the script (deferred), for a page
  # with the library, a picker or the editor's button
  def assets_tags(view)
    view.stylesheet_link_tag('gk_icons', plugin: 'gk_icons') +
      view.content_tag(:script, ERB::Util.json_escape(js_words.to_json).html_safe, type: 'application/json', id: 'gk-icons-texts') +
      view.javascript_include_tag('gk_icons', plugin: 'gk_icons', defer: true)
  end

  # What changes when any icon changes: for long caching of the single-icon addresses
  def stamp
    [own_file, core_file].sum { |f| File.exist?(f) ? File.mtime(f).to_i : 0 }.to_s(36)
  end

  # The icon as a file of its own, for stylesheets (mask-image cannot point into a sprite)
  # nil without GK GUI Stuff (gate.rb), as for a name that is not there
  def url(name)
    return nil unless GkIcons.gui?

    if name.to_s.include?('/') && Store.ready?
      pk, n = Store.find(name)
      return nil unless pk

      _id, ext = Store.file_id(name)
      return "#{Redmine::Utils.relative_url_root}/gk_icons/p/#{pk[:key]}/#{ERB::Util.url_encode(n)}.#{ext}?v=#{Store.stamp}"
    end
    if name.to_s.include?('/')
      pack, n = Packs.find(name)
      return nil unless pack

      _path, ext = Packs.file(name)
      return "#{Redmine::Utils.relative_url_root}/gk_icons/p/#{pack.key}/#{ERB::Util.url_encode(n)}.#{ext}?v=#{Packs.stamp.abs.to_s(36)}"
    end
    "#{Redmine::Utils.relative_url_root}/gk_icons/i/#{name}.svg?v=#{stamp}"
  end

  # The declarations that draw an icon on an element of the stylesheet's own (a ::before): a shape as a mask in
  # the text's colour, a picture as a background
  def css_paint(name)
    u = url(name) or return nil
    if mono?(name)
      "background-color: currentColor; -webkit-mask: url(#{u}) center / contain no-repeat; mask: url(#{u}) center / contain no-repeat;"
    else
      "background: url(#{u}) center / contain no-repeat;"
    end
  end

  # The whole icon as a standalone svg document, the file the controller serves and the measuring reads. The stroke
  # is the text's colour (currentColor): a mask needs only the shape, and the element the mask is on gives the colour
  def document(name)
    body = markup(name) or return nil
    %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">#{body}</svg>)
  end

  # The helper every view has
  module Helper
    # A page with an icon picker or the library asks for the script, the stylesheet and the words once
    # While Insert icon in the editor is on, the head hook already puts the same tags on every page; adding them again
    # would give a second #gk-icons-texts (one id twice) and load the stylesheet and the script twice
    def gk_icons_assets
      return if @gk_icons_assets || (GkIcons.gui? && GkIcons.feature?('icons.editor_insert'))

      @gk_icons_assets = true
      content_for(:header_tags) { GkIcons.assets_tags(self) }
      nil
    end

    # fluid: true leaves the size to the stylesheet (an icon in text follows the font); size stays the fallback
    def gk_icon(name, label = nil, **options)
      fluid = options.delete(:fluid)
      case GkIcons.source(name)
      when :core then sprite_icon(name.to_s, label, **options)
      when :own then sprite_icon(name.to_s, label, **options, plugin: 'gk_icons')
      when :pack
        size = (options[:size] || 18).to_i
        # From the pack's sprite (one request for many icons), drawn in the text's colour or as it is
        if (sp = Store.ready? && Store.sprite_ref(name))
          cls = ['gk-icon', "s#{size}", GkIcons.mono?(name) ? 'gk-icon-mono' : 'gk-icon-colour', options[:css_class]].compact.join(' ')
          # in text (fluid) the stylesheet sizes it to the font by what it draws (the style on gk_icon_in_text's span);
          # the attributes keep its shape where there is no stylesheet
          ar = fluid ? GkIcons.text_ratio(name) : 1.0
          svg = content_tag('svg', tag.use(href: "#{sp[0]}##{sp[1]}"), class: cls, width: (size * ar).round, height: size, 'aria-hidden': true)
          return label ? svg + content_tag(:span, label, class: ['icon-label', ('hidden' if options[:icon_only])].compact.join(' ')) : svg
        end
        cls = ['gk-icon', "s#{size}", GkIcons.mono?(name) ? 'gk-icon-mono' : 'gk-icon-colour', options[:css_class]].compact.join(' ')
        style = "--gk-icon: url(#{GkIcons.url(name)});#{fluid ? '' : " inline-size: #{size}px; block-size: #{size}px;"}"
        tag = content_tag('span', '', class: cls, style: style, 'aria-hidden': true)
        label ? tag + content_tag(:span, label, class: ['icon-label', ('hidden' if options[:icon_only])].compact.join(' ')) : tag
      else label.to_s # an unknown name draws nothing, never a broken picture
      end
    end

    # An icon in text as formatted text writes it (GkIcons::Text) and the Packs tab shows it: the icon in a span whose
    # title is its code; the span carries what the icon draws and its pack's fit (GkIcons.text_style), so that core's
    # own svg is placed the same way; data-gk-icons-code is the code a click copies (gk_icons_client.js), kept apart from
    # the title, which core's hover tooltip empties while it shows
    def gk_icon_in_text(ref, title)
      content_tag('span', gk_icon(ref, size: 16, fluid: true), class: 'gk-icon-in-text', title: title, style: GkIcons.text_style(ref),
                                                                  data: { gk_icons_code: title })
    end
  end


  class Hooks < Redmine::Hook::ViewListener
    # Silent without GK GUI Stuff (gate.rb)
    include GkIcons::Gate::Listener

    # The client's way to the same icons: where the two sprites are, and which names are ours. The client itself is
    # assets (gk_icons_client.js with gk_icons_client.css, loaded on every page, in the head so that GkIcons is there
    # before any other script asks for it); its settings are data in the JSON element #gk-icons-config before it.
    def view_layouts_base_html_head(_context = {})
      # The store is read again in the background when a pack folder changed (no page waits for it)
      Store.sync_later
      cfg = { core: asset_path('icons.svg'), own: asset_path('plugin_assets/gk_icons/icons.svg'), names: GkIcons.own.keys,
              one: "#{Redmine::Utils.relative_url_root}/gk_icons/i/", v: GkIcons.stamp,
              # The store's stamp in the address, so that the cached list follows a change of state or group
              namesUrl: "#{Redmine::Utils.relative_url_root}/gk_icons/names?v=#{Store.ready? ? Store.stamp : Packs.stamp.abs.to_s(36)}",
              pack: "#{Redmine::Utils.relative_url_root}/gk_icons/p/" }
      # The button Insert icon in the editor's toolbar (icons.editor_insert): the script, its words and its stylesheet
      # on every page while the function is on, since an editor can be on any page
      editor = GkIcons.feature?('icons.editor_insert')
      cfg[:editorInsert] = true if editor
      if Store.ready?
        cfg.merge!(pv: Store.stamp, sprite: Store.sprite_base, sv: Store.stamp,
                   packs: Store.index.transform_values { |p| { mono: p[:mono], svg: p[:icons].values.first&.dig(:files)&.values&.first&.key?('svg') } })
      else
        cfg.merge!(pv: Packs.stamp.abs.to_s(36),
                   packs: Packs.all.transform_values { |p| { mono: p.mono, svg: Packs.file("#{p.key}/#{p.icons.keys.first}")&.last == 'svg' } })
      end
      # A click on an icon in formatted text (an issue, a note, a wiki page) copies its code, :pack/name:, said by GK GUI
      # Stuff's shared whisper under the icon (GkGui.copy), which closes core's hover tooltip first; an icon inside a link
      # follows the link. Only while Icons in text is on for the person.
      cfg[:copy] = ::I18n.t(:text_gk_icons_js_copied_code) if GkIcons.appearance?(GkIcons::IN_TEXT)
      out = content_tag(:script, ERB::Util.json_escape(cfg.to_json).html_safe, type: 'application/json', id: 'gk-icons-config') +
            stylesheet_link_tag('gk_icons_client', plugin: 'gk_icons') +
            javascript_include_tag('gk_icons_client', plugin: 'gk_icons')
      editor ? out + GkIcons.assets_tags(self) : out
    end
  end
end
