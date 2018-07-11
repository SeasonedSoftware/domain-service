require 'pg'
require 'json'
require 'diplomat'
require './lib/base_service'
# create / update frontend at traefik loadbalancer
# environment vars in fn application
# DATABASE_URL: database connection string
# DEFAULT_PUBLIC_BACKEND_URI: http://127.0.0.1:80
# CONSUL_URI: http://consul.host
# CONSUL_ACL_TOKEN: acltoken
#
# input:
# {
#   'id': 'mobilization_id',
#   'action': 'refresh_frontend'
# }
#
class TraefikService < BaseService
  def self.run!(context, input)
    new(context, input).run
  end

  def initialize(context, input)
    raise 'missing CONSUL_URI env' if ENV['CONSUL_URI'].nil?
    raise 'missing CONSUL_ACL_TOKEN env' if ENV['CONSUL_ACL_TOKEN'].nil?

    super

    configure_consul
  end

  def run
    return if mobilization['traefik_host_rule'].nil?
    generate_public_backend unless have_default_public_backend?

    generate_mob_frontend
  end

  def mobilization
    @mobilization ||= @pgconn.exec_params(
      %(select * from mobilizations where id = $1),
      [mobilization_id]
    ).first
  end

  def generate_mob_frontend
    Diplomat::Kv.put(*mob_frontend_backend_kv)
    Diplomat::Kv.put(*mob_frontend_rule_kv)
  end

  def generate_public_backend
    Diplomat::Kv.put(*default_backend_server_kv)
    Diplomat::Kv.put(*default_backend_weight_kv)
  end

  def have_default_public_backend?
    !Diplomat::Kv.get(default_backend_server_kv[0].to_s).nil?
  rescue Diplomat::KeyNotFound
    return false
  end

  protected

  def mob_frontend_backend_kv
    ["traefik/frontends/#{mobilization_id}_public_frontend/backend", 'default_public_backend']
  end

  def mob_frontend_rule_kv
    ["traefik/frontends/#{mobilization_id}_public_frontend/routes/main/rule", mobilization['traefik_host_rule']]
  end

  def default_backend_server_kv
    ['traefik/backends/default_public_backend/servers/server1/url', ENV['DEFAULT_PUBLIC_BACKEND_URI']]
  end

  def default_backend_weight_kv
    ['traefik/backends/default_public_backend/servers/server1/weight', '1']
  end

  def mobilization_id
    @mobilization_id ||= @input['id']
  end

  def configure_consul
    Diplomat.configure do |config|
      config.url = ENV['CONSUL_URI']
      config.acl_token =  ENV['CONSUL_ACL_TOKEN']
      config.options = {ssl: { version: :TLSv1_2 }}
    end
  end
end
