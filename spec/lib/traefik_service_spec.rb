require 'spec_helper'
require './lib/traefik_service'

RSpec.describe TraefikService do
  let(:context) { double(call_id: 'call_id_mock') }
  let(:input_action) { 'refresh_frontend' }
  let(:input) { { 'action' => input_action, 'id' => 1234 } }
  let(:pgconn_mock) { double() }
  let(:mob_mock) { {
    'traefik_host_rule' => 'Host: foo.bar.com'
  } }

  let(:get_mob_sql) { %(select * from mobilizations where id = $1) }

  before do
    ENV['DATABASE_URL'] = 'postgres://someurl'
    ENV['CONSUL_URI'] = 'consul.uri'
    ENV['DEFAULT_PUBLIC_BACKEND_URI'] = 'backend.url'
    ENV['CONSUL_ACL_TOKEN'] = 'acltoken'

    allow(PG).to receive(:connect).and_return(pgconn_mock)
    allow(Diplomat::Kv).to receive(:put).with('traefik/frontends/1234_public_frontend/backend', 'default_public_backend').and_return(true)
    allow(Diplomat::Kv).to receive(:put).with('traefik/frontends/1234_public_frontend/routes/main/rule', 'Host: foo.bar.com').and_return(true)

    allow(Diplomat::Kv).to receive(:put).with('traefik/backends/default_public_backend/servers/server1/url', 'backend.url').and_return(true)
    allow(Diplomat::Kv).to receive(:put).with('traefik/backends/default_public_backend/servers/server1/weight', 1).and_return(true)
    allow(pgconn_mock).to receive(:exec_params).with(
      get_mob_sql,
      [1234]
    ).and_return([mob_mock])
  end

  subject { TraefikService.new(context, input) }

  describe '.mobilization' do
    it 'should execute sql to get the mobilization data' do
      expect(pgconn_mock).to receive(:exec_params).with(get_mob_sql, [1234])
      subject.mobilization
    end
  end

  describe '.generate_mob_frontend' do
    it 'should call consult kv storage for mobilization frontend' do
      expect(Diplomat::Kv).to receive(:put).with(
        'traefik/frontends/1234_public_frontend/backend', 
        'default_public_backend'
      )
      expect(Diplomat::Kv).to receive(:put).with(
        'traefik/frontends/1234_public_frontend/routes/main/rule',
        mob_mock['traefik_host_rule']
      )
      subject.generate_mob_frontend
    end
  end

  describe '.generate_public_backend' do
    it 'should call consult kv storage for mobilization public backend' do
      expect(Diplomat::Kv).to receive(:put).with(
        'traefik/backends/default_public_backend/servers/server1/url', 
        'backend.url'
      )
      expect(Diplomat::Kv).to receive(:put).with(
        'traefik/backends/default_public_backend/servers/server1/weight', 
        1
      )
      subject.generate_public_backend
    end
  end

  describe '.run' do
    context 'when have default public backend already in consul' do
      before do
        allow(Diplomat::Kv).to receive(:get).with('traefik/backends/default_public_backend/servers/server1/url').and_return('backend.url')
      end

      it 'should not call generate_public_backend' do
        expect(subject).to receive(:have_default_public_backend?).and_return(true).and_call_original
        expect(Diplomat::Kv).to receive(:put).with(
          'traefik/frontends/1234_public_frontend/backend', 
          'default_public_backend'
        )
        expect(Diplomat::Kv).to receive(:put).with(
          'traefik/frontends/1234_public_frontend/routes/main/rule',
          mob_mock['traefik_host_rule']
        )
        expect(Diplomat::Kv).to_not receive(:put).with(
          'traefik/backends/default_public_backend/servers/server1/url', 
          'backend.url'
        )
        expect(Diplomat::Kv).to_not receive(:put).with(
          'traefik/backends/default_public_backend/servers/server1/weight', 
          1
        )

        subject.run
      end
    end

    context 'when have default public backend already in consul' do
      before do
        allow(Diplomat::Kv).to receive(:get).with('traefik/backends/default_public_backend/servers/server1/url').and_raise(Diplomat::KeyNotFound)
      end

      it 'should not call generate_public_backend' do
        expect(subject).to receive(:have_default_public_backend?).and_return(false).and_call_original
        expect(Diplomat::Kv).to receive(:put).with(
          'traefik/frontends/1234_public_frontend/backend', 
          'default_public_backend'
        )
        expect(Diplomat::Kv).to receive(:put).with(
          'traefik/frontends/1234_public_frontend/routes/main/rule',
          mob_mock['traefik_host_rule']
        )
        expect(Diplomat::Kv).to receive(:put).with(
          'traefik/backends/default_public_backend/servers/server1/url', 
          'backend.url'
        )
        expect(Diplomat::Kv).to receive(:put).with(
          'traefik/backends/default_public_backend/servers/server1/weight', 
          1
        )

        subject.run
      end
    end

  end


end
