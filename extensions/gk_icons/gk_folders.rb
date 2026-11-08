# frozen_string_literal: true

# Where a GK plugin keeps a folder of its own in Redmine's attachments folder: <attachments>/gk/<plugin>/<folder>, the
# plugin named without gk_, so that the attachments folder holds one folder of GK's and no plugin writes the path
# itself. None of the plugins that keep such a folder requires another, so each carries this same file; whichever
# loads, the answer is the same. A folder an administrator has set in a setting is that setting's own.
module GkFolders
  module_function

  # attachments: the folder to start from, Redmine's own unless given
  def root(attachments: ::Attachment.storage_path) = File.join(attachments.to_s, 'gk')

  def path(*parts, attachments: ::Attachment.storage_path)
    File.join(root(attachments: attachments), *parts.map(&:to_s))
  end
end
