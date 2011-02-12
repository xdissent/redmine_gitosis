require 'redmine'
require_dependency 'principal'
require_dependency 'user'

require_dependency 'gitosis'
require_dependency 'gitosis/patches/application_controller_patch'
require_dependency 'gitosis/patches/repositories_controller_patch'
require_dependency 'gitosis/patches/repositories_helper_patch'
require_dependency 'gitosis/patches/git_adapter_patch'

Redmine::Plugin.register :redmine_gitosis do
  name 'Redmine Gitosis plugin'
  author 'Jan Schulz-Hofen'
  description 'Enables Redmine to update a gitosis server.'
  version '0.0.5alpha'
  settings :default => {
    'gitosisUrl' => 'gitosis@localhost:gitosis-admin.git',
    'gitosisIdentityFile' => '/srv/gitosis/.ssh/id_dsa',
    'developerBaseUrls' => 'gitosis@localhost:',
    'readOnlyBaseUrls' => 'http://xdissent.com/git/',
    'basePath' => '/srv/gitosis/repositories/',
    'repoNameCustomField' => 0
    }, 
    :partial => 'redmine_gitosis'
end

# initialize hook
class GitosisPublicKeyHook < Redmine::Hook::ViewListener
  render_on :view_my_account_contextual, :inline => "| <%= link_to(l(:label_public_keys), public_keys_path) %>" 
end

class GitosisProjectShowHook < Redmine::Hook::ViewListener
  render_on :view_projects_show_left, :partial => 'redmine_gitosis'
end

# initialize association from user -> public keys
User.send(:has_many, :gitosis_public_keys, :dependent => :destroy)

# initialize observer
ActiveRecord::Base.observers = ActiveRecord::Base.observers << GitosisObserver
