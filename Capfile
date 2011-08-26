# Steps to doing an initial deployment:
#
# cap deploy:setup
# Copy prod.json to /var/www/manager.pgxn.org/
# cap deploy -s branch=$tag

load 'deploy'

default_run_options[:pty] = true  # Must be set for the password prompt from git to work

set :application, "manager"
set :domain,      "pgxn.org"
set :repository,  "https://github.com/pgxn/pgxn-manager.git"
set :scm,         :git
set :deploy_via,  :remote_cache
set :branch,      "master"
set :deploy_to,   "/var/www/#{application}.#{domain}"
set :master,      "/var/www/master.#{domain}"
set :pgxnuser,    "pgxn"

# Prevent creation of Rails-style shared directories.
set :shared_children, %()

role :app, 'xanthan.postgresql.org'

namespace :deploy do
  desc 'Verify attempts to deploy master'
  task :before_deploy do
    if self[:branch] == 'master'
      unless Capistrano::CLI.ui.agree("\n    Are you sure you want to deploy master? ")
        puts "\n", 'Specify a branch via "-s branch=vX.X.X"', "\n"
        exit
      end
    end
  end

  task :setup_root do
    # Need to grant permission so anyone can do a deploy.
    run "sudo chmod -R 0777 #{ deploy_to }"
  end

  task :finalize_update, :except => { :no_release => true } do
    # Build it!
    run <<-CMD
      if [ ! -d #{ master } ]; then
          sudo mkdir -p #{ master };
          sudo chown -R #{ pgxnuser }:#{ pgxnuser } #{ master };
      fi

      # Build it!
      cd #{latest_release};
      rm conf/prod.json;
      ln -s #{ deploy_to }/prod.json conf/;
      perl Build.PL --db_super_user postgres --context prod;
      ./Build;
      # ./Build db;
    CMD
  end

  task :start do
    run 'plackup -E prod #{latest_release}/bin/pgxn_manager.psgi'
  end

  task :restart do
    run 'plackup -E prod #{latest_release}/bin/pgxn_manager.psgi'
  end

  task :stop do
    run 'plackup -E prod #{latest_release}/bin/pgxn_manager.psgi'
  end

end

after('deploy:setup', 'deploy:setup_root')

