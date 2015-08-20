require 'faraday'
require 'json'

namespace :slack do
  start = Time.now
  elapsed_time = -> { sprintf('%.2f', Time.now - start) }

  set :slack_endpoint, 'https://api.netbox.ru/'

  set :slack_deployer, -> {
    username = `git config --get user.name`.strip
    username = `whoami`.strip unless username
    username
  }

  set :slack_deployer_email, -> {
    username = `git config --get user.email`.strip
    username = 'none' unless username
    username
  }

  set :slack_post_message_api_endpoint, -> {
    "/event/deploy"
  }

  set :slack_path, -> { fetch(:slack_post_message_api_endpoint) }

  set :slack_stage, -> {
    stage = fetch(:stage)
    stage.to_s == 'production' ? ":warning: #{stage}" : stage
  }

  set :slack_start_body, -> {
    return {
      type: "start",
      name: fetch(:slack_deployer),
      email: fetch(:slack_deployer_email),
      application: fetch(:application),
      branch: fetch(:branch),
      stage: fetch(:slack_stage),
      revision: fetch(:current_revision)
    }
  }

  set :slack_failure_body, -> {
    return {
      type: "failure",
      name: fetch(:slack_deployer),
      email: fetch(:slack_deployer_email),
      application: fetch(:application),
      branch: fetch(:branch),
      stage: fetch(:slack_stage),
      revision: fetch(:current_revision),
      time: elapsed_time.call
    }
  }

  set :slack_success_body, -> {
    return {
      type: "success",
      name: fetch(:slack_deployer),
      email: fetch(:slack_deployer_email),
      application: fetch(:application),
      branch: fetch(:branch),
      stage: fetch(:slack_stage),
      revision: fetch(:current_revision),
      time: elapsed_time.call
    }
  }

  set :slack_client, -> {
    Faraday.new(fetch :slack_endpoint) do |c|
      c.request :url_encoded
      c.adapter Faraday.default_adapter

      v = Faraday::VERSION.split('.')
      if v.join('.').to_f >= 0.9
        c.options.timeout = 5
        c.options.open_timeout = 5
      end
    end
  }

  def post_to_slack_with(body)
    run_locally do
      res = fetch(:slack_client).post fetch(:slack_path), body

      if ENV['DEBUG']
        require 'awesome_print'
        ap body
        ap res
      end
    end
  end

  desc 'Post message to Slack (ex. cap production "slack:notify[yo!])"'
  task :post, :message do |t, args|
    post_to_slack_with fetch(:slack_default_body).merge(text: args[:message])
  end

  namespace :deploy do
    desc 'Notify a deploy starting to Slack'
    task :start do
      post_to_slack_with fetch(:slack_start_body)
    end
    after 'deploy:started', 'slack:deploy:start'

    desc 'Notify a deploy rollback to Slack'
    task :rollback do
      post_to_slack_with fetch(
        :"slack_#{fetch(:deploying) ? :failure : :success}_body")
    end
    after 'deploy:finishing_rollback', 'slack:deploy:rollback'

    desc 'Notify a deploy finish to Slack'
    task :finish do
      post_to_slack_with fetch(:slack_success_body)
    end
    after 'deploy:finishing', 'slack:deploy:finish'
  end
end
