require './mimeograph'
require 'sidekiq/web'

Sidekiq.configure_client do |config|
  config.redis = { :size => 1 }
end
run Rack::URLMap.new('/' => Sinatra::Application, '/sidekiq' => Sidekiq::Web)
