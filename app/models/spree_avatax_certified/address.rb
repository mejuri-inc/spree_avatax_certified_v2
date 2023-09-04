require 'json'
require 'net/http'
require 'addressable/uri'
require 'base64'
require 'logger'

module SpreeAvataxCertified
  class Address
    include AvataxHelper
    attr_reader :order, :address

    def initialize(order = nil,line = nil, bill_address)
      @order = order
      @line = line
      @address = {
        :billTo => bill_address
      }
      @logger ||= AvataxHelper::AvataxLog.new('avalara_order_addresses', 'SpreeAvataxCertified::Address', 'building addresses')
      build_addresses
    end

    def build_addresses
      @address[:shipTo] = ship_to_address
      @address[:shipFrom] = ship_from_address
    end

    def ship_to_address
      unless order.ship_address.nil?

        order_ship_address = order.pos? ? order.purchase_location.stock_location : order.ship_address

        shipping_address = {
          :line1 => order_ship_address.address1,
          :line2 => order_ship_address.address2,
          :city => order_ship_address.city,
          :region => order_ship_address.state_name.presence || order_ship_address.state&.name,
          :country => order_ship_address.country.iso,
          :postalCode => order_ship_address.zipcode
        }

        @logger.debug shipping_address

        shipping_address
      end
    end

    def ship_from_address
      stock_location = @line.stock_location
      resolve_stock_location if stock_location.blank?

      stock_location_address = {
        :line1 => stock_location.address1,
        :line2 => stock_location.address2,
        :city => stock_location.city,
        :postalCode => stock_location.zipcode,
        :country => Spree::Country.find(stock_location.country_id).iso
      }

      @logger.debug stock_location_address

      stock_location_address
    end

    def validate
      address = order.ship_address
      if address_validation_enabled? && country_enabled?(Spree::Country.find(address[:country_id]))

        return address if address.nil?

        address_hash = {
          Line1: address[:address1],
          Line2: address[:address2],
          City: address[:city],
          Region: Spree::State.find(address[:state_id]).abbr,
          Country: Spree::Country.find(address[:country_id]).iso,
          PostalCode: address[:zipcode]
        }

        encodedquery = Addressable::URI.new
        encodedquery.query_values = address_hash
        uri = URI(service_url + encodedquery.query)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE

        res = http.get(uri.request_uri, 'Authorization' => credential)

        response = JSON.parse(res.body)

        if response['Address']['City'] == address[:city] || response['Address']['Region'] == Spree::State.find(address[:state_id]).abbr
          return response
        else
          response['ResultCode'] = 'Error'
          suggested_address = response['Address']
          response['Messages'] = [{
                                    'Summary' => "Did you mean #{suggested_address['Line1']}, #{suggested_address['City']}, #{suggested_address['Region']}, #{suggested_address['PostalCode']}?"
          }]
          return response
        end
      else
        'Address validation disabled'
      end
    rescue => e
      'error in address validation'
    end

    def address_validation_enabled?
      Spree::Config.avatax_address_validation
    end

    def country_enabled?(current_country)
      Spree::Config.avatax_address_validation_enabled_countries.each do |country|
        return true if current_country.name == country
      end
      false
    end

    private

    def credential
      'Basic ' + Base64.encode64(account_number + ':' + license_key)
    end

    def service_url
      Spree::Config.avatax_endpoint + AVATAX_SERVICEPATH_ADDRESS + 'validate?'
    end

    def license_key
      Spree::Config.avatax_license_key
    end

    def account_number
      Spree::Config.avatax_account
    end

    def resolve_stock_location
      package = Spree::Stock::Coordinator.new(@order).packages.find { |package| package.line_items.any? {|li| li.id == @line.id} }
      package.stock_location
    end
  end
end
