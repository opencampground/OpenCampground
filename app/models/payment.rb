class Payment < ActiveRecord::Base
  include MyLib

  belongs_to :creditcard
  belongs_to :reservation
  has_one    :card_transaction, :dependent => :delete
  has_one    :paypal_transaction, :dependent => :delete
  validates_presence_of :reservation_id

  # a virtual method for subtotal
  def subtotal
    @subtotal
  end

  def subtotal=(st)
    @subtotal = st
  end

  def before_save
    self.amount = 0.0 if self.amount.nil?
    self.cc_fee = 0.0 if self.cc_fee.nil?
    self.creditcard_id = 1 unless self.creditcard_id
    if defined? self.pmt_date
      self.pmt_date = currentDate unless self.pmt_date
    end
  end

  def self.total(res_id)
    tot = 0.0
    find_all_by_reservation_id(res_id).each { |p| tot += p.amount}
    return tot
  end

  def credit_card_no_obscured
    if credit_card_no.length > 4
      return 'xxxxxxxx'+credit_card_no.slice(-4,4)
    else
      return credit_card_no
    end
  end

  def taxes
    ###########################################
    # compute what portion of the charges
    # return the amount split into tax and net 
    ###########################################
    if (reservation.total + reservation.tax_amount) == amount
      ActiveRecord::Base.logger.debug "payment is full amount #{amount}"
      net = reservation.total
      tax = reservation.tax_amount
      ActiveRecord::Base.logger.debug "tax is #{tax} net is #{net}"
    elsif reservation.tax_amount > 0.0
      ActiveRecord::Base.logger.debug "tax amount is #{reservation.tax_amount} and total is #{reservation.total}"
      tax_rate = reservation.tax_amount.to_f/reservation.total.to_f
      ActiveRecord::Base.logger.debug "tax_rate is #{tax_rate} and amount is #{amount}"
      net = (amount.to_f/ (1.0 + tax_rate))
      tax = amount - net
      ActiveRecord::Base.logger.debug "tax is #{tax} net is #{net}"
    else # tax is <= 0.0
      ActiveRecord::Base.logger.debug "tax is <= 0 #{tax}"
      net = amount
      tax = 0.0
      ActiveRecord::Base.logger.debug "tax is #{tax} net is #{net}"
    end
    return net, tax
  rescue
    return amount, 0.0
  end
  
  private

  def exp_str
    if self.cc_expire
      self.cc_expire.strftime("%m/%y")
    else
      currentDate.strftime("%m/%y")
    end
  end

  def exp_str=(str)
    m,y = str.split /\//
    self.cc_expire = Date.new(y.to_i+2000, m.to_i, 1)
  rescue
    # in case the Date blows up do nothing
  end

  def amount_formatted=(str)
    ###########################################
    # save the formatted value
    ###########################################
    self.amount = str.gsub(/[^0-9.]/,'').to_i
  end

  def amount_formatted
    ###########################################
    # format the amount for display
    ###########################################
    option = Option.first
    n = number_2_currency(amount)
    return n
  end

  def deposit_formatted=(str)
    ###########################################
    # save the formatted value
    ###########################################
    self.deposit = str.gsub(/[^0-9.]/,'').to_i
  end
  
  def deposit_formatted
    ###########################################
    # format the deposit for display
    ###########################################
    option = Option.first
    n = number_2_currency(amount)
    return n
  end

end
