require 'spec_helper'
require './lib/actions_dispatcher'

RSpec.describe ActionsDispatcher do
  let(:context) { double(call_id: 'call_id_mock') }
  let(:input_action) { 'refresh_frontend' }
  let(:input) { { 'action' => input_action, 'id' => 1234 } }

  describe 'input actions' do
    subject { ActionsDispatcher.new(context, input) }

    context 'when create_hosted_zone' do
      let(:input_action) { 'create_hosted_zone' }

      it 'service should be DomainService' do
        expect(subject.service).to eq(DomainService)
      end

      it 'redirect_action should be service.run!' do
        expect(DomainService).to receive(:run!).with(context, input)
        subject.redirect_action
      end
    end

    context 'when create_dns_record' do
      let(:input_action) { 'create_dns_record' }

      it 'service should be DomainService' do
        expect(subject.service).to eq(DomainService)
      end

      it 'redirect_action should be service.run!' do
        expect(DomainService).to receive(:run!).with(context, input)
        subject.redirect_action
      end
    end

    context 'when verify_customer_domain' do
      let(:input_action) { 'verify_custom_domain' }

      it 'service should be DomainService' do
        expect(subject.service).to eq(DomainService)
      end

      it 'redirect_action should be service.run!' do
        expect(DomainService).to receive(:run!).with(context, input)
        subject.redirect_action
      end
    end

    context 'when refresh_frontend' do
      let(:input_action) { 'refresh_frontend' }

      it 'service should be DomainService' do
        expect(subject.service).to eq(TraefikService)
      end

      it 'redirect_action should be service.run!' do
        expect(TraefikService).to receive(:run!).with(context, input)
        subject.redirect_action
      end
    end
  end
end
