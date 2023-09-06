require 'logger'

Spree::Order.class_eval do

  has_one :avalara_transaction, dependent: :destroy

  def avalara_eligible?
    Spree::Config.avatax_iseligible
  end

  def cancel_avalara
    return nil unless avalara_transaction.present?
    self.avalara_transaction.cancel_order
  end

  def avalara_capture
    logger.debug 'avalara capture'
    create_avalara_transaction if avalara_transaction.nil?
    line_items.reload

    @rtn_tax = self.avalara_transaction.commit_avatax('SalesOrder')

    logger.info_and_debug('tax amount', @rtn_tax)
    @rtn_tax
  end

  def avalara_capture_finalize
    logger.debug 'avalara capture finalize'
    create_avalara_transaction if avalara_transaction.nil?
    line_items.reload
    @rtn_tax = avalara_transaction.commit_avatax_final('SalesInvoice')
    save_line_tax_breakdown @rtn_tax['lines'] unless @rtn_tax['lines'].nil?
    logger.info_and_debug('tax amount', @rtn_tax)
    @rtn_tax
  end

  def avatax_cache_key
    key = ['Spree::Order']
    key << self.number
    key.join('-')
  end

  def save_line_tax_breakdown tax_lines
    tax_lines.each do |tax_line|
      line_item = Spree::LineItem.find(tax_line['lineNumber'].sub('-LI', ''))
      next if line_item.nil?
      tax = line_item.adjustments.tax.first
      return if tax.nil?

      tax.meta[:tax_breakdown] = tax_line['details']
      tax.save
    end
  end

  private

  def logger
    @logger ||= AvataxHelper::AvataxLog.new('avalara_order', 'order class', 'start order processing')
  end
end
