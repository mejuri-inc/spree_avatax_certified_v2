require 'logging'
require_dependency 'spree/order'

module Spree
  class AvalaraTransaction < ActiveRecord::Base
    AVALARA_TRANSACTION_LOGGER = AvataxHelper::AvataxLog.new('post_order_to_avalara', __FILE__)

    belongs_to :order
    belongs_to :return_authorization
    validates :order, presence: true
    validates :order_id, uniqueness: true
    has_many :adjustments, as: :source

    def lookup_avatax
      post_order_to_avalara(false, 'SalesOrder')
    end

    def commit_avatax(invoice_dt = nil, return_auth = nil)
      if tax_calculation_enabled?
        if %w(ReturnInvoice ReturnOrder).include?(invoice_dt)
          post_return_to_avalara(false, invoice_dt, return_auth)
        else
          post_order_to_avalara(false, invoice_dt)
        end
      else
        { TotalTax: '0.00' }
      end
    end

    def commit_avatax_final(invoice_dt = nil, return_auth = nil)
      if document_committing_enabled?
        if tax_calculation_enabled?
          if %w(ReturnInvoice ReturnOrder).include?(invoice_dt)
            post_return_to_avalara(true, invoice_dt, return_auth)
          else
            post_order_to_avalara(true, invoice_dt)
          end
        else
          { TotalTax: '0.00' }
        end
      else
        AVALARA_TRANSACTION_LOGGER.debug 'avalara document committing disabled'
        'avalara document committing disabled'
      end
    end

    def cancel_order
      cancel_order_to_avalara('SalesInvoice')
    end

    private

    def cancel_order_to_avalara(doc_type = 'SalesInvoice')
      AVALARA_TRANSACTION_LOGGER.info('cancel order to avalara')

      cancel_tax_request = {
        CompanyCode: Spree::Config.avatax_company_code,
        DocType: doc_type,
        DocCode: order.number,
        CancelCode: 'DocVoided'
      }

      mytax = TaxSvc.new
      cancel_tax_result = mytax.cancel_tax(cancel_tax_request)

      AVALARA_TRANSACTION_LOGGER.debug cancel_tax_result

      if cancel_tax_result == 'error in Tax'
        return 'Error in Tax'
      else
        return cancel_tax_result
      end
    end

    def post_order_to_avalara(commit = false, invoice_detail = nil)
      AVALARA_TRANSACTION_LOGGER.info('post order to avalara')
      avatax_line = SpreeAvataxCertified::Line.new(order, invoice_detail,bill_to_address)

      # Discount = General order discounts without line items discounts
      discount = order.adjustments.promotion.eligible.sum(:amount).abs
      discount = discount < 0 ? "0".to_s : discount.to_s
      gettaxes = {
          createTransactionModel:{
          code: order.number,
          totalDiscount:  discount,
          commit: commit,
          type: invoice_detail ? invoice_detail : 'SalesOrder',
          lines: avatax_line.lines
        }.merge(base_tax_hash)
      }

      AVALARA_TRANSACTION_LOGGER.debug gettaxes

      mytax = TaxSvc.new

      tax_result = mytax.get_tax(gettaxes)

      AVALARA_TRANSACTION_LOGGER.info_and_debug('tax result', tax_result)

      return { totalTax: '0.00' } if tax_result == 'error in Tax'

      tax_result if tax_result['code'] == order.number
    end

    def post_return_to_avalara(commit = false, invoice_detail = nil, return_auth = nil)
      AVALARA_TRANSACTION_LOGGER.info('starting post return order to avalara')

      avatax_line = SpreeAvataxCertified::Line.new(order, invoice_detail, return_auth,bill_to_address)

      taxoverride = {
        type: 'None',
        reason: 'Return',
        taxDate: order.completed_at.strftime('%F')
      }

      gettaxes = {
        adjustmentReason: 'ProductReturned',
        createTransactionModel:{
          code: order.number.to_s + '.' + return_auth.id.to_s,
          commit: commit,
          type: invoice_detail ? invoice_detail : 'ReturnOrder',
          lines: avatax_line.lines
          }.merge(base_tax_hash)
      }
      gettaxes[:taxOverride] = taxoverride

      AVALARA_TRANSACTION_LOGGER.debug gettaxes

      mytax = TaxSvc.new

      tax_result = mytax.get_tax(gettaxes)

      AVALARA_TRANSACTION_LOGGER.info_and_debug('tax result', tax_result)

      return { TotalTax: '0.00' } if tax_result == 'error in Tax'
      return tax_result if tax_result['ResultCode'] == 'Success'
    end

    def base_tax_hash
      doc_date = order.completed? ? order.completed_at.strftime('%F') : Date.today.strftime('%F')
      {
        customerCode: customer_code,
        date: doc_date,
        companyCode: Spree::Config.avatax_company_code,
        entityUseCode: customer_usage_type,
        exemptionNo: order.user.try(:exemption_number),
        referenceCode: order.number,
        DetailLevel: 'Tax'
      }
    end

    def customer_usage_type
      order.user ? order.user.avalara_entity_use_code.try(:use_code) : ''
    end

    def customer_code
      order.user ? order.user.id : order.email
    end

    def avatax_client_version
      AVATAX_CLIENT_VERSION || 'SpreeExtV2.4'
    end

    def document_committing_enabled?
      Spree::Config.avatax_document_commit
    end

    def tax_calculation_enabled?
      Spree::Config.avatax_tax_calculation
    end

    def bill_to_address
      origin = JSON.parse(Spree::Config.avatax_origin)
      {
        :line1 => origin['Address1'],
        :line2 => origin['Address2'],
        :city => origin['City'],
        :region => origin['Region'],
        :postalCode => origin['Zip5'],
        :country => origin['Country']
      }
    end
  end
end
