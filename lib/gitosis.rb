require 'lockfile'
require 'inifile'

module Gitosis

  def self.repository_name(project)
    parent_name = project.parent ? repository_name(project.parent) + "/" : ""
    name = project.identifier
    custom_field = Setting.plugin_redmine_gitosis['repoNameCustomField']
    if custom_field
      custom_name = project.custom_values.detect {|c| c.custom_field_id == custom_field}
      name = custom_name.value unless custom_name.nil?
    end
    "#{parent_name}#{name}"
  end

  def self.get_urls(project)
    urls = {:read_only => [], :developer => []}
    read_only_baseurls = Setting.plugin_redmine_gitosis['readOnlyBaseUrls'].split(/[\r\n\t ,;]+/)
    developer_baseurls = Setting.plugin_redmine_gitosis['developerBaseUrls'].split(/[\r\n\t ,;]+/)
    project_path = repository_name(project) + ".git"
    read_only_baseurls.each {|baseurl| urls[:read_only] << baseurl + project_path}
    developer_baseurls.each {|baseurl| urls[:developer] << baseurl + project_path}
    urls
  end

  def self.update_repositories(projects)
    projects = (projects.is_a?(Array) ? projects : [projects])
  
    if(defined?(@recursionCheck))
      if(@recursionCheck)
        return
      end
    end
    @recursionCheck = true

    # Don't bother doing anything if none of the projects we've been handed have a Git repository
    unless projects.detect{|p|  p.repository.is_a?(Repository::Git) }.nil?

      lockfile=File.new(File.join("/tmp",'redmine_gitosis_lock'),File::CREAT|File::RDONLY)
      retries=5
      loop do
        break if lockfile.flock(File::LOCK_EX|File::LOCK_NB)
        retries-=1
        sleep 2
        raise Lockfile::MaxTriesLockError if retries<=0
      end

      # HANDLE GIT

      # create tmp dir
      local_dir = File.join("/tmp","redmine_gitosis_#{Time.now.to_i}")

      Dir.mkdir local_dir

      # Create GIT_SSH script
      ssh_with_identity_file = File.join(local_dir, 'ssh_with_identity_file.sh')
      File.open(ssh_with_identity_file, "w") do |f|
          f.puts "#!/bin/bash"
          f.puts "exec ssh -o stricthostkeychecking=no -i #{Setting.plugin_redmine_gitosis['gitosisIdentityFile']} \"$@\""
      end
      File.chmod(0755, ssh_with_identity_file)
      
      # clone repo
      `env GIT_SSH=#{ssh_with_identity_file} git clone #{Setting.plugin_redmine_gitosis['gitosisUrl']} #{local_dir}/gitosis`
      
      changed = false
      projects.select{|p| p.repository.is_a?(Repository::Git)}.each do |project|
        # fetch users
        users = project.member_principals.map(&:user).compact.uniq
        write_users = users.select{ |user| user.allowed_to?(:commit_access, project) }
        read_users = users.select{ |user| user.allowed_to?(:view_changesets, project) && !user.allowed_to?(:commit_access, project) }
        # write key files
        users.map{|u| u.gitosis_public_keys.active}.flatten.compact.uniq.each do |key|
          File.open(File.join(local_dir, 'gitosis/keydir',"#{key.identifier}.pub"), 'w') {|f| f.write(key.key.gsub(/\n/,'')) }
        end
        
        # delete inactives
        users.map{|u| u.gitosis_public_keys.inactive}.flatten.compact.uniq.each do |key|
          File.unlink(File.join(local_dir, 'gitosis/keydir',"#{key.identifier}.pub")) rescue nil
        end
        
        # write config file
        conf = IniFile.new(File.join(local_dir,'gitosis','gitosis.conf'))
        original = conf.clone
        name = repository_name(project)
        
        conf["group #{name}_readonly"]['readonly'] = name
        conf["group #{name}_readonly"]['members'] = read_users.map{|u| u.gitosis_public_keys.active}.flatten.map{ |key| "#{key.identifier}" }.join(' ')
        
        conf["group #{name}"]['writable'] = name
        conf["group #{name}"]['members'] = write_users.map{|u| u.gitosis_public_keys.active}.flatten.map{ |key| "#{key.identifier}" }.join(' ')
        
        # git-daemon support for read-only anonymous access
        if User.anonymous.allowed_to?( :view_changesets, project )
          conf["repo #{name}"]['daemon'] = 'yes'
        else
          conf["repo #{name}"]['daemon'] = 'no'
        end
        
        unless conf.eql?(original)
          conf.write 
          changed = true
        end
        
      end
      if changed
        git_push_file = File.join(local_dir, 'git_push.sh')  
        new_dir= File.join(local_dir,'gitosis')
        File.open(git_push_file, "w") do |f|
          f.puts "#!/bin/sh"
          f.puts "cd #{new_dir}"
          f.puts "git add keydir/* gitosis.conf"
          f.puts "git config user.email '#{Setting.mail_from}'"
          f.puts "git config user.name 'Redmine'"
          f.puts "git commit -a -m 'updated by Redmine Gitosis'"
          f.puts "GIT_SSH=#{ssh_with_identity_file} git push"
        end
        File.chmod(0755, git_push_file)
      
        # add, commit, push, and remove local tmp dir
        `#{git_push_file}`
      end
      # remove local copy
      `rm -Rf #{local_dir}`
      
      lockfile.flock(File::LOCK_UN)
    end
    @recursionCheck = false
  end
end