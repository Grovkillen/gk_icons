# frozen_string_literal: true

require 'strscan'
require 'zlib'
require 'nokogiri'

# gk_icons measure: the part of its box an icon really draws on, read once when a pack is read in (Store) and kept, so
# that an icon in text can be as high as the text's capitals and stand on the baseline, whatever room its pack leaves
# around the pictures. Plain Ruby (Nokogiri for the svg), no Redmine: it can be tried on files by itself.
#   Measure.file(data, ext)  { 'vb' => [x, y, w, h], 'ink' => [x0, y0, x1, y1] or nil }, or nil when not readable
#   Measure.fit(measured)    the numbers the stylesheet places the icon by, relative to the box's height
# An svg's ink is the bounding box of its geometry: path (every command, arcs too, curves by their extremes), rect,
# circle, ellipse, line, polyline, polygon, image, use (of an element or a symbol), nested svg, with every transform on
# the way. A stroke widens the shape by half its width (by the square's diagonal where a corner can be square). What
# cannot be measured (text) counts as the whole box; clip paths and masks are not read, so the box can only be larger
# than the drawing, never smaller. Shapes with neither fill nor stroke, and hidden ones, draw nothing and are skipped.
# A png's ink is the box of its pixels that are not fully transparent.
module GkIcons
  module Measure
    # Kept with the measurements (Store): a change in how icons are measured measures every file again
    VERSION = 1
    # The height of a capital (M) in em in core's font, Noto Sans (cap height 714 of 1000 units)
    CAP = 0.714
    # An icon that draws little of its box (a dash, a dot) is not blown up to the capitals' height: the height it is
    # placed by is at least this part of its box, around the middle of what it draws
    FLOOR = 0.5
    # The widest an icon in text is drawn, as a multiple of its height
    WIDE = 4
    SKIP = %w[defs clipPath mask pattern marker symbol linearGradient radialGradient filter metadata title desc style script].freeze
    SHAPES = %w[path rect circle ellipse line polyline polygon image].freeze
    NUM = /[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/
    ID = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0].freeze
    DEPTH = 12
    # A png larger than this (pixels) is not read for its transparent edge: it counts as drawing on all of its box
    PIXELS = 4_000_000

    module_function

    def file(data, ext)
      ext.to_s == 'png' ? png(data.to_s.b) : svg(data)
    rescue StandardError
      nil
    end

    # ------------------------------------------------------------------ the numbers for the stylesheet
    # ar: the box's width over its height; k: the height the icon is placed by, over the box's height; b: how far the
    # bottom of that height stands above the box's bottom; l and r: the room left and right of the drawing. All relative
    # to the box's height, so that the stylesheet scales them by the box it draws.
    def fit(measured)
      return nil unless measured.is_a?(Hash) && measured['vb']

      vx, vy, vw, vh = measured['vb'].map(&:to_f)
      return nil unless vw.positive? && vh.positive?

      x0, y0, x1, y1 = (measured['ink'] || [vx, vy, vx + vw, vy + vh]).map(&:to_f)
      need = [y1 - y0, FLOOR * vh, (x1 - x0) / WIDE].max
      bottom = ((y0 + y1) / 2) + (need / 2)
      { ar: vw / vh, k: need / vh, b: (vy + vh - bottom) / vh, l: (x0 - vx) / vh, r: (vx + vw - x1) / vh }.transform_values { |v| v.round(4) }
    end

    # ------------------------------------------------------------------ png
    def png(data)
      return nil unless data.byteslice(0, 8) == "\x89PNG\r\n\x1a\n".b

      pos = 8
      w = h = depth = ctype = interlace = trns = nil
      idat = +''.b
      while pos + 8 <= data.bytesize
        len = data.byteslice(pos, 4).unpack1('N')
        type = data.byteslice(pos + 4, 4)
        body = data.byteslice(pos + 8, len)
        case type
        when 'IHDR' then w, h, depth, ctype, _c, _f, interlace = body.unpack('NNCCCCC')
        when 'IDAT' then idat << body
        when 'tRNS' then trns = body
        when 'IEND' then break
        end
        pos += 12 + len
      end
      return nil unless w.to_i.positive? && h.to_i.positive?

      vb = [0, 0, w, h]
      bpp = { 6 => 4, 4 => 2, 3 => 1 }[ctype]
      # a picture without an alpha channel this reads (16 bits, interlaced, no transparency), or one too large to read
      # in reasonable time, counts as drawing on all of its box
      return { 'vb' => vb, 'ink' => [0, 0, w, h] } unless depth == 8 && bpp && interlace.to_i.zero? && (ctype != 3 || trns) && w * h <= PIXELS

      alpha_box(Zlib::Inflate.inflate(idat), w, h, bpp, ctype, trns, vb)
    end

    # Only the alpha channel is unfiltered: a png's filters take each byte from the same channel of the pixel before
    # and of the row above, so the alpha bytes alone are enough. A palette's index is its alpha through tRNS.
    def alpha_box(raw, w, h, bpp, ctype, trns, vb)
      stride = w * bpp
      at = Array.new(w) { |x| (x * bpp) + bpp - 1 }
      prev = Array.new(w, 0)
      x0 = w
      y0 = h
      x1 = y1 = -1
      seen = trns ? trns.bytes : []
      h.times do |y|
        f = raw.getbyte(y * (stride + 1))
        row = raw.byteslice((y * (stride + 1)) + 1, stride).unpack('C*').values_at(*at)
        unfilter(row, prev, f, 1)
        prev = row
        alpha = ctype == 3 ? row.map { |i| seen.fetch(i, 255) } : row
        lo = alpha.index { |a| !a.zero? }
        next unless lo

        hi = alpha.rindex { |a| !a.zero? }
        x0 = lo if lo < x0
        x1 = hi if hi > x1
        y0 = y if y < y0
        y1 = y
      end
      { 'vb' => vb, 'ink' => x1.negative? ? nil : [x0, y0, x1 + 1, y1 + 1] }
    end

    def unfilter(row, prev, filter, bpp)
      n = row.size
      case filter
      when 1 then (bpp...n).each { |i| row[i] = (row[i] + row[i - bpp]) & 0xff }
      when 2 then n.times { |i| row[i] = (row[i] + prev[i]) & 0xff }
      when 3 then n.times { |i| row[i] = (row[i] + (((i >= bpp ? row[i - bpp] : 0) + prev[i]) >> 1)) & 0xff }
      when 4
        n.times do |i|
          a = i >= bpp ? row[i - bpp] : 0
          b = prev[i]
          c = i >= bpp ? prev[i - bpp] : 0
          p = a + b - c
          pa = (p - a).abs
          pb = (p - b).abs
          pc = (p - c).abs
          row[i] = (row[i] + (pa <= pb && pa <= pc ? a : (pb <= pc ? b : c))) & 0xff
        end
      end
      row
    end

    # ------------------------------------------------------------------ svg
    def svg(text)
      text = text.to_s.dup.force_encoding('UTF-8').scrub
      doc = Nokogiri::XML(text) { |c| c.nonet }
      doc.remove_namespaces!
      root = doc.root
      return nil unless root && root.name == 'svg'

      vb = view_box(root) or return nil
      ids = {}
      doc.xpath('//*[@id]').each { |e| ids[e['id']] ||= e }
      # stroke widths a stylesheet in the file may give (classes are not read): every shape may have the widest
      css = doc.xpath('//style').map(&:text).join("\n")
      css_sw = css.scan(/stroke-width\s*:\s*(#{NUM})/o).flatten.map(&:to_f).max
      ctx = { ids: ids, vb: vb, css_stroke: css.match?(/stroke\s*:\s*(?!none)[#a-z]/i) ? (css_sw || 1.0) : nil, box: [], whole: false }
      walk(root, ID, style(root, { fill: true, stroke: false, sw: 1.0, square: true }, vb), ctx, 0, top: true)
      ink = ctx[:whole] ? vb_rect(vb) : clip(ctx[:box], vb)
      { 'vb' => vb, 'ink' => ink }
    end

    # As the sprite reads the box: the viewBox, else width and height, else 24 by 24
    def view_box(el)
      vb = el['viewBox'].to_s.strip.split(/[\s,]+/).map(&:to_f)
      return vb if vb.size == 4 && vb[2].positive? && vb[3].positive?

      w = el['width'].to_s[/\A\s*([\d.]+)/, 1].to_f
      h = el['height'].to_s[/\A\s*([\d.]+)/, 1].to_f
      w.positive? && h.positive? ? [0.0, 0.0, w, h] : [0.0, 0.0, 24.0, 24.0]
    end

    def vb_rect(vb) = [vb[0], vb[1], vb[0] + vb[2], vb[1] + vb[3]].map { |v| v.round(3) }

    def clip(box, vb)
      return nil if box.empty?

      x0, y0, x1, y1 = box
      r = vb_rect(vb)
      x0 = [x0, r[0]].max
      y0 = [y0, r[1]].max
      x1 = [x1, r[2]].min
      y1 = [y1, r[3]].min
      x1 > x0 && y1 > y0 ? [x0, y0, x1, y1].map { |v| v.round(3) } : nil
    end

    # The painting an element passes on: fill and stroke on or off, the stroke's width and whether a corner can be square
    def style(el, parent, vb)
      props = {}
      %w[fill stroke stroke-width stroke-linecap stroke-linejoin display visibility opacity].each { |k| props[k] = el[k] if el[k] }
      el['style'].to_s.split(';').each do |decl|
        k, v = decl.split(':', 2).map { |s| s.to_s.strip }
        props[k] = v if k && v && !v.empty?
      end
      s = parent.dup
      s[:fill] = props['fill'].strip != 'none' if props['fill']
      s[:stroke] = !%w[none transparent].include?(props['stroke'].strip) if props['stroke']
      if (sw = props['stroke-width'])
        n = sw.to_f
        n = n * Math.sqrt(((vb[2]**2) + (vb[3]**2)) / 2) / 100 if sw.include?('%')
        s[:sw] = n
      end
      join = props['stroke-linejoin']
      cap = props['stroke-linecap']
      s[:join] = join if join
      s[:cap] = cap if cap
      s[:square] = (s[:join] || 'miter') == 'miter' || s[:cap] == 'square'
      s[:hidden] = props['display'] == 'none' || props['opacity'].to_s.strip.match?(/\A0*\.?0*\z/) && !props['opacity'].to_s.strip.empty?
      s[:invisible] = %w[hidden collapse].include?(props['visibility'].to_s.strip) if props['visibility']
      s
    end

    def walk(el, m, st, ctx, depth, top: false)
      return if depth > DEPTH || st[:hidden]

      name = el.name
      return if !top && SKIP.include?(name)

      if %w[text textPath tspan foreignObject].include?(name)
        ctx[:whole] = true unless st[:invisible]
        return
      end
      if name == 'use'
        use(el, m, st, ctx, depth)
        return
      end
      if name == 'svg' && !top
        m = multiply(multiply(m, transform(el['transform'])), nested(el))
      elsif !top || el['transform']
        m = multiply(m, transform(el['transform']))
      end
      if SHAPES.include?(name)
        shape(el, m, st, ctx)
        return
      end
      el.element_children.each { |c| walk(c, m, style(c, st, ctx[:vb]), ctx, depth + 1) }
    end

    # A use of another element (x and y move it) or of a symbol, whose viewBox fills the use's width and height
    def use(el, m, st, ctx, depth)
      ref = (el['href'] || el['xlink:href']).to_s
      target = ref.start_with?('#') ? ctx[:ids][ref[1..]] : nil
      return unless target

      m = multiply(multiply(m, transform(el['transform'])), [1.0, 0.0, 0.0, 1.0, el['x'].to_f, el['y'].to_f])
      if %w[symbol svg].include?(target.name)
        vb = target['viewBox'].to_s.strip.split(/[\s,]+/).map(&:to_f)
        w = (el['width'] || target['width']).to_f
        h = (el['height'] || target['height']).to_f
        if vb.size == 4 && vb[2].positive? && vb[3].positive? && w.positive? && h.positive?
          s = [w / vb[2], h / vb[3]].min
          m = multiply(m, [s, 0.0, 0.0, s, (-vb[0] * s) + ((w - (vb[2] * s)) / 2), (-vb[1] * s) + ((h - (vb[3] * s)) / 2)])
        end
        inner = style(target, st, ctx[:vb])
        target.element_children.each { |c| walk(c, m, style(c, inner, ctx[:vb]), ctx, depth + 1) }
      else
        walk(target, m, style(target, st, ctx[:vb]), ctx, depth + 1, top: true)
      end
    end

    # A nested svg: its x and y, and its viewBox into its width and height
    def nested(el)
      x = el['x'].to_f
      y = el['y'].to_f
      vb = el['viewBox'].to_s.strip.split(/[\s,]+/).map(&:to_f)
      w = el['width'].to_f
      h = el['height'].to_f
      return [1.0, 0.0, 0.0, 1.0, x, y] unless vb.size == 4 && vb[2].positive? && vb[3].positive? && w.positive? && h.positive?

      s = [w / vb[2], h / vb[3]].min
      [s, 0.0, 0.0, s, x - (vb[0] * s) + ((w - (vb[2] * s)) / 2), y - (vb[1] * s) + ((h - (vb[3] * s)) / 2)]
    end

    def shape(el, m, st, ctx)
      return if st[:invisible]

      stroke = st[:stroke] || !ctx[:css_stroke].nil?
      image = el.name == 'image'
      return unless st[:fill] || stroke || image

      local = case el.name
              when 'path' then path_box(el['d'])
              when 'rect', 'image'
                x = el['x'].to_f
                y = el['y'].to_f
                w = el['width'].to_f
                h = el['height'].to_f
                w.positive? && h.positive? ? [x, y, x + w, y + h] : nil
              when 'circle'
                r = el['r'].to_f
                r.positive? ? [el['cx'].to_f - r, el['cy'].to_f - r, el['cx'].to_f + r, el['cy'].to_f + r] : nil
              when 'ellipse'
                rx = el['rx'].to_f
                ry = el['ry'].to_f
                rx.positive? && ry.positive? ? [el['cx'].to_f - rx, el['cy'].to_f - ry, el['cx'].to_f + rx, el['cy'].to_f + ry] : nil
              when 'line' then box_of([[el['x1'].to_f, el['y1'].to_f], [el['x2'].to_f, el['y2'].to_f]])
              else box_of(el['points'].to_s.scan(NUM).map(&:to_f).each_slice(2).select { |p| p.size == 2 })
              end
      return unless local

      if stroke && !image
        sw = [st[:stroke] ? st[:sw] : 0.0, ctx[:css_stroke] || 0.0].max
        half = sw / 2.0 * (st[:square] ? Math.sqrt(2) : 1.0)
        local = [local[0] - half, local[1] - half, local[2] + half, local[3] + half]
      end
      corners = [[local[0], local[1]], [local[2], local[1]], [local[0], local[3]], [local[2], local[3]]].map { |x, y| apply(m, x, y) }
      add(ctx, box_of(corners))
    end

    def add(ctx, b)
      return unless b

      ctx[:box] = ctx[:box].empty? ? b : [[ctx[:box][0], b[0]].min, [ctx[:box][1], b[1]].min, [ctx[:box][2], b[2]].max, [ctx[:box][3], b[3]].max]
    end

    def box_of(points)
      return nil if points.empty?

      xs = points.map(&:first)
      ys = points.map(&:last)
      [xs.min, ys.min, xs.max, ys.max]
    end

    # ------------------------------------------------------------------ transforms: [a b c d e f], x' = a x + c y + e
    def multiply(m, n)
      [(m[0] * n[0]) + (m[2] * n[1]), (m[1] * n[0]) + (m[3] * n[1]), (m[0] * n[2]) + (m[2] * n[3]), (m[1] * n[2]) + (m[3] * n[3]),
       (m[0] * n[4]) + (m[2] * n[5]) + m[4], (m[1] * n[4]) + (m[3] * n[5]) + m[5]]
    end

    def apply(m, x, y) = [(m[0] * x) + (m[2] * y) + m[4], (m[1] * x) + (m[3] * y) + m[5]]

    def transform(text)
      m = ID
      text.to_s.scan(/(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)/) do |fn, args|
        a = args.scan(NUM).map(&:to_f)
        t = case fn
            when 'matrix' then a.size == 6 ? a : ID
            when 'translate' then [1.0, 0.0, 0.0, 1.0, a[0] || 0.0, a[1] || 0.0]
            when 'scale' then [a[0] || 1.0, 0.0, 0.0, a[1] || a[0] || 1.0, 0.0, 0.0]
            when 'rotate'
              r = (a[0] || 0.0) * Math::PI / 180
              rot = [Math.cos(r), Math.sin(r), -Math.sin(r), Math.cos(r), 0.0, 0.0]
              if a.size >= 3
                multiply(multiply([1.0, 0.0, 0.0, 1.0, a[1], a[2]], rot), [1.0, 0.0, 0.0, 1.0, -a[1], -a[2]])
              else
                rot
              end
            when 'skewX' then [1.0, 0.0, Math.tan((a[0] || 0.0) * Math::PI / 180), 1.0, 0.0, 0.0]
            else [1.0, Math.tan((a[0] || 0.0) * Math::PI / 180), 0.0, 1.0, 0.0, 0.0]
            end
        m = multiply(m, t)
      end
      m
    end

    # ------------------------------------------------------------------ path data
    # The box of a path: every end point, the extremes of each curve, and of each arc within its sweep
    def path_box(d)
      s = StringScanner.new(d.to_s)
      pts = []
      x = y = sx = sy = 0.0
      cmd = nil
      ctrl = nil # the last control point of a cubic (for S) or a quadratic (for T), with the command that set it
      num = lambda do
        s.skip(/[\s,]*/)
        t = s.scan(NUM) or raise ArgumentError, 'number'
        t.to_f
      end
      flag = lambda do
        s.skip(/[\s,]*/)
        t = s.scan(/[01]/) or raise ArgumentError, 'flag'
        t == '1'
      end
      loop do
        s.skip(/[\s,]*/)
        break if s.eos?

        if (c = s.scan(/[MmLlHhVvCcSsQqTtAaZz]/))
          cmd = c
        elsif cmd.nil? || cmd.match?(/[Zz]/)
          break
        elsif cmd == 'M'
          cmd = 'L'
        elsif cmd == 'm'
          cmd = 'l'
        end
        rel = cmd == cmd.downcase
        ox = rel ? x : 0.0
        oy = rel ? y : 0.0
        case cmd.upcase
        when 'Z'
          x = sx
          y = sy
          ctrl = nil
        when 'M'
          x = ox + num.call
          y = oy + num.call
          sx = x
          sy = y
          pts << [x, y]
          ctrl = nil
        when 'L'
          x = ox + num.call
          y = oy + num.call
          pts << [x, y]
          ctrl = nil
        when 'H'
          x = ox + num.call
          pts << [x, y]
          ctrl = nil
        when 'V'
          y = (rel ? y : 0.0) + num.call
          pts << [x, y]
          ctrl = nil
        when 'C', 'S'
          if cmd.upcase == 'C'
            x1 = ox + num.call
            y1 = oy + num.call
          else
            x1, y1 = ctrl && ctrl[0] == :c ? [(2 * x) - ctrl[1], (2 * y) - ctrl[2]] : [x, y]
          end
          x2 = ox + num.call
          y2 = oy + num.call
          ex = ox + num.call
          ey = oy + num.call
          pts.concat(cubic([x, y], [x1, y1], [x2, y2], [ex, ey]))
          ctrl = [:c, x2, y2]
          x = ex
          y = ey
        when 'Q', 'T'
          if cmd.upcase == 'Q'
            x1 = ox + num.call
            y1 = oy + num.call
          else
            x1, y1 = ctrl && ctrl[0] == :q ? [(2 * x) - ctrl[1], (2 * y) - ctrl[2]] : [x, y]
          end
          ex = ox + num.call
          ey = oy + num.call
          pts.concat(quad([x, y], [x1, y1], [ex, ey]))
          ctrl = [:q, x1, y1]
          x = ex
          y = ey
        when 'A'
          rx = num.call.abs
          ry = num.call.abs
          phi = num.call
          large = flag.call
          sweep = flag.call
          ex = ox + num.call
          ey = oy + num.call
          pts.concat(arc(x, y, rx, ry, phi, large, sweep, ex, ey))
          ctrl = nil
          x = ex
          y = ey
        end
      end
      box_of(pts)
    rescue ArgumentError
      box_of(pts)
    end

    def cubic(p0, p1, p2, p3)
      out = [p0, p3]
      [0, 1].each do |i|
        a = -p0[i] + (3 * p1[i]) - (3 * p2[i]) + p3[i]
        b = 2 * (p0[i] - (2 * p1[i]) + p2[i])
        c = p1[i] - p0[i]
        roots(a, b, c).each do |t|
          mt = 1 - t
          out << [0, 1].map { |j| (mt**3 * p0[j]) + (3 * mt * mt * t * p1[j]) + (3 * mt * t * t * p2[j]) + (t**3 * p3[j]) }
        end
      end
      out
    end

    def quad(p0, p1, p2)
      out = [p0, p2]
      [0, 1].each do |i|
        den = p0[i] - (2 * p1[i]) + p2[i]
        next if den.abs < 1e-12

        t = (p0[i] - p1[i]) / den
        next unless t.positive? && t < 1

        mt = 1 - t
        out << [0, 1].map { |j| (mt * mt * p0[j]) + (2 * mt * t * p1[j]) + (t * t * p2[j]) }
      end
      out
    end

    # The roots of a t^2 + b t + c within (0, 1)
    def roots(a, b, c)
      list = if a.abs < 1e-12
               b.abs < 1e-12 ? [] : [-c / b]
             else
               disc = (b * b) - (4 * a * c)
               disc.negative? ? [] : [(-b + Math.sqrt(disc)) / (2 * a), (-b - Math.sqrt(disc)) / (2 * a)]
             end
      list.select { |t| t.positive? && t < 1 }
    end

    # An arc's end points and its extremes within the sweep (the svg specification's endpoint to centre conversion)
    def arc(x1, y1, rx, ry, phi_deg, large, sweep, x2, y2)
      return [[x2, y2]] if x1 == x2 && y1 == y2
      return [[x1, y1], [x2, y2]] if rx.zero? || ry.zero?

      phi = phi_deg * Math::PI / 180
      cp = Math.cos(phi)
      sp = Math.sin(phi)
      dx = (x1 - x2) / 2
      dy = (y1 - y2) / 2
      x1p = (cp * dx) + (sp * dy)
      y1p = (-sp * dx) + (cp * dy)
      lam = ((x1p**2) / (rx**2)) + ((y1p**2) / (ry**2))
      if lam > 1
        rx *= Math.sqrt(lam)
        ry *= Math.sqrt(lam)
      end
      num = (rx**2 * ry**2) - (rx**2 * y1p**2) - (ry**2 * x1p**2)
      den = (rx**2 * y1p**2) + (ry**2 * x1p**2)
      co = den.zero? ? 0.0 : Math.sqrt([num / den, 0.0].max)
      co = -co if large == sweep
      cxp = co * rx * y1p / ry
      cyp = -co * ry * x1p / rx
      cx = (cp * cxp) - (sp * cyp) + ((x1 + x2) / 2)
      cy = (sp * cxp) + (cp * cyp) + ((y1 + y2) / 2)
      ang = ->(ux, uy, vx, vy) { Math.atan2((ux * vy) - (uy * vx), (ux * vx) + (uy * vy)) }
      t1 = ang.call(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
      dt = ang.call((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
      dt -= 2 * Math::PI if !sweep && dt.positive?
      dt += 2 * Math::PI if sweep && dt.negative?
      at = ->(t) { [cx + (rx * cp * Math.cos(t)) - (ry * sp * Math.sin(t)), cy + (rx * sp * Math.cos(t)) + (ry * cp * Math.sin(t))] }
      out = [[x1, y1], [x2, y2]]
      tx = Math.atan2(-ry * sp, rx * cp)
      ty = Math.atan2(ry * cp, rx * sp)
      [tx, tx + Math::PI, ty, ty + Math::PI].each do |t|
        delta = dt >= 0 ? (t - t1) % (2 * Math::PI) : (t1 - t) % (2 * Math::PI)
        out << at.call(t) if delta <= dt.abs + 1e-9
      end
      out
    end
  end
end
