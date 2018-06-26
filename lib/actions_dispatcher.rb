require 'json'
require './lib/domain_service'
require './lib/traefik_service'

class ActionsDispatcher
  def self.run!(context, input)
    new(context, input).redirect_action
  end

  def initialize(context, input)
    @context = context
    @input = input
  end

  def redirect_action
    service.run!(@context, @input) unless service.nil?
  end

  def service
    case 
    when domain_service_actions.include?(input_action)
      return DomainService
    when traefik_service_actions.include?(input_action)
      return TraefikService
    end
  end

  def domain_service_actions
    %w(create_hosted_zone create_dns_record verify_custom_domain)
  end

  def traefik_service_actions
    %w(refresh_frontend)
  end

  def input_action
    @input['action']
  end
end
