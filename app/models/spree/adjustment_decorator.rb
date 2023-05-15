Spree::Adjustment.class_eval do
  scope :not_tax, -> { where.not(source_type: 'Spree::TaxRate') }

  def avatax_cache_key
    key = ['Spree::Adjustment']
    key << self.id
    key << self.amount
    key.join('-')
  end

  def tax_breakdown
    meta[:tax_breakdown] unless meta[:tax_breakdown].nil?
    taxes = order.avalara_capture
    order.save_line_tax_breakdown taxes['TaxLines']
    meta[:tax_breakdown]
  end
end
