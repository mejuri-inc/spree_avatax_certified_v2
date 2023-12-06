module SpreeAvataxCertified
  class Line
    include AvataxHelper
    attr_reader :order, :invoice_type, :lines, :stock_locations, :return_authorization

    def initialize(order, invoice_type, return_authorization=nil,bill_address)
      @logger ||= AvataxHelper::AvataxLog.new('avalara_order_lines', 'SpreeAvataxCertified::Line', 'building lines')
      @order = order
      @bill_address = bill_address
      @invoice_type = invoice_type
      @lines = []
      @return_authorization = return_authorization
      @stock_locations = order_stock_locations
      build_lines
    end

    def build_lines
      @logger.info('build lines')

      if invoice_type == 'ReturnInvoice' || invoice_type == 'ReturnOrder'
        return_authorization_lines
      else
        item_lines_array
        shipment_lines_array
      end
    end

    def item_line(line_item)
      avatax_address = SpreeAvataxCertified::Address.new(order,line_item,@bill_address)

      {
        number: "#{line_item.id}-LI",
        description: line_item.name[0..255],
        taxCode: line_item.tax_category.try(:description) || 'P0000000',
        itemCode: line_item.variant.sku,
        quantity: line_item.quantity,
        amount: line_item.discounted_amount.to_f,
        entityUseCode: customer_usage_type,
        discounted: true,
        addresses: avatax_address.address,
        taxIncluded: tax_included_in_price?(line_item)
      }
    end

    def item_lines_array
      @logger.info('build line_item lines')
      line_item_lines = []

      order.line_items.each do |line_item|
        line_item_lines << item_line(line_item)
      end

      @logger.info_and_debug('item_lines_array', line_item_lines)

      lines.concat(line_item_lines) unless line_item_lines.empty?
      line_item_lines
    end

    def shipment_lines_array
      @logger.info('build shipment lines')

      ship_lines = []
      order.shipments.each do |shipment|
        if shipment.tax_category
          ship_lines << shipment_line(shipment)
        end
      end

      @logger.info_and_debug('shipment_lines_array', ship_lines)
      lines.concat(ship_lines) unless ship_lines.empty?
      ship_lines
    end

    def shipment_line(shipment)
      {
        number: "#{shipment.id}-FR",
        itemCode: shipment.shipping_method.name,
        quantity: 1,
        amount: shipment.discounted_amount.to_f,
        entityUseCode: customer_usage_type,
        description: 'Shipping Charge',
        taxCode: shipment.shipping_method_tax_code,
        discounted: false,
        taxIncluded: tax_included_in_price?(shipment)
      }
    end

    def return_authorization_lines
      @logger.info('build return return_authorization lines')

      return_auth_lines = []

      order.return_authorizations.each do |return_auth|
        next if return_auth != return_authorization
        amount = return_auth.amount / return_auth.inventory_units.select(:line_item_id).uniq.count
        return_auth.inventory_units.group_by(&:line_item_id).each_value do |inv_unit|
          quantity = inv_unit.uniq.count
          return_auth_lines << return_item_line(inv_unit.first.line_item, quantity, amount)
        end
      end

      @logger.info_and_debug('return_authorization_lines', return_auth_lines)
      lines.concat(return_auth_lines) unless return_auth_lines.empty?
      return_auth_lines
    end

    def return_item_line(line_item, quantity, amount)
      @logger.info("build return_line_item line: #{line_item.name}")

      avatax_address = SpreeAvataxCertified::Address.new(@order,line_item,@bill_address)

      line = {
        :number => "#{line_item.id}-LI",
        :description => line_item.name[0..255],
        :taxCode => line_item.tax_category.try(:description) || 'P0000000',
        :itemCode => line_item.variant.sku,
        :quantity => quantity,
        :amount => -amount.to_f,
        :addresses => avatax_address.address,
        :entityUseCode => order.user ? order.user.avalara_entity_use_code.try(:use_code) : '',
        :taxIncluded => true
      }

      tax_override = {
        type: 'TaxAmount',
        reason: 'Return',
        taxAmount: -return_line_item_taxes(line_item, quantity)
      }

      line[:taxOverride] = tax_override

      @logger.debug line

      line
    end

    def order_stock_locations
      @logger.info('getting stock locations')

      stock_location_ids = stock_location_ids_from_order(order)
      stock_locations = Spree::StockLocation.where(id: stock_location_ids)
      @logger.debug stock_locations
      stock_locations
    end

    def get_stock_location(line_item)
      line_item_stock_locations = @stock_locations.joins(:stock_items).where(spree_stock_items: {variant_id: line_item.variant_id})

      if line_item_stock_locations.empty?
        'Orig'
      else
        "#{line_item_stock_locations.first.id}"
      end
    end

    def tax_included_in_price?(item)
      if item.tax_category.present?
        order.tax_zone.tax_rates.where(tax_category: item.tax_category).try(:first).try(:included_in_price)
      else
        order.tax_zone.tax_rates.try(:first).try(:included_in_price)
      end
    end

    def customer_usage_type
      order.user ? order.user.avalara_entity_use_code.try(:use_code) : ''
    end

    def return_line_item_taxes(line_item, quantity)
      total_tax_amount = line_item.additional_tax_total + line_item.included_tax_total
      (total_tax_amount * (quantity.to_f / line_item.quantity)).to_f
    end
  end
end
