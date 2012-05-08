default_run_options[:pty] = true  # Must be set for the password prompt from git to work
$:.unshift(File.expand_path('./lib', ENV['rvm_path']))
# 
# # Load RVM's capistrano plugin.    
require "rvm/capistrano"
set :rvm_ruby_string, 'ree'

set :repository, "git@github.com:jwigal/emcommeast-store.git"  # Your clone URL
set :scm, "git"
set :user, "deploy"  # The server's user for deploys
#set :scm_passphrase, "p@ssw0rd"  # The deploy user's password
set :branch, "master"
set :deploy_via, :remote_cache

set :application, "emcommeast-store"
set :keep_releases, 4 
set :deploy_to, "/home/deploy/store.emcommeast.org/"
# app servers
server "50.17.220.217", :app, :web, :db, :primary => true

# If you aren't using Subversion to manage your source code, specify
# your SCM below:
# set :scm, :subversion
set :scm_user, "jeff@wigaldesign.com"
set :use_sudo, false
set :rails_env, "production"
set :bundle_without, [:development]



#capistrano multi-stage
#http://weblog.jamisbuck.org/2007/7/23/capistrano-multistage
# set :stages, %w(staging production)
# set :default_stage, "staging"
# require 'capistrano/ext/multistage'
require 'bundler/capistrano'
# require 'airbrake/capistrano'

#http://www.zorched.net/2008/06/17/capistrano-deploy-with-git-and-passenger/
namespace :deploy do
  namespace :git do
    desc "Tag the release with the current day/time"
    task :tag_release  do
      version = capture("cat #{current_path}/REVISION").strip
      `git tag release-#{Time.now.strftime("%Y%m%d-%H%M")} #{version} && git push --tags` if version
    end
  end
  
  desc "deploy the precompiled assets"
  task :deploy_assets, :except => { :no_release => true } do
     run_locally("rake assets:clean && rake precompile")
     upload("public/assets", "#{release_path}/public/assets", :via =>
:scp, :recursive => true)
     run_locally("rake assets:clean")
  end
  
  desc "Restarting passenger with restart.txt"
  task :restart, :roles => :app, :except => { :no_release => true } do
    run "touch #{current_path}/tmp/restart.txt"
  #  run "wget --spider --background --no-check-certificate --quiet --header=\"Host: assignr.com\" https://localhost/login > /dev/null 2>&1 "
  end
  [:start, :stop].each do |t|
    desc "#{t} task is a no-op with mod_rails"
    task t, :roles => :app do ; end
  end

  # advanced rails recipes #74

  desc "Copy .yml configuration files to correct location"
  task :copy_configuration_ymls, :roles => [:db, :app] do
    run "cp #{shared_path}/database.yml #{release_path}/config/database.yml"
  end
  
    
  task :chmod_script_files_in_application, :roles => [:app, :db] do
    %w(about console dbconsole destroy generate plugin runner 
             server delayed_job).each do |dir|
      run "chmod 755 #{release_path}/script/#{dir}"
    end
  end

  # http://almosteffortless.com/2007/03/25/working-with-attachment_fu/
  # symlink the shared/system/attachments folder as the RAILS_ROOT/attachments folder
  # desc "symlink the shared/system/attachments folder as the RAILS_ROOT/attachments folder"
  # task :link_attachments_folder, :roles =>  [:app, :db] do 
  #   run "rm -rf #{release_path}/attachments"
  #   run "mkdir -p #{shared_path}/system/attachments"
  #   run "ln -nfs #{shared_path}/system/attachments #{release_path}/attachments"
  # end
  # 
  # desc "run migrations in all environments"
  # task :migrate_all, :roles => :app do 
  #   run "cd #{release_path} ; rake db:migrate:all"
  # end
  
  #http://clarkware.com/cgi/blosxom/2007/01/05
  namespace :web do
    desc "Serve up a custom maintenance page."
    task :disable_web, :roles => :web do
      require 'erb'
      on_rollback { run "rm #{shared_path}/system/maintenance.html" }
    
      reason      = ENV['REASON']
      deadline    = ENV['UNTIL']
    
      template = File.read("app/views/admin/maintenance.html.erb")
      page = ERB.new(template).result(binding)
    
      put page, "#{shared_path}/system/maintenance.html", 
                :mode => 0644
    end
    
    after "deploy:update_code", "deploy:copy_configuration_ymls"
    after "deploy:update", "deploy:cleanup" 
  end
