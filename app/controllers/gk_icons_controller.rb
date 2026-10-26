# frozen_string_literal: true

# gk_icons: one icon as a file of its own (for stylesheets: mask-image cannot point into a sprite), and the
# list of all icons as JSON. Icons are not secrets: no login, long caching (the address carries a stamp that
# changes when the sprites change). Only names from the two sprites are answered; nothing is read by path.
class GkIconsController < ApplicationController
  # The library's three tabs for an administrator, Icons, Packs and Groups; everyone else sees the library only
  TABS = %w[icons packs groups].freeze
  # A page of its own, as My account and Administration: no project's main menu
  self.main_menu = false

  # Only these actions are open, so an action added later is not public by mistake
  skip_before_action :check_if_login_required, only: %i[show pack sprite packs names index], raise: false # rest-ok: icons are not secrets
  accept_api_auth :index
  before_action :require_login, only: [:library]
  before_action :require_admin, only: %i[refresh choose choose_many pack_state pack_text group_create group_update group_member group_members_many]
  # The library is for administrators unless the function icons.library_for_users is on
  before_action :library_for_users, only: [:library]

  def show
    svg = GkIcons.document(params[:name].to_s)
    return head(:not_found) unless svg

    expires_in 1.year, public: true
    harmless
    send_data svg, type: 'image/svg+xml', disposition: 'inline'
  end

  # A pack's icon: the file the index knows for that pack and name, never a path from the address. The address's
  # ending is a wish: a pack with both svg and png files (the page guesses the ending per pack) gets the file the
  # icon has, with that file's own type
  def pack
    ref = "#{params[:pack]}/#{params[:name]}"
    if GkIcons::Store.ready?
      id, ext = GkIcons::Store.file_id(ref, variant: params[:variant], ext: params[:ext])
      return head(:not_found) unless id

      file = GkIconsFile.find_by(id: id) or return head(:not_found)
      expires_in 1.year, public: true
      harmless
      return send_data(file.content, type: (ext == 'svg' ? 'image/svg+xml' : 'image/png'), disposition: 'inline')
    end
    path, ext = GkIcons::Packs.file(ref, variant: params[:variant], ext: params[:ext])
    return head(:not_found) unless path && File.file?(path)

    expires_in 1.year, public: true
    harmless
    send_file path, type: (ext == 'svg' ? 'image/svg+xml' : 'image/png'), disposition: 'inline'
  end

  # A chunk of a pack's sprite: Store::CHUNK icons as symbols, built from the store and kept as a file
  def sprite
    return head(:not_found) unless GkIcons::Store.ready?

    path = GkIcons::Store.sprite_file(params[:pack].to_s, params[:chunk].to_i)
    return head(:not_found) unless path

    # The file is built with the store's stamp now; an address with another stamp is not cached long, so an old
    # address never keeps another content for a year
    if params[:v].to_s == GkIcons::Store.stamp
      expires_in 1.year, public: true
    else
      expires_now
    end
    harmless
    send_file path, type: 'image/svg+xml', disposition: 'inline'
  end

  # The packs are for everyone; where they lie on the server (the roots, absolute paths) is for an administrator
  def packs
    out = { api_version: 1 }
    out[:roots] = GkIcons::Packs.roots.map { |r| { path: r, found: File.directory?(r) } } if User.current.admin?
    out[:packs] = GkIcons::Packs.all.values.map do |p|
      { key: p.key, name: p.name, icons: p.icons.size, variants: p.variants, mono: p.mono, license: p.meta['license'], version: p.meta['version'] }
    end
    render json: out
  end

  # The library: every icon there is, to look through and search; a click copies how the icon is written
  def library
    @tab = User.current.admin? && TABS.include?(params[:tab].to_s) ? params[:tab].to_s : 'icons'
    ready = GkIcons::Store.ready?
    @packs = ready ? GkIconsPack.order(:key).to_a : []
    @counts = ready ? GkIcons::Store.index.transform_values { |p| p[:icons].size } : {}
    @groups = GkIcons::Store.groups
  end

  # A whole pack's state, only from the Packs tab: chosen, reason
  def pack_state
    # Save with the state the pack already has changes nothing and writes no history
    row = GkIconsPack.find_by(key: params[:key].to_s)
    was = row && (row.chosen.to_s == 'disabled' ? 'disabled' : 'active')
    return back(:packs, l(:text_gk_icons_js_unchanged)) if was && was == params[:chosen].to_s

    GkIcons::Store.choose!(params[:key].to_s, params[:chosen].to_s, params[:reason].to_s, User.current, whole_pack: true, place: 'icons.choose')
    back(:packs, l(:notice_successful_update))
  rescue GkIcons::Store::ReasonError => e
    back(:packs, nil, e.message)
  rescue ArgumentError => e
    back(:packs, nil, l(:"error_gk_icons_#{e.message}"))
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # A pack's height, place and side space in text from the Packs tab: scale, shift, gap (blank or the pack's own: the pack's pack.yml), reason
  def pack_text
    changed = GkIcons::Store.fit!(params[:key].to_s, params[:scale], params[:shift], params[:gap], params[:reason].to_s, User.current)
    back(:packs, l(changed ? :notice_successful_update : :text_gk_icons_js_unchanged))
  rescue GkIcons::Store::ReasonError => e
    back(:packs, nil, e.message)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Many icons at once from the Icons tab: refs[], chosen, reason
  def choose_many
    changed, skipped = GkIcons::Store.choose_many!(Array(params[:refs]), params[:chosen].to_s, params[:reason].to_s, User.current, place: 'icons.choose')
    render json: { ok: true, changed: changed, skipped: skipped }
  rescue GkIcons::Store::ReasonError => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  rescue ArgumentError => e
    render json: { ok: false, error: l(:"error_gk_icons_#{e.message}") }, status: :unprocessable_entity
  end

  # Many icons into a group or out of it: refs[], member (1 or 0)
  def group_members_many
    changed = GkIcons::Store.members_many!(params[:key], Array(params[:refs]), params[:member].to_s == '1', User.current)
    render json: { ok: true, changed: changed }
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # The names in groups, short: the client builds the addresses itself (one list for the library and the picker).
  # From the store, only what is offered (the icon and its pack active), with each icon's sprite chunk; all=1 for
  # an administrator gives every icon with its state, and each pack's state
  def names
    groups = [{ key: 'core', label: l(:label_gk_icons_group_core), prefix: '', names: GkIcons.core.keys.sort },
              { key: 'own', label: l(:label_gk_icons_group_own), prefix: '', names: (GkIcons.own.keys - GkIcons.core.keys).sort }]
    all = params[:all].to_s == '1' && User.current.admin?
    if GkIcons::Store.ready?
      GkIcons::Store.index.values.sort_by { |p| p[:key] }.each do |p|
        next unless all || p[:state] == 'active'

        names = p[:order].select { |n| all || p[:icons][n][:state] == 'active' }
        g = { key: p[:key], label: p[:name], prefix: "#{p[:key]}/", names: names, chunks: names.map { |n| p[:chunk][n] } }
        g.merge!(states: names.map { |n| p[:icons][n][:state] }, state: p[:state]) if all
        groups << g
      end
    else
      GkIcons::Packs.all.values.sort_by(&:key).each do |p|
        groups << { key: p.key, label: p.name, prefix: "#{p.key}/", names: p.icons.keys.sort }
      end
    end
    # The instance's own groups across the packs (sets): only active groups and offered icons, all=1 every group
    # with its state and every member
    offered = ->(r) { r.include?('/') ? GkIcons::Store.offered?(r) : GkIcons.exists?(r) }
    sets = GkIcons::Store.groups.filter_map do |g|
      next unless all || g[:state] == 'active'

      s = { key: g[:key], label: g[:name], refs: all ? g[:refs] : g[:refs].select(&offered) }
      s.merge!(state: g[:state], reason: g[:reason], description: g[:description]) if all
      s
    end
    GkIcons::Store.warm_sprites_later if GkIcons::Store.ready?
    if all
      expires_now
    else
      expires_in 5.minutes
    end
    render json: { api_version: 1, store: GkIcons::Store.ready?, groups: groups, sets: sets }
  end

  # Groups, an administrator's: create one, change its name or state (a reason for a state), put an icon in or take it
  # out
  def group_create
    g = GkIcons::Store.create_group!(params[:name], User.current)
    return back(:groups, l(:notice_successful_create)) if form?

    render json: { ok: true, key: g.key }
  rescue ArgumentError => e
    return back(:groups, nil, l(:"error_gk_icons_#{e.message}")) if form?

    render json: { ok: false, error: l(:"error_gk_icons_#{e.message}") }, status: :unprocessable_entity
  end

  def group_update
    g = GkIcons::Store.update_group!(params[:key], User.current, name: params[:name], chosen: params[:chosen].presence,
                                                                   reason: params[:reason], description: params[:description],
                                                                   place: 'icons.group_state')
    return back(:groups, l(:notice_successful_update)) if form?

    render json: { ok: true, key: g.key, state: g.state }
  rescue GkIcons::Store::ReasonError => e # The place's mode refused it, records' message
    return back(:groups, nil, e.message) if form?

    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  rescue ArgumentError => e
    return back(:groups, nil, l(:"error_gk_icons_#{e.message}")) if form?

    render json: { ok: false, error: l(:"error_gk_icons_#{e.message}") }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def group_member
    GkIcons::Store.member!(params[:key], params[:ref].to_s, params[:member].to_s == '1', User.current)
    return back(:groups, l(:notice_successful_update)) if form?

    render json: { ok: true }
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Read the pack folders again now: the counts as JSON
  def refresh
    counts = GkIcons::Store.sync!(user: User.current)
    render json: { ok: true, counts: counts }
  rescue StandardError => e
    render json: { ok: false, error: l(:error_gk_icons_refresh, detail: GkIcons::Text.display_path(e.message)) }, status: :unprocessable_entity
  end

  # An icon's or a pack's state: chosen active or disabled, with a reason
  def choose
    state = GkIcons::Store.choose!(params[:ref].to_s, params[:chosen].to_s, params[:reason].to_s, User.current,
                                    whole_pack: params[:whole_pack].to_s == '1', place: 'icons.choose')
    render json: { ok: true, chosen: state }
  rescue GkIcons::Store::ReasonError => e # The place's mode refused it, records' message
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  rescue ArgumentError => e
    render json: { ok: false, error: l(:"error_gk_icons_#{e.message}") }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def index
    render json: { api_version: 1, tabler_release: tabler_release,
                   icons: (params[:packs].to_s == '1' ? GkIcons.all_names : GkIcons.names).map { |n| { name: n, source: GkIcons.source(n), url: GkIcons.url(n) } } }
  end

  private

  # A plain form on a tab (not the script, which asks for JSON)
  def form? = !request.format.json? && !request.xhr? && params[:form].to_s == '1'

  def back(tab, notice, error = nil)
    flash[:notice] = notice if notice
    flash[:error] = error if error
    redirect_to gk_icons_library_path(tab: tab)
  end

  # The Tabler Icons release the plugin's own sprite is built from, as config/icon_source.yml says
  def tabler_release
    file = GkIcons::Text.join_path(Redmine::Plugin.find(:gk_icons).directory, 'config', 'icon_source.yml')
    (YAML.safe_load(File.read(file, encoding: 'UTF-8')) || {})['tabler_release'].to_s
  rescue StandardError
    ''
  end

  def library_for_users
    require_admin unless User.current.admin? || GkIcons.feature?('icons.library_for_users')
  end

  # An icon is a picture: opened by itself in the browser it may run nothing and fetch nothing (a pack is files
  # somebody put on the server, and an svg can carry script). A sprite's png icons are data: images.
  def harmless
    response.headers['Content-Security-Policy'] = "sandbox; default-src 'none'; style-src 'unsafe-inline'; img-src data:"
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end
end
