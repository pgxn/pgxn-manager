# Steps to doing an initial deployment:
#
# Create system users "pgxn" and "pgxn_manager"
# Create ~/.pgpass for users "pgxn" and "pgxn_manager" (if necessary)
# cap deploy:setup
# Copy prod.json to ~pgxn/pgxn-manager/shared/conf/prod.json
# cap deploy:cold -s branch=$tag -s db_super=$super
# cap deploy -s branch=$tag
# cap deploy:migrate -s db_super=$super
#
# -s options:
# * user - Deployment user; default: "pgxn"
# * db_super - Database user who owns the database; default: "postgres"
# * pgxn_user - User to run the app; default: "pgxn_manager"
# * pgoptions - Value to use for PGOPTIONS env var during migrations

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
set :run_from,    "/var/virtuals/pgxn/#{application}.#{domain}"
set :mirror_root, "/var/virtuals/pgxn/master.#{domain}"
set :user,        "pgxn"
set :pgxn_user,   "pgxn_manager"
set :host,        "depesz.com"

# Prevent creation of Rails-style shared directories.
set :shared_children, %w(log pids conf)

role :app, host

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
      ln -fs #{shared_path}/conf/prod.json conf/prod.json || exit $?;
      ln -fs #{shared_path}/log || exit $?;
      ln -fs #{shared_path}/pids || exit $?;
      perl Build.PL --context prod --db_super_user #{ exists?(:db_super) ? fetch(:db_super) : 'postgres' } || exit $?;
      ./Build installdeps || exit $?;
      ./Build || exit $?;
    CMD
  end

  task :start_script do
    top.upload 'eg/debian_init', '/tmp/pgxn-manager', :mode => 0755
    run 'sudo mv /tmp/pgxn-manager /etc/init.d/ && sudo /usr/sbin/update-rc.d pgxn-manager defaults'
  end

  task :setup_mirror_root do
    run "mkdir -p #{ mirror_root }", :hosts => "#{ pgxn_user }@#{ host }"
  end

  task :symlink_production do
    run "ln -fs #{ latest_release } #{ run_from }"
  end

  task :migrate do
    default_environment['PGOPTIONS']  = pgoptions if exists?(:pgoptions)
    run "cd #{ latest_release } && ./Build db --context prod --db_super_user #{ exists?(:db_super) ? fetch(:db_super) : 'postgres' } || exit $? "
  end

  task :start do
#    run 'sudo /etc/init.d/pgxn-manager start'
    run "cd #{ run_from } && starman -E prod --workers 5 --preload-app --max-requests 100 --listen 127.0.0.1:7496 --daemonize --pid pids/pgxn_manager.pid --error-log log/pgxn_manager.log bin/pgxn_manager.psgi", :hosts => "#{ pgxn_user }@#{ host }"
  end

  task :restart do
#    run 'sudo /etc/init.d/pgxn-manager restart'
    stop
    start
  end

  task :stop do
#    run 'sudo /etc/init.d/pgxn-manager stop'
    run <<-CMD, :hosts => "#{ pgxn_user }@#{ host }"
        if [ -f "#{ run_from }/pids/pgxn_manager.pid" ]; then
            kill `cat "#{ run_from }/pids/pgxn_manager.pid"`;
        fi
    CMD
  end

end

before 'deploy:cold',    'deploy:setup_mirror_root'
before 'deploy:update',  'deploy:check_branch'
#after  'deploy:update',  'deploy:start_script'
after  'deploy:symlink', 'deploy:symlink_production'
