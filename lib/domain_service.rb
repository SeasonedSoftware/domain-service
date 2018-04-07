require 'pg'
require 'aws-sdk'
require 'json'

# Create dns/domain via aws-skd [route53]
#
# environment vars in fn application:
#   DATABASE_URL: database connection string
#   AWS_ACCESS_KEY_ID: aws credentials access key id
#   AWS_SECRET_ACCESS_KEY: aws credentials access key
#   AWS_REGION: aws default region
#
# input:
# {
#   'id': 'community_id',
#   'domain': 'domain_name',
#   'action': 'create_hosted_zone'
# }
#

class DomainService
  def initialize(context, input)
    raise 'missing DATABASE_URL env' if ENV['DATABASE_URL'].nil?
    raise 'missing AWS_REGION' if ENV['AWS_REGION'].nil?
    raise 'missing AWS_SECRET_ACCESS_KEY' if ENV['AWS_SECRET_ACCESS_KEY'].nil?
    raise 'missing AWS_ACCESS_KEY_ID' if ENV['AWS_ACCESS_KEY_ID'].nil?

    @pgconn = PG.connect(ENV['DATABASE_URL'])
    @context = context
    @input = input
  end

  def self.run!(context, input)
    STDERR.puts("[DomainService] start for call_id  #{context.call_id}")
    new(context, input).run
  end

  def route53
    @route53 = Aws::Route53::Client.new(region: (ENV['AWS_ROUTE53_REGION'] || 'sa-east-1'))
  end

  def run
    STDERR.puts("[DomainService]#{call_id} - Processing #{input_action}")
    case input_action
    when 'create_hosted_zone'
      if not verify_hosted_zone
        create_dns
      else
        updated_dns(verify_hosted_zone)
      end
    end
  end

  def create_dns
    response = route53.create_hosted_zone(hosted_zone_template)
    update_dns_hosted_zone(JSON.parse(response.to_h.to_json)) unless response.hosted_zone.id.nil?

    {
      action: "created_dns",
      response: response.hosted_zone.name
    }
  end

  def updated_dns(hosted_zone)
    update_dns_hosted_zone(JSON.parse(hosted_zone.to_h.to_json))

    {
      action: "updated_dns",
      response: hosted_zone.hosted_zone.name
    }
  end

  private
  def community
    @community ||= @pgconn.exec_params('select * from communities where id = $1', [community_id]).first
  end

  def verify_hosted_zone
    dns_hosted_zone_id = @pgconn.exec_params(%Q{
     select
       response -> 'hosted_zone' ->> 'id' AS "hosted_zone_id"
     from dns_hosted_zones
     where id = $1;
     }, [dns_hosted_zone['id']]).first

    if dns_hosted_zone_id['hosted_zone_id'].nil?
      false
    else
      response = route53.get_hosted_zone({ id: dns_hosted_zone_id['hosted_zone_id'] })
    end
  end

  def dns_hosted_zone
    @dns_hosted_zone ||= @pgconn.exec_params(%Q{
      select *
        from dns_hosted_zones
      where community_id = $1
      and domain_name = $2
    }, [community_id, domain_name]).first
  end

  def update_dns_hosted_zone(hosted_zone)
    @pgconn.exec_params(%Q{
      update dns_hosted_zones
        set response = $1, updated_at = now()
      where id = $2
    }, [hosted_zone.to_json, dns_hosted_zone['id']])
  end

  def hosted_zone_template
    {
      name: domain_name,
      caller_reference: "#{DateTime.now.strftime('%Q')}#{rand(0..999)}",
      hosted_zone_config: {
        comment: dns_hosted_zone['comment'],
        private_zone: false
      }
    }
  end

  def input_action
    @input_action ||= @input['action']
  end

  def call_id
    @call_id ||= @context.call_id
  end

  def community_id
    @community_id ||= @input['id']
  end

  def domain_name
    @domain_name ||= @input['domain']
  end
end
