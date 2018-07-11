require 'fdk'
require 'json'
require 'jwt'
require './lib/actions_dispatcher'

def run(context, input)
  if result = decode_token(input)
    ActionsDispatcher.run!(context, result[0])
  end
# rescue Exception => e
#   { error: "#{e.inspect}" }
end

def decode_token(input)
  JWT.decode(input, ENV['JWT_SECRET'], true, algorithm: 'HS512')
end

FDK.handle(:run)
