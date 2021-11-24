require 'spec_helper'

describe SpreeAvataxCertified::Address, :type => :model do
  let(:country){ FactoryGirl.create(:country) }
  let(:address){ FactoryGirl.create(:address) }
  let(:order) { FactoryGirl.create(:order_with_line_items) }

  before do
    Spree::Config.avatax_address_validation = true
    order.ship_address.update_attributes(city: 'Tuscaloosa', address1: '220 Paul W Bryant Dr')
  end

  let(:address_lines) { SpreeAvataxCertified::Address.new(order) }

  describe '#initialize' do
    it 'should have order' do
      expect(address_lines.order).to eq(order)
    end
    it 'should have addresses be an array' do
      expect(address_lines.addresses).to be_kind_of(Array)
    end
  end

  describe '#build_addresses' do
    it 'receives origin_address' do
        expect(address_lines).to receive(:origin_address)
        address_lines.build_addresses
    end
    it 'receives order_ship_address' do
        expect(address_lines).to receive(:order_ship_address)
        address_lines.build_addresses
    end
    it 'receives origin_ship_addresses' do
        expect(address_lines).to receive(:origin_ship_addresses)
        address_lines.build_addresses
    end
  end

  describe '#origin_address' do
    it 'returns an array' do
      expect(address_lines.origin_address).to be_kind_of(Array)
    end

    it 'has the origin address return a hash' do
      expect(address_lines.origin_address[0]).to be_kind_of(Hash)
    end
  end

  describe '#order_ship_address' do
    it 'returns an array' do
      expect(address_lines.order_ship_address).to be_kind_of(Array)
    end

    it 'has the origin address return a hash' do
      expect(address_lines.order_ship_address[0]).to be_kind_of(Hash)
    end

    if 'has attributes that matches' do
      order_ship_address = order.ship_address
      ship_address = address_lines.order_ship_address[0]

      expect(ship_address['AddressCode']).to eq('Dest')
      expect(ship_address['Line1']).to eq(order_ship_address.address1)
      expect(ship_address['Line2']).to eq(order_ship_address.address2)
      expect(ship_address['City']).to eq(order_ship_address.city)
      expect(ship_address['Region']).to eq(order_ship_address.state.name)
      expect(ship_address['Country']).to eq(order_ship_address.country.iso)
      expect(ship_address['PostalCode']).to eq(order_ship_address.zipcode)
    end
  end

  describe "#validate" do
    it "validates address with success" do
      result = address_lines.validate
      expect(address_lines.validate["ResultCode"]).to eq("Success")
    end

    it "does not validate when config settings are false" do
      Spree::Config.avatax_address_validation = false
      result = address_lines.validate
      expect(address_lines.validate).to eq("Address validation disabled")
    end
  end

  describe '#address_validation_enabled?' do
    it 'returns true' do
      expect(address_lines.address_validation_enabled?).to be_truthy
    end

    it 'returns false' do
      Spree::Config.avatax_address_validation = false
      expect(address_lines.address_validation_enabled?).to be_falsey
    end
  end

  describe '#country_enabled?' do
    it 'returns true if the current country is enabled' do
      expect(address_lines.country_enabled?(Spree::Country.first)).to be_truthy
    end
  end
end
