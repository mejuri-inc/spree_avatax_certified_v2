require 'json'
require 'net/http'
require 'addressable/uri'
require 'base64'
require 'rest-client'
require 'logging'

module Spree
  class AddressValidationError < StandardError; end
end

class TaxSvc # rubocop:disable Metrics/ClassLength
  READ_TIMEOUT_ERROR = RestClient::Exceptions::ReadTimeout
  OPEN_TIMEOUT_ERROR = RestClient::Exceptions::OpenTimeout

  ADDRESS_ERRORS = ['Invalid or missing state/province',
                    'Zip is not valid for the state',
                    'Invalid ZIP/Postal Code',
                    'Address cannot be geocoded',
                    'Address not geocoded',
                    'The address is not deliverable.'].freeze

  def get_tax(request_hash) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    log(__method__, request_hash)
    RestClient.log = logger.logger
    order_number = request_hash[:DocCode]
    res = response('get', request_hash)
    logger.info 'RestClient call'
    logger.debug res
    response = JSON.parse(res.body)

    if response['ResultCode'] != 'Success'
      logger.info_and_debug("Avatax Error: Order ##{order_number}", response)

      raise 'error in Tax' unless Spree::Config.avatax_address_validation
      raise 'error in Tax' unless response['Messages'].any? do |message|
        ADDRESS_ERRORS.any? { |error| message['Summary'].include? error }
      end

      raise Spree::AddressValidationError.new('Address Validation Failed.')
    else
      response
    end
  rescue Spree::AddressValidationError => e
    Raven.capture_exception(e)
    raise e
  rescue StandardError => e
    # UDL-946 - Notify a failure to calculate taxes for an order
    if [READ_TIMEOUT_ERROR, OPEN_TIMEOUT_ERROR].any? { |klass| e.instance_of?(klass) }
      message = "[#{Rails.env}] Total Tax 0.0 calculated for Order: #{order_number}. Error: #{e}."
      Slack_client.chat_postMessage(channel: 'mejuri-web-avalara-errors', text: message)
    end
    msg = "Rest Client Error for Order ##{order_number}. Error: #{e}"
    logger.info msg
    'error in Tax'
  end

  def cancel_tax(request_hash)
    if tax_calculation_enabled?
      log(__method__, request_hash)
      res = response('cancel', request_hash)
      logger.debug res
      JSON.parse(res.body)['CancelTaxResult']
    end
  rescue => e
    logger.debug e, 'error in Cancel Tax'
    'error in Cancel Tax'
  end

  def estimate_tax(coordinates, sale_amount)
    if tax_calculation_enabled?
      log(__method__)

      return nil if coordinates.nil?
      sale_amount = 0 if sale_amount.nil?

      uri = URI(service_url + coordinates[:latitude].to_s + ',' + coordinates[:longitude].to_s + '/get?saleamount=' + sale_amount.to_s )
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      res = http.get(uri.request_uri, 'Authorization' => credential, 'Content-Type' => 'application/json')
      JSON.parse(res.body)
    end
  rescue => e
    logger.debug e, 'error in Estimate Tax'
    'error in Estimate Tax'
  end

  def ping
    logger.info 'Ping Call'
    self.estimate_tax({ latitude: '40.714623', longitude: '-74.006605'}, 0)
  end

  protected

  def logger
    AvataxHelper::AvataxLog.new('tax_svc', 'tax_service', 'call to tax service')
  end

  private

  def tax_calculation_enabled?
    Spree::Config.avatax_tax_calculation
  end

  def credential
    'Basic ' + Base64.encode64(account_number.to_s + ':' + license_key)
  end

  def service_url
    Spree::Config.avatax_endpoint + AVATAX_SERVICEPATH_TAX
  end

  def license_key
    Spree::Config.avatax_license_key
  end

  def account_number
    Spree::Config.avatax_account
  end

  def response(uri, request_hash)
    RestClient::Request.execute(method: :post,
                                timeout: service_timeout,
                                open_timeout: service_open_timeout,
                                url: service_url + uri,
                                payload: JSON.generate(request_hash),
                                headers: {
                                  authorization: credential,
                                  content_type: 'application/json'
                                }) do |response, _request, _result|
      response
    end
  end

  def service_timeout
    Spree::Config.avatax_read_timeout.presence&.to_f || 10
  end

  def service_open_timeout
    Spree::Config.avatax_open_timeout.presence&.to_f || 5
  end

  def log(method, request_hash = nil)
    logger.info method.to_s + ' call'
    unless request_hash.nil?
      logger.debug request_hash
      logger.debug JSON.generate(request_hash)
    end
  end
end
