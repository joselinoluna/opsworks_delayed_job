# Adapted from deploy::rails: https://github.com/aws/opsworks-cookbooks/blob/master/deploy/recipes/rails.rb

include_recipe 'deploy'

node[:deploy].each do |application, deploy|

  if deploy[:application_type] != 'rails'
    Chef::Log.debug("Skipping opsworks_delayed_job::deploy application #{application} as it is not a Rails app")
    next
  end

  opsworks_deploy_dir do
    user deploy[:user]
    group deploy[:group]
    path deploy[:deploy_to]
  end

  include_recipe "opsworks_delayed_job::setup"

  template "#{deploy[:deploy_to]}/shared/config/memcached.yml" do
    cookbook "rails"
    source "memcached.yml.erb"
    mode 0660
    owner deploy[:user]
    group deploy[:group]
    variables(:memcached => (deploy[:memcached] || {}), :environment => deploy[:rails_env])
  end

  node.set[:opsworks][:rails_stack][:restart_command] = ':'

  opsworks_deploy do
    deploy_data deploy
    app application
  end

  execute "restart delayed_job" do
    command node[:delayed_job][application][:restart_command]
  end
  
  Chef::Log.debug("Updating cron tab...")
      
  bash "update-crontab-#{application}" do
    deploy = node[:deploy][application]
    layers = node[:opsworks][:instance][:layers]

    cwd "#{deploy[:deploy_to]}/current"
    user 'deploy'
    code "bundle exec whenever --set environment=#{deploy[:rails_env]} --update-crontab #{application} --roles #{layers.join(',')}"
    only_if "cd #{deploy[:deploy_to]}/current && bundle show whenever"
  end
end
