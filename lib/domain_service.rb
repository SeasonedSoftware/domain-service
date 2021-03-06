require 'pg'
require 'aws-sdk'
require 'json'
require './lib/base_service'

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
#   'id': 'dns_hosted_zone_id',
#   'domain': 'domain_name',
#   'action': 'create_hosted_zone'
# }
#

class DomainService < BaseService
  def initialize(context, input)
    raise 'missing AWS_REGION' if ENV['AWS_REGION'].nil?
    raise 'missing AWS_SECRET_ACCESS_KEY' if ENV['AWS_SECRET_ACCESS_KEY'].nil?
    raise 'missing AWS_ACCESS_KEY_ID' if ENV['AWS_ACCESS_KEY_ID'].nil?
    raise 'missing AWS_ROUTE_IP' if ENV['AWS_ROUTE_IP'].nil?
    raise 'missing JWT_SECRET' if ENV['JWT_SECRET'].nil?
    super
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
      if not verify_hosted_zone_aws
        create_dns
        create_default_records
        save_record_resources
      else
        updated_dns(verify_hosted_zone)
        create_default_records
        save_record_resources
      end
    when 'create_dns_record'
      create_dns_records
    when 'verify_custom_domain'
      # call consul/traefk
      verify_custom_domain
    end
  end

  # create dns_hosted_zone in Route53
  def create_dns
    response = route53.create_hosted_zone(hosted_zone_template)
    update_dns_hosted_zone(JSON.parse(response.to_h.to_json)) unless response.hosted_zone.id.nil?

    {
      action: "created_dns",
      response: response.hosted_zone.name
    }
  end

  # update dns_hosted_zone in database
  def updated_dns(hosted_zone)
    update_dns_hosted_zone(JSON.parse(hosted_zone.to_h.to_json))

    {
      action: "updated_dns",
      response: hosted_zone.hosted_zone.name
    }
  end

  # created dns_records default after created hosted_zone
  def create_default_records
    default_records_1 = records_template(dns_hosted_zone_aws_id['hosted_zone_id'], domain_name, 'A', values: [ENV['AWS_ROUTE_IP']], comments: 'autocreated')

    default_records_2 = records_template(dns_hosted_zone_aws_id['hosted_zone_id'], "*.#{domain_name}", 'A', values: [ENV['AWS_ROUTE_IP']], comments: 'autocreated')

    route53.change_resource_record_sets(default_records_1.to_h)
    route53.change_resource_record_sets(default_records_2.to_h)

    {
      status: "200",
      response: domain_name
    }
  end


  def save_record_resources
    @pgconn.prepare('insert_record', 'insert into public.dns_records(dns_hosted_zone_id, name, record_type, value, ttl, created_at, updated_at) values ($1, $2, $3, $4, $5, now(), now())')

    list_resource_records.each do |record_set|
      quant_records = @pgconn.exec_params('select * from public.dns_records where name = $1 and record_type = $2', [(record_set.name.gsub(/\.$/, '')), record_set.type])

      if quant_records.count == 0
        @pgconn.exec_prepared('insert_record', [dns_hosted_zone['id'], eval(%Q("#{record_set.name.gsub(/\.$/, '')}")), record_set.type, record_set.resource_records.map{|r| r.value}.join("\n"), record_set.ttl])
      end
    end

    {
      status: "200",
      response: domain_name
    }
  end

  def create_dns_record
    record = default_records_template(xxx, dns_record['name'], dns_record['recorD_type'], values: dns_record['values'], comments: dns_record['comments'])

    route53.change_resource_record_sets(record.to_h)
  end

  def verify_custom_domain
    puts "LOGGER COSTUM_DOMAIN MOBI_ID =>> #{input['id']} CUSTOM_DOMAIN =>> #{input['custom_domain']} POSTGRES_ACTION =>> #{input['pg_action']}"
  end

  private

  def dns_record
    if input_action = 'create_dns_record'
      @dns_record ||= @pgconn.exec_params(%Q{
        select *
          from public.dns_records
        where id = $1
      }, [input['id']]).first
    end
  end

  def verify_hosted_zone_aws
    if dns_hosted_zone_aws_id['hosted_zone_id'].nil?
      false
    else
      response = route53.get_hosted_zone({ id: dns_hosted_zone_aws_id['hosted_zone_id'] })
    end
  end

  def dns_hosted_zone_aws_id
    @dns_hosted_zone_aws_id = @pgconn.exec_params(%Q{
     select
       response -> 'hosted_zone' ->> 'id' AS "hosted_zone_id"
     from dns_hosted_zones
     where id = $1;
    }, [dns_hosted_zone_id]).first
  end

  def dns_hosted_zone
    @dns_hosted_zone ||= @pgconn.exec_params(%Q{
      select *
        from dns_hosted_zones
      where id = $1
    }, [dns_hosted_zone_id]).first
  end

  def update_dns_hosted_zone(hosted_zone)
    @pgconn.exec_params(%Q{
      update dns_hosted_zones
        set response = $1, updated_at = now()
      where id = $2
    }, [hosted_zone.to_json, dns_hosted_zone_id])
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

  def records_template hosted_zone_id, domain_name, type, values: nil, comments: nil, action: 'UPSERT', ttl_seconds: 300# 3600
    batch = {
      change_batch: {
        changes: [
          {
            action: action,
            resource_record_set: {
              name: domain_name,
              ttl: ttl_seconds,
              type: type
            },
          }
        ]
      },
      hosted_zone_id: hosted_zone_id
    }

    batch[:change_batch][:changes][0][:resource_record_set][:resource_records] = values.map{|v| { value: v } } if values
    batch[:change_batch][:comment] = comments if comments

    batch
  end

  def list_resource_records
    resource_records = []

    response = route53.list_resource_record_sets({hosted_zone_id: dns_hosted_zone_aws_id['hosted_zone_id']})
    while (response['is_truncated'])
      resource_records += (response['resource_record_sets'])
      response = route53.list_resource_record_sets({hosted_zone_id: dns_hosted_zone_aws_id['hosted_zone_id'], start_record_name: response['next_record_name']})
    end
    resource_records += (response['resource_record_sets'])
    resource_records
  end

  def dns_hosted_zone_id
    @dns_hosted_zone_id ||= @input['id']
  end

  def domain_name
    @domain_name ||= @input['domain']
  end
end
