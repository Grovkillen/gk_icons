# frozen_string_literal: true

get 'gk_icons/i/:name.svg', to: 'gk_icons#show', as: 'gk_icons_file', constraints: { name: /[a-z0-9-]+/ }, format: false
get 'gk_icons', to: 'gk_icons#index', as: 'gk_icons', defaults: { format: 'json' }
get 'gk_icons/p/:pack/:name.:ext', to: 'gk_icons#pack', as: 'gk_icons_pack_file', constraints: { pack: /[a-z0-9_-]+/, name: /[^\/]+?/, ext: /svg|png/ }, format: false
get 'gk_icons/s/:pack/:chunk.svg', to: 'gk_icons#sprite', as: 'gk_icons_sprite', constraints: { pack: /[a-z0-9_-]+/, chunk: /\d+/ }, format: false
get 'gk_icons/packs', to: 'gk_icons#packs', as: 'gk_icons_packs', defaults: { format: 'json' }
get 'gk_icons/names', to: 'gk_icons#names', as: 'gk_icons_names'   # With the session (all=1 for an administrator)
get 'gk_icons/library', to: 'gk_icons#library', as: 'gk_icons_library'
# a page's own request with the session (not format json: Redmine reads json as the API, without the session)
post 'gk_icons/refresh', to: 'gk_icons#refresh', as: 'gk_icons_refresh'
post 'gk_icons/choose', to: 'gk_icons#choose', as: 'gk_icons_choose'
# Many icons at once, a whole pack's state from the Packs tab, many icons into a group or out of it
post 'gk_icons/choose_many', to: 'gk_icons#choose_many', as: 'gk_icons_choose_many'
post 'gk_icons/packs/:key/state', to: 'gk_icons#pack_state', as: 'gk_icons_pack_state', constraints: { key: /[a-z0-9_-]+/ }
post 'gk_icons/packs/:key/text', to: 'gk_icons#pack_text', as: 'gk_icons_pack_text', constraints: { key: /[a-z0-9_-]+/ }
# Groups across the packs
post 'gk_icons/groups', to: 'gk_icons#group_create', as: 'gk_icons_groups'
post 'gk_icons/groups/:key', to: 'gk_icons#group_update', as: 'gk_icons_group', constraints: { key: /[a-z0-9][a-z0-9_-]*/ }
post 'gk_icons/groups/:key/members', to: 'gk_icons#group_member', as: 'gk_icons_group_members', constraints: { key: /[a-z0-9][a-z0-9_-]*/ }
post 'gk_icons/groups/:key/members_many', to: 'gk_icons#group_members_many', as: 'gk_icons_group_members_many', constraints: { key: /[a-z0-9][a-z0-9_-]*/ }
