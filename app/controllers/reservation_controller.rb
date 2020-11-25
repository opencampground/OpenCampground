class ReservationController < ApplicationController
  include MyLib
  include CalculationHelper
  before_filter :cookies_required, :only => [:list] # the first thing you get to
  before_filter :login_from_cookie
  before_filter :check_login
  before_filter :check_dates, :only => [:find_space, :update_dates, :change_space, :express_2]
  before_filter :set_defaults
  before_filter :cleanup_abandoned, :only => [:new, :express, :select_change, :change_space]
  in_place_edit_for :reservation, :adults
  in_place_edit_for :reservation, :pets
  in_place_edit_for :reservation, :kids
  in_place_edit_for :reservation, :length
  in_place_edit_for :reservation, :slides
  in_place_edit_for :reservation, :rig_age
  in_place_edit_for :reservation, :special_request
  in_place_edit_for :reservation, :rigtype_id
  in_place_edit_for :reservation, :vehicle_state
  in_place_edit_for :reservation, :vehicle_license
  in_place_edit_for :reservation, :vehicle_state_2
  in_place_edit_for :reservation, :vehicle_license_2

  def index
    ####################################################
    # we should never get here except by error
    ####################################################
    debug "entered from #{session[:controller]} #{session[:action]}"
    redirect_to :action => 'list'
  end

  def new
    @page_title = I18n.t('titles.new_res')
    ####################################################
    # new reservation.  Just make available all of
    # the fields needed for a reservation
    ####################################################

    session[:payment_id] = nil if session[:payment_id] 
    if params[:stage] == 'new'
      @reservation = Reservation.new
      @reservation.startdate = currentDate
      @reservation.enddate = @reservation.startdate + 1
      session[:reservation_id] = nil
      session[:payment_id] = nil
      session[:desired_type] = 0
    else
      begin
        @reservation = Reservation.find session[:reservation_id].to_i
        info "loaded reservation #{session[:reservation_id]} from session"
      rescue
        @reservation = Reservation.new
        @reservation.startdate = currentDate
        @reservation.enddate = @reservation.startdate + 1
      end
    end
    debug "checking for open #{@reservation.startdate} to #{@reservation.enddate}"
    closed_start, closed_end, open = Campground.closed_dates(@reservation.startdate, @reservation.enddate)
    unless open
      debug 'not open'
      flash.now[:warning] = I18n.t('reservation.Flash.ClosedDates', :closed => DateFmt.format_date(closed_start), :open => DateFmt.format_date(closed_end))
      @reservation.startdate = Campground.next_open
      @reservation.enddate = @reservation.startdate + 1
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
    @seasonal_ok = @option.use_seasonal?
    @storage_ok = @option.use_storage?
    # we will not save the res because if we will 
    # need it later it is already saved
    @count  = Space.available( @reservation.startdate, @reservation.enddate, session[:desired_type]).size if @option.show_available?
    @extras = Extra.active
    session[:canx_action] = 'abandon'
    session[:change] = false

  end

  def express
    @page_title = I18n.t('titles.express')
    ####################################################
    # new express reservation.  Just make available all of
    # the fields needed for a reservation
    ####################################################

    session[:payment_id] = nil
    session[:reservation_id] = nil
    @reservation = Reservation.new
    @reservation.startdate = currentDate
    @reservation.enddate = @reservation.startdate + 1
    closed_start, closed_end, open = Campground.closed_dates(@reservation.startdate, @reservation.enddate)
    unless open
      flash.now[:warning] = I18n.t('reservation.Flash.ClosedDates', :closed => DateFmt.format_date(closed_start), :open => DateFmt.format_date(closed_end))
      @reservation.startdate = Campground.next_open
      @reservation.enddate = @reservation.startdate + 1
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
    @storage_ok = false
    # we will not save the res because if we will 
    # need it later it is already saved
    @spaces  = Space.available( @reservation.startdate,
			        @reservation.enddate,
			        @reservation.sitetype_id)
    @count = @spaces.size
    @extras = Extra.active
    session[:canx_action] = 'abandon'
    session[:change] = false
  end

  def express_2
    unless params[:space] && params[:reservation]
      redirect_to :action => :express and return
    end
    # first time through
    @reservation = Reservation.new(params[:reservation])
    @reservation.startdate = @date_start
    @reservation.enddate = @date_end
    closed_start, closed_end, open = Campground.closed_dates(@reservation.startdate, @reservation.enddate)
    unless open
      flash[:error] = I18n.t('reservation.Flash.SpaceUnavailable') +
		      "<br />" +
		      I18n.t('reservation.Flash.ClosedDates', :closed => DateFmt.format_date(closed_start), :open => DateFmt.format_date(closed_end))
      redirect_to :action => :express and return
    end
    flash[:warning] = I18n.t('reservation.Flash.EarlyStart') if @reservation.startdate < currentDate
    @reservation.save!
    session[:reservation_id] = @reservation.id
    session[:startdate] = @reservation.startdate
    session[:enddate] = @reservation.enddate
    redirect_to :action => :space_selected, :space_id => params[:space][:space_id].to_i, :reservation_id => @reservation.id
  end

  def confirm_res
    ####################################################
    # save the camper in the reservation
    ####################################################
    # this is usually called from camper so the parameters contain a camper id
    
    @reservation = get_reservation
    @payments = Payment.find_all_by_reservation_id @reservation.id
    @payment = Payment.new :reservation_id => @reservation.id
    session[:payment_id] = nil
    @page_title = I18n.t('titles.ConfirmResId', :reservation_id => @reservation.id)
    if params[:camper_id]
      @reservation.update_attributes :camper_id =>  params[:camper_id].to_i
      @reservation.camper.active
    end
    if @option.use_variable_charge?
      @variable_charge = VariableCharge.new
      new_variable_charge if params[:variable_charge] && params[:variable_charge][:amount] != '0.0'
    end
    @skip_render = true
    @use_navigation = false
    @integration = Integration.first
    recalculate_charges
    @extras = Extra.active
    session[:current_action] = 'confirm_res'
    session[:canx_action] = 'abandon'
    session[:canx_controller] = 'reservation'
    session[:next_action] = session[:action]
    session[:camper_found] = 'confirm_res'
    session[:fini_action] = 'list'
    session[:change] = false
    render :action => :show and return
  rescue => err
    error 'Reservation could not be updated(1). ' + err.to_s
    session[:reservation_id] = nil
    flash[:error] = I18n.t('reservation.Flash.UpdateFail')
    redirect_to :action => :new and return
  end

  def create
    ####################################################
    # create and save a new reservation.
    ####################################################
    @reservation = get_reservation
    create_res
    session[:reservation_id] = nil
    session[:payment_id] = nil
    redirect_to :action => :list and return
  rescue => err
    error 'Problem in Reservation.  Reservation is not complete!' + err.to_s
    flash[:error] = I18n.t('reservation.Flash.UpdateFail')
    redirect_to :action => :show, :reservation_id => @reservation.id and return
  end

  def expand
    @page_title = I18n.t('titles.res_list')
    ####################################################
    # List all reservations with groups expanded.  
    # Sort by the start date, group and space of the reservation
    ####################################################
    session[:list] = 'expand'
    session[:reservation_id] = nil
    session[:next_controller] = nil
    session[:next_action] = nil

    if params[:page]
      page = params[:page]
      session[:page] = page
    else
      page = session[:page]
    end
    begin
      reservations = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", false, true, false],
				      :include => ["camper", "space", "rigtype"],
				      :order => @option.res_list_sort )
    rescue
      @option.update_attributes :res_list_sort => "unconfirmed_remote desc, startdate, group_id, spaces.position asc"
      reservations = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", false, true, false],
				      :include => ["camper", "space", "rigtype"],
				      :order => @option.res_list_sort )
    end
    @reservations = reservations.paginate(:page => page, :per_page => @option.disp_rows)
    return_here
    session[:reservation_id] = nil if session[:reservation_id] 
    session[:payment_id] = nil if session[:payment_id] 
    session[:current_action] = 'expand'
  end

  def sort_by_res
    @option.update_attributes get_sort.to_sym => "unconfirmed_remote desc, reservations.id asc"
    redirect_to :action => session[:list]
  end

  def sort_by_start
    @option.update_attributes get_sort.to_sym => "unconfirmed_remote desc, startdate, group_id, spaces.position asc"
    redirect_to :action => session[:list]
  end

  def sort_by_end
    @option.update_attributes get_sort.to_sym => "unconfirmed_remote desc, enddate, startdate, group_id, spaces.position asc"
    redirect_to :action => session[:list]
  end

  def sort_by_name
    @option.update_attributes get_sort.to_sym => "unconfirmed_remote desc, campers.last_name, startdate, group_id, spaces.position asc"
    redirect_to :action => session[:list]
  end

  def sort_by_space
    @option.update_attributes get_sort.to_sym => "unconfirmed_remote desc, spaces.position, startdate, group_id, campers.last_name asc"
    redirect_to :action => session[:list]
  end

  def list
    @page_title = I18n.t('titles.res_list')
    ####################################################
    # List all reservations.  This is used
    # as the central focus of the application.  Sort
    # by the start date, group and space of the reservation
    ####################################################
    session[:next_controller] = nil
    session[:next_action] = nil
    session[:reservation_id] = nil
    if (Space.first == nil)  # this is for startup with no spaces defined
      if @option.use_login? && session[:user_id] != nil
	if @user_login.admin
	  redirect_to :controller => 'setup/index', :action => 'index'
	else
	  redirect_to :controller => :admin, :action => :index
	end
      else
	redirect_to :controller => 'setup/index', :action => 'index'
      end
    else
      session[:list] = 'list'
      if params[:page]
	page = params[:page]
	session[:page] = page
      else
	page = session[:page]
      end
      begin
	res = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", false, true, false],
			       :include => ["camper", "space", "rigtype"],
			       :order => @option.res_list_sort )
      rescue
	@option.update_attributes :res_list_sort => "unconfirmed_remote desc, startdate, group_id, spaces.position asc"
	res = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", false, true, false],
			       :include => ["camper", "space"],
			       :order => @option.res_list_sort )
      end
      @saved_group = nil
      res = res.reject do |r|
	contract(r)
      end
      reservations = res.compact
      @reservation = Reservation.new
      @reservations = reservations.paginate(:page => page, :per_page => @option.disp_rows)
    end

    ####################################################
    # return to here from a camper show
    ####################################################
    return_here
    session[:reservation_id] = nil if session[:reservation_id] 
    session[:payment_id] = nil if session[:payment_id] 
    session[:current_action] = 'list'
  end

  def change_dates
    session[:change] = true
    @page_title = I18n.t('titles.ChangeDates')
    @reservation = get_reservation
    @extras = Extra.active
    @seasonal_ok = @reservation.check_seasonal
    @storage_ok = @reservation.check_storage
    debug "seasonal_ok = #{@seasonal_ok}, storage_ok = #{@storage_ok}"
    @available_str = @reservation.get_possible_dates
    session[:early_date] = @reservation.early_date
    session[:late_date] = @reservation.late_date
    session[:startdate] = @reservation.startdate
    session[:enddate] = @reservation.enddate
    session[:canx_action] = 'cancel_change'
    unless flash[:error] # coming back after an error
      session[:next_action] = session[:action]
    end
    debug 'Cancel action = ' + session[:canx_action]
    @use_navigation = false
    @change_action = 'date'
  rescue => err
    flash[:error]= 'Error handling reservation ' + err.to_s
    error '#change_dates Error handling reservation ' + err.to_s
    redirect_to :action => :list
  end

  def extend_stay
    # fetch reservation
    @reservation = get_reservation
    old_end = @reservation.enddate
    if params[:enddate]
      new_end = params[:enddate]
    else
      new_end = @reservation.enddate + 1.day
    end
    debug "changing enddate to #{new_end}"
    # check that there is no reservation precluding extension
    @reservation.enddate = new_end
    conflict = @reservation.conflicts?
    if conflict == false
      #empty so space is free, up the stay by one day
      @reservation.update_attributes :enddate => new_end
      @reservation.camper.active if @reservation.camper
      @reservation.add_log("end date changed from #{old_end} to #{new_end}") if @reservation.confirm?
      @skip_render = true
      recalculate_charges
    else
      flash[:error] = I18n.t('reservation.Flash.ExtendConflict',
                              :space_name => @reservation.space.name,
			      :enddate => @reservation.enddate,
			      :conflict_id => conflict.id)
    end
  rescue => err
    error 'Unable to extend reservation ' + err.to_s
    flash[:error] = I18n.t('reservation.Flash.ExtendFail')
  ensure
    redirect_to :action => :in_park
  end

  def recalculate_charges
    ####################################################
    # recalculate the charges for this reservation using
    # the current rates.  We could be coming from checkin
    # or from show.
    ####################################################
    debug 'recalculate_charges'
    if defined?(@reservation)
      session[:reservation_id] = @reservation.id
    else
      @reservation = get_reservation
    end
    # calculate charges
    Charges.new( @reservation.startdate,
		 @reservation.enddate,
		 @reservation.space.price.id, 
		 @reservation.discount_id,
		 @reservation.id,
		 @reservation.seasonal,
		 @reservation.storage)
    charges_for_display(@reservation)
    begin
      if @reservation.save
	flash[:notice] = I18n.t('reservation.Flash.UpdateSuccess',
	                         :reservation_id => @reservation.id.to_s,
				 :camper_name => @reservation.camper.full_name) if @reservation.camper unless (@skip_notice or flash[:error])
      else
	flash[:error] = I18n.t('reservation.Flash.UpdateFail') unless @skip_notice
      end
    rescue ActiveRecord::StaleObjectError => err
      error 'Problem updating reservation' + err.to_s 
      flash[:error] = I18n.t('reservation.Flash.UpdateFail') unless @skip_notice
      locking_error(@reservation)
    rescue => err
      error 'Problem updating reservation' + err.to_s 
      flash[:error] = I18n.t('reservation.Flash.UpdateFail') unless @skip_notice
    end
    redirect_to :action => session[:current_action], :reservation_id => @reservation.id unless @skip_render
  end

  def update_camper
    ####################################################
    # store the data from an change of camper for a reservation
    ####################################################
    session[:change] = false
    @reservation = get_reservation
    former_camper = @reservation.camper.full_name
    @reservation.camper_id = params[:camper_id].to_i
    begin
      if @reservation.save
	flash[:notice] = I18n.t('reservation.Flash.UpdateSuccess',
	                         :reservation_id => @reservation.id,
				 :camper_name => @reservation.camper.full_name)
	@reservation.add_log("camper changed from #{former_camper}")
	if session[:camper_found]
	  redirect_to :action => session[:camper_found] and return
	elsif @reservation.checked_in?
	  redirect_to :action => 'in_park' and return
	else
	  redirect_to :action => 'list' and return
	end
      else
	flash.now[:error] = I18n.t('reservation.Flash.UpdateFail')
	@page_title = I18n.t('titles.ChangeRes')
	@available_str = @reservation.get_possible_dates
	session[:early_date] = @reservation.early_date
	session[:late_date] = @reservation.late_date
	render :action => 'edit'
      end
    rescue ActiveRecord::StaleObjectError => err
      locking_error(@reservation)
      error 'Problem updating reservation' + err.to_s 
      flash.now[:error] = I18n.t('reservation.Flash.UpdateFail')
    rescue => err
      error 'Problem updating reservation' + err.to_s 
      flash.now[:error] = I18n.t('reservation.Flash.UpdateFail')
    end
  end

  def space_selected
    @page_title = I18n.t('titles.Review')
    ####################################################
    # the space has been selected, now compute the total
    # charges and fetch info for display and completion
    ####################################################

    @reservation = get_reservation
    @payments = Payment.find_all_by_reservation_id @reservation.id
    # if we are changing dates we will not have a space in params
    @reservation.space_id = params[:space_id].to_i if params[:space_id]
    check_length @reservation
    spaces = Space.confirm_available(@reservation.id, @reservation.space_id, @reservation.startdate, @reservation.enddate)
    # debug "#{spaces.size} spaces in conflict"
    if spaces.size > 0
      flash[:error] = I18n.t('reservation.Flash.Conflict')
      error 'space conflict'
      redirect_to :action => :new and return
    end
    @reservation.save!
    session[:next_controller] = 'reservation'
    session[:next_action] = 'confirm_res'
    session[:fini_action] = 'confirm_res'
    session[:current_action] = 'space_selected'
    session[:camper_found] = 'confirm_res'
    session[:change] = false
    if @option.use_variable_charge?
      @variable_charge = VariableCharge.new
      new_variable_charge if params[:variable_charge] && params[:variable_charge][:amount] != '0.0'
    end
    ####################################################
    # calculate charges
    ####################################################
    Charges.new(@reservation.startdate,
		@reservation.enddate,
		@reservation.space.price.id,
		@reservation.discount_id,
		@reservation.id,
		@reservation.seasonal,
		@reservation.storage)
    charges_for_display @reservation

    ####################################################
    # save the reservation
    ####################################################
    @reservation.save!
    # session[:reservation_id] = @reservation.id
    @use_navigation = false
    @integration = Integration.first
    session[:canx_action] = 'abandon'
    render :action => :show
  rescue => err
    error 'Reservation could not be updated(3) ' + err.to_s
    session[:reservation_id] = nil
    flash[:error] = I18n.t('reservation.Flash.UpdateFail')
    redirect_to :action => :new and return
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
    if params[:reservation]
      # first time through
      @reservation = Reservation.new(params[:reservation])
      @reservation.startdate = @date_start
      @reservation.enddate = @date_end
      debug "start #{@reservation.startdate}, end #{@reservation.enddate}"
      closed_start, closed_end, open = Campground.closed_dates(@reservation.startdate, @reservation.enddate)
      debug "open is #{Campground.open?(@reservation.startdate, @reservation.enddate)}"
      debug "closed start = #{closed_start}, closed end = #{closed_end}, open = #{open}"
    unless open || (@option.use_storage? && @reservation.storage?)
	flash[:error] = I18n.t('reservation.Flash.SpaceUnavailable') +
			"<br />" +
			I18n.t('reservation.Flash.ClosedDates', :closed => DateFmt.format_date(closed_start), :open => DateFmt.format_date(closed_end))
	redirect_to :action => :new and return
      end
      flash.now[:warning] = I18n.t('reservation.Flash.EarlyStart') if @reservation.startdate < currentDate
      @reservation.save!
      if params[:extra]
	extras = Extra.active
	extras.each do |e|
	  ex_key = "extra#{e.id}".to_sym
	  ct_key = "count#{e.id}".to_sym

	  debug "looking for #{e.id} with keys #{ex_key} and #{ct_key}"
	  #if params[:extra].key?("extra#{ex.id}".to_sym) && (params[:extra]["extra#{ex.id}".to_sym] != '0')
	  if params[:extra].key?(ex_key)
	    debug "found extra #{e.id} "
	    if (params[:extra][ex_key] != '0')
	      debug "and it is true"
	      @reservation.extras << e
	      debug "added extra #{e.id}"
	      ec=ExtraCharge.first(:conditions => [ "extra_id = ? and reservation_id = ?", 
						     e.id, @reservation.id] )
	      if e.extra_type == Extra::COUNTED || e.extra_type == Extra::OCCASIONAL
		ec.save_charges((params[:extra][ct_key]).to_i)
		debug "counted value #{e.id}, value is #{ec.number}"
	      else
		ec.save_charges( 0 )
	      end
	    else
	      debug "and it is false"
	    end
	  else
	    debug "not found extra #{e.id}"
	  end
	end
      end
      session[:reservation_id] = @reservation.id
      if @reservation.seasonal?
        @season = Season.find 1
      else
	@season = Season.find_by_date(@reservation.startdate)
      end
      session[:season] = @season.id
      session[:startdate] = @reservation.startdate
      session[:enddate] = @reservation.enddate
    end
    @reservation = Reservation.find session[:reservation_id].to_i unless defined?(@reservation)
    @season = Season.find(session[:season].to_i) unless defined?(@season)
    spaces = spaces_for_display(@reservation, @season, @reservation.sitetype_id)
    @spaces = spaces.paginate :page => params[:page], :per_page => @option.disp_rows
    @use_navigation = false
    @map =  '/map/' + @option.map if @option.map && !@option.map.empty? && @option.use_map?
    debug 'map is ' + @map if @map
    if @reservation.confirm?
      session[:canx_action] = 'cancel_change'
    else
      session[:canx_action] = 'abandon'
    end
    debug session[:canx_action]
  rescue => err
    error 'Reservation could not be updated(4) ' + err.to_s
    flash[:error] = I18n.t('reservation.Flash.UpdateFail')
    session[:reservation_id] = nil
    redirect_to :action => :new
  end

  def select_change
    ####################################################
    # get reservation info for selecting new space
    ####################################################
    session[:change] = true
    @page_title = I18n.t('titles.DateSel')
    @reservation = get_reservation
    redirect_to :action => :list and return unless @reservation
    session[:startdate] = @reservation.startdate
    session[:enddate] = @reservation.enddate
    @seasonal_ok = @option.use_seasonal?
    @storage_ok = @option.use_storage?
    @count  = Space.available( @reservation.startdate, @reservation.enddate, @reservation.sitetype_id).size if @option.show_available?
    @use_navigation = false
    @change_action = 'space'
    session[:canx_action] = 'cancel_change'
    debug 'Cancel action = ' + session[:canx_action]
  #  unless flash[:error]
  #    session[:canx_action] = session[:action]
  #    session[:next_action] = session[:action]
  #  end
  rescue => err
    error 'Reservation could not be updated(2) ' + err.to_s
    flash[:error] = I18n.t('reservation.Flash.UpdateFail')
    redirect_to :action => session[:canx_action], :reservation_id => @reservation.id
  end

  def change_space
    ####################################################
    # given the parameters specified find all spaces not
    # already reserved that fit the spec and supply data
    # for presentation
    ####################################################
    session[:change] = true
    @page_title = I18n.t('titles.ChangeSpace')
    @reservation = get_reservation
    unless params[:page]     
      session[:seasonal] = @reservation.seasonal
      debug "seasonal is #{session[:seasonal]}"
      session[:storage] = @reservation.storage
      debug "storage is #{session[:storage]}"
      if params[:reservation][:sitetype_id]
	session[:desired_type] = params[:reservation][:sitetype_id].to_i
      else
	session[:desired_type] = @reservation.sitetype_id
      end
      debug "desired type is #{session[:desired_type]}"
      if session[:seasonal] == true
	session[:startdate] = @reservation.startdate
	session[:enddate] = @reservation.enddate
      else
	# these dates come from application_controller
	@reservation.startdate = @date_start
	@reservation.enddate = @date_end
	session[:startdate] = @reservation.startdate
	session[:enddate] = @reservation.enddate
	closed_start, closed_end, open = Campground.closed_dates(@reservation.startdate, @reservation.enddate)
	unless open || (@option.use_storage? && @reservation.storage?)
	  flash[:error] = I18n.t('reservation.Flash.SpaceUnavailable') +
			  "<br />" +
			  I18n.t('reservation.Flash.ClosedDates', :closed => DateFmt.format_date(closed_start), :open => DateFmt.format_date(closed_end))
	  if @reservation.camper_id? && @reservation.camper_id > 0
	    redirect_to :action => session[:current_action], :reservation_id => @reservation.id and return
	  else
	    session[:reservation_id] = @reservation.id
	    redirect_to :action => 'space_selected', :reservation_id => @reservation.id and return
	  end
	end
      end
    end
    debug "seasonal is #{session[:seasonal]}, storage is #{session[:storage]}, desired type is #{session[:desired_type]}"
    @season = Season.find_by_date(@reservation.startdate)
    spaces = spaces_for_display(@reservation, @season, session[:desired_type])
    @count = spaces.size if show_available?
    @spaces = spaces.paginate :page => params[:page], :per_page => @option.disp_rows
    @use_navigation = false
    @change_action = 'space'
  rescue => err
    flash[:error]= 'Error handling reservation ' + err.to_s
    error '#change_space Error handling reservation ' + err.to_s
    redirect_to :action => :list
  end
  
  def space_changed
    ####################################################
    # update the reservation
    ####################################################

    debug "seasonal is #{session[:seasonal]}, storage is #{session[:storage]}, desired type is #{session[:desired_type]}"
    @reservation = get_reservation
    former_space = @reservation.space.name
    @reservation.space_id = params[:space_id].to_i
    @reservation.sitetype_id = session[:desired_type]
    @reservation.startdate = session[:startdate]
    @reservation.enddate = session[:enddate]
    @reservation.seasonal = session[:seasonal]
    @reservation.storage = session[:storage]
    spaces = Space.confirm_available(@reservation.id, @reservation.space_id, @reservation.startdate, @reservation.enddate)
    # debug "#{spaces.size} spaces in conflict"
    if spaces.size > 0
      flash[:error] = I18n.t('reservation.Flash.Conflict')
      error 'space conflict'
      redirect_to :action => :select_change, :reservation_id => @reservation.id  and return
    end
    ####################################################
    # calculate charges
    ####################################################
    @skip_render = true
    @skip_notice = true
    begin
      if @reservation.save
	# this reload should not be needed but...
	@reservation.reload
	recalculate_charges
	@reservation.add_log("space changed from #{former_space}") if @reservation.confirm?
	if @reservation.camper_id? && @reservation.camper_id > 0
	  flash[:notice] = I18n.t('reservation.Flash.SpaceChgName',
	                           :reservation_id => @reservation.id.to_s,
				   :camper_name => @reservation.camper.full_name,
				   :space => @reservation.space.name)
	else
	  flash[:notice] = I18n.t('reservation.Flash.SpaceChg',
	                           :reservation_id => @reservation.id.to_s,
				   :space => @reservation.space.name)
	end
      else
	flash[:error] = I18n.t('reservation.Flash.UpdateFail')
      end
      check_length @reservation
    rescue ActiveRecord::StaleObjectError => err
      error 'Reservation change failed ' + err.to_s
      locking_error(@reservation)    
    rescue => err
      error 'Reservation change failed ' + err.to_s
      flash[:error] = I18n.t('reservation.Flash.UpdateFail')
    ensure
      unless @reservation.camper_id? && @reservation.camper_id > 0
        session[:reservation_id] = @reservation.id
	redirect_to :action => 'space_selected', :reservation_id => @reservation.id
      else
	redirect_to :action => session[:current_action], :reservation_id => @reservation.id
      end
    end
  end

  def find_reservation
    @page_title = I18n.t('titles.find_res')
    session[:reservation_id] = nil
    session[:payment_id] = nil
    session[:next_controller] = 'reservation'
    session[:next_action] = 'show'
    session[:camper_found] = 'find_by_campername'
    @campers = Array.new
  end

  def show
    @reservation = get_reservation
    if @reservation.camper_id == 0
      redirect_to :action => :space_selected, :reservation_id => @reservation.id 
      return
    elsif !@reservation.confirm?
      redirect_to :action => :confirm_res, :reservation_id => @reservation.id 
      return
    end
    if @option.use_variable_charge?
      @variable_charge = VariableCharge.new
      new_variable_charge if params[:variable_charge] && params[:variable_charge][:amount] != '0.0'
    end
    session[:payment_id] = nil
    @cancel_ci = false
    @payments = Payment.find_all_by_reservation_id @reservation.id
    @payment = Payment.new
    if params[:camper_id] && !@reservation.camper_id && !@reservation.archived?
      @reservation.update_attributes :camper_id =>  params[:camper_id].to_i
      @reservation.camper.active
    end
    if @reservation.archived?
      begin
        archived = Archive.find_by_reservation_id @reservation.id
        @reason = archived.close_reason
      rescue
        @reason = 'unknown'
      end
    else
      if @reservation.checked_in? && ((Date.today - @reservation.startdate  ) <= 2 ) 
	if @option.use_login? && session[:user_id] != nil && @user_login.admin?
	  @cancel_ci = true
	elsif !@option.use_login?
	  @cancel_ci = true
	end
      end
    end
    if @reservation.group_id
      @page_title = I18n.t('titles.GroupResId', :reservation_id => @reservation.id, :name => @reservation.group.name)
    else
      @page_title = I18n.t('titles.ResId', :reservation_id => @reservation.id)
    end
    if params[:recalculate]
      @skip_render = true
      @skip_notice = true
      recalculate_charges
    end
    @integration = Integration.first
    if @integration
      debug "integration name is #{@integration.name}"
      if @integration.name == 'CardConnect' || @integration.name == 'CardConnect_o'
	@cash_id = Creditcard.find_or_create_by_name('Cash').id
	@check_id = Creditcard.find_or_create_by_name('Check').id
	if @integration.cc_hsn == 'None' 
	  # use 41em if 4 items
	  @spacing = '34em' # 3 items
	else
	  @spacing = '50em' # 5 items
	end
      end
    end
    charges_for_display @reservation
    session[:current_action] = 'show'
    session[:current_controller] = 'reservation'
    session[:camper_found] = 'show'
    session[:next_action] = session[:action] # this is the last action before this
    session[:canx_action] = 'abandon'
    debug 'Cancel action = ' + session[:canx_action]
    session[:canx_controller] = 'reservation'
    session[:fini_action] = session[:list]
    @final = 0.0
  end

  def find_by_number
    ####################################################
    # find a reservation given the reservation number
    ####################################################
    session[:reservation_id] = nil
    session[:payment_id] = nil
    begin
      @reservation = Reservation.find(params[:reservation][:id].to_i)
      if @reservation.archived
	begin
	  archived = Archive.find_by_reservation_id @reservation.id
	  @reason = archived.close_reason
	rescue
	  @reason = 'unknown'
	end
      end
      session[:reservation_id] = @reservation.id
      redirect_to :action => :show, :reservation_id => @reservation.id
    rescue ActiveRecord::RecordNotFound => err
      error err.to_s
      flash[:error] = I18n.t('reservation.Flash.NotFound',
                             :id => params[:reservation][:id].to_i)
      redirect_to :action => 'find_reservation'
    end
  end

  def find_by_campername
    session[:reservation_id] = nil
    session[:payment_id] = nil
    @reservations = Reservation.all(:conditions => ["confirm = ? and camper_id = ?", true, params[:camper_id].to_i])
    debug "found #{@reservations.size} reservations"
    if @reservations.size > 1
      @page_title = I18n.t('titles.ResName', :name => @reservations[0].camper.full_name)
    elsif @reservations.size == 1
      @reservation = @reservations[0]
      session[:reservation_id] = @reservation.id
      if @reservation.archived
	begin
	  archived = Archive.find_by_reservation_id @reservation.id
	  @reason = archived.close_reason
	rescue
	  @reason = 'unknown'
	end
      end
      redirect_to :action => :show, :reservation_id => @reservation.id
    else
      begin
	camper = Camper.find params[:camper_id].to_i
	debug "camper #{camper.full_name} found"
	@page_title = I18n.t('titles.NoResFoundName', :name => camper.full_name)
      rescue => err
	error I18n.t('camper.NotFound') + err.to_s
	@page_title = I18n.t('titles.NoResFound')
      end
    end
  end

  def checkin
    ####################################################
    # Just gather information to present a summary
    # to the customer unless you have a group in which
    # case just complete the checkin.
    ####################################################
    @reservation = get_reservation
    @payments = Payment.find_all_by_reservation_id session[:reservation_id].to_i
    @payment = Payment.new
    @page_title = I18n.t('titles.Checkin', :name => @reservation.camper.full_name)
    if params[:camper_id]
      @reservation.update_attributes :camper_id =>  params[:camper_id].to_i
      @reservation.camper.active
    end
    ################################
    # general stuff for display
    ################################
    if @reservation.space.unavailable
      flash[:error] = I18n.t('reservation.Flash.CheckinFailUnavail',
                             :space => @reservation.space.name,
			     :camper_name => @reservation.camper.full_name,
			     :reservation_id => @reservation.id)
    elsif rr = @reservation.space.occupied
      flash[:error] = I18n.t('reservation.Flash.CheckinFailOcc',
                             :space => @reservation.space.name,
			     :camper_name => @reservation.camper.full_name,
			     :reservation_id => @reservation.id,
			     :other_camper => rr.camper.full_name,
			     :other_reservation => rr.id)
    end
    unless @reservation.startdate == currentDate
      flash[:notice] = I18n.t('reservation.Flash.CheckinVer',
                              :reservation_id => @reservation.id,
			      :space => @reservation.space.name,
			      :startdate => @reservation.startdate)
    end

    session[:current_action] = 'checkin'
    session[:current_controller] = 'reservation'
    session[:next_action] = session[:action]
    session[:camper_found] = 'checkin'
    if @reservation.group_id? && @reservation.group_id > 0
      if @reservation.space.unavailable
	flash[:error] = I18n.t('reservation.Flash.CheckinFailUnavail',
	                       :space => @reservation.space.name,
			       :camper_name => @reservation.camper.full_name,
			       :reservation_id => @reservation.id)
      elsif rr = @reservation.space.occupied
	flash[:error] = I18n.t('reservation.Flash.CheckinFailOcc',
	                       :space => @reservation.space.name,
			       :camper_name => @reservation.camper.full_name,
			       :reservation_id => @reservation.id,
			       :other_camper => rr.camper.full_name,
			       :other_reservation => rr.id)
      else
	@reservation.checked_in = true
	@reservation.camper.active
	@reservation.add_log("checkin")
	begin
	  if @reservation.save
	    flash[:notice] = I18n.t('reservation.Flash.CheckedIn',
	                            :camper_name => @reservation.camper.full_name,
				    :space => @reservation.space.name)
	    session[:reservation_id] = nil
	    session[:payment_id] = nil
	  else
	    flash[:error] = I18n.t('reservation.Flash.CheckinFail',
	                           :camper_name => @reservation.camper.full_name,
				   :space => @reservation.space.name)
	  end
	rescue ActiveRecord::StaleObjectError => err
	  error err.to_s
	  locking_error(@reservation)
	rescue => err
	  error err.to_s
	  flash[:error] = I18n.t('reservation.Flash.CheckinFail',
	                         :camper_name => @reservation.camper.full_name,
				 :space => @reservation.space.name)
	end
      end
      redirect_to  :action => :list and return
    end
    if @option.use_variable_charge?
      @variable_charge = VariableCharge.new
      new_variable_charge if params[:variable_charge] && params[:variable_charge][:amount] != '0.0'
    end
    charges_for_display @reservation
    @integration = Integration.first
    session[:canx_action] = 'abandon'  
    debug 'Cancel action = ' + session[:canx_action]
    session[:canx_controller] = 'reservation'
    session[:fini_action] = session[:list]
    render :action => :show
  end

  def checkin_now
    ####################################################
    # immediate checkin of current reservation in session
    # first create and save the res then do the checkin
    ####################################################
    @reservation = get_reservation
    create_res(true) # skip email
    @reservation.checked_in = true
    @reservation.camper.active
    complete_checkin
  rescue => err
    error 'checkin not completed ' + err.to_s
    flash[:error] = I18n.t('reservation.Flash.CheckinFail',
                           :camper_name => @reservation.camper.full_name,
			   :space => @reservation.space.name)
    redirect_to :action => :show, :reservation_id => @reservation.id
  end

  def do_checkin
    ####################################################
    # do checkin.  Resume on reservation/list
    ####################################################
    @reservation = get_reservation
    @reservation.checked_in = true
    @reservation.camper.active
    complete_checkin
  rescue => err
    error 'checkin not completed ' + err.to_s
    flash[:error] = I18n.t('reservation.Flash.CheckinFail',
                           :camper_name => @reservation.camper.full_name,
			   :space => @reservation.space.name)
    redirect_to :action => :show, :reservation_id => @reservation.id
  end

  def cancel_checkin
    @reservation = get_reservation
    if @reservation.checked_in?
      @reservation.update_attribute :checked_in, false
      @reservation.add_log("cancel checkin")
    else
      flash[:error] = "Reservation #{@reservation.id} not checked in, cannot cancel checkin"
    end
    redirect_to :action => :show, :reservation_id => @reservation.id
  rescue
    redirect_to :action => :list
  end

  def cancel
    @page_title = I18n.t('titles.CancelReservation')
    ####################################################
    # Just gather information to present a summary
    ####################################################
    @reservation = get_reservation
  end

  def destroy
    ####################################################
    # complete the destruction of a reservation
    ####################################################
    begin
      @reservation = get_reservation
      @reservation.add_log("cancelled")
      if params[:cancel_charge] && params[:cancel_charge].to_f > 0.0
        debug "cancel_charge is #{params[:cancel_charge]}"
	@reservation.update_attributes :cancelled => true, :cancel_charge => params[:cancel_charge] 
      else
	@reservation.update_attributes :cancelled => true, :cancel_charge => 0.0
      end
      if params[:email] == '1'
        # send an email
	begin
	  email = ResMailer.deliver_reservation_cancel(@reservation, params[:close_reason])
	  flash[:warning] = I18n.t('reservation.Flash.CancelSent')
	rescue => err
	  error err.to_s
	  flash[:error] = I18n.t('reservation.Flash.CancelErr')
	end
      else
       debug "no cancel message sent"
      end
      if @option.use_login? && defined? @user_login
	Reason.close_reason_is "cancelled by: #{@user_login.name} at: #{currentTime} reason: " + params[:close_reason]
      else
	Reason.close_reason_is "cancelled at: #{currentTime} reason: " + params[:close_reason]
      end
    rescue ActiveRecord::RecordNotFound => err
      info err.to_s
      # probably means the reservation is already gone
      redirect_to :action => 'list' and return
    end
    camper = @reservation.camper.full_name
    id = @reservation.id
    charges_for_display(@reservation)
    # then archive the reservation
    begin
      debug 'archiving record'
      @reservation.archive
      flash[:notice] = I18n.t('reservation.Flash.Canceled', :camper_name => camper, :reservation_id => id)
      session[:reservation_id] = nil
      session[:payment_id] = nil
      redirect_to :action => :show, :reservation_id => @reservation.id
    rescue RuntimeError => err
      error err.to_s
      flash[:error] = I18n.t('reservation.Flash.CanxFail',
			     :reservation_id => session[:reservation_id])
      redirect_to :action => 'list'
    rescue ActiveRecord::StaleObjectError => err
      error err.to_s
      locking_error(@reservation)
      redirect_to :action => 'list'
    end
  end

  def undo_cancel
    @reservation = get_reservation
    unless @reservation.cancelled?
      flash[:error] = 'Reservation #{@reservation.id} not cancelled, cannot undo cancel'
    else
      res = Reservation.conflict(@reservation)
      if res
	flash[:error] = I18n.t('reservation.Flash.UndoCanxFail1',:reservation_id => @reservation.id)
	res.each do |r|
	  flash[:error] += r.id.to_s + ' '
	end
	flash[:error] += I18n.t('reservation.Flash.UndoCFail2')
      else
	@reservation.add_log("undo cancel")
	arch = Archive.find_by_reservation_id @reservation.id
	arch.destroy if arch
	@reservation.update_attributes :archived => false, :cancelled => false, :cancel_charge => 0.0
	flash[:notice] = I18n.t('reservation.Flash.UndoCanxOK', :reservation_id => @reservation.id)
      end  
    end
    redirect_to :action => :show, :reservation_id => @reservation.id
  end

  def undo_checkout
    @reservation = get_reservation
    unless @reservation.checked_out?
      flash[:error] = "Reservation #{@reservation.id} not checked out.  Checkout cannot be undone"
    else  
      res = Reservation.conflict(@reservation)
      if res
	flash[:error] = I18n.t('reservation.Flash.UndoCOFail1',:reservation_id => @reservation.id)
	res.each do |r|
	  flash[:error] += r.id.to_s + ' '
	end
	flash[:error] += I18n.t('reservation.Flash.UndoCFail2')
      else
	@reservation.add_log("undo checkout")
	arch = Archive.find_by_reservation_id @reservation.id
	arch.destroy if arch
	@reservation.update_attributes :archived => false, :checked_out => false
	flash[:notice] = I18n.t('reservation.Flash.UndoCOOK', :reservation_id => @reservation.id)
      end  
    end
    redirect_to :action => :show, :reservation_id => @reservation.id
  end

  def in_park
    @page_title = I18n.t('titles.in_park')
    ####################################################
    # gather a list of all currently in the park
    # with groups condensed
    ####################################################
    session[:list] = 'in_park'
    session[:reservation_id] = nil
    session[:next_controller] = nil
    session[:next_action] = nil

    if params[:page]
      page = params[:page]
      session[:page] = page
    else
      page = session[:page]
    end
    begin
      res = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", true, true, false],
			     :include => ["camper", "space", "rigtype"],
			     :order => @option.inpark_list_sort )
      @count = res.size
    rescue
      @option.update_attributes :inpark_list_sort => "unconfirmed_remote desc, enddate, startdate, group_id, spaces.position asc"
      res = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", true, true, false],
			     :include => ["camper", "space", "rigtype"],
			     :order => @option.inpark_list_sort )
      @count = res.size
    end
    @saved_group = nil
    res = res.reject do |r|
      contract(r)
    end
    reservations = res.compact

    @reservations = reservations.paginate(:page => page, :per_page => @option.disp_rows)
    
    ####################################################
    # return to here from a camper show
    ####################################################
    return_here
    session[:reservation_id] = nil if session[:reservation_id] 
    session[:payment_id] = nil if session[:payment_id] 
    session[:current_action] = 'in_park'
    render(:action => 'list')
  end

  def in_park_expand
    @page_title = I18n.t('titles.in_park')
    ####################################################
    # gather a list of all currently in the park
    # with groups expanded
    ####################################################
    session[:list] = 'in_park_expand'
    session[:reservation_id] = nil
    session[:next_controller] = nil
    session[:next_action] = nil
    if params[:page]
      page = params[:page]
      session[:page] = page
    else
      page = session[:page]
    end
    begin
      reservations = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", true, true, false],
				      :include => ["camper", "space", "rigtype"],
				      :order => @option.inpark_list_sort )
      @count = reservations.size
    rescue
      @option.update_attributes :inpark_list_sort => "unconfirmed_remote desc, enddate, startdate, group_id, spaces.position asc"
      reservations = Reservation.all( :conditions =>  ["checked_in = ? and confirm = ? and archived = ?", true, true, false],
				      :include => ["camper", "space", "rigtype"],
				      :order => @option.inpark_list_sort )
      @count = reservations.size
    end
    @reservations = reservations.paginate(:page => page, :per_page => @option.disp_rows)
    return_here
    session[:current_action] = 'in_park_expand'
    session[:reservation_id] = nil if session[:reservation_id] 
    session[:payment_id] = nil if session[:payment_id] 
    render(:action => 'expand')
  end

  def do_checkout
    ####################################################
    # complete the checkout process
    ####################################################
    @reservation = get_reservation
    if (status = @reservation.checkout(@option, @option.use_login ? @user_login.name : nil))
      session[:reservation_id] = nil if session[:reservation_id] 
      session[:payment_id] = nil if session[:payment_id] 
      flash[:notice] = I18n.t('reservation.Flash.CheckedOut', :camper_name => @reservation.camper.full_name)
      if @option.use_feedback? && Email.address_valid?(@reservation.camper.email)
	render :action => :feedback
      else
	redirect_to  :action => 'in_park'
      end
    else
      error status.to_s
      flash[:error] = I18n.t('reservation.Flash.CheckoutFail', :camper_name => @reservation.camper.full_name)
      redirect_to  :action => 'in_park'
    end
  rescue => err
    error err.to_s
    flash[:error] = I18n.t('reservation.Flash.CheckoutFail', :camper_name => @reservation.camper.full_name)
    redirect_to  :action => 'in_park'
  rescue ActiveRecord::RecordNotFound => err
    error 'Reservation not found ' + err.to_s
    flash[:error] = I18n.t('reservation.Flash.NotFound', :id => session[:reservation_id])
    redirect_to  :action => 'in_park'
  rescue ActiveRecord::StaleObjectError => err
    error err.to_s
    locking_error(@reservation)
    redirect_to  :action => 'in_park'
  end

  def feedback
    sent = false
    # this is a bogus reservation just for creating the message
    # it will never be saved
    @reservation = Reservation.new :camper_id => params[:camper_id].to_i,
				   :space_id => params[:space_id].to_i,
				   :startdate => params[:startdate],
				   :enddate => params[:enddate],
				   :total => params[:total],
				   :deposit => params[:deposit]
    @reservation.id = params[:reservation_id].to_i
    begin
      email = ResMailer.deliver_reservation_feedback(@reservation)
      flash[:warning] = I18n.t('reservation.Flash.FeedbackSent')
    rescue => err
      error err.to_s
      flash[:error] = I18n.t('reservation.Flash.FeedbackErr')
    end
    redirect_to  :action => 'in_park'
  end

  def get_override
    @reservation = get_reservation
  end

  def override
    @reservation = get_reservation
    if @reservation.update_attributes :override_total => params[:reservation][:override_total].to_f
      @reservation.add_log("override to #{@reservation.override_total}")
      @skip_render = true
      recalculate_charges
      if defined? session[:current_action]
	redirect_to :action => session[:current_action], :reservation_id => @reservation.id
      else
	redirect_to :action => :show, :reservation_id => @reservation.id
      end
    else
      render :action => :get_override and return
    end
  end

  def cancel_override
    @reservation = get_reservation
    if @reservation.update_attributes :override_total => 0.0
      @reservation.add_log("cancel override")
      @skip_render = true
      recalculate_charges
      if defined? session[:current_action]
	redirect_to :action => session[:current_action], :reservation_id => @reservation.id
      else
	redirect_to :action => :show, :reservation_id => @reservation.id
      end
    else
      render :action => :get_override and return
    end
  rescue
    flash[:error] = "reservation #{params[:id]} not found"
    if defined? session[:current_action]
      redirect_to :action => session[:current_action], :reservation_id => @reservation.id
    else
      redirect_to :action => :show, :reservation_id => @reservation.id
    end
  end

  def review
    ####################################################
    # review data in a reservation.
    # reservation id is in session at the end of this
    ####################################################
    @page_title = I18n.t('titles.ConfirmRes')
    @reservation = get_reservation
    if params[:camper_id]
      @reservation.update_attributes :camper_id =>  params[:camper_id].to_i
      @reservation.camper.active
    end
    @payments = Payment.find_all_by_reservation_id @reservation.id
    @payment = Payment.new
    @integration = Integration.first
    if @option.use_variable_charge?
      @variable_charge = VariableCharge.new
      new_variable_charge if params[:variable_charge] && params[:variable_charge][:amount] != '0.0'
    end
    charges_for_display @reservation
    session[:early_date] = 0
    session[:late_date] = 0
    session[:canx_action] = 'abandon'
    debug 'Cancel action = ' + session[:canx_action]
    session[:next_action] = session[:action]
    session[:camper_found] = 'review'
    session[:current_action] = 'review'
    render :action => :show
  end

  def remote_not_confirmed
    @reservation = get_reservation
    if @option.use_remote_res_reject? 
      if Email.address_valid?(@reservation.camper.email)
	sent = false
	begin
	  email = ResMailer.deliver_remote_reservation_reject(@reservation)
	  flash[:warning] = I18n.t('reservation.Flash.NonConfSent')
	rescue => err
	  error err.to_s
	  flash[:error] = I18n.t('reservation.Flash.NonConfErr')
	end
      else
	flash[:warning] = I18n.t('reservation.Flash.NonConfNotSent')
      end
    end
    @reservation.add_log("remote reservation not confirmed")
    Reason.close_reason_is "Remote reservation not confirmed"
    begin
      @reservation.archive
      session[:reservation_id] = nil
      session[:payment_id] = nil
      redirect_to :action => 'list'
    rescue RuntimeError => err
      error err.to_s
      redirect_to :action => 'list'
    rescue ActiveRecord::StaleObjectError => err
      error err.to_s
      locking_error(@reservation)
      redirect_to :action => 'list'
    end
  end

  def remote_confirmed
    @reservation = get_reservation
    if @option.use_remote_res_confirm?
      if Email.address_valid?(@reservation.camper.email)
	sent = false
	begin
	  email = ResMailer.deliver_remote_reservation_confirmation(@reservation)
	  flash[:warning] = I18n.t('reservation.Flash.ConfSent')
	rescue => err
	  error err.to_s
	  flash[:error] = I18n.t('reservation.Flash.ConfErr')
	end
      else
	flash[:warning] = I18n.t('reservation.Flash.ConfNotSent')
      end
    end
    @reservation.update_attribute :unconfirmed_remote, false
    @reservation.add_log("remote reservation confirmed")
    redirect_to :action => 'list'
  end

  ####################################################
  # methods called from in_place_edit
  ####################################################

  def set_payment_deposit_formatted
    @reservation = get_reservation
    if params[:value] 
      pmt = currency_2_number(params[:value])
      if @option.use_login? && defined? @user_login
	name = @user_login.name
      else
	name = ""
      end
      if params[:id]
        @payment = Payment.find params[:id].to_i
	@payment.update_attributes :amount => pmt, :name => name
      elsif session[:payment_id]
	@payment = Payment.find session[:payment_id].to_i
	@payment.update_attributes :amount => pmt, :name => name
      else
	@payment = Payment.create! :amount => pmt, :reservation_id => session[:reservation_id], :name => name
	@payment.reload
      end
      @pmt_method = @payment.creditcard.name
      session[:payment_id] = @payment.id
      debug "#set_payment_deposit_formatted going to charges for display with res #{@reservation.id}"
      charges_for_display(@reservation)
      render :update do |page|
	page[:pmt].replace_html :partial => 'pmt'
	page[:charges].reload
      end
    else
      render :nothing => true
    end
  end

  def set_reservation_onetime_formatted
    if params[:id]
      @reservation = Reservation.find params[:id].to_i
    else
      @reservation = get_reservation
    end
    if params[:value] 
      discount = currency_2_number(params[:value].to_f)
      # debug "discount is #{discount}"
      @reservation.update_attributes :onetime_discount => discount
      @skip_render = true
      recalculate_charges
      charges_for_display(@reservation)
      render :update do |page|
	page[:onetimedisc].replace_html :partial => 'get_one_time_discount'
	page[:charges].reload
      end
    else
      render :nothing => true
    end
  end

  def set_payment_memo
    @reservation = get_reservation
    if params[:value] 
      if params[:id]
        @payment = Payment.find params[:id].to_i
      else
	@payment = Payment.find(session[:payment_id].to_i)
      end
      @payment.update_attributes :memo => params[:value]
      @pmt_method = @payment.creditcard.name
      charges_for_display(@reservation)
      render :update do |page|
	page[:flash].replace_html ""
	page[:pmt].replace_html :partial => 'pmt'
	page[:charges].reload
      end
    else
      render :nothing => true
    end
  end

  def set_payment_credit_card_no
    @reservation = get_reservation
    if params[:value] 
      if params[:id]
        @payment = Payment.find params[:id].to_i
      else
	debug "session payment is #{session[:payment_id]}"
	@payment = Payment.find(session[:payment_id].to_i)
      end
      @pmt_method = @payment.creditcard.name
      if @payment.creditcard.validate_cc_number? && !Creditcard.valid_credit_card?(params[:value])
	render :update do |page|
	  page[:flash].replace_html I18n.t('reservation.Flash.CardNoInvalid')
	  page[:cc_error].replace_html I18n.t('reservation.Flash.CardNoInvalid')
	  page[:flash][:style][:color] = 'red'
	  page[:flash].visual_effect :highlight
	  # debug "editorID = #{params[:editorId]}"
	  page[:pmt].replace_html :partial => 'pmt'
	  # debug "editorID = #{params[:editorId]}"
	  # page[params[:editorId]][:style][:background_color] = 'red'
	  # page[params[:editorId]].visual_effect :highlight
	  page.visual_effect :highlight, params[:editorId], {:startcolor => 'ff0000'}
	end
      else
	@payment.update_attributes :credit_card_no => params[:value] 
	charges_for_display(@reservation)
	render :update do |page|
	  page[:cc_error].replace_html ''
	  page[:flash].replace_html ""
	  page[:pmt].replace_html :partial => 'pmt'
	  page[:charges].reload
	end
      end
    else
      render :nothing => true
    end
  end

  def set_payment_exp_str
    @reservation = get_reservation
    if params[:value] 
      if params[:id]
        @payment = Payment.find params[:id].to_i
      else
	debug "session payment is #{session[:payment_id]}"
	@payment = Payment.find(session[:payment_id].to_i)
      end
      @pmt_method = @payment.creditcard.name
      begin
	mo,yr = params[:value].split '/'
	exp_dt = "01-#{mo}-20#{yr}".to_date.end_of_month
	debug "expire date is #{exp_dt}"
      rescue
	exp_dt = currentDate.beginning_of_year
      end
      if @payment.creditcard.card_expired?( exp_dt )
	debug "card expired"
	render :update do |page|
	  page[:flash].replace_html I18n.t('reservation.Flash.CardExpired')
	  page[:cc_error].replace_html I18n.t('reservation.Flash.CardExpired')
	  page[:flash][:style][:color] = 'red'
	  page[:flash].visual_effect :highlight
	  page[:pmt].replace_html :partial => 'pmt'
	  page.visual_effect :highlight, params[:editorId], {:startcolor => 'ff0000'}
	end
      else
	@payment.update_attributes :cc_expire => exp_dt
	render :update do |page|
	  page[:cc_error].replace_html ''
	  page[:flash].replace_html ""
	  page[:pmt].replace_html :partial => 'pmt'
	end
      end
    else
      render :nothing => true
    end
  end

  def set_camper_last_name
    # Parameters: {"action"=>"set_camper_last_name",
    #		   "id"=>"4",
    #		   "value"=>"",
    #		   "controller"=>"reservation",
    #		   "editorId"=>"camper_last_name_4_in_place_editor"}
    @reservation = get_reservation
    unless [:post, :put].include?(request.method) then
      return render(:text => 'Method not allowed', :status => 405)
    end
    @item = Camper.find(params[:id].to_i)
    err = @item.update_attributes(:last_name => params[:value])
    unless err
      @item.reload
    end  
    render :text => CGI::escapeHTML(@item.last_name.to_s)
  end

  ####################################################
  # methods called from observers
  ####################################################

  def update_group
    @reservation = get_reservation
    if params[:group_id] != ""
      @id = params[:group_id].to_i
      @group = Group.find(@id)
    else
      @id = nil
      @group = Group.find(@reservation.group_id)
    end
    @reservation.update_attributes :group_id => @id
    @group.update_attributes :expected_number => Reservation.find_all_by_group_id(@group.id).count
    render(:nothing => true)
  end

  def update_cc_expire
    @integration = Integration.first
    @reservation = get_reservation
    if params[:payment]
      if session[:payment_id]
	exp = Date.new(params[:payment]['cc_expire(1i)'].to_i,
		       params[:payment]['cc_expire(2i)'].to_i,
		       params[:payment]['cc_expire(3i)'].to_i)
	exp_dt = exp.end_of_month
        @payment = Payment.find session[:payment_id].to_i
      end
      @payment.update_attributes :cc_expire => exp_dt
      @pmt_method = @payment.creditcard.name
      charges_for_display(@reservation)
      if @payment.creditcard.card_expired?( exp_dt )
	render :update do |page|
	  page[:flash].replace_html I18n.t('reservation.Flash.CardExpired')
	  page[:cc_error].replace_html I18n.t('reservation.Flash.CardExpired')
	  page[:flash][:style][:color] = 'red'
	  page[:flash].visual_effect :highlight
	  page[:pmt].replace_html :partial => 'pmt'
	  page.visual_effect :highlight, :cc_expire, {:startcolor => 'ff0000'}
	end
      else
	render :update do |page|
	  page[:cc_error].replace_html ''
	  page[:flash].replace_html ""
	  page[:pmt].replace_html :partial => 'pmt'
	  page[:charges].reload
	end
      end
    else
      error 'no params[:payment]'
      render(:nothing => true)
    end
  end 

  def update_check
    @reservation = get_reservation
    #  check if Check is a 'credit card' if not create it
    #  with appropriate options
    creditcard = Creditcard.find_or_create_by_name('Check')
    #  then render the creditcard display
    @payment = Payment.create! :reservation_id => @reservation.id,
			       :creditcard_id => creditcard.id
    session[:payment_id] = @payment.id
    debug "session payment created and defined as #{session[:payment_id]}"
    charges_for_display(@reservation)
    render :update do |page|
      page[:pmt].replace_html :partial => 'pmt'
    end
  end

  def update_cash
    @reservation = get_reservation
    #  check if Cash is a 'credit card' if not create it
    #  with appropriate options
    creditcard = Creditcard.find_or_create_by_name('Cash')
    #  then render the creditcard display
    @payment = Payment.create! :reservation_id => @reservation.id,
			       :creditcard_id => creditcard.id
    session[:payment_id] = @payment.id
    debug "session payment created and defined as #{session[:payment_id]}"
    charges_for_display(@reservation)
    render :update do |page|
      page[:pmt].replace_html :partial => 'pmt'
    end
  end

  def update_cc
    @integration = Integration.first
    @reservation = get_reservation
    if params[:creditcard_id]
      debug 'we have an id!'
      if session[:payment_id]
	debug "session payment defined as #{session[:payment_id]}"
        @payment = Payment.find session[:payment_id].to_i
	@payment.update_attributes :creditcard_id => params[:creditcard_id].to_i
      else
	debug "creating new payment"
	new_payment = true
        @payment = Payment.create! :reservation_id => session[:reservation_id].to_i,
			       :creditcard_id => params[:creditcard_id].to_i
	@payment.reload
	session[:payment_id] = @payment.id
	debug "session payment created and defined as #{session[:payment_id]}"
      end
      @pmt_method = Creditcard.find(params[:creditcard_id]).name
      charges_for_display(@reservation)
      render :update do |page|
	page[:pmt].replace_html :partial => 'pmt'
	page[:charges].reload unless new_payment
      end
    else
      error 'no params[:creditcard_id]'
      render(:nothing => true)
    end
  end 

  def update_pmt_date
    @reservation = get_reservation
    @payment = Payment.find session[:payment_id].to_i
    @pmt_method = @payment.creditcard.name
    begin
      if params[:date]
	@payment.update_attributes :pmt_date => params[:date]
      elsif params[:day]
	pmt = Date.new(@payment.pmt_date.year, @payment.pmt_date.mon, params[:day].to_i)
	@payment.update_attributes :pmt_date => pmt
      elsif params[:month]
	pmt = Date.new(@payment.pmt_date.year, params[:month].to_i, @payment.pmt_date.day)
	@payment.update_attributes :pmt_date => pmt
      elsif params[:year]
	pmt = Date.new(params[:year].to_i, @payment.pmt_date.mon, @payment.pmt_date.day)
	@payment.update_attributes :pmt_date => pmt
      end
    rescue => err
      error err.to_s
    end
    charges_for_display(@reservation)
    render :update do |page|
      page[:pmt].replace_html :partial => 'pmt'
      page[:charges].reload
    end
  end

  def update_recommend
    @reservation = get_reservation
    if params[:recommender_id]
      @recommenders = Recommender.active
      @reservation.update_attributes :recommender_id => params[:recommender_id].to_i
    else
      error 'no params[:recommender_id]'
    end
    render(:nothing => true)
  end 

  def update_rigtype
    @reservation = get_reservation
    if params[:rigtype_id]
      @reservation.update_attributes :rigtype_id => params[:rigtype_id].to_i
    else
      error 'no params[:rigtype_id]'
    end
    render(:nothing => true)
  end 

  def update_seasonal
    if defined?(params[:seasonal])
      if session[:reservation_id]
	res = Reservation.find(session[:reservation_id].to_i)
	space_id = res.space_id
      else
        space_id = 0
      end
      @reservation = Reservation.new(:startdate => @option.season_start,
				     :enddate => @option.season_end,
				     :space_id => space_id,
				     :seasonal => params[:seasonal],
				     :storage => false)
      @seasonal_ok = @reservation.check_seasonal
      @storage_ok = @reservation.check_storage
      debug "seasonal_ok = #{@seasonal_ok}, storage_ok = #{@storage_ok}"
      render :update do |page|
	page[:dates].reload
      end
    else
      error 'no params[:seasonal]'
      render(:nothing => true)
    end
  rescue => err
    error err.to_s
    render(:nothing => true)
  end

  def update_storage
    if defined?(params[:storage])
      if session[:reservation_id]
	res = Reservation.find(session[:reservation_id].to_i)
	space_id = res.space_id
	startdate = res.startdate
	enddate = res.enddate
      else
        space_id = 0
	startdate = session[:startdate]
	enddate = session[:enddate]
      end
      @reservation = Reservation.new(:startdate => startdate,
				     :enddate => enddate,
				     :space_id => space_id,
				     :storage => params[:storage],
				     :seasonal => false)
      @seasonal_ok = @reservation.check_seasonal
      @storage_ok = @reservation.check_storage
      debug "seasonal_ok = #{@seasonal_ok}, storage_ok = #{@storage_ok}"
      render :update do |page|
	page[:dates].reload
      end
    else
      error 'no params[:storage]'
      render(:nothing => true)
    end
  rescue => err
    error err.to_s
    render(:nothing => true)
  end

  def update_discount
    @reservation = get_reservation
    if params[:discount_id]
      if @reservation.seasonal? && Discount.skip_seasonal?
	debug 'rendering nothing and returning'
	render(:nothing => true)
	return
      end
      @payments = Payment.find_all_by_reservation_id @reservation.id
      @reservation.update_attributes :discount_id => params[:discount_id].to_i
      @skip_render = true
      recalculate_charges
      charges_for_display(@reservation)
      render :update do |page|
	page[:charges].reload
      end
    else
      error 'no params[:discount_id]'
      render(:nothing => true)
    end
  end

  def update_extras
    @reservation = get_reservation
    if params[:extra]
      debug "in update_extras"
      @payments = Payment.find_all_by_reservation_id @reservation.id
      extra = Extra.find params[:extra].to_i
      debug "extra_type is #{extra.extra_type.to_s}"
      case extra.extra_type
      when Extra::MEASURED
	debug 'extra is MEASURED'
	if params[:checked] == 'true'
	  old = ExtraCharge.find_all_by_extra_id_and_reservation_id_and_charge(extra.id, @reservation.id, 0.0)
	  old.each {|o| o.destroy } # get rid of partially filled out records
	  ec = ExtraCharge.create :reservation_id => @reservation.id, :extra_id => extra.id
	  session[:ec] = ec.id
	  @current = @reservation.space.current
	  hide = false
	  debug "created new measured entity"
	else
	  ec = ExtraCharge.find session[:ec].to_i
	  ec.destroy
	  session[:ec] = nil
	  hide = true
	  debug "destroyed measured entity"
	end
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
	  debug "destroyed entity"
	else
	  # extra charge is not currently applied
	  # extra was added, apply it
	  ec = ExtraCharge.create :reservation_id => @reservation.id,
				  :extra_id => extra.id
	  hide = false
	  debug "created new entity"
	end
      end
      @skip_render = true
      # recalculate_charges.. skip recalc because the charges do not change
      charges_for_display(@reservation)
      # debug "recalculated charges"
      debug "saved reservation"
      cnt = "count_#{extra.id}".to_sym
      ext = "extra#{extra.id}".to_sym
      render :update do |page|
	case ec.extra.extra_type
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
	  # debug "measured"
	  measure = "measure_#{extra.id}".to_sym
	  if hide
	    # debug "hide"
	    page[measure].hide
	  else
	    # debug "show"
	    page[measure].show
	  end
	end
	# debug "reload charges"
	page[:charges].reload
      end
      # render :partial => 'space_summary', :layout => false
      debug "done with update_extras"
    else
      error 'no params[:extra]'
      render(:nothing => true)
    end
  end 

  def update_count
    @reservation = get_reservation
    if params[:extra_id]
      extra_id = params[:extra_id].to_i
      @payments = Payment.find_all_by_reservation_id @reservation.id
      ec = ExtraCharge.find_by_extra_id_and_reservation_id(extra_id, @reservation.id)
      debug "updating count to #{params[:number]}"
      ec.update_attributes :number => params[:number].to_i

      @skip_render = true
      recalculate_charges
      charges_for_display(@reservation)
      # render :partial => 'space_summary', :layout => false
      # debug "rendered space_summary"
      render :update do |page|
	# debug "reload charges"
	page[:charges].reload
      end
    else
      error 'no params[:extra_id]'
      render :nothing => true
    end
  end

  def update_initial
    @reservation = get_reservation
    if params[:value]
      debug "update initial: current = #{params[:value]}"
      @reservation.space.update_attributes :current => params[:value].to_f
    else
      error 'no params[:value]'
    end
    render :nothing => true
  end

  def update_final
    @reservation = get_reservation
    if params[:value] && params[:extra_id]
      final = params[:value].to_f
      final = 0.0 unless final
      extra_id = params[:extra_id].to_i
      debug "update_final: final = #{final}, extra_id = #{extra_id}"
      @payments = Payment.find_all_by_reservation_id @reservation.id
      @extra = Extra.find params[:extra_id].to_i

      initial = @reservation.space.current ? @reservation.space.current.to_f : 0.0
      used =  final - initial
      debug "initial = #{initial}, final = #{final}, used = #{used}"
      if used > 0
	debug "computing charges"
	# compute charges
	charge = used * @extra.rate
	debug "charge = #{charge}"
	# update charges
	ec = ExtraCharge.create(:extra_id => @extra.id,
				:reservation_id => @reservation.id,
				:initial => initial,
				:measured_rate => @extra.rate,
				:final => final,
				:charge => charge )
	# set new current value
	@reservation.space.update_attributes :current => final
	@skip_render = true
	# recalculate_charges
	charges_for_display(@reservation)
	render :update do |page|
	  # debug "reload charges"
	  page[:charges].reload
	end
      else
	# flash warning
	debug "computing charges"
	render :nothing => true
      end
    else
      error 'no params[:value] or [:extra_id]'
      render :nothing => true
    end
  end

  def update_mail_msg
    @reservation = get_reservation
    if @reservation.deposit == 0.0
      pmt = Payment.find_by_reservation_id @reservation.id
      @reservation.update_attributes :deposit => pmt.amount if pmt
    end
    sent = false
    if @option.use_confirm_email?
      if Email.address_valid?(@reservation.camper.email)
	begin
	  email = ResMailer.deliver_reservation_update(@reservation)
	  sent = true
	rescue => err
	  error err.to_s
	end
      end
    end
    render :update do |page|
      if sent
	page[:flash].replace_html "<span id=\"inputError\">" + I18n.t('reservation.Flash.UpdateSent') + "</span>"
	page[:flash][:style][:color] = 'green'
      else
	page[:flash].replace_html "<span id=\"inputError\">" + I18n.t('reservation.Flash.UpdateErr') + "</span>"
	page[:flash][:style][:color] = 'red'
      end
      page[:flash].visual_effect :highlight
      page[:update_mail_msg].replace_html ""
    end
  end

  def purge
    id = params[:reservation_id]
    if User.authorized?('reservation','purge')
      begin
	Reservation.destroy id
	info "reservation #{id} purged"
      rescue ActiveRecord::RecordNotFound => err
	flash[:error] = I18n.t('reservation.Flash.Purged', :id => id)
      end
      arch = Archive.find_by_reservation_id id
      begin
	Archive.destroy arch.id
	info "archive #{arch.id} for reservation #{id} purged"
      rescue => err
	flash[:error] = I18n.t('reservation.Flash.Purged', :id => id)
      end
      flash[:notice] = I18n.t('reservation.Flash.Purged', :id => id)
    else
      flash[:error] = I18n.t('general.Flash.NotAuth')
    end
    redirect_to :action => 'list'
  rescue => err
    redirect_to :action => 'list'
  end

  def abandon
    res = Reservation.find(params[:reservation_id].to_i)
    if res.id != 0
      Reason.close_reason_is "abandoned"
      begin
	res.archive
      rescue RuntimeError => err
	error 'Abandon: ' + err.to_s
      rescue ActiveRecord::StaleObjectError => err
	error 'Abandon: ' + err.to_s
	locking_error(res)
      end
      flash[:notice] = "Reservation #{res.id} deleted"
    else
      res.destroy
    end
    SpaceAlloc.delete_all(["reservation_id = ?", session[:reservation_id]])
    session[:reservation_id] = nil
    session[:payment_id] = nil
    session[:group_id] = nil
    session[:current_action] = 'show'
  rescue ActiveRecord::RecordNotFound => err
    info err.to_s
    # probably means the reservation is already gone
  rescue => err
    error err.to_s
  ensure
    if session[:list]
      redirect_to :action => session[:list], :controller => :reservation
    else
      redirect_to :action => :list, :controller => :reservation
    end
  end

  private
  ####################################################
  # methods that cannot be called externally
  ####################################################

  def set_defaults
    if params[:controller] == 'reservation'
      session[:remote] = nil
    end
    @skip_render = false
  end

  def new_variable_charge
    debug 'new_variable_charge'
    debug "params are #{params[:variable_charge]}"
    variable_charge = VariableCharge.new(params[:variable_charge])
    variable_charge.reservation_id = @reservation.id
    variable_charge.save!
    if params[:taxes]
      params[:taxes].each do |t|
	tax = Taxrate.find_by_name t[0]
	if t[1] == '1'
	  variable_charge.taxrates << tax unless variable_charge.taxrates.exists?(tax)
	else
	  variable_charge.taxrates.delete(tax) if variable_charge.taxrates.exists?(tax)
	end
      end
    end
  end

  def get_reservation
    if params[:reservation_id] && params[:reservation_id] != ''
      reservation = Reservation.find(params[:reservation_id].to_i)
      debug 'got res from params'
      session[:reservation_id] = reservation.id
    else
      reservation = Reservation.find(session[:reservation_id].to_i)
      info 'got res from session'
    end
    reservation
  rescue ActiveRecord::RecordNotFound => err
    error 'Reservation not found ' + err.to_s
    flash[:error] = I18n.t('reservation.Flash.NotFound',
			    :id => session[:reservation_id])
    if session[:list]
      redirect_to :action => session[:list] and return
    else
      redirect_to :action => :list and return
    end
  end

  def get_reservation_by_id
    # the set functions from inplace edit pass the 
    # reservation id in an id parameter
    if params[:id]
      reservation = Reservation.find(params[:id].to_i)
      debug 'got res from params'
      session[:reservation_id] = reservation.id
    else
      reservation = Reservation.find(session[:reservation_id].to_i)
      info 'got res from session'
    end
    reservation
  rescue ActiveRecord::RecordNotFound => err
    error 'Reservation not found ' + err.to_s
    flash[:error] = I18n.t('reservation.Flash.NotFound',
			    :id => session[:reservation_id])
    if session[:list]
      redirect_to :action => session[:list] and return
    else
      redirect_to :action => :list and return
    end
  end

  def check_length res
    if  res.space.length > 0 &&
	res.length &&
	res.length > res.space.length
	  flash[:warning] = I18n.t('reservation.Flash.CamperLong',
				    :camper_length => res.length,
				    :space_length => res.space.length)
    end
  end

  def spaces_for_display(res, season, sitetype)
    sp = []
    spaces = Space.available(res.startdate, res.enddate, sitetype)
    debug "#{spaces.size} spaces found"
    spaces.each do |s|
      rate = Rate.find_current_rate(season.id, s.price_id)
      if res.storage?
	next unless @option.use_storage? 
	next if rate.not_storage
      elsif res.seasonal?
	next unless @option.use_seasonal?
	next if rate.not_seasonal
      else
	next if rate.no_rate?(res.enddate - res.startdate)
      end
      sp << s
    end
    debug "#{sp.size} spaces kept"
    return sp
  end

  ###################################################################
  # a method to muster the charge variables for display
  ###################################################################
  def charges_for_display(res)
    warn = ''
    res.reload
    debug "charges_for_display"
    @season_cnt = Season.active.count
    @charges = Charge.stay(res.id)
    total = 0.0
    @charges.each do |c| 
      warn += "charge rate for season #{c.season.name} is zero. Correct in setup->prices." if c.amount == 0.00
      total += c.amount - c.discount 
    end
    flash[:warning] = warn unless warn.empty?
    debug "charges #{total}"
    total += calculate_extras(res.id)
    debug "added extras #{total}"
    total += VariableCharge.charges(res.id)
    debug "added variable #{total}"
    total -= res.onetime_discount
    debug "after onetime discount #{total}"
    tax_amount = Taxrate.calculate_tax(res.id, @option)
    debug "saving total #{total} and tax_amount #{tax_amount}"
    res.update_attributes(:total => total, :tax_amount => tax_amount)
    debug "getting taxes"
    @tax_records = Tax.find_all_by_reservation_id(res.id)
    debug "getting extras"
    @extras = Extra.active
    debug "getting payments"
    @payments = Payment.find_all_by_reservation_id session[:reservation_id].to_i
  end


  def get_sort
    ####################################################
    # get the sort attribute for options
    ####################################################
    list = case session[:list]
      when 'list' then 'res'
      when 'expand' then 'res'
      when 'in_park' then 'inpark'
      when 'in_park_expand' then 'inpark'
    end
    list + '_list_sort'
  end

  def complete_checkin
    ####################################################
    # Complete checkin.
    ####################################################
    if @reservation.space.unavailable
      flash[:error] = I18n.t('reservation.Flash.CheckinFailUnavail',
                             :space => @reservation.space.name,
			     :camper_name => @reservation.camper.full_name,
			     :reservation_id => @reservation.id)
    elsif rr = @reservation.space.occupied
      flash[:error] = I18n.t('reservation.Flash.CheckinFailOcc',
                             :space => @reservation.space.name,
			     :camper_name => @reservation.camper.full_name,
			     :reservation_id => @reservation.id,
			     :other_camper => rr.camper.full_name,
			     :other_reservation => rr.id)
    else
      @reservation.add_log("checkin")
      begin
	if @reservation.save
	  flash[:notice] = I18n.t('reservation.Flash.CheckedIn',
	                          :camper_name => @reservation.camper.full_name,
				  :space => @reservation.space.name)
	  session[:reservation_id] = nil
	  session[:payment_id] = nil if session[:payment_id] 
	else
	  flash[:error] = I18n.t('reservation.Flash.CheckinFail',
	                         :camper_name => @reservation.camper.full_name,
				 :space => @reservation.space.name)
	end
      rescue ActiveRecord::StaleObjectError => err
	error err.to_s
	locking_error(@reservation)
      rescue => err
	error err.to_s
	flash[:error] = I18n.t('reservation.Flash.CheckinFail',
	                       :camper_name => @reservation.camper.full_name,
			       :space => @reservation.space.name)
      end
    end
    redirect_to :action => 'list'
  end

  def create_res(skip_email = false)
    ####################################################
    # save the data in the database
    ####################################################
    @reservation.confirm = true
    payment = Payment.find_by_reservation_id(@reservation.id)
    @reservation.deposit = payment.amount if payment
    @reservation.add_log("reservation made")
    if @reservation.save
      flash[:notice] = I18n.t('reservation.Flash.UpdateSuccess',
                              :reservation_id => @reservation.id,
			      :camper_name => @reservation.camper.full_name)
      if @option.use_confirm_email? && (skip_email == false)
	if Email.address_valid?(@reservation.camper.email)
	  begin
	    email = ResMailer.deliver_reservation_confirmation(@reservation)
	    flash[:warning] = I18n.t('reservation.Flash.ConfSent')
	  rescue => err
	    flash[:error] = I18n.t('reservation.Flash.ConfErr')
	    error err.to_s
	  end
	else
	  flash[:warning] = I18n.t('reservation.Flash.ConfNotSent')
	end
      end
    else
      raise
    end
    session[:group_id] = nil
  end

  def contract(res)
    ####################################################
    # given the reservation find if it should be displayed
    ####################################################
    if res.group_id == nil
      @saved_group = nil
      nil
    else
      if res.group_id == @saved_group
	1
      else
	@saved_group = res.group_id
	nil
      end
    end
  end

end
