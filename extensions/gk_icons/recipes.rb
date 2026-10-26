# frozen_string_literal: true

module GkIcons
  # Recipes for common icon packs (config/icon_pack_recipes/<key>.yml): text only, read for the help on the Packs tab
  # and in the README. A recipe says where a package is downloaded, which folder in it has the icons and the pack.yml
  # to put beside them, one pack per style. Nothing is downloaded or copied by the plugin.
  module Recipes
    DIR = File.expand_path('../../config/icon_pack_recipes', __dir__)

    module_function

    # The recipes in name order: { 'key' => recipe hash }. A file that cannot be read is left out and logged.
    def all
      Dir.glob(File.join(DIR, '*.yml')).sort.each_with_object({}) do |path, h|
        r = YAML.safe_load(File.read(path, encoding: 'bom|utf-8'))
        h[File.basename(path, '.yml')] = r if r.is_a?(Hash) && r['packs'].is_a?(Array)
      rescue StandardError => e
        Rails.logger.warn("[gk_icons] icon pack recipe #{File.basename(path)} not read: #{e.class} #{e.message}")
      end.sort_by { |_, r| r['name'].to_s.downcase }.to_h
    end

    # A pack's pack.yml as the recipe gives it, with the version the recipe was tried with
    def pack_yml(recipe, pack)
      pack['pack'].to_h.merge('version' => recipe['verified'].to_s).to_yaml.sub(/\A---\n/, '')
    end
  end
end
