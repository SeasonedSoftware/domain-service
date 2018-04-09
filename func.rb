require 'fdk'
require 'json'
require 'jwt'
require './lib/domain_service'

def run(context, input)
  if verify_token(input)
    DomainService.run!(context, input)
  end
rescue Exception => e
  { error: "#{e.inspect}" }
end

def verify_token(input)
  JWT.decode(input['api_key'], ENV['JWT_SECRET'], true, algorithm: 'HS512')
end

FDK.handle(:run)
