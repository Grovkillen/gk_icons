# frozen_string_literal: true

require 'yaml'
require 'zlib'

# gk_icons packs: icon packs live outside the plugin and are found, never configured. A pack is a folder with
# icon files in it; putting a folder in a packs root is all it takes (no setting, no code, no restart of
# anything but the index, which notices the folder by itself).
#
# Where packs are looked for (every root that exists is used; a pack found in a later root replaces one with
# the same key found earlier):
#   1. <the machine's instances folder>/../icon_packs                shared by every instance on the machine
#   2. <the instance's files>/icon_packs                             this instance only
#   3. the folders in the environment variable GK_ICON_PACKS (separated as PATH is: ; on Windows)
#
# What a pack folder may hold:
#   pack.yml (optional): key, name, version, license, attribution, homepage, variants, default_variant,
#                        files (the folder with the icons, default the pack folder itself), shortcodes (a file
#                        with name|:alias:|HEX per line), mono (true: drawn in the text's colour; false: as it is;
#                        left out: decided by looking at an icon)
#   the icons: *.svg and *.png. The name is the file's name without extension, in lower case. A variant is a
#   subfolder (flags/4x3/se.svg) or an ending listed in variants (smile-1F600-google.png).
# Without pack.yml the folder's name is the key and everything else is worked out.
#
# A pack icon is written <key>/<name> wherever an icon name is written: gk_icon('fa/hammer'), the palette.
module GkIcons
  module Packs
    Pack = Struct.new(:key, :name, :dir, :root, :meta, :icons, :aliases, :mono, :variants, :default_variant, keyword_init: true)
    KEY = /\A[a-z0-9][a-z0-9_-]{0,39}\z/
    EXTS = %w[svg png].freeze

    module_function

    def roots
      list = []
      list << File.expand_path(Rails.root.join('..', '..', '..', 'icon_packs').to_s)
      list << instance_root
      list.concat(ENV['GK_ICON_PACKS'].to_s.split(File::PATH_SEPARATOR).map(&:strip).reject(&:empty?).map { |p| File.expand_path(p) })
      list.uniq
    end

    # Root 2: the instance's files (where Redmine keeps attachments), icon_packs
    def instance_root
      files = (Redmine::Configuration['attachments_storage_path'].presence || Rails.root.join('files').to_s)
      File.expand_path(File.join(files, 'icon_packs'))
    end

    def live_roots = roots.select { |r| File.directory?(r) }

    # What the index depends on: the roots, their pack folders and each pack.yml. A new folder changes its
    # root's time; a changed pack.yml changes its own. (Files added to an existing pack change the pack folder's time.)
    # Looked at no more often than every few seconds: the folders are asked for their times, and a page has
    # many icons
    def stamp
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return @stamp_value if @stamp_value && @stamp_at && now - @stamp_at < 5

      @stamp_at = now
      @stamp_value = read_stamp
    end

    # A sum that is the same in every process and after a restart (Array#hash is seeded per process, so the
    # addresses' ?v= differed between workers and the long caching seldom hit)
    def read_stamp
      times = live_roots.flat_map do |r|
        [File.mtime(r).to_i] + Dir.children(r).sort.map do |c|
          d = File.join(r, c)
          next 0 unless File.directory?(d)

          y = File.join(d, 'pack.yml')
          File.mtime(d).to_i + (File.exist?(y) ? File.mtime(y).to_i : 0)
        end
      end
      Zlib.crc32(times.join(','))
    rescue StandardError
      0
    end

    def all
      s = stamp
      return @all if @all && @stamp == s

      @stamp = s
      @all = build
    end

    def reset! = (@all = @stamp_value = nil)

    def build
      packs = {}
      live_roots.each do |root|
        Dir.children(root).sort.each do |child|
          dir = File.join(root, child)
          next unless File.directory?(dir) && !child.start_with?('.', '_')

          pack = read_pack(dir, root)
          packs[pack.key] = pack if pack && pack.icons.any?
        rescue StandardError => e
          Rails.logger.warn("[gk_icons] pack #{dir} not read: #{e.class}: #{e.message}")
        end
      end
      packs
    end

    def read_pack(dir, root)
      yml = File.join(dir, 'pack.yml')
      meta = File.exist?(yml) ? (YAML.safe_load(File.read(yml, encoding: 'bom|utf-8')) || {}) : {}
      meta = {} unless meta.is_a?(Hash)
      key = meta['key'].to_s.presence || File.basename(dir).downcase.gsub(/[^a-z0-9_-]/, '-')
      return nil unless key.match?(KEY)

      files_dir = File.expand_path(File.join(dir, meta['files'].to_s.presence || '.'))
      return nil unless files_dir.start_with?(File.expand_path(dir)) && File.directory?(files_dir)

      variants = Array(meta['variants']).map(&:to_s)
      icons = {}
      add = lambda do |path, variant|
        ext = File.extname(path).delete('.').downcase
        return unless EXTS.include?(ext)

        name = File.basename(path, '.*')
        # an ending that is a listed variant: smile-1F600-google
        if variant.nil? && (v = variants.find { |x| name.downcase.end_with?("-#{x.downcase}") })
          variant = v
          name = name[0...-(v.length + 1)]
        end
        n = name.downcase.gsub(/[^a-z0-9_.-]/, '-')
        ((icons[n] ||= {})[variant || ''] ||= {})[ext] = path
      end
      Dir.children(files_dir).sort.each do |entry|
        path = File.join(files_dir, entry)
        if File.directory?(path)
          next if entry.start_with?('.', '_')

          Dir.children(path).sort.each { |f| add.call(File.join(path, f), entry) if File.file?(File.join(path, f)) }
        else
          add.call(path, nil)
        end
      end
      default = meta['default_variant'].to_s
      default = '' if default.empty? || default == 'generic' || icons.values.none? { |v| v.key?(default) }
      default = icons.values.first.keys.first.to_s if icons.any? && icons.values.none? { |v| v.key?(default) }
      Pack.new(key: key, name: meta['name'].to_s.presence || File.basename(dir), dir: dir, root: root, meta: meta, icons: icons,
               aliases: read_aliases(dir, meta, icons), mono: mono?(meta, icons, default), variants: icons.values.flat_map(&:keys).uniq.sort,
               default_variant: default)
    end

    # name|:alias:|HEX per line (an emoji pack's list of shortcodes): alias => icon name
    def read_aliases(dir, meta, icons)
      file = meta['shortcodes'].to_s
      path = File.expand_path(File.join(dir, file))
      return {} if file.empty? || !path.start_with?(File.expand_path(dir)) || !File.file?(path)

      File.foreach(path, encoding: 'bom|utf-8').each_with_object({}) do |line, h|
        name, code, hex = line.strip.split('|')
        next if name.to_s.empty? || code.to_s.empty?

        full = [name, hex].compact.join('-').downcase.gsub(/[^a-z0-9_.-]/, '-')
        target = icons.key?(full) ? full : (icons.key?(name.downcase) ? name.downcase : nil)
        h[code.delete(':').downcase] = target if target
      end
    end

    # Drawn in the text's colour or as it is: what pack.yml says, else a look at one icon (an svg that
    # names no colour of its own is a shape)
    def mono?(meta, icons, default)
      return meta['mono'] == true if [true, false].include?(meta['mono'])

      sample = icons.values.first.to_h.dig(default, 'svg') || icons.values.first.to_h.values.first.to_h['svg']
      return false unless sample

      text = File.read(sample, 4000, encoding: 'UTF-8').to_s
      !text.match?(/(fill|stroke|stop-color)\s*[:=]\s*["']?\s*(#(?!000\b|000000\b)[0-9a-fA-F]{3,8}|rgb|url\()/)
    end

    # 'fa/hammer' to [pack, name] when both are known (an alias counts as a name)
    def find(ref)
      key, name = ref.to_s.split('/', 2)
      pack = all[key.to_s] or return nil
      name = name.to_s.downcase
      name = pack.aliases[name] if !pack.icons.key?(name) && pack.aliases.key?(name)
      pack.icons.key?(name) ? [pack, name] : nil
    end

    def exists?(ref) = !find(ref).nil?

    # The file for an icon: the variant asked for, else the pack's default; svg before png
    def file(ref, variant: nil, ext: nil)
      pack, name = find(ref)
      return nil unless pack

      by_variant = pack.icons[name]
      v = by_variant[variant.to_s] || by_variant[pack.default_variant] || by_variant.values.first
      e = ext && v[ext.to_s] ? ext.to_s : (v.key?('svg') ? 'svg' : v.keys.first)
      [v[e], e]
    end

    def names = all.values.flat_map { |p| p.icons.keys.map { |n| "#{p.key}/#{n}" } }
  end
end
