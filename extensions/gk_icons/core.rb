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
  def source(name)
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
  def names = (core.keys + own.keys).uniq.sort
  def all_names = names + Packs.names

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
  # --gk-gap); the stylesheet (Hooks) places the icon by them. Only what differs from the stylesheet's defaults.
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

  # The rules for an icon in text, in every heading and paragraph, Redmine's own icons (svg.icon-svg) too. The box (the
  # icon's whole viewBox, --gk-h high) is as high as makes the part the icon draws (--gk-k of the box) the capitals'
  # height (Measure::CAP) times the pack's scale. The room left and right of the drawing is taken away by negative side
  # margins and the pack's gap put there instead (the drawing is not mirrored, so the two sides change places in a
  # right-to-left page). The drawing's bottom stands on the baseline, moved by the pack's shift; the block margins make
  # the box take no height on the line (its margin box is the baseline itself), so an icon never makes a line higher
  # than its text, at any scale. No child combinator in the rules: the tag's content is escaped, and > would become &gt;
  def in_text_css
    h = 'var(--gk-h)'
    gap = "var(--gk-gap, #{TEXT_GAP}em)"
    left = "calc(#{gap} - #{h} * var(--gk-l, 0))"
    right = "calc(#{gap} - #{h} * var(--gk-r, 0))"
    sel = 'span.gk-icon-in-text svg, span.gk-icon-in-text span.gk-icon'
    rtl = '[dir=rtl] span.gk-icon-in-text svg, [dir=rtl] span.gk-icon-in-text span.gk-icon'
    'span.gk-icon-in-text { display: inline; line-height: 1; } ' \
      "#{sel} { display: inline-block; --gk-h: calc(#{Measure::CAP}em * var(--gk-scale, 1) / var(--gk-k, 1)); " \
      "inline-size: calc(#{h} * var(--gk-ar, 1)); block-size: #{h}; vertical-align: baseline; " \
      "margin-block: calc(#{h} * var(--gk-b, 0) - var(--gk-shift, 0em) - #{h}) calc(var(--gk-shift, 0em) - #{h} * var(--gk-b, 0)); " \
      "margin-inline: #{left} #{right}; } " \
      "#{rtl} { margin-inline: #{right} #{left}; }"
  end

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
  JS_WORDS = %w[search all none no_match copied showing all_states state_active state_disabled state_missing missing_info missing_choose
                saved refreshing refreshed groups no_groups selected mark mark_title mark_disabled mark_missing only_disabled
                pack_off pack pack_change none_marked changed skipped choose_group in_text in_code state cannot_disable
                change_state choose_active choose_disabled unchanged ratio similar insert pack_or_group].freeze
  CORE_WORDS = { name: :field_name, copy: :button_copy, close: :button_close, cancel: :button_cancel, previous: :label_previous,
                 next: :label_next, per_page: :label_display_per_page, save: :button_save }.freeze

  def js_words
    JS_WORDS.to_h { |k| [k, ::I18n.t(:"text_gk_icons_js_#{k}")] }.merge(CORE_WORDS.transform_keys(&:to_s).transform_values { |k| ::I18n.t(k) })
  end

  # The stylesheet, the words and the script (deferred), for a page with the library, a picker or the editor's button
  def assets_tags(view)
    view.stylesheet_link_tag('gk_icons', plugin: 'gk_icons') +
      view.javascript_tag("window.GkIconsText = #{js_words.to_json};") +
      view.javascript_include_tag('gk_icons', plugin: 'gk_icons', defer: true)
  end

  # What changes when any icon changes: for long caching of the single-icon addresses
  def stamp
    [own_file, core_file].sum { |f| File.exist?(f) ? File.mtime(f).to_i : 0 }.to_s(36)
  end

  # The icon as a file of its own, for stylesheets (mask-image cannot point into a sprite)
  def url(name)
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

  # The whole icon as a standalone svg document, stroke in black (a mask needs only the shape)
  def document(name)
    body = markup(name) or return nil
    %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">#{body}</svg>)
  end

  # The helper every view has
  module Helper
    # A page with an icon picker or the library asks for the script, the stylesheet and the words once
    def gk_icons_assets
      return if @gk_icons_assets

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
    # own svg is placed the same way
    def gk_icon_in_text(ref, title)
      content_tag('span', gk_icon(ref, size: 16, fluid: true), class: 'gk-icon-in-text', title: title, style: GkIcons.text_style(ref))
    end
  end

  class Hooks < Redmine::Hook::ViewListener
    # The client's way to the same icons: where the two sprites are, and which names are ours
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
      style = content_tag('style', '.gk-icon { display: inline-block; vertical-align: -0.18em; flex: none; } ' \
                                   'span.gk-icon-mono { background-color: currentColor; -webkit-mask: var(--gk-icon) center / contain no-repeat; mask: var(--gk-icon) center / contain no-repeat; } ' \
                                   'span.gk-icon-colour { background: var(--gk-icon) center / contain no-repeat; } ' \
                                   'svg.gk-icon.gk-icon-mono { fill: currentColor; stroke: none; } ' \
                                   'svg.gk-icon.gk-icon-colour { fill: #000; stroke: none; } ' \
                                   "#{GkIcons.in_text_css}",
                           id: 'gk-icons-style')
      out = style + javascript_tag(<<~JS)
        window.GkIcons = (function (c) {
          var own = {}; c.names.forEach(function (n) { own[n] = 1; });
          var NS = 'http://www.w3.org/2000/svg';
          return {
            namesUrl: c.namesUrl,
            // the editor's button (icons.editor_insert) is drawn only while the function is on
            editorInsert: !!c.editorInsert,
            own: function (n) { return !!own[n]; },
            url: function (n) {
              if (n.indexOf('/') < 0) return c.one + n + '.svg?v=' + c.v;
              var k = n.split('/')[0], p = c.packs[k];
              return c.pack + k + '/' + encodeURIComponent(n.slice(k.length + 1)) + (p && !p.svg ? '.png' : '.svg') + '?v=' + c.pv;
            },
            chunks: {},
            // A sprite is fetched before any icon points into it, at most two at a time, and again when it fails (the
            // server answered 500 when many were built at once, and the browser never asks again for a sprite a <use>
            // could not load); known: the symbols it holds, so an icon left out is fetched by itself
            loads: {}, queue: [], busy: 0,
            load: function (url) {
              var self = this;
              if (!this.loads[url]) {
                this.loads[url] = new Promise(function (resolve, reject) { self.queue.push({ url: url, resolve: resolve, reject: reject, tries: 0 }); self.pump(); });
              }
              return this.loads[url];
            },
            pump: function () {
              var self = this;
              while (this.busy < 2 && this.queue.length) {
                var job = this.queue.shift();
                this.busy += 1;
                fetch(job.url, { credentials: 'same-origin' }).then(function (r) {
                  if (!r.ok) throw new Error(String(r.status));
                  return r.text();
                }).then(function (text) {
                  var ids = {}; text.replace(/<symbol id="([^"]+)"/g, function (m, id) { ids[id] = 1; return m; });
                  this.resolve(ids);
                }.bind(job), function () {
                  var j = this;
                  j.tries += 1;
                  if (j.tries < 3) { setTimeout(function () { self.queue.push(j); self.pump(); }, 700 * j.tries); } else { j.reject(); }
                }.bind(job)).then(function () { self.busy -= 1; self.pump(); });
              }
            },
            // one: the icon's own file, never the sprite
            svg: function (n, size, one) {
              if (!one && n.indexOf('/') >= 0 && c.sprite && this.chunks[n] != null) {
                // From the pack's sprite, the chunk known from the list of names
                var k0 = n.split('/')[0], pk0 = c.packs[k0], sv = document.createElementNS(NS, 'svg'), us = document.createElementNS(NS, 'use');
                var sid = ('i-' + k0 + '-' + n.slice(k0.length + 1)).replace(/[^A-Za-z0-9_.-]/g, '_');
                sv.setAttribute('class', 'gk-icon s' + (size || 18) + ' ' + (pk0 && pk0.mono ? 'gk-icon-mono' : 'gk-icon-colour'));
                sv.setAttribute('width', size || 18); sv.setAttribute('height', size || 18); sv.setAttribute('aria-hidden', 'true');
                var url = c.sprite + k0 + '/' + this.chunks[n] + '.svg?v=' + c.sv, self = this;
                sv.appendChild(us);
                this.load(url).then(function (ids) {
                  if (ids[sid]) { us.setAttribute('href', url + '#' + sid); return; }
                  if (sv.parentNode) sv.parentNode.replaceChild(self.svg(n, size, true), sv);
                }, function () { if (sv.parentNode) sv.parentNode.replaceChild(self.svg(n, size, true), sv); });
                return sv;
              }
              if (n.indexOf('/') >= 0) {
                var pk = c.packs[n.split('/')[0]], e = document.createElement('span');
                e.className = 'gk-icon s' + (size || 18) + ' ' + (pk && pk.mono ? 'gk-icon-mono' : 'gk-icon-colour');
                e.style.setProperty('--gk-icon', 'url(' + this.url(n) + ')');
                e.style.inlineSize = e.style.blockSize = (size || 18) + 'px'; e.setAttribute('aria-hidden', 'true');
                return e;
              }
              var s = document.createElementNS(NS, 'svg'), u = document.createElementNS(NS, 'use');
              s.setAttribute('class', 's' + (size || 18) + ' icon-svg'); s.setAttribute('aria-hidden', 'true');
              // core's stylesheet sizes only some s-classes (s18, s24): the size as attributes too
              s.setAttribute('width', size || 18); s.setAttribute('height', size || 18);
              u.setAttribute('href', (own[n] ? c.own : c.core) + '#icon--' + n);
              s.appendChild(u);
              return s;
            }
          };
        })(#{cfg.to_json});
      JS
      out += in_text_copy if GkIcons.feature?('icons.in_text')
      editor ? out + GkIcons.assets_tags(self) : out
    end

    # A click on an icon in formatted text (an issue, a note, a wiki page) copies its code, :pack/name:, and says
    # "Copied" at the icon, so that an icon found anywhere can be put in a note; an icon inside a link follows the link.
    # With core's hover tooltip (jQuery UI's, setupHoverTooltips) the tooltip that showed the icon's code says "Copied"
    # instead, and shows the code again when it closes (the pointer leaves); core empties the title while it shows, so
    # the code is read where the tooltip keeps it. Without it "Copied" is a word of its own at the icon, the title taken
    # off meanwhile and put back when the word goes.
    def in_text_copy
      word = ::I18n.t(:text_gk_icons_js_copied)
      sel = 'span.gk-icon-in-text[title], span.gk-icon-in-text[data-gk-icons-title]'
      style = content_tag('style', 'span.gk-icon-in-text[title], span.gk-icon-in-text[data-gk-icons-title] { cursor: copy; position: relative; } ' \
                                   'span.gk-icon-in-text .gk-icons-copied-text { position: absolute; inset-block-end: 100%; inset-inline-start: 50%; ' \
                                   'translate: -50% 0; z-index: 5; padding-inline: 5px; border-radius: 3px; font-size: 12px; line-height: 1.6; ' \
                                   'white-space: nowrap; background: var(--oc-gray-9, #212529); color: var(--oc-white, #ffffff); }')
      style + javascript_tag(<<~JS)
        document.addEventListener('click', function (e) {
          var s = e.target.closest && e.target.closest(#{sel.to_json});
          if (!s || s.closest('a, .jstEditor, textarea')) return;
          var jq = window.jQuery, tip = !!(jq && jq.fn.tooltip && jq(s).tooltip('instance'));
          var title = s.getAttribute('title') || s.getAttribute('data-gk-icons-title') || (jq && jq(s).data('ui-tooltip-title')) || s.gkIconsCode;
          if (!title) return;
          s.gkIconsCode = title;
          var code = ':' + title + ':';
          var said = function () {
            if (tip) {
              if (s.gkIconsTipWas === undefined) {
                s.gkIconsTipWas = jq(s).tooltip('option', 'content');
                jq(s).one('tooltipclose', function () { jq(s).tooltip('option', 'content', s.gkIconsTipWas); s.gkIconsTipWas = undefined; });
              }
              // the tooltip that shows (the pointer is on the icon) only changes its words and closes as core's do; one
              // that does not show (a touch) is opened and closed again by the script, as a programmatic open never
              // closes when the pointer leaves
              var shown = !!s.getAttribute('aria-describedby');
              jq(s).tooltip('option', 'content', #{word.to_json});
              if (!shown) { jq(s).tooltip('open'); setTimeout(function () { jq(s).tooltip('close'); }, 1200); }
              return;
            }
            var old = s.querySelector('.gk-icons-copied-text'); if (old) old.remove();
            if (s.hasAttribute('title')) { s.setAttribute('data-gk-icons-title', title); s.removeAttribute('title'); }
            var n = document.createElement('span'); n.className = 'gk-icons-copied-text'; n.setAttribute('role', 'status');
            n.textContent = #{word.to_json}; s.appendChild(n);
            clearTimeout(s.gkIconsCopied);
            s.gkIconsCopied = setTimeout(function () {
              n.remove();
              if (!s.hasAttribute('title') && s.hasAttribute('data-gk-icons-title')) s.setAttribute('title', s.getAttribute('data-gk-icons-title'));
              s.removeAttribute('data-gk-icons-title');
            }, 1200);
          };
          var old = function () {
            var a = document.createElement('textarea'); a.value = code; a.style.position = 'fixed'; a.style.opacity = '0';
            document.body.appendChild(a); a.select();
            try { if (document.execCommand('copy')) said(); } catch (x) { /* nothing copied, nothing said */ }
            a.remove();
          };
          if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(code).then(said, old); else old();
        });
      JS
    end
  end
end