end

namespace :assets do
	desc "create symlinks from shared resources to the release path"
	task :symlink_spree, :roles => :app do
		release_image_dir = "#{release_path}/public/spree/"
		shared_image_dir = "#{shared_path}/uploaded-files/spree/"
		run "mkdir -p #{release_image_dir}"
		run "mkdir -p #{shared_image_dir}"
		run "ln -nfs #{shared_image_dir} #{release_image_dir}"
	end
  desc "deploy the precompiled assets"
  task :precompile, :except => { :no_release => true } do
    run "echo this is my code running instead"
    run "cd #{release_path} ; RAILS_ENV=#{rails_env} bundle exec rake assets:precompile:primary"
    run "cd #{release_path} ; RAILS_ENV=#{rails_env} bundle exec rake assets:precompile:nondigest"
  end
end

set :asset_env, "RAILS_GROUPS=assets"
set :assets_prefix, "assets"
set :assets_role, [:web]

namespace :assets do
  task :symlink_compile_spree, :roles => [:web], :except => { :no_release => true } do
    run "mkdir -p #{latest_release}/public"
    run "mkdir -p #{shared_path}/assets"
    run "ln -s #{shared_path}/assets #{release_path}/public/assets"
		shared_image_dir = "#{shared_path}/uploaded-files/spree"
    run "mkdir -p #{shared_image_dir}"
    run "rm -rf #{release_path}/public/spree"
    run "ln -s #{shared_image_dir} #{release_path}/public/spree"
    run "cd #{release_path} ; RAILS_ENV=#{rails_env} bundle exec rake assets:precompile:primary"
    run "cd #{release_path} ; RAILS_ENV=#{rails_env} bundle exec rake assets:precompile:nondigest"
  end
end

after 'deploy:update_code', 'assets:symlink_compile_spree'


=begin
namespace :deploy do
  namespace :assets do
    desc <<-DESC
      [internal] This task will set up a symlink to the shared directory \
      for the assets directory. Assets are shared across deploys to avoid \
      mid-deploy mismatches between old application html asking for assets \
      and getting a 404 file not found error. The assets cache is shared \
      for efficiency. If you cutomize the assets path prefix, override the \
      :assets_prefix variable to match.
    DESC
    task :symlink, :roles => assets_role, :except => { :no_release => true } do
      run <<-CMD
        rm -rf #{latest_release}/public/#{assets_prefix} &&
        mkdir -p #{latest_release}/public &&
        mkdir -p #{shared_path}/assets &&
        ln -s #{shared_path}/assets #{latest_release}/public/#{assets_prefix}
      CMD
    end

    desc <<-DESC
      Run the asset precompilation rake task. You can specify the full path \
      to the rake executable by setting the rake variable. You can also \
      specify additional environment variables to pass to rake via the \
      asset_env variable. The defaults are:

        set :rake,      "rake"
        set :rails_env, "production"
        set :asset_env, "RAILS_GROUPS=assets"
    DESC
    task :precompile_quick, :roles => assets_role, :except => { :no_release => true } do
      run "cd #{release_path} ; RAILS_ENV=#{rails_env} bundle exec rake assets:precompile:primary"
      run "cd #{release_path} ; RAILS_ENV=#{rails_env} bundle exec rake assets:precompile:nondigest"
    end

    desc <<-DESC
      Run the asset clean rake task. Use with caution, this will delete \
      all of your compiled assets. You can specify the full path \
      to the rake executable by setting the rake variable. You can also \
      specify additional environment variables to pass to rake via the \
      asset_env variable. The defaults are:

        set :rake,      "rake"
        set :rails_env, "production"
        set :asset_env, "RAILS_GROUPS=assets"
    DESC
    task :clean, :roles => assets_role, :except => { :no_release => true } do
      run "cd #{latest_release} && #{rake} RAILS_ENV=#{rails_env} #{asset_env} assets:clean"
    end
  end
end
=end
