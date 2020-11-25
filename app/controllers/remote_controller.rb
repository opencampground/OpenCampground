class RemoteController < ApplicationController
  include MyLib
  before_filter :cookies_required, :only => [:index ]
  before_filter :check_for_remote
  before_filter :proceed, :except => [:index, :finished]
  before_filter :startup, :except => [:finished]
  # before_filter :check_for_remote2, :except => [:index, :finished]
  before_filter :check_dates, :only => [:find_space, :update_dates, :change_space]
  before_filter :cleanup_abandoned, :only => [:index, :change_dates, :change_space]
  in_place_edit_for :reservation, :adults
  in_place_edit_for :reservation, :pets
  in_place_edit_for :reservation, :kids
  in_place_edit_for :reservation, :length
  in_place_edit_for :reservation, :slides
  in_place_edit_for :reservation, :rig_age
  in_place_edit_for :reservation, :special_request
  in_place_edit_for :reservation, :rigtype_id

  def index
    @page_title = I18n.t('titles.new_res')
    debug 'In remote index'
    session[:proceed] = 'proceed'
    session[:remote] = true
    session[:controller] = :remote
    session[:action] = :index
    ####################################################
    # new reservation.  Just make available all of
    # the fields needed for a reservation
    ####################################################
    flash.now[:error] = params[:flash] if params[:flash]
    @extras = Extra.for_remote
    begin
      @prompt = Prompt.find_by_display_and_locale!('index', I18n.locale.to_s)
    rescue
      @prompt = Prompt.find_by_display_and_locale('index', 'en')
    end
    if session[:reservation_id]
      begin
        @reservation = Reservation.find session[:reservation_id].to_i
	debug "loaded reservation #{session[:reservation_id]} from session"
      rescue
        # reservation in session is not available
	# error 'Could not find reservation that is in session'
	@reservation = Reservation.new
	session[:reservation_id] = nil
	sd = currentDate
	if Blackout.count > 0
	  sd = Blackout.available(sd, sd +1)
	end
	@reservation.startdate = sd
	@reservation.enddate = sd + 1
	closed_start, closed_end, open = Campground.closed_dates(@reservation.startdate, @reservation.enddate)
	unless open
	  @reservation.startdate = Campground.next_open
	  @reservation.enddate = @reservation.startdate + 1
	end
      end
    else
      @reservation = Reservation.new
      session[:reservation_id] = nil
      sd = currentDate
      if Blackout.count > 0
	sd = Blackout.available(sd, sd +1)
      end
      @reservation.startdate = sd
      @reservation.enddate = sd + 1
      closed_start, closed_end, open = Campground.closed_dates(@reservation.startdate, @reservation.enddate)
      unless open
	@reservation.startdate = Campground.next_open
	@reservation.enddate = @reservation.startdate + 1
      end
    end
    if @option.use_reserve_by_wk?
      y,w,d = Date::jd_to_commercial(Date::civil_to_jd(@reservation.startdate.year,
                                                       @reservation.startdate.month,
                                                       @reservation.startdate.day))
      session[:count] = 0
      session[:number] = w
      session[:year] = y
    end
    session[:startdate] = @reservation.startdate
    session[:enddate] = @reservation.enddate
    @seasonal_ok = false
    session[:day] = @reservation.startdate.day.to_s
    session[:month] = @reservation.startdate.month.to_s
    session[:year] = @reservation.startdate.year.to_s
    if @option.show_remote_available?
      @count = Space.available( @reservation.startdate, @reservation.enddate, 0).size
      debug @count.to_s + ' sites available'
    else
      @count = 0
    end
    @extras = Extra.for_remote
  rescue => err
    error err.to_s
  end

  def payment
    @reservation = get_reservation
    if (@option.require_gateway? || @option.allow_gateway?) && (@reservation.total + @reservation.tax_amount) > 0.0
      debug 'gateway used'
      info "mobile is #{@mobile}"
      info "user agent is #{request.user_agent}"
      @deposit = @reservation.deposit_amount
      @integration = Integration.first
      begin
	@gateway = @integration.name
      rescue
	debug 'in rescue, @gateway is None'
	error 'configuration error.  Gateway not set up'
	@gateway = 'None'
	redirect_to :action => :confirmation and return
      end
      if @gateway == 'PayPal' || @gateway == 'PayPal_r'
        @paypal_transaction = PaypalTransaction.new :reservation_id => @reservation.id
      end
    else
      debug 'no gateway used, @gateway is none'
      @gateway = 'None'
      redirect_to :action => :confirmation and return
    end
    name,d1,d2 = @gateway.partition('_')
    name += '-a' if @option.allow_gateway?
    name += '-payment'
    debug "prompt name is #{name}"
    begin
      @prompt = Prompt.find_by_display_and_locale!(name, I18n.locale.to_s)
    rescue
      @prompt = Prompt.find_by_display_and_locale(name, 'en')
    end
    # debug @prompt.inspect
    debug '@gateway is ' + @gateway
  rescue => err
    error err.to_s
  end

  def abandon_remote
    res = get_reservation
    if res.confirm?
      # do not destroy
    else
      res.destroy
    end
  rescue => err
    info err.to_s
  ensure
    redirect_to :controller => :remote, :action => :finished and return
  end


  def confirmation
    debug
    @page_title = I18n.t('titles.ConfirmRes')
    @extras = Extra.for_remote
    @reservation = get_reservation
    @reservation.add_log("remote reservation made")
    @reservation.camper.active
    if @option.remote_auto_accept?
      debug 'doing remote auto accept'
      @reservation.update_attributes :confirm => true, :unconfirmed_remote => false
      @reservation.add_log("automatic accept")
      # check camper in if date <= today and remote_auto_checkin
      # do not do an auto_checkin unless auto_accept
      if @reservation.startdate <= currentDate && @option.auto_checkin_remote?
	debug "doing automatic checkin"
	@reservation.checked_in = true
	@reservation.add_log("automatic checkin")
      end
    else
      # the confirm => true may be redundant CC and PP differ in handling
      @reservation.update_attributes :confirm => true, :unconfirmed_remote => true
    end
    @payments = Payment.find_all_by_reservation_id @reservation.id
    recalculate_charges
    @deposit = @reservation.deposit_amount
    begin
      @prompt = Prompt.find_by_display_and_locale!('confirmation', I18n.locale.to_s)
    rescue
      @prompt = Prompt.find_by_display_and_locale('confirmation', 'en')
    end

    # send confirmation emails
    @reservation.save!
    if @option.use_confirm_email?
      if Email.address_valid?(@reservation.camper.email)
	debug 'send confirmation emails'
	begin
	  if @reservation.unconfirmed_remote? 
	    email = ResMailer.deliver_remote_reservation_received(@reservation)
	  else
	    # already accepted.  Must have been auto accept
	    email = ResMailer.deliver_remote_reservation_confirmation(@reservation)
	  end
	rescue => err
	  error err.to_s
	end
      end
    end
    reset_session
    render :action => :show
  rescue ActiveRecord::RecordNotFound
    error "could not find reservation #{session[:reservation_id]}"
    reset_session
    flash[:error] = 'Error in process, starting over'
    redirect_to :controller => :remote, :action => :index and return
  rescue => err
    error err.to_s
    reset_session
    flash[:error] = 'Error in process, starting over'
    redirect_to :controller => :remote, :action => :index and return
  end

  def confirm_without_payment
    debug
    @page_title = I18n.t('titles.ConfirmRes')
    begin
      @prompt = Prompt.find_by_display_and_locale!('confirmation', I18n.locale.to_s)
    rescue
      @prompt = Prompt.find_by_display_and_locale('confirmation', 'en')
    end
    @extras = Extra.for_remote
    @reservation = get_reservation
    @reservation.add_log("remote reservation made")
    @reservation.camper.active
    if @option.remote_auto_accept?
      debug "doing auto accept"
      @reservation.update_attributes :confirm => true, :unconfirmed_remote => false
      @reservation.add_log("automatic accept")
      # check camper in if date <= today and remote_auto_checkin
      # auto_checkin requires auto accept
      if @reservation.startdate <= currentDate && @option.auto_checkin_remote?
	debug "doing automatic checkin"
	@reservation.checked_in = true
	@reservation.add_log("automatic checkin")
      end
    else
      @reservation.update_attributes :confirm => true, :unconfirmed_remote => true
    end
    @payments = Payment.find_all_by_reservation_id @reservation.id
    recalculate_charges
    @reservation.save!
    @deposit = @reservation.deposit_amount
    # send confirmation emails
    if @option.use_confirm_email?
      if Email.address_valid?(@reservation.camper.email)
	debug 'send confirmation emails'
	begin
	  email = ResMailer.deliver_remote_reservation_received(@reservation)
	rescue => err
	  error 'problem in mail delivery ' + err.to_s
	end
      end
    end
    reset_session
    render :action => :show
  rescue ActiveRecord::RecordNotFound
    error "could not find reservation #{session[:reservation_id]}"
    reset_session
    flash[:error] = 'Error in process, starting over'
    redirect_to :controller => :remote, :action => :index and return
  rescue => err
    error 'other: ' + err.to_s
    flash.now[:error] = 'Error in reservation process'
    render :action => :show
  end

  def space_selected
    @page_title = I18n.t('titles.ReviewRes')
    ####################################################
    # the space has been selected, now compute the total
    # charges and fetch info for display and completion
    ####################################################
    # debug "locale is #{I18n.locale}"
    @extras = Extra.for_remote
    begin
      @prompt = Prompt.find_by_display_and_locale!('show', I18n.locale.to_s)
    rescue
      @prompt = Prompt.find_by_display_and_locale('show', 'en')
    end
    @reservation = get_reservation

    # if we are changing dates we will not have a space in params
    if params[:space_id] && @reservation
      @space = Space.find(params[:space_id].to_i)
      @reservation.space_id = params[:space_id].to_i
    end
    spaces = Space.confirm_available(@reservation.id, @reservation.space_id, @reservation.startdate, @reservation.enddate)
    debug "#{spaces.size} spaces in conflict"
    if spaces.size > 0
      error 'space conflict'
      reset_session
      # flash[:error] = 'Conflicting reservation for space, select again'
      @reservation.destroy
      redirect_to(:action => :index, :flash => 'Conflicting reservation for space, select again') and return
    end
    check_length @reservation
    @reservation.save
    recalculate_charges
    ####################################################
    # calculate charges
    ####################################################
    if @option.require_gateway? || @option.allow_gateway?
      @formatted_total = number_2_currency(@reservation.total)
      begin
	@gateway = Integration.first.name
      rescue
        @gateway = 'None'
      end
    else
      @gateway = 'None'
    end
    @deposit = @reservation.deposit_amount
    debug "@deposit isa #{@deposit.class.to_s}"
    debug "@deposit: #{@deposit.inspect}"
    # session[:reservation_id] = @reservation.id
    render :action => :show
  rescue => err
    error err.to_s
  end

  def find_space
    @page_title = I18n.t('titles.SelSpace')
    ####################################################
    # given the parameters specified find all spaces not
    # already reserved that fit the spec and supply data
    # for presentation
    # We will save the data selected the first time
    # in the session to be used when we advance from
    # page to page.
    ####################################################
    
    begin
      @prompt = Prompt.find_by_display_and_locale!('find_space', I18n.locale.to_s)
    rescue
      @prompt = Prompt.find_by_display_and_locale('find_space', 'en')
    end
    if session[:reservation_id]
      @reservation = get_reservation
      debug "Existing reservation ##{@reservation.id}"
    else 
      redirect_to :action => :index and return unless params[:reservation]
      @reservation = Reservation.new(params[:reservation])
      debug 'New reservation'
      debug "sitetype #{@reservation.sitetype_id} initially from reservation" if @reservation.sitetype_id
    end
    @reservation.startdate = @date_start
    @reservation.enddate = @date_end
    @reservation.unconfirmed_remote = true
    if @reservation.startdate < currentDate
      flash.now[:error] = I18n.t('general.Flash.WrongStart')
      @reservation.startdate = currentDate
      @reservation.enddate = @reservation.startdate + 1 if @reservation.enddate <= @reservation.startdate
    end
    closed_start, closed_end, open = Campground.closed_dates(@reservation.startdate, @reservation.enddate)
    unless open
      debug 'Campground closed'
      reset_session
      flash[:error] = I18n.t('reservation.Flash.SpaceUnavailable') +
		      '<br />' +
		      I18n.t('reservation.Flash.ClosedDates',
			  :closed => DateFmt.format_date(closed_start),
			  :open => DateFmt.format_date(closed_end))
      redirect_to :action => :index and return
    end
    debug 'Campground open'
    @reservation.discount_id ||= 1
    @reservation.save!
    @reservation.reload
    session[:reservation_id] = @reservation.id
    # destroy old extra charges if any
    ExtraCharge.find_all_by_reservation_id(@reservation.id).each {|e| e.destroy}
    if params[:extra]
      extras = Extra.active
      extras.each do |e|
	ex_key = "extra#{e.id}".to_sym
	ct_key = "count#{e.id}".to_sym
	
	debug "looking for #{e.id} with keys #{ex_key} and #{ct_key}"
	#if params[:extra].key?("extra#{ex.id}".to_sym) && (params[:extra]["extra#{ex.id}".to_sym] != '0')
	if (params[:extra].key?(ex_key) && (params[:extra][ex_key] != '0')) 
	  debug "found extra #{e.id} and it is true"
	  @reservation.extras << e
	  debug "added extra #{e.id}"
	  ec=ExtraCharge.first(:conditions => [ "extra_id = ? and reservation_id = ?", 
						e.id, @reservation.id] )
	  if e.extra_type == Extra::COUNTED || e.extra_type == Extra::OCCASIONAL
	    debug "extra count is #{params[:extra][ct_key]}"
	    ec.save_charges((params[:extra][ct_key]).to_i)
	    debug "counted value #{e.id}, value is #{ec.number}"
	  else
	    ec.save_charges( 0 )
	  end
	else
	  debug "not found extra #{e.id}"
	end
      end
    end
    @spaces = remote_for_display(@reservation)
    @map =  '/map/' + @option.remote_map if @option.remote_map && !@option.remote_map.empty? && @option.use_remote_map?
    unless @spaces.size > 0
      reset_session
      flash[:error] = "No spaces are available that meet your criteria.  Please change dates or site type and try again"
      redirect_to :action => :index and return
    end
    debug "@reservation.id = #{@reservation.id}"
  rescue => err
    error err.to_s
    reset_session
    flash[:error] = err.to_s
    redirect_to :action => :index and return
  end

  def change_dates
    @page_title = I18n.t('titles.ChangeDates')
    @reservation = get_reservation
    @extras = Extra.for_remote
    @seasonal_ok = false
    @available_str = @reservation.get_possible_dates(true)
    session[:early_date] = @reservation.early_date
    session[:late_date] = @reservation.late_date
    session[:startdate] = @reservation.startdate
    session[:enddate] = @reservation.enddate
    session[:day] = @reservation.startdate.day.to_s
    session[:month] = @reservation.startdate.month.to_s
    session[:year] = @reservation.startdate.year.to_s
    session[:canx_action] = session[:action]
  rescue => err
    error err.to_s
    reset_session
    flash[:error] = 'Error in change dates. Start over'
    redirect_to :action => :index and return
  end

  def select_change
    ####################################################
    # get reservation info for selecting new space
    ####################################################
    @page_title = I18n.t('titles.DateSel')

    @reservation = get_reservation
    @seasonal_ok = false
    @count  = Space.available( @reservation.startdate, @reservation.enddate, @reservation.sitetype_id.to_i).size if @option.show_remote_available?
  rescue => err
    error err.to_s
    reset_session
    flash[:error] = 'Error in select_change. Start over'
    redirect_to :action => :index and return
  end
  
  def change_space
    @page_title = I18n.t('titles.ChangeSpace')
    ####################################################
    # given the parameters specified find all spaces not
    # already reserved that fit the spec and supply data
    # for presentation
    ####################################################
    
    @reservation = get_reservation
    # these dates come from application_controller
    session[:startdate] = @date_start
    session[:enddate] = @date_end
    session[:desired_type] = (params[:reservation][:sitetype_id]).to_i
    debug "desired type = #{session[:desired_type]}"
    session[:day] = @reservation.startdate.day.to_s
    session[:month] = @reservation.startdate.month.to_s
    session[:year] = @reservation.startdate.year.to_s
    @spaces = remote_for_display(@reservation)
  rescue => err
    error err.to_s
    reset_session
    flash[:error] = 'Error in change_space. Start over'
    redirect_to :action => :index and return
  end
  
  def space_changed
    ####################################################
    # update the reservation
    ####################################################
    
    @reservation = get_reservation
    @reservation.space_id = params[:space_id].to_i
    @reservation.startdate = session[:startdate]
    @reservation.enddate = session[:enddate]
    @reservation.sitetype_id = session[:desired_type]
    spaces = Space.confirm_available(@reservation.id, @reservation.space_id, @reservation.startdate, @reservation.enddate)
    debug "#{spaces.size} spaces in conflict"
    if spaces.size > 0
      error 'space conflict'
      reset_session
      flash[:error] = "Conflicting reservation for space, select again"
      redirect_to :action => :select_change and return
    end
    check_length @reservation
    @reservation.save
    recalculate_charges
    ####################################################
    # calculate charges
    ####################################################
    redirect_to :action => :space_selected and return
  rescue => err
    error err.to_s
    reset_session
    flash[:error] = 'Error in space_changed. Start over ' + err.to_s
    redirect_to :action => :index and return
  end
  
  def finished
    reset_session
  rescue => err
    error err.to_s
  ensure
    if @option.home.blank?
      render :inline => '<h1>Reservation completed.  Please close this window.</h1>'
    else
      redirect_to @option.home and return
    end
  end

  ####################################################
  # methods called from observers
  ####################################################

  def update_recommend
    if params[:recommender_id]
      begin
	@reservation = get_reservation
      rescue ActiveRecord::RecordNotFound
	error "cannot find reservation #{session[:reservation_id]}"
	render(:nothing => true) and return
      end
      @reservation.update_attributes :recommender_id => params[:recommender_id].to_i
    end
    render(:nothing => true)
  rescue => err
    error err.to_s
  end

  def update_rigtype
    if params[:rigtype_id]
      begin
	@reservation = get_reservation
      rescue ActiveRecord::RecordNotFound
	error "cannot find reservation #{session[:reservation_id]}"
	render(:nothing => true) and return
      end
      @reservation.update_attributes :rigtype_id => params[:rigtype_id].to_i
    end
    render(:nothing => true)
  rescue => err
    error err.to_s
  end

  def update_discount
    if params[:discount_id]
      begin
	@reservation = get_reservation
      rescue ActiveRecord::RecordNotFound
	error "cannot find reservation #{session[:reservation_id]}"
	render(:nothing => true) and return
      end
      @reservation.update_attributes :discount_id => params[:discount_id].to_i
      recalculate_charges
      @deposit = @reservation.deposit_amount
      render :update do |page|
	page[:charges].reload
      end
    else
      render(:nothing => true)
    end
  rescue => err
    error err.to_s
  end

  def update_counted
    if params[:extra_id]
      extra_id = params[:extra_id].to_i
      debug "extra_id is #{extra_id}"
      cnt = "count_#{extra_id}".to_sym
      render :update do |page|
	if params[:number].to_i == 1
	  # debug "show"
	  page[cnt].show
	else
	  # debug "hide"
	  page[cnt].hide
	end
      end
    else
      render(:nothing => true)
    end
  rescue => err
    error err.to_s
  end

  def update_extras
    if params[:extra]
      debug "in update_extras"
      begin
	@reservation = get_reservation
      rescue ActiveRecord::RecordNotFound
	error "cannot find reservation #{session[:reservation_id]}"
	render(:nothing => true) and return
      end
      extra = Extra.find params[:extra].to_i
      debug "extra_type is #{extra.extra_type.to_s}"
      case extra.extra_type
      when Extra::MEASURED
	debug 'extra is MEASURED'
      when Extra::OCCASIONAL, Extra::COUNTED, Extra::DEPOSIT
	debug 'extra COUNTED or OCCASIONAL or DEPOSIT'
	if (ec = ExtraCharge.find_by_extra_id_and_reservation_id(extra.id, @reservation.id))
	  # extra charge currently is applied so we have dropped it
	  ec.destroy
	  hide = true
	  debug "destroyed entity"
	else
	  # extra charge is not currently applied
	  # extra was added, apply it
	  # start out with a value of 1
	  ec = ExtraCharge.create :reservation_id => @reservation.id, 
				  :extra_id => extra.id,
				  :number => 1
	  hide = false
	  debug "created new entity"
	end
      else
	debug 'extra STANDARD'
	if (ec = ExtraCharge.find_by_extra_id_and_reservation_id(extra.id, @reservation.id))
	  # extra charge currently is applied so we have dropped it
	  ec.destroy
	  hide = true
	  debug "destroyed entity, hiding"
	else
	  # extra charge is not currently applied
	  # extra was added, apply it
	  ec = ExtraCharge.create :reservation_id => @reservation.id,
				  :extra_id => extra.id
	  hide = false
	  debug "created new entity, unhiding"
	end
      end
      @skip_render = true
      recalculate_charges
      debug "recalculated charges"
      @deposit = @reservation.deposit_amount
      debug "saved reservation"
      cnt = "count_#{extra.id}".to_sym
      ext = "extra#{extra.id}".to_sym
      render :update do |page|
	case extra.extra_type
	when Extra::COUNTED, Extra::OCCASIONAL
	  # debug "counted"
	  if hide
	    # debug "hide"
	    page[cnt].hide
	  else
	    # debug "show"
	    page[cnt].show
	  end
	when Extra::MEASURED
	  debug "measured"
	end
	# debug "reload charges"
	page[:charges].reload
      end
    end
    # render(:nothing => true)
  rescue => err
    error err.to_s
  end

  def update_count
    if params[:extra_id] 
      extra_id = params[:extra_id].to_i
      begin
	@reservation = get_reservation
      rescue ActiveRecord::RecordNotFound
	error "cannot find reservation #{session[:reservation_id]}"
	render(:nothing => true) and return
      end
      ec = ExtraCharge.first(:conditions => ["EXTRA_ID = ? and RESERVATION_ID = ?",
					    extra_id, @reservation.id])
      debug "updating count to #{params[:number].to_i}"
      ec.update_attributes :number => params[:number].to_i
    
      @skip_render = true
      recalculate_charges
      debug "recalculated charges"
      @deposit = @reservation.deposit_amount
      # render :partial => 'space_summary', :layout => false
      # debug "rendered space_summary"
      render :update do |page|
	# debug "reload charges"
        page[:charges].reload
      end
    else
      render(:nothing => true)
    end
  rescue => err
    error err.to_s
  end

  def to_pp
    # make sure the reservation still exists before we send out
    reservation = Reservation.find params[:id].to_i
    render :layout => false
  rescue => err
    info err.to_s
    flash[:error] = "The reservation has been canceled or it has timed out from inactivity.\nThe reservation process will Start Over."
    redirect_to :action => :index
  end

  private
  ####################################################
  # methods that cannot be called externally
  ####################################################

  def check_length res
    if  res.space.length > 0 &&
	res.length &&
	res.length > res.space.length
	  flash[:warning] = I18n.t('reservation.Flash.CamperLong',
				    :camper_length => res.length,
				    :space_length => res.space.length)
    end
  end

  def check_for_remote2
    redirect_to :action => :finished and return unless session[:remote]
  rescue => err
    error err.to_s
  end

  def remote_for_display(res)
    @season = Season.find_by_date(res.startdate)
    debug "season is #{@season.id}"
    spaces = Array.new
    if session[:desired_type]
      dt = session[:desired_type]
    else
      dt = res.sitetype_id
    end
    debug "sitetype_id is #{dt}"
    av_spaces = Space.available_remote(res.startdate,
				     res.enddate,
				     dt.to_i) 
    debug "found #{av_spaces.size} spaces from available"
    av_spaces.each_index do |ix|
      debug "checking #{av_spaces[ix].name}"
      if Rate.find_current_rate(@season.id, av_spaces[ix].price_id).no_rate?(res.enddate - res.startdate)
	debug "deleting #{av_spaces[ix].name}"
	av_spaces.delete_at ix
      else
	debug "keeping #{av_spaces[ix].name}"
      end
    end
    debug "found #{av_spaces.size} spaces before compact"
    spaces = av_spaces.compact
    debug "found #{spaces.size} spaces"
    return spaces
  rescue => err
    error err.to_s
  end

  def check_for_remote
    debug 'check_for remote:'
    unless @option.use_remote_reservations?
      redirect_to '/404.html' and return
    end
  rescue => err
    error err.to_s
  end

  def recalculate_charges
    @reservation = get_reservation unless defined?(@reservation)
    # calculate charges
    Charges.new(@reservation.startdate,
		@reservation.enddate,
		@reservation.space.price.id,
		@reservation.discount_id,
		@reservation.id,
		@reservation.seasonal)
    @charges = Charge.stay(@reservation.id)
    total = 0.0
    @charges.each { |c| total += c.amount - c.discount }
    total += calculate_extras(@reservation.id)
    tax_amount = Taxrate.calculate_tax(@reservation.id, @option)
    @reservation.total = total
    @reservation.tax_amount = tax_amount
    @tax_records = Tax.find_all_by_reservation_id(@reservation.id)
    begin
      unless @reservation.save
	flash.now[:error] = 'Problem updating reservation'
      end
    rescue ActiveRecord::StaleObjectError => err
      error err.to_s
      locking_error(@reservation)
    end
  rescue => err
    error err.to_s
  end

  def get_reservation
    if params[:reservation_id]
      reservation = Reservation.find params[:reservation_id]
      debug 'loaded reservation from params'
    elsif session[:reservation_id]
      begin
	reservation = Reservation.find session[:reservation_id].to_i
	debug "get_reservation: loaded reservation #{session[:reservation_id]} from session"
      rescue ActiveRecord::RecordNotFound
	error "get_reservation: could not find reservation #{session[:reservation_id]}"
	session[:startdate] = nil
	session[:enddate] = nil
	session[:reservation_id] = nil
	flash[:error] = 'Error in process, reservation has been deleted. Starting over'
	redirect_to :controller => :remote, :action => :index # and return
      end
    else
      error 'get_reservation: no reservation id in session'
      reset_session
      flash[:error] = 'Error in process, starting over'
      redirect_to :controller => :remote, :action => :index and return
    end
    return reservation
  rescue => err
    error "get_reservation: #{err.to_s}"
    reset_session
    flash[:error] = 'Error in process, starting over'
    redirect_to :controller => :remote, :action => :index and return
  end

  def get_server_path
    request.protocol + request.host_with_port
  rescue => err
    error err.to_s
  end

end
