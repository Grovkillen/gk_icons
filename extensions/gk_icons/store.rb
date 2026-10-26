# frozen_string_literal: true

require 'digest'
require 'base64'
require 'set'
require 'fileutils'
require 'nokogiri'

# gk_icons store
# * the packs' files are read into the database (GkIconsPack, GkIconsFile) and served from there; the folders
#   (packs.rb) are only where they are read from;
# * read again by itself when a pack folder changes (Packs.stamp) or at least every SWEEP seconds, in the
#   background, and at once from the library's button (an administrator);
# * three states, kept apart in two columns: chosen (active or disabled, an administrator's choice with a reason)
#   and on_disk (false when the file is gone; its copy stays here). The state is missing, disabled or active, in
#   that order (States). Only active icons are offered (library, picker); an icon already written somewhere is
#   drawn whatever its state, from the copy here, so no text breaks;
# * the page gets icons as sprites, in the pack's name order, at most CHUNK icons and about CHUNK_BYTES each, built
#   from the database and kept as files with the store's stamp in the name: a few requests for a library page instead
#   of one per icon;
# * each file is measured when it is read (Measure: the part of its box the picture draws on), so that an icon in text
#   is as high as the capitals and stands on the baseline; kept by content beside the sprites (measure.json).
# Until the first reading is done the plugin serves from disk as before (Store.ready? is false).
module GkIcons
  # The state of a pack or an icon file: missing (gone from disk) before disabled (chosen) before active
  module States
    LIST = %w[active disabled missing].freeze
    CHOICES = %w[active disabled].freeze

    def state
      return 'missing' unless on_disk

      chosen == 'disabled' ? 'disabled' : 'active'
    end

    def offered? = state == 'active'
  end

  module Store
    CHUNK = 200
    # The way sprites are built; part of the stamp, so a sprite built the old way is never served or cached again
    # under the new addresses
    BUILD = 3
    CHUNK_BYTES = 300 * 1024 # a png weighs a third more in the sprite (base64)
    SWEEP = 600 # seconds: a full look at the files' times even when no folder changed (a file replaced in place)
    BATCH = 100
    # One reading at a time in a process: the button waits for a reading in the background
    RUN_LOCK = Mutex.new
    # A reason refused by the place's mode in records, with records' own message
    class ReasonError < ArgumentError; end

    module_function

    # Where the administrator writes the reason (place given: icons.choose, icons.group_state) the place's mode
    # in records decides (off keeps none, optional accepts blank, required refuses blank). The scenario passes no
    # place, and the reason stays required as before; so does every reason without records.
    def reason_text!(reason, place)
      if place && defined?(::GkRecords::Reasons)
        check = ::GkRecords::Reasons.check(place, reason)
        raise ReasonError, check.error unless check.ok

        return check.text
      end
      raise ArgumentError, 'reason' if reason.to_s.strip.empty?

      reason.to_s.strip
    end

    def table?
      @table ||= ActiveRecord::Base.connection.data_source_exists?('gk_icons_files') && ActiveRecord::Base.connection.data_source_exists?('gk_icons_packs')
    rescue StandardError
      false
    end

    # What changes when anything in the store changes; asked at most every few seconds
    def stamp
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return @stamp if @stamp && @stamp_at && now - @stamp_at < 3

      @stamp_at = now
      @stamp = read_stamp
    end

    def read_stamp
      return '0' unless table?

      f = GkIconsFile.pluck(Arel.sql('COUNT(*)'), Arel.sql('MAX(updated_at)')).first
      p = GkIconsPack.pluck(Arel.sql('COUNT(*)'), Arel.sql('MAX(updated_at)')).first
      g = groups_table? ? GkIconsGroup.pluck(Arel.sql('COUNT(*)'), Arel.sql('MAX(updated_at)')).first : []
      m = groups_table? ? GkIconsGroupMember.pluck(Arel.sql('COUNT(*)'), Arel.sql('MAX(updated_at)')).first : []
      Zlib.crc32(([BUILD] + [f, p, g, m].flatten).map { |v| v.respond_to?(:to_f) ? v.to_f : v.to_s }.join(',')).to_s(36)
    rescue StandardError
      '0'
    end

    def ready? = table? && index.any?

    def groups_table?
      @groups_table ||= ActiveRecord::Base.connection.data_source_exists?('gk_icons_groups')
    rescue StandardError
      false
    end

    def reset!
      @stamp = @stamp_at = @index = @index_stamp = @groups = @groups_stamp = nil
    end

    # ------------------------------------------------------------------ where an icon is already written
    # Two settings, disabled_where_used and missing_where_used: shown (the default) or hidden. Hidden is as an
    # unknown name: the code stays as it was written, nothing broken is drawn. A pack's state goes before its
    # icons'.
    WHERE_USED = { 'disabled' => 'disabled_where_used', 'missing' => 'missing_where_used' }.freeze

    def effective_state(ref)
      pk, name = find(ref)
      return nil unless pk

      pk[:state] == 'active' ? pk[:icons][name][:state] : pk[:state]
    end

    # settings: the plugin's settings to judge by, when not the saved ones
    def drawable?(ref, settings: nil)
      st = effective_state(ref) or return false
      return true if st == 'active'

      (settings || Setting.plugin_gk_icons || {})[WHERE_USED[st]].to_s != 'hidden'
    rescue StandardError
      true
    end

    # ------------------------------------------------------------------ groups
    # [{ key:, name:, description:, state:, reason:, refs: [] }] in the groups' order
    def groups
      return [] unless groups_table?

      s = stamp
      return @groups if @groups && @groups_stamp == s

      @groups_stamp = s
      members = GkIconsGroupMember.order(:position, :id).pluck(:group_id, :ref).group_by(&:first)
      @groups = GkIconsGroup.order(:position, :name).map do |g|
        { key: g.key, name: g.name, description: g.description, state: g.state, reason: g.reason,
          refs: Array(members[g.id]).map(&:last) }
      end
    rescue StandardError => e
      Rails.logger.warn("[gk_icons] groups not read: #{e.class}: #{e.message}")
      []
    end

    # A reference that may be in a group: a pack's icon the store knows, or a name of Redmine's or our own
    # A pack icon the index does not know yet (the index can be read again in the background from another connection,
    # before a change in this one is committed) is asked of the table itself
    def known_ref?(ref)
      return GkIcons.exists?(ref) unless ref.to_s.include?('/')

      exists?(ref) || GkIconsFile.where(pack: ref.to_s.split('/').first, name: ref.to_s.split('/', 2).last).exists?
    end

    GROUP_KEY = /\A[a-z0-9][a-z0-9_-]{0,59}\z/

    # key: given by the caller (a scenario finds its group again by its own key), never taken from another group;
    # without it the key is made from the name
    def create_group!(name, user, key: nil)
      name = name.to_s.strip
      raise ArgumentError, 'group_name' if name.empty?

      if key
        key = key.to_s
        raise ArgumentError, 'group_key' unless key.match?(GROUP_KEY)
        raise ArgumentError, 'group_key taken' if GkIconsGroup.exists?(key: key)
      else
        base = name.downcase.unicode_normalize(:nfkd).gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')[0, 50]
        base = 'group' if base.empty?
        key = base
        n = 1
        key = "#{base}-#{n += 1}" while GkIconsGroup.exists?(key: key)
      end
      g = GkIconsGroup.create!(key: key, name: name, position: GkIconsGroup.maximum(:position).to_i + 1,
                               changed_by_id: user&.id, changed_at: Time.current)
      History.write(g, 'icons_group_made', { 'name' => name }, user: user)
      reset!
      g
    end

    # Name, description and state; a change of state asks a reason, like an icon's
    def update_group!(key, user, name: nil, chosen: nil, reason: nil, description: nil, place: nil)
      g = GkIconsGroup.find_by!(key: key.to_s)
      attrs = {}
      attrs[:name] = name.to_s.strip if name && name.to_s.strip.present?
      attrs[:description] = description.to_s if description
      if chosen && chosen.to_s != g.chosen
        raise ArgumentError, 'chosen' unless States::CHOICES.include?(chosen.to_s)

        reason = reason_text!(reason, place)
        attrs.merge!(chosen: chosen.to_s, reason: reason, changed_by_id: user&.id, changed_at: Time.current)
      end
      before = g.attributes.slice('name', 'description', 'chosen')
      g.update!(attrs) if attrs.any?
      changes = attrs.slice(:name, :description, :chosen).to_h { |k, v| [k.to_s, [before[k.to_s], v]] }.reject { |_k, (a, b)| a == b }
      History.write(g, 'icons_group_changed', changes, reason: (reason if changes.key?('chosen')), user: user) if changes.any?
      reset!
      Rails.logger.info("[gk_icons] group #{g.key} changed by #{user&.login}: #{attrs.except(:changed_at).to_h}")
      g
    end

    # Many icons at once from the Icons tab, one reason for all (checked once as the place icons.choose says); only a
    # pack's icons have a state, so Redmine's and the plugin's own are skipped.
    # One event per icon, as when they are chosen one by one. Returns [changed, skipped].
    def choose_many!(refs, chosen, reason, user, place: nil)
      raise ArgumentError, 'chosen' unless States::CHOICES.include?(chosen.to_s)

      reason = reason_text!(reason, place)
      changed = skipped = 0
      GkIconsFile.transaction do
        Array(refs).map(&:to_s).uniq.each do |ref|
          pk, name = ref.include?('/') ? find(ref) : nil
          next skipped += 1 unless pk
          next skipped += 1 if pk[:icons][name][:state] == chosen.to_s

          was = pk[:icons][name][:state]
          GkIconsFile.where(pack: pk[:key], name: name)
                     .update_all(chosen: chosen.to_s, reason: reason, changed_by_id: user&.id, changed_at: Time.current, updated_at: Time.current)
          now_state = if was == 'missing' then 'missing' elsif chosen.to_s == 'disabled' then 'disabled' else 'active' end
          History.write(GkIconsPack.find_by(key: pk[:key]), 'icons_state_chosen',
                        { 'icon' => "#{pk[:key]}/#{name}", 'chosen' => chosen.to_s, 'state' => [was, now_state] }, reason: reason, user: user)
          changed += 1
        end
      end
      reset!
      clear_sprites
      Rails.logger.info("[gk_icons] #{changed} icons #{chosen} by #{user&.login} (#{skipped} skipped): #{reason}")
      [changed, skipped]
    end

    # Many icons into a group or out of it: [changed]
    def members_many!(key, refs, on, user)
      changed = 0
      Array(refs).map(&:to_s).uniq.each do |ref|
        g = GkIconsGroup.find_by!(key: key.to_s)
        next unless known_ref?(ref)

        had = g.members.exists?(ref: ref)
        next if had == on

        member!(key, ref, on, user)
        changed += 1
      end
      changed
    end

    # An icon in or out of a group
    def member!(key, ref, on, user)
      g = GkIconsGroup.find_by!(key: key.to_s)
      raise ActiveRecord::RecordNotFound unless known_ref?(ref)

      if on
        m = g.members.find_or_create_by!(ref: ref.to_s) do |x|
          x.position = g.members.maximum(:position).to_i + 1
          x.added_by_id = user&.id
        end
        History.write(g, 'icons_member_added', { 'icon' => ref.to_s }, user: user) if m.previously_new_record?
      else
        gone = g.members.where(ref: ref.to_s).delete_all
        g.touch
        History.write(g, 'icons_member_removed', { 'icon' => ref.to_s }, user: user) if gone.positive?
      end
      reset!
      Rails.logger.info("[gk_icons] #{ref} #{on ? 'into' : 'out of'} group #{g.key} by #{user&.login}")
      true
    end

    # ------------------------------------------------------------------ the index (no content)
    # key => { key:, name:, mono:, default_variant:, aliases:, state:, license:,
    #          icons: { name => { files: { variant => { ext => [id, state, bytes, sha256] } }, state: }, order: [names],
    #          chunk: { name => n } }
    def index
      s = stamp
      return @index if @index && @index_stamp == s

      @index_stamp = s
      @index = build_index
    end

    def build_index
      return {} unless table?

      out = {}
      GkIconsPack.find_each do |p|
        out[p.key] = { key: p.key, name: p.name.presence || p.key, mono: p.mono, default_variant: p.default_variant.to_s,
                       aliases: p.alias_map, state: p.state, license: p.license, icons: {}, order: [], chunk: {} }
      end
      GkIconsFile.without_content.order(:pack, :name).each do |f|
        pk = out[f.pack] or next
        icon = (pk[:icons][f.name] ||= { files: {}, states: [] })
        (icon[:files][f.variant] ||= {})[f.ext] = [f.id, f.state, f.bytes.to_i, f.sha256]
        icon[:states] << f.state
      end
      out.each_value do |pk|
        pk[:icons].each_value do |icon|
          st = icon.delete(:states)
          # an icon is as its best file: active if any file is, else disabled if any is, else missing
          icon[:state] = States::LIST.find { |x| st.include?(x) } || 'missing'
        end
        pk[:order] = pk[:icons].keys.sort
        cut_chunks(pk)
      end
      out
    rescue StandardError => e
      Rails.logger.warn("[gk_icons] store index not read: #{e.class}: #{e.message}")
      {}
    end

    # The pack's icons cut into sprites: a new sprite when the next icon would pass CHUNK_BYTES or CHUNK icons.
    # An icon's weight is its file as drawn (the default variant, svg before png; png counted as base64).
    def cut_chunks(pk)
      pk[:chunks] = []
      size = count = 0
      pk[:order].each do |n|
        files = pk[:icons][n][:files]
        v = files[pk[:default_variant]] || files.values.first
        e = v.key?('svg') ? 'svg' : v.keys.first
        b = v[e][2].to_i
        b = (b * 4 / 3) + 100 if e == 'png'
        if count.positive? && (size + b > CHUNK_BYTES || count >= CHUNK)
          size = count = 0
        end
        pk[:chunks] << [] if count.zero?
        pk[:chunks].last << n
        pk[:chunk][n] = pk[:chunks].size - 1
        size += b
        count += 1
      end
    end

    # 'fa/hammer' to [pack, name] (an alias counts as a name), whatever the state
    def find(ref)
      key, name = ref.to_s.split('/', 2)
      pk = index[key.to_s] or return nil
      name = name.to_s.downcase
      name = pk[:aliases][name] if !pk[:icons].key?(name) && pk[:aliases].key?(name)
      pk[:icons].key?(name) ? [pk, name] : nil
    end

    def exists?(ref) = !find(ref).nil?

    # Offered: the icon and its pack both active
    def offered?(ref)
      pk, name = find(ref)
      pk && pk[:state] == 'active' && pk[:icons][name][:state] == 'active'
    end

    # [file id, ext] for an icon: the variant asked for, else the pack's default; svg before png
    def file_id(ref, variant: nil, ext: nil)
      entry, e = file_entry(ref, variant: variant, ext: ext)
      entry ? [entry[0], e] : nil
    end

    # The index's [id, state, bytes, sha256] of that file, and its ext
    def file_entry(ref, variant: nil, ext: nil)
      pk, name = find(ref)
      return nil unless pk

      by_variant = pk[:icons][name][:files]
      v = by_variant[variant.to_s] || by_variant[pk[:default_variant]] || by_variant.values.first
      e = ext && v[ext.to_s] ? ext.to_s : (v.key?('svg') ? 'svg' : v.keys.first)
      [v[e], e]
    end

    def symbol_id(pack, name) = "i-#{pack}-#{name}".gsub(/[^A-Za-z0-9_.-]/, '_')

    # ------------------------------------------------------------------ what an icon draws (Measure)
    # Each file is measured when it is read in (sync_files): its box and the part of it the picture draws on. The
    # measurement is kept by the content's SHA-256 (the same content measures the same, and a changed file gets a new
    # one) in <Rails.root>/tmp/gk_icons/measure.json beside the sprites, so that no page measures. A file the store
    # read before, or a measure.json that was emptied, is measured in the background after the next reading
    # (measure_later); an icon drawn before that is measured once when it is drawn and kept with the others.
    def measure_file = File.join(sprite_dir, 'measure.json')

    def measures
      @measures ||= load_measures
    end

    def load_measures
      data = JSON.parse(File.read(measure_file))
      data.is_a?(Hash) && data['v'] == Measure::VERSION && data['files'].is_a?(Hash) ? data['files'] : {}
    rescue StandardError
      {}
    end

    # Another process's measurements are kept too: the file on disk and this process's are merged before writing
    def save_measures
      FileUtils.mkdir_p(sprite_dir)
      merged = load_measures.merge(measures)
      @measures = merged
      @measures_dirty = false
      tmp = "#{measure_file}.#{Process.pid}.#{Thread.current.object_id}.tmp"
      File.write(tmp, JSON.generate('v' => Measure::VERSION, 'files' => merged))
      File.rename(tmp, measure_file)
    rescue SystemCallError => e
      File.delete(tmp) if tmp && File.exist?(tmp)
      Rails.logger.warn("[gk_icons] measurements not kept: #{e.message}")
    end

    # A file's measurement, made once for its content; {} when the file could not be read (drawn by its whole box)
    def measure_data(sha, data, ext)
      return measures[sha] if measures.key?(sha)

      @measures_dirty = true
      measures[sha] = Measure.file(data, ext) || {}
    end

    # The measurement of the file an icon is drawn from, or nil
    def measure(ref)
      entry, ext = file_entry(ref)
      return nil unless entry

      sha = entry[3]
      return measures[sha] if sha && measures.key?(sha)

      row = GkIconsFile.where(id: entry[0]).pick(:sha256, :content) or return nil
      measure_data(row[0], row[1], ext)
    rescue StandardError => e
      Rails.logger.warn("[gk_icons] #{ref} not measured: #{e.class}: #{e.message}")
      nil
    end

    # Every drawn file (one per icon, as file_entry chooses) that has no measurement is measured in the background, one
    # run at a time, a connection only while a batch is read
    def measure_later
      @measure_guard ||= Mutex.new
      go = @measure_guard.synchronize do
        next false if @measuring

        @measuring = true
      end
      return unless go

      Thread.new do
        Rails.application.executor.wrap do
          missing = index.values.flat_map do |pk|
            pk[:order].filter_map do |n|
              entry, ext = file_entry("#{pk[:key]}/#{n}")
              entry && entry[3] && !measures.key?(entry[3]) ? [entry[0], ext] : nil
            end
          end
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          missing.each_slice(BATCH) do |slice|
            GkIconsFile.where(id: slice.map(&:first)).pluck(:sha256, :ext, :content).each { |sha, ext, data| measure_data(sha, data, ext) }
            ActiveRecord::Base.connection_pool.release_connection
          end
          save_measures if @measures_dirty
          Rails.logger.info(format('[gk_icons] %<n>d icons measured in %<s>.1f s', n: missing.size, s: Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0)) if missing.any?
        end
      rescue StandardError => e
        Rails.logger.warn("[gk_icons] icons not measured: #{e.class}: #{e.message}")
      ensure
        @measuring = false
      end
    end

    # Where the page finds an icon in a sprite: the address of the chunk and the symbol's id
    def sprite_ref(ref)
      pk, name = find(ref)
      return nil unless pk

      ["#{sprite_base}#{pk[:key]}/#{pk[:chunk][name]}.svg?v=#{stamp}", symbol_id(pk[:key], name)]
    end

    def sprite_base = "#{Redmine::Utils.relative_url_root}/gk_icons/s/"

    # ------------------------------------------------------------------ reading from disk
    # Reads every pack folder into the database: new files added, changed files read again (time or size differ,
    # then the content's SHA-256 decides), files gone marked missing, files back marked on disk. Returns the counts.
    def sync!(user: nil)
      raise 'gk_icons tables missing (migrate)' unless table?

      RUN_LOCK.synchronize { read_all(user) }
    end

    def read_all(user)
      counts = Hash.new(0)
      now = Time.current
      packs = Packs.build
      left = GkIconsPack.all.index_by(&:key)
      packs.each do |key, p|
        row = left.delete(key) || GkIconsPack.new(key: key)
        counts[:packs_added] += 1 if row.new_record?
        row.assign_attributes(name: p.name, license: p.meta['license']&.to_s, version: p.meta['version']&.to_s,
                              attribution: p.meta['attribution']&.to_s, mono: p.mono, default_variant: p.default_variant.to_s,
                              aliases: p.aliases.to_json, root: p.dir, on_disk: true)
        row.save! if row.changed?
        before = counts.dup
        sync_files(key, p, counts, now)
        read_event(row, before, counts, user)
      end
      left.each_value do |row|
        next unless row.on_disk

        row.update!(on_disk: false)
        counts[:packs_missing] += 1
        n = GkIconsFile.where(pack: row.key, on_disk: true).update_all(on_disk: false, updated_at: now)
        counts[:missing] += n
        History.write(row, 'icons_read', { 'pack' => 'missing', 'missing' => n }, user: user)
      end
      @last_sync = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      reset!
      clear_sprites
      # the files read now are measured; the rest (read before, or a measure.json emptied) in the background
      measure_later
      Rails.logger.info("[gk_icons] read from disk#{user ? " by #{user.login}" : ''}: #{counts.to_h}")
      counts.to_h
    end

    # A reading that changed something in a pack is an event on it: what came, changed, went or came back
    def read_event(row, before, counts, user)
      diff = %i[added changed missing back].to_h { |k| [k.to_s, counts[k] - before[k]] }.select { |_k, v| v.positive? }
      History.write(row, 'icons_read', diff, user: user) if diff.any?
    end

    def sync_files(key, pack, counts, now)
      known = {}
      GkIconsFile.where(pack: key).pluck(:id, :name, :variant, :ext, :source_mtime, :bytes, :on_disk, :sha256).each do |r|
        known[r[1..3]] = r
      end
      seen = Set.new
      fresh = []
      pack.icons.each do |name, by_variant|
        by_variant.each do |variant, by_ext|
          by_ext.each do |ext, path|
            k = [name, variant.to_s, ext]
            seen << k
            st = File.stat(path)
            old = known[k]
            if old && old[4] == st.mtime.to_i && old[5] == st.size && old[6]
              counts[:unchanged] += 1
              next
            end
            data = File.binread(path)
            sha = Digest::SHA256.hexdigest(data)
            # what the picture draws, measured while its content is in hand (Measure)
            measure_data(sha, data, ext)
            if old
              attrs = { source_mtime: st.mtime.to_i, bytes: data.bytesize, on_disk: true }
              if old[7] != sha
                attrs.merge!(content: data, sha256: sha)
                counts[:changed] += 1
              else
                counts[old[6] ? :touched : :back] += 1
              end
              GkIconsFile.find(old[0]).update!(attrs)
            else
              fresh << { pack: key, name: name, variant: variant.to_s, ext: ext, content: data, sha256: sha, bytes: data.bytesize,
                         source_mtime: st.mtime.to_i, on_disk: true, chosen: 'active', created_at: now, updated_at: now }
              counts[:added] += 1
              if fresh.size >= BATCH
                GkIconsFile.insert_all(fresh)
                fresh = []
              end
            end
          rescue SystemCallError => e
            Rails.logger.warn("[gk_icons] #{path} not read: #{e.message}")
          end
        end
      end
      GkIconsFile.insert_all(fresh) if fresh.any?
      gone = known.reject { |k, r| seen.include?(k) || !r[6] }.values.map(&:first)
      counts[:missing] += GkIconsFile.where(id: gone).update_all(on_disk: false, updated_at: now) if gone.any?
    end

    # By itself: when a pack folder changed, or SWEEP seconds after the last reading; in the background, one at a
    # time, so that no page waits for it. The first reading in a process is the same (only changed files are read).
    def sync_later
      return unless table?

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      disk = Packs.stamp
      due = @synced_stamp != disk || @last_sync.nil? || now - @last_sync > SWEEP
      # an empty store (emptied, or never read) reads itself in again, at most once a minute when there is nothing to read
      due ||= index.empty? && now - @last_sync > 60
      return unless due

      @guard ||= Mutex.new
      busy = @guard.synchronize do
        next true if @syncing

        @syncing = true
        false
      end
      return if busy

      @synced_stamp = disk
      @last_sync = now
      Thread.new do
        Rails.application.executor.wrap { sync! }
      rescue StandardError => e
        Rails.logger.warn("[gk_icons] reading from disk failed: #{e.class}: #{e.message}")
      ensure
        @guard.synchronize { @syncing = false }
      end
    rescue StandardError => e
      @guard&.synchronize { @syncing = false }
      Rails.logger.warn("[gk_icons] reading from disk not started: #{e.class}: #{e.message}")
    end

    def syncing? = !!@syncing

    # ------------------------------------------------------------------ state
    # An administrator's choice for an icon (all its files) or a pack, with a reason; returns the new state
    # A pack's height, place and side space in text (GkIcons.text_fit), set on the Packs tab: kept in the plugin's
    # settings (pack_text). A value equal to the pack's own (its pack.yml, else the plugin's default) and a blank field
    # are kept as no value, so that the pack goes on following its pack.yml; the change and its reason in the pack's
    # history. Returns false when nothing changed.
    def fit!(key, scale, shift, gap, reason, user)
      row = GkIconsPack.find_by!(key: key.to_s)
      base = GkIcons.text_base(row.key)
      clean = lambda do |k, v|
        s = v.to_s.strip.tr(',', '.')
        next nil if s.empty?

        n = s.to_f.clamp(*GkIcons::TEXT_RANGE[k]).round(3)
        n == base[k] ? nil : n.to_s
      end
      now = { 'scale' => clean.call('scale', scale), 'shift' => clean.call('shift', shift), 'gap' => clean.call('gap', gap) }.compact
      settings = (Setting.plugin_gk_icons || {}).to_h
      all = (settings['pack_text'] || {}).to_h
      was = (all[row.key] || {}).to_h.slice('scale', 'shift', 'gap')
      return false if was == now

      reason = reason_text!(reason, 'icons.text_fit')
      now.empty? ? all.delete(row.key) : all[row.key] = now
      Setting.plugin_gk_icons = settings.merge('pack_text' => all)
      History.write(row, 'icons_text_fit', { 'pack' => row.key, 'scale' => [was['scale'], now['scale']], 'shift' => [was['shift'], now['shift']],
                                             'gap' => [was['gap'], now['gap']] },
                    reason: reason, user: user)
      true
    end

    def choose!(ref, chosen, reason, user, whole_pack: false, place: nil)
      raise ArgumentError, 'chosen' unless States::CHOICES.include?(chosen.to_s)

      reason = reason_text!(reason, place)
      attrs = { chosen: chosen.to_s, reason: reason, changed_by_id: user&.id, changed_at: Time.current }
      if whole_pack
        row = GkIconsPack.find_by!(key: ref.to_s.split('/').first)
        was = row.state
        row.update!(attrs)
        History.write(row, 'icons_state_chosen', { 'pack' => row.key, 'state' => [was, row.state] }, reason: reason, user: user)
      else
        pk, name = find(ref)
        # the index may have been read again in the background without a change this connection has not committed
        pk, name = (reset! || true) && find(ref) unless pk
        raise ActiveRecord::RecordNotFound unless pk
        was = pk[:icons][name][:state]
        GkIconsFile.where(pack: pk[:key], name: name).update_all(attrs.merge(updated_at: Time.current))
        now_state = if was == 'missing' then 'missing' elsif chosen.to_s == 'disabled' then 'disabled' else 'active' end
        History.write(GkIconsPack.find_by(key: pk[:key]), 'icons_state_chosen',
                      { 'icon' => "#{pk[:key]}/#{name}", 'chosen' => chosen.to_s, 'state' => [was, now_state] }, reason: reason, user: user)
      end
      reset!
      clear_sprites
      Rails.logger.info("[gk_icons] #{whole_pack ? 'pack' : 'icon'} #{ref} #{chosen} by #{user&.login}: #{reason}")
      chosen.to_s
    end

    # ------------------------------------------------------------------ sprites
    def sprite_dir = Rails.root.join('tmp', 'gk_icons').to_s

    def clear_sprites
      FileUtils.rm_rf(Dir.glob(File.join(sprite_dir, '*.svg')))
    rescue StandardError
      nil
    end

    # Every chunk of every pack built in the background when the library or a picker asks for the names, so that
    # showing more never waits for a chunk to be built (it took up to 5 s for a chunk of flags)
    def warm_sprites_later
      st = stamp
      @warm_guard ||= Mutex.new
      go = @warm_guard.synchronize do
        next false if @warmed == st || @warming

        @warming = true
      end
      return unless go

      Thread.new do
        Rails.application.executor.wrap do
          # a connection only while a chunk is read: the pool is small on purpose, and pages wait for it
          index.each_value do |pk|
            Array(pk[:chunks]).each_index do |c|
              sprite_file(pk[:key], c)
              ActiveRecord::Base.connection_pool.release_connection
            end
          end
          # files of other stamps are not served any more
          Dir.glob(File.join(sprite_dir, '*.svg')).each { |p| File.delete(p) unless File.basename(p, '.svg').end_with?("-#{st}") }
          @warmed = st
        end
      rescue StandardError => e
        Rails.logger.warn("[gk_icons] sprites not built ahead: #{e.class}: #{e.message}")
      ensure
        @warming = false
      end
    end

    # The file for one chunk of a pack, built when first asked for
    def sprite_file(key, chunk)
      pk = index[key.to_s] or return nil
      names = Array(pk[:chunks][chunk.to_i])
      return nil if names.nil? || names.empty?

      path = File.join(sprite_dir, "#{key}-#{chunk.to_i}-#{stamp}.svg")
      return path if File.exist?(path)

      # One builder per file in a process (two requests, or a request and the building ahead, wrote the same temporary
      # file and one of them answered 500; the browser never asks again for a failed sprite)
      @build_guard ||= Mutex.new
      lock = @build_guard.synchronize { (@build_locks ||= {})[path] ||= Mutex.new }
      lock.synchronize { File.exist?(path) ? path : build_sprite(path, key, names) }
    end

    def build_sprite(path, key, names)
      FileUtils.mkdir_p(sprite_dir)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ids = names.map { |n| file_id("#{key}/#{n}")&.first }.compact
      rows = GkIconsFile.where(id: ids).to_h { |f| [f.name, f] }
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      body = names.filter_map { |n| (rows[n] && symbol(key, n, rows[n])) || png_instead(key, n) }.join("\n")
      t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Rails.logger.info(format('[gk_icons] sprite %<f>s built: read %<r>d ms, symbols %<s>d ms', f: File.basename(path), r: ((t1 - t0) * 1000).round, s: ((t2 - t1) * 1000).round))
      tmp = "#{path}.#{Process.pid}.#{Thread.current.object_id}.tmp"
      File.write(tmp, %(<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">\n#{body}\n</svg>\n))
      File.rename(tmp, path)
      path
    rescue SystemCallError
      # another process finished it first (the name is the same for the same content)
      File.delete(tmp) if tmp && File.exist?(tmp)
      File.exist?(path) ? path : raise
    end

    SVG_ROOT = %r{<svg\b([^>]*)>(.*)</svg>}m
    KEEP = %w[fill stroke stroke-width stroke-linecap stroke-linejoin stroke-miterlimit fill-rule clip-rule style opacity].freeze

    def symbol(key, name, file)
      id = symbol_id(key, name)
      if file.ext == 'png'
        w, h = png_size(file.content)
        return %(<symbol id="#{id}" viewBox="0 0 #{w} #{h}"><image width="#{w}" height="#{h}" href="data:image/png;base64,#{Base64.strict_encode64(file.content)}"/></symbol>)
      end

      text = file.content.dup.force_encoding('UTF-8')
      text = text.scrub.sub(/\A﻿/, '').gsub(/<\?xml.*?\?>|<!DOCTYPE[^>]*>|<!--.*?-->/m, '')
      # A file that is not an svg document (a pack had whole web pages saved as.svg) is left out; one broken file
      # made the rest of its sprite unreadable, so its icons stayed empty
      return refuse(key, name, 'not an svg document') unless text.lstrip.start_with?('<svg')
      m = text.match(SVG_ROOT) or return refuse(key, name, 'no svg root')
      attrs = m[1]
      inner = m[2]
      vb = attrs[/viewBox="([^"]+)"/i, 1] || begin
        w = attrs[/\bwidth="([\d.]+)/, 1]
        h = attrs[/\bheight="([\d.]+)/, 1]
        w && h ? "0 0 #{w} #{h}" : '0 0 24 24'
      end
      keep = KEEP.filter_map { |a| (v = attrs[/\s#{a}="([^"]*)"/, 1]) ? %(#{a}="#{v}") : nil }.join(' ')
      # the ids inside one icon (gradients, clip paths) made unique in the sprite, and the references to them
      pre = "#{id}-"
      inner = inner.gsub(/\bid="([^"]+)"/) { %(id="#{pre}#{Regexp.last_match(1)}") }
                   .gsub(/url\(\s*#([^)\s]+)\s*\)/) { "url(##{pre}#{Regexp.last_match(1)})" }
                   .gsub(/((?:xlink:)?href)="#([^"]+)"/) { %(#{Regexp.last_match(1)}="##{pre}#{Regexp.last_match(2)}") }
      sym = %(<symbol id="#{id}" viewBox="#{vb}"><g #{keep}>#{inner}</g></symbol>)
      well_formed?(sym) ? sym : refuse(key, name, 'not well-formed')
    end

    # The symbol must stand as XML by itself, or the browser stops reading the sprite where it breaks
    def well_formed?(sym)
      Nokogiri::XML(%(<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">#{sym}</svg>)) { |c| c.strict.nonet }
      true
    rescue Nokogiri::XML::SyntaxError
      false
    end

    # An icon whose svg was left out is drawn from a png of any of its variants when the pack has one (the emoji pack has
    # a png beside each svg)
    def png_instead(key, name)
      files = index.dig(key.to_s, :icons, name, :files) or return nil
      id = files.values.filter_map { |v| v['png']&.first }.first or return nil
      f = GkIconsFile.find_by(id: id)
      f && f.ext == 'png' ? symbol(key, name, f) : nil
    end

    def refuse(key, name, why)
      Rails.logger.warn("[gk_icons] #{key}/#{name} left out of the sprite: #{why}")
      nil
    end

    def png_size(data)
      return [64, 64] unless data.byteslice(1, 3) == 'PNG'

      data.byteslice(16, 8).unpack('NN')
    end
  end
end
