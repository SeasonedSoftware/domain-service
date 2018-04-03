require 'fdk'
require 'json'
require './lib/domain_service'

def run(context, input)
  DomainService.run!(context, input)
end

FDK.handle(:run)
