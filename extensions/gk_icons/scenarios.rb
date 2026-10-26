# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

module GkIcons
  # gk_icons in scenarios: the store's states, tried on a pack of its own in a temporary folder, never on the packs
  # that are there. Everything is done in a transaction that is rolled back, and the store's index is read again
  # afterwards, so the instance is as it was.
  # icons_store: cycle two icons read in (added 2); one file removed from disk (missing 1, its copy kept and the
  # icon still drawn); the file back (back 1, active again); the other disabled with a reason (not offered, still
  # drawn); a choice without a reason refused
  # The step icons (below) gives an instance the scenario's own packs, states, groups and settings; the expectations
  # icons_pack, icons_state, icons_group and icons_in_text read what is there. Neither touches a pack the scenario did
  # not bring.
  module Scenarios
    KEY = 'scn-store-test'
    SVG = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M2 2h20v20H2z"/></svg>)

    module_function

    def pack_in(dir) = Packs.read_pack(dir, File.dirname(dir))

    def cycle
      checks = []
      Dir.mktmpdir('gk_icons_scn') do |tmp|
        dir = File.join(tmp, KEY)
        Dir.mkdir(dir)
        File.write(File.join(dir, 'one.svg'), SVG)
        File.write(File.join(dir, 'two.svg'), SVG.sub('20v20', '10v10'))
        ::GkIconsFile.transaction(requires_new: true) do
          now = Time.current
          ::GkIconsPack.create!(key: KEY, name: KEY, mono: true, on_disk: true)
          c = Hash.new(0)
          Store.sync_files(KEY, pack_in(dir), c, now)
          checks << ['added 2', c[:added] == 2]
          Store.reset!
          checks << ['both active and offered', Store.offered?("#{KEY}/one") && Store.offered?("#{KEY}/two")]

          File.delete(File.join(dir, 'one.svg'))
          c = Hash.new(0)
          Store.sync_files(KEY, pack_in(dir), c, now)
          Store.reset!
          one = ::GkIconsFile.find_by(pack: KEY, name: 'one')
          checks << ['missing 1', c[:missing] == 1 && one&.state == 'missing']
          checks << ['copy kept', one && one.content.to_s.include?('<svg')]
          checks << ['missing not offered, still drawn', !Store.offered?("#{KEY}/one") && Store.exists?("#{KEY}/one")]

          File.write(File.join(dir, 'one.svg'), SVG)
          c = Hash.new(0)
          Store.sync_files(KEY, pack_in(dir), c, now)
          Store.reset!
          checks << ['back 1, active', c[:back] + c[:changed] == 1 && ::GkIconsFile.find_by(pack: KEY, name: 'one')&.state == 'active']

          refused = begin
            Store.choose!("#{KEY}/two", 'disabled', '', nil)
            false
          rescue ArgumentError
            true
          end
          checks << ['no reason refused', refused]
          Store.choose!("#{KEY}/two", 'disabled', 'scenario', nil)
          two = ::GkIconsFile.find_by(pack: KEY, name: 'two')
          checks << ['disabled with reason', two&.state == 'disabled' && two.reason == 'scenario']
          checks << ['disabled not offered, still drawn', !Store.offered?("#{KEY}/two") && Store.drawable?("#{KEY}/two")]

          # Where it is written, as the setting says (given here, never written to the saved settings)
          hidden = { 'disabled_where_used' => 'hidden' }
          Store.reset!
          checks << ['disabled hidden by the setting', !Store.drawable?("#{KEY}/two", settings: hidden) && Store.drawable?("#{KEY}/one", settings: hidden)]

          # A group across packs, with an icon of the pack and one of Redmine's own
          g = Store.create_group!('Prov grupp', nil)
          Store.member!(g.key, "#{KEY}/one", true, nil)
          Store.member!(g.key, "#{KEY}/two", true, nil)
          core_name = GkIcons.core.keys.first
          Store.member!(g.key, core_name, true, nil) if core_name
          grp = Store.groups.find { |x| x[:key] == g.key }
          checks << ['group with members', grp && grp[:refs].include?("#{KEY}/one") && (core_name.nil? || grp[:refs].include?(core_name))]
          Store.member!(g.key, "#{KEY}/one", false, nil)
          grp = Store.groups.find { |x| x[:key] == g.key }
          checks << ['member taken out, icon kept', grp && !grp[:refs].include?("#{KEY}/one") && Store.exists?("#{KEY}/one")]
          refused = begin
            Store.update_group!(g.key, nil, chosen: 'disabled', reason: '')
            false
          rescue ArgumentError
            true
          end
          checks << ['group state needs a reason', refused]
          Store.update_group!(g.key, nil, chosen: 'disabled', reason: 'scenario')
          checks << ['group disabled', Store.groups.find { |x| x[:key] == g.key }&.dig(:state) == 'disabled']

          # The Icons tab acts on many at once (one reason; Redmine's own and those already so are left), the Packs tab
          # on a whole pack, and many icons go into a group at once
          refused = begin
            Store.choose_many!(["#{KEY}/one"], 'disabled', '', nil)
            false
          rescue ArgumentError
            true
          end
          checks << ['many without a reason refused', refused]
          changed, skipped = Store.choose_many!(["#{KEY}/one", "#{KEY}/two", core_name].compact, 'disabled', 'scenario', nil)
          checks << ['many disabled at once', changed == 1 && skipped == (core_name ? 2 : 1) && ::GkIconsFile.find_by(pack: KEY, name: 'one')&.state == 'disabled']
          Store.choose_many!(["#{KEY}/one", "#{KEY}/two"], 'active', 'scenario', nil)
          checks << ['many enabled at once', Store.offered?("#{KEY}/one") && Store.offered?("#{KEY}/two")]
          Store.choose!(KEY, 'disabled', 'scenario', nil, whole_pack: true)
          checks << ['a whole pack disabled', Store.index[KEY]&.dig(:state) == 'disabled' && !Store.offered?("#{KEY}/one")]
          Store.choose!(KEY, 'active', 'scenario', nil, whole_pack: true)
          g2 = Store.create_group!('Prov grupp två', nil)
          first = Store.members_many!(g2.key, ["#{KEY}/one", "#{KEY}/two"], true, nil)
          again = Store.members_many!(g2.key, ["#{KEY}/one", "#{KEY}/two"], true, nil)
          checks << ['many into a group, once', first == 2 && again.zero? && Store.groups.find { |x| x[:key] == g2.key }&.dig(:refs)&.size == 2]

          # The history in records, on the pack and the group, with the reason
          if History.on?
            pack_row = ::GkIconsPack.find_by(key: KEY)
            ev = ->(type, id, kind) { ::GkRecordsEvent.where(target_type: type, target_id: id, kind: kind) }
            chosen = ev.call('gk_icons_pack', pack_row.id, 'icons_state_chosen').to_a
            checks << ['history: state chosen with reason', chosen.any? { |x| x.details_hash['icon'] == "#{KEY}/two" && x.reason_text == 'scenario' }]
            checks << ['history: group made', ev.call('gk_icons_group', g.id, 'icons_group_made').exists?]
            checks << ['history: members in and out', ev.call('gk_icons_group', g.id, 'icons_member_added').count == (core_name ? 3 : 2) &&
                                                      ev.call('gk_icons_group', g.id, 'icons_member_removed').count == 1]
            checks << ['history: group state with reason', ev.call('gk_icons_group', g.id, 'icons_group_changed').to_a.any? { |x| x.reason_text == 'scenario' }]
          end
          raise ActiveRecord::Rollback
        end
      end
      failed = checks.reject { |_k, ok| ok }.map(&:first)
      { 'ok' => failed.empty?, 'want' => checks.map(&:first).join(', '), 'got' => failed.empty? ? 'ok' : "not: #{failed.join(', ')}" }
    ensure
      Store.reset!
    end

    # ------------------------------------------------------------------ the step icons
    # icons: in a scenario gives the instance packs, states, groups and settings, as an administrator would:
    #   packs: [folder, ...]         folders under the scenario's packs/, copied into the instance's own pack root
    #                                (<files>/icon_packs, root 2 in packs.rb) and read into the store
    #   missing: [pack/name, ...]    read in once, then its files are taken off the disk: missing, its copy kept
    #   states: [{ ref: pack/name, chosen: active|disabled, reason_key:, by: }]   whole_pack: true for a pack's own state
    #   groups: [{ key:, name_key:, members: [refs], by: }]   chosen: and reason_key: for the group's own state
    #   settings: { disabled_where_used: shown|hidden, missing_where_used: shown|hidden }
    # A reason is the scenario's text icons.reasons.<reason_key>, a group's name icons.groups.<name_key>; by is one of the
    # scenario's people. A reference gk/<name> is Redmine's or the plugin's own icon <name>, as in text.
    # Emptying the instance keeps the icon tables and empties the files folder, so every part looks at what is there and
    # changes only what differs: run again on top of itself, the step changes nothing and writes no event.
    TEXT_STATES = %w[shown hidden].freeze

    def ref_of(ref) = ref.to_s.delete_prefix('gk/')

    def ref_error(kind, key) = ::GkScenarios::Error.new(::I18n.t(:error_gk_scenarios_ref, kind: kind, key: key))

    # The scenario's packs copied into root 2, file by file and only where the copy differs (the time is kept, so the
    # store does not read an unchanged file again). An icon in missing that the store already has is not copied (and taken
    # away if it is there); one the store never read is copied this once, and its copies are returned to be taken away
    # after the reading. Returns [{ key:, copied: }, ...] and the paths to take away.
    def copy_packs(ctx, data)
      root = Packs.instance_root
      missing = Array(data['missing']).map(&:to_s)
      later = []
      packs = Array(data['packs']).map do |folder|
        name = File.basename(folder.to_s)
        src = File.join(ctx.scenario.dir, 'packs', name)
        raise ::GkScenarios::Error, ::I18n.t(:error_gk_scenarios_missing, file: ::GkScenarios.shown_path(src)) unless File.directory?(src)

        pack = Packs.read_pack(src, File.dirname(src)) or raise ref_error('icon pack', folder)
        dest = File.join(root, name)
        # the files of the pack's missing icons, relative to the pack folder: kept off the disk, or copied once (the
        # pack's paths are expanded, so the folder is too before it is cut off)
        base = "#{File.expand_path(src)}/"
        off = {}
        missing.each do |ref|
          key, icon = ref.split('/', 2)
          next unless key == pack.key

          files = pack.icons[icon.to_s.downcase] or raise ref_error('icon', ref)
          read_before = ::GkIconsFile.exists?(pack: pack.key, name: icon.to_s.downcase)
          files.values.flat_map(&:values).each { |p| off[File.expand_path(p).delete_prefix(base)] = read_before }
        end
        copied = 0
        Dir.glob('**/*', base: src).sort.each do |rel|
          from = File.join(src, rel)
          to = File.join(dest, rel)
          next unless File.file?(from)

          if off[rel]
            File.delete(to) if File.exist?(to)
            next
          end
          later << to if off.key?(rel)
          next if File.exist?(to) && FileUtils.compare_file(from, to)

          FileUtils.mkdir_p(File.dirname(to))
          FileUtils.cp(from, to, preserve: true)
          copied += 1
        end
        { key: pack.key, copied: copied }
      end
      [packs, later]
    end

    def run_step(ctx)
      data = ctx.scenario.data['icons'] || {}
      return if data.empty?

      unless Store.table?
        ctx.remark('gk_icons: the tables are missing (migrate)')
        return
      end

      had = ::GkIconsPack.pluck(:key)
      packs, later = copy_packs(ctx, data)
      Store.sync!
      if later.any?
        later.each { |p| File.delete(p) if File.exist?(p) }
        Store.sync!
      end
      Store.reset!
      packs.each { |p| ctx.note(:icons_pack, p[:key], ::GkIconsPack.find_by(key: p[:key]), !had.include?(p[:key]) || p[:copied].positive?) }
      Array(data['missing']).each { |ref| ctx.note(:icons_missing, ref, nil, later.any?) }

      Array(data['states']).each do |s|
        ref = ref_of(s['ref'])
        chosen = s['chosen'].to_s
        raise ref_error('icon state', chosen) unless States::CHOICES.include?(chosen)

        user = s['by'] ? ctx.get(:user, s['by']) : nil
        reason = ctx.scenario.t(:icons, :reasons, s['reason_key'])
        if s['whole_pack']
          row = ::GkIconsPack.find_by(key: ref.split('/').first) or raise ref_error('icon pack', ref)
          changed = row.chosen.to_s != chosen
          Store.choose!(row.key, chosen, reason, user, whole_pack: true) if changed
        else
          pk, name = Store.find(ref)
          raise ref_error('icon', ref) unless pk

          changed = ::GkIconsFile.where(pack: pk[:key], name: name).distinct.pluck(:chosen) != [chosen]
          Store.choose!(ref, chosen, reason, user) if changed
        end
        ctx.note(:icons_state, ref, nil, changed)
      end

      Array(data['groups']).each do |g|
        user = g['by'] ? ctx.get(:user, g['by']) : nil
        row = ::GkIconsGroup.find_by(key: g['key'].to_s)
        created = row.nil?
        # a group that is there keeps the name it has (a person may have renamed it while trying)
        row ||= Store.create_group!(ctx.scenario.t(:icons, :groups, g['name_key']), user, key: g['key'].to_s)
        refs = Array(g['members']).map { |r| ref_of(r) }
        unknown = refs.reject { |r| Store.known_ref?(r) }
        raise ref_error('icon', unknown.join(', ')) if unknown.any?

        changed = Store.members_many!(row.key, refs, true, user).positive?
        if g['chosen'] && row.reload.chosen.to_s != g['chosen'].to_s
          Store.update_group!(row.key, user, chosen: g['chosen'].to_s, reason: ctx.scenario.t(:icons, :reasons, g['reason_key']))
          changed = true
        end
        ctx.note(:icons_group, g['key'], row, created || changed)
      end

      want = (data['settings'] || {}).to_h { |k, v| [k.to_s, v.to_s] }
      return if want.empty?

      bad = want.reject { |k, v| Store::WHERE_USED.value?(k) && TEXT_STATES.include?(v) }
      raise ref_error('icons setting', bad.map { |k, v| "#{k}: #{v}" }.join(', ')) if bad.any?

      s = (::Setting.plugin_gk_icons || {}).to_h.transform_keys(&:to_s)
      changed = want.reject { |k, v| s[k].to_s == v }
      ::Setting.plugin_gk_icons = s.merge(changed) if changed.any?
      ctx.note(:icons_settings, 'settings', nil, changed.any?)
    end

    # ------------------------------------------------------------------ icons in a text
    # What Text.apply draws, counted: a view that answers gk_icon with nothing, so the count does not hang on sprites or a
    # request. Which codes are drawn is Text's and GkIcons.exists?'s alone (the settings for disabled and missing
    # icons count, the function icons.in_text does not).
    class CountView
      include ActionView::Helpers::TagHelper

      def gk_icon(_name, _label = nil, **) = ''.html_safe

      # the span Text.apply counts, without the icon and without measuring it
      def gk_icon_in_text(_ref, title) = content_tag('span', '', class: 'gk-icon-in-text', title: title)
    end

    def icons_in(text)
      return 0 if text.to_s.strip.empty?

      html = ::Redmine::WikiFormatting.to_html(::Setting.text_formatting, text.to_s)
      Text.apply(html, CountView.new).to_s.scan('class="gk-icon-in-text"').size
    end

    def table_missing = { 'ok' => false, 'want' => 'the tables (migrate)', 'got' => '-' }

    def register!
      return unless defined?(::GkScenarios::Expect)

      # The icons are the instance's own settings, not a scenario's data, so emptying the instance leaves them (the
      # administrator's states and groups stay)
      if defined?(::GkScenarios::Wipe)
        ::GkScenarios::Wipe.keep('gk_icons_packs', 'gk_icons_files', 'gk_icons_groups', 'gk_icons_group_members')
      end

      # After the people (by:) and before the issues, so that an issue's text finds its icons from the start
      if defined?(::GkScenarios::Steps)
        ::GkScenarios::Steps.register('icons', plugin: :gk_icons, order: 30) { |ctx| run_step(ctx) }
      end

      ::GkScenarios::Expect.register('icons_store') do |_ctx, e|
        next table_missing unless Store.table?
        next({ 'ok' => false, 'want' => 'icons_store: cycle', 'got' => e['icons_store'].to_s }) unless e['icons_store'].to_s == 'cycle'

        cycle
      end

      # icons_pack: <key>, icons: N (state: active|disabled|missing): the pack is in the store with N icons, missing ones
      # counted (their copies are kept)
      ::GkScenarios::Expect.register('icons_pack') do |_ctx, e|
        next table_missing unless Store.table?

        Store.reset!
        pk = Store.index[e['icons_pack'].to_s]
        want = ["#{e['icons']} icons", e['state']].compact.join(', ')
        got = pk ? "#{pk[:icons].size} icons, #{pk[:state]}" : 'no such pack'
        ok = !pk.nil? && e.key?('icons') && pk[:icons].size == e['icons'].to_i && (e['state'].nil? || pk[:state] == e['state'].to_s)
        { 'ok' => ok, 'want' => want, 'got' => got }
      end

      # icons_state: <pack/name>, equals: active|disabled|missing: the icon's own state (its pack's beside it)
      ::GkScenarios::Expect.register('icons_state') do |_ctx, e|
        next table_missing unless Store.table?

        Store.reset!
        pk, name = Store.find(ref_of(e['icons_state']))
        got = pk ? pk[:icons][name][:state] : nil
        { 'ok' => !got.nil? && got == e['equals'].to_s, 'want' => e['equals'].to_s, 'got' => pk ? "#{got} (pack #{pk[:state]})" : 'no such icon' }
      end

      # icons_group: <key>, members: N (state: active|disabled): the group is there with N members
      ::GkScenarios::Expect.register('icons_group') do |_ctx, e|
        next table_missing unless Store.table? && Store.groups_table?

        Store.reset!
        g = Store.groups.find { |x| x[:key] == e['icons_group'].to_s }
        want = ["#{e['members']} members", e['state']].compact.join(', ')
        got = g ? "#{g[:refs].size} members, #{g[:state]} (#{g[:refs].join(' ')})" : 'no such group'
        ok = !g.nil? && e.key?('members') && g[:refs].size == e['members'].to_i && (e['state'].nil? || g[:state] == e['state'].to_s)
        { 'ok' => ok, 'want' => want, 'got' => got }
      end

      # icons_in_text: <issue key>, equals: N: the icons drawn in the issue's description and notes, whether the function
      # icons.in_text is on or not
      ::GkScenarios::Expect.register('icons_in_text') do |ctx, e|
        issue = ::GkScenarios::Expect.issue_for(ctx, e['icons_in_text'].to_s)
        next({ 'ok' => false, 'want' => e['equals'].to_s, 'got' => 'no issue' }) unless issue

        Store.reset!
        notes = issue.journals.where.not(notes: [nil, '']).order(:id).pluck(:notes)
        counts = [icons_in(issue.description)] + notes.map { |n| icons_in(n) }
        got = counts.sum
        { 'ok' => e.key?('equals') && got == e['equals'].to_i, 'want' => e['equals'].to_s,
          'got' => "#{got} (description #{counts.first}, notes #{counts.drop(1).join(' ')})" }
      end
    end
  end

  def self.register_scenarios! = Scenarios.register!
end
