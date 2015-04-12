require 'dashing'

ENVIRONMENT = ENV['RACK_ENV'] || 'development'
DBCONFIG = YAML.load(ERB.new(File.read(File.join('config', 'database.yml'))).result)

ActiveRecord::Base.establish_connection(DBCONFIG[ENVIRONMENT])

configure do
  set :auth_token, 'YOUR_AUTH_TOKEN'

  helpers do
    def protected!
     # Put any authentication code you want in here.
     # This method is run before accessing any resource.
    end
  end
end

map Sinatra::Application.assets_prefix do
  run Sinatra::Application.sprockets
end

run Sinatra::Application
