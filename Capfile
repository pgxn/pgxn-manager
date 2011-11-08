# Steps to doing an initial deployment:
#
# Create system user "pgxn"
# Create ~/.pgpass for user "postgres" (if necessary)
# cap deploy:setup
# Copy prod.json to /etc/pgxn-manager.json
# cap deploy:cold -s branch=$tag -s db_super=$super -s pgoptions=--search_path=public,contrib 
# cap deploy -s branch=$tag
# cap deploy:migrate -s db_super=$super

load 'deploy'

default_run_options[:pty] = true  # Must be set for the password prompt from git to work

set :application, "manager"
set :domain,      "pgxn.org"
set :repository,  "https://github.com/pgxn/pgxn-manager.git"
set :scm,         :git
set :deploy_via,  :remote_cache
set :use_sudo,    false
set :branch,      "master"
set :deploy_to,   "~/pgxn-manager"
set :run_from,    "/var/www/#{application}.#{domain}"
set :master,      "/var/www/master.#{domain}"
set :pgxnuser,    "pgxn"
set :conf_file,   "/etc/pgxn-manager.json"

# Prevent creation of Rails-style shared directories.
set :shared_children, %()

role :app, 'xanthan.postgresql.org'

namespace :deploy do
  desc 'Confirm attempts to deploy master'
  task :check_branch do
    if self[:branch] == 'master'
      unless Capistrano::CLI.ui.agree("\n    Are you sure you want to deploy master? ")
        puts "\n", 'Specify a branch via "-s branch=vX.X.X"', "\n"
        exit
      end
    end
  end

  task :finalize_update, :except => { :no_release => true } do
    # Build it!
    run <<-CMD
      cd #{ latest_release };
      rm -f conf/prod.json;
      ln -s #{ conf_file } conf/prod.json || exit $?;
      perl Build.PL --context prod || exit $?;
      ./Build installdeps || exit $?;
      ./Build || exit $?;
    CMD
  end

  task :start_script do
    top.upload 'eg/debian_init', '/tmp/pgxn-manager', :mode => 0755
    run 'sudo mv /tmp/pgxn-manager /etc/init.d/ && sudo /usr/sbin/update-rc.d pgxn-manager defaults'
  end

  task :setup_master do
    run <<-CMD
      sudo mkdir -p #{ master };
      sudo chown -R #{ pgxnuser } #{ master };
    CMD
  end

  task :symlink_production do
    run "sudo ln -fs #{ latest_release } #{ run_from }"
  end

  task :migrate do
    default_environment['PGOPTIONS']  = pgoptions if exists?(:pgoptions)
    run "cd #{ latest_release } && ./Build db --db_super_user #{ exists?(:db_super) ? fetch(:db_super) : 'postgres' }"
  end

  task :start do
    run 'sudo /etc/init.d/pgxn-manager start'
  end

  task :restart do
    run 'sudo /etc/init.d/pgxn-manager restart'
  end

  task :stop do
    run 'sudo /etc/init.d/pgxn-manager stop'
  end

end

before 'deploy:cold',    'deploy:setup_master'
before 'deploy:update',  'deploy:check_branch'
after  'deploy:update',  'deploy:start_script'
after  'deploy:symlink', 'deploy:symlink_production'
