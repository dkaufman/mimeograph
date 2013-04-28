require './mimeograph'
require 'sidekiq/web'

if settings.production?
  Sidekiq.configure_client do |config|
    config.redis = { :size => 1, :url => ENV['REDISTOGO_URL'] }
  end
end
run Rack::URLMap.new('/' => Sinatra::Application, '/sidekiq' => Sidekiq::Web)
