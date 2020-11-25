class Discount < ActiveRecord::Base
  has_many :reservations
  acts_as_list
  validate :either_or?
  validates_presence_of :name
  validates_uniqueness_of :name
  validates_numericality_of :discount_percent,
			    :greater_than_or_equal_to => 0.00,
			    :less_than_or_equal_to => 100.00
  before_destroy :check_use
  before_save :zap_nul
  before_validation :check_amounts

  # constants for how applied
  ONCE = 1
  PER_DAY = 2
  PER_WEEK = 3
  PER_MONTH = 4
  # constants for length and delay
  DAY = 1
  WEEK = 2
  MONTH = 3

  default_scope :order => :position
  named_scope :active, :conditions => ["active = ?", true]
  named_scope :for_remote, :conditions => ["active = ? and show_on_remote = ?", true, true]

  attr_accessor :_count

  def _duration_units
    units(duration_units)
  end

  def _delay_units
    units(delay_units)
  end

  def units(unit)
    case unit
    when DAY
      'day(s)'
    when WEEK
      'weeks(s)'
    when MONTH
      'month(s)'
    end
  end

  def charge(total, units = Charge::DAY, startdate = currentDate, count = 1)
    ActiveRecord::Base.logger.debug "Discount#charge called with total = #{total}, units = #{units}, count = #{count} _count = #{@_count}"
    ActiveRecord::Base.logger.debug "Discount#charge duration = #{self.duration}"
    # ActiveRecord::Base.logger.debug self.inspect
    val = 0.0

    # _count contains the number of days left in the discount
    @_count = self.duration unless @_count
    if self.duration == 0
      discount_duration = 0
    else
      if count >= @_count
	discount_duration = @_count
	@_count = 0
      else
	discount_duration = count
	@_count -= count
      end
      if units == Charge::DAY && discount_duration > 0
	enddate = startdate + discount_duration
	cur = startdate
	while cur < enddate
	  ActiveRecord::Base.logger.debug "#{cur.day} is #{self.send(cur.strftime("%A").downcase.to_sym)}"
	  unless self.send(cur.strftime("%A").downcase.to_sym)
	    ActiveRecord::Base.logger.debug "#{cur.day} not discounted"
	    discount_duration -= 1
	  end
	  cur = cur.succ
	end
      end
      ActiveRecord::Base.logger.debug "Discount#charge days to discount = #{discount_duration}, days left = #{@_count}"
    end

    # if this is a percent discount
    if discount_percent != 0.0 
      ActiveRecord::Base.logger.debug "Discount#charge percent discount #{discount_percent} discount_duration #{discount_duration} count is #{count}"
      case units
      when Charge::DAY 
	# ActiveRecord::Base.logger.debug "Discount#charge units = Charge::DAY"
	if duration_units == DAY && self.duration > 0 
	  ActiveRecord::Base.logger.debug "Discount#charge duration_units = DAY and disc_appl_daily is #{disc_appl_daily?}"
	  val =  total / count * discount_duration * discount_percent / 100.0 if disc_appl_daily
	  ActiveRecord::Base.logger.debug "#{val} = #{total}/#{count} * #{discount_duration} / 100.0"
	else
	  val =  total * discount_percent / 100.0 if disc_appl_daily
	  ActiveRecord::Base.logger.debug "#{val} = #{total} * #{discount_duration} / 100.0"
	end
      when Charge::WEEK
	# ActiveRecord::Base.logger.debug "Discount#charge units = Charge::WEEK"
	if duration_units == WEEK && self.duration > 0
	  val =  total / count * discount_duration * discount_percent / 100.0 if disc_appl_week
	else
	  val =  total * discount_percent / 100.0 if disc_appl_week
	end
      when Charge::MONTH
	# ActiveRecord::Base.logger.debug "Discount#charge units = Charge::MONTH"
	if duration_units == MONTH && self.duration > 0
	  val =  total / count * discount_duration * discount_percent / 100.0 if disc_appl_month
	else
	  val =  total * discount_percent / 100.0 if disc_appl_month
	end
      when Charge::SEASON
	val =  total * discount_percent / 100.0 if disc_appl_seasonal
      end
    # if this is an amount discount
    elsif amount > 0.0
      val = amount
      # ActiveRecord::Base.logger.debug "Discount#charge amount once #{val}"
    else # stated $/day discount
      ActiveRecord::Base.logger.debug "Discount#charge amount discount #{amount_daily}, weekly #{amount_weekly}, monthly #{amount_monthly} discount_duration #{discount_duration}"
      case units
      when Charge::DAY
	if duration_units == DAY && discount_duration > 0
	  val =  amount_daily * discount_duration if self.send(startdate.strftime("%A").downcase.to_sym)
	else
	  val =  amount_daily * count if self.send(startdate.strftime("%A").downcase.to_sym)
	end
	ActiveRecord::Base.logger.debug "Discount#charge amount discount daily #{val}"
      when Charge::WEEK
	ActiveRecord::Base.logger.debug "Discount#charge in weekly and disc_appl_week = #{disc_appl_week}"
	val =  amount_weekly * count
	ActiveRecord::Base.logger.debug "Discount#charge amount discount weekly #{val}"
      when Charge::MONTH
	ActiveRecord::Base.logger.debug "Discount#charge in monthly and disc_appl_month = #{disc_appl_month}, amount monthly = #{amount_monthly}, count = #{count}"
	val =  amount_monthly * count
	ActiveRecord::Base.logger.debug "Discount#charge amount discount monthly #{val}"
      when Charge::SEASON
        val =  amount
	# ActiveRecord::Base.logger.debug "Discount#charge amount discount season #{val}"
      else
        val =  amount
	# ActiveRecord::Base.logger.debug "Discount#charge amount discount other #{val}"
      end
    end
    ActiveRecord::Base.logger.debug "Discount#charge amount is #{val}"
    return val
  end
    
  def self.skip_seasonal?
    # true if no discounts apply to seasonal
    self.all.each {|d| return false if d.disc_appl_seasonal}
    return true
  end

private

  def zap_nul
    self.delay = 0 unless self.delay
    self.duration = 0 unless self.duration
  rescue
  end

  def either_or?
    if (discount_percent != 0.0) && ((amount + amount_daily + amount_weekly + amount_monthly) != 0.0)
      errors.add(:discount_percent, "specified and amount specified.  Can only have amount or percent not both")
    end
    if (amount != 0.0) && ((amount_daily + amount_weekly + amount_monthly) != 0.0)
      errors.add(:amount, "Once provided.  Cannot have daily, weekly or monthly if once is selected")
    end
    if (discount_percent != 0.0) && !(disc_appl_daily | disc_appl_week | disc_appl_month | disc_appl_seasonal)
      errors.add(:discount_percent, "specified and no applicability specified.  One of the applies to items must be selected")
    end
  end

  def check_use
    res = Reservation.find_all_by_discount_id id
    if res.size > 0
      lst = ''
      res.each {|r| lst << " #{r.id},"}
      errors.add "discount in use by reservation(s) #{lst}"
      return false
    end
  end

  def check_amounts
    self.amount ||= 0.0
    self.amount_daily ||= 0.0
    self.amount_weekly ||= 0.0
    self.amount_monthly ||= 0.0
    self.discount_percent ||= 0.0
  end
end
