class Report::PaymentsController < ApplicationController
  before_filter :login_from_cookie
  before_filter :check_login
  include ApplicationHelper

  # GET /report_payments/new
  # GET /report_payments/new.xml
  def new
    @page_title = "Payments Report Definition"
    @reservation = Reservation.new
    @reservation.startdate = currentDate
    @reservation.enddate = currentDate
    @today = true
    @yesterday = false
    @l_week = false
    @l_month = false
    @l_year = false
    @payment = Payment.new
  end

  # POST /report_payments
  # POST /report_payments.xml
  def create
    if params[:csv]
      startdate = session[:startdate]
      enddate = session[:enddate]
      sort = session[:sort]
      if startdate == enddate
	csv_string = "\"Payments\", #{startdate}\n"
      else
	csv_string = "\"Payments\", #{startdate}, \"thru\", #{enddate}\n"
      end
      @payments = Payment.all(:conditions => ["pmt_date >= ? AND pmt_date < ?",
					      startdate.to_datetime.at_midnight,
					      enddate.tomorrow.to_datetime.at_midnight],
			      :include => ['reservation','creditcard'],
			      :order => 'reservation_id')
      csv_string << '"ID","Res #","Camper","Space Name","Sitetype","Pmt Type","Date","Memo","Charges","Tax","Total"'
      csv_string << "\n"
      total = 0.0
      @payments.each do |p|
	date = p.pmt_date.strftime("%m/%d/%Y")
	net,tax = p.taxes
	debug p.creditcard.inspect
	begin
	  res = Reservation.find p.reservation_id
	  debug "reservation #{p.reservation_id} found"
	  name = res.camper.full_name
	rescue
	  debug "reservation #{p.reservation_id} not found"
	  name = Archive.find_by_reservation_id(p.reservation_id).name
	end
	csv_string << "\"#{pmt_id(p)}\", #{p.reservation_id},\"#{name}\",#{p.reservation.space.name},#{p.reservation.space.sitetype.name}\",\"#{p.creditcard.name}\",#{date},\"#{p.memo}\",#{net.round(2)},#{tax.round(2)},#{p.amount.round(2)}\n"
      end
      send_data(csv_string, 
		:type => 'text/csv;charset=iso-8859-1;header=present',
		:disposition => 'attachment; filename=Payments.csv') if csv_string.length
    elsif params[:bsa]
      csv_string = ""
      startdate = session[:startdate]
      enddate = session[:enddate]
      sort = session[:sort]
      @payments = Payment.all(:conditions => ["pmt_date >= ? AND pmt_date < ?",
					      startdate.to_datetime.at_midnight,
					      enddate.tomorrow.to_datetime.at_midnight],
			      :include => ['reservation','creditcard'],
			      :order => 'reservation_id')
      # csv_string << '"Post Date", "Reciept Item Code", "Reference #", "GL number Debit", "GL number Credit", "Amount", "Paid by", "Tender type code"'
      # csv_string << "\n"
      total = 0.0
      @payments.each do |p|
	date = p.pmt_date.strftime("%m/%d/%Y")
	net,tax = p.taxes
	debug p.creditcard.inspect
	begin
	  res = Reservation.find p.reservation_id
	  name = res.camper.full_name
	rescue
	  debug "reservation #{p.reservation_id} not found"
	  name = Archive.find_by_reservation_id(p.reservation_id).name
	end
	csv_string << "#{p.updated_at.strftime("%m/%d/%Y")},\"OCG\",\"#{p.reservation_id}\",,,#{p.amount.round(2)},\"#{name}\",\"#{p.creditcard.name}\"\n"
      end
      send_data(csv_string, 
		:type => 'text/csv;charset=iso-8859-1;header=present',
		:disposition => 'attachment; filename=Payments.csv') if csv_string.length
    else
      @res = Reservation.new(params[:reservation])
      session[:startdate] = @res.startdate
      session[:enddate] = @res.enddate
      @sort = params[:payment][:subtotal]
      session[:sort] = @sort
      @payments = 0.0
      if @res.startdate == @res.enddate
	@page_title = "Payments for #{@res.startdate} sorted by #{@sort}"
      else
	@page_title = "Payments for #{@res.startdate} thru #{@res.enddate} sorted by #{@sort}"
      end
      case @sort
      when 'None'
	order = 'reservation_id'
      when 'Reservation'
	order = 'reservation_id,pmt_date'
      when 'Month', 'Week'
	order = 'pmt_date'
      when 'Payment Type'
	order = 'creditcard_id,pmt_date'
      end

      @payments = Payment.all(:conditions => ["pmt_date >= ? AND pmt_date < ?",
					      @res.startdate.to_datetime.at_midnight,
					      @res.enddate.tomorrow.to_datetime.at_midnight],
			      :include => ['reservation','creditcard'],
			      :order => order )
    end
    unless @payments.size > 0 
      flash[:notice] = "No payments for #{@res.startdate} thru #{@res.enddate}"
      redirect_to new_report_payment_url
    else
      @subtotal = 0.0
      @net_sub = 0.0
      @tax_sub = 0.0
      @first_time = true
      @count = 0
      @res = 0
      @week =  @payments[0].pmt_date.to_date.cweek
      @dt = @payments[0].pmt_date.to_date
      @month = @dt.month
      @card =  @payments[0].creditcard_id
      debug @card.inspect
      @cardname =  @payments[0].creditcard.name
    end
  end

  # PUT /report_payments/1
  # PUT /report_payments/1.xml
  def update
    @reservation = Reservation.new
    case params[:when]
    when 'today'
      @reservation.startdate = currentDate
      @reservation.enddate = currentDate
      @today = true
      @yesterday = false
      @l_week = false
      @l_month = false
      @l_year = false
    when 'yesterday'
      @reservation.startdate = currentDate.yesterday
      @reservation.enddate = currentDate.yesterday
      @today = false
      @yesterday = true
      @l_week = false
      @l_month = false
      @l_year = false
    when 'l_week'
      # wk = currentDate.cweek
      # wk -= 1
      sd,ed = get_dates_from_week(currentDate.year, currentDate.cweek - 1, 1)
      ed -= 1.day
      debug "sd #{sd}, ed #{ed}"
      @reservation.startdate = sd
      @reservation.enddate = ed
      @today = false
      @yesterday = false
      @l_week = true
      @l_month = false
      @l_year = false
    when 'l_month'
      dt = currentDate.change(:month => (currentDate.month - 1))
      debug "dt #{dt}"
      @reservation.startdate = dt.beginning_of_month
      @reservation.enddate = dt.end_of_month
      @today = false
      @yesterday = false
      @l_week = false
      @l_month = true
      @l_year = false
    when 'l_year'
      year = currentDate.year
      year -= 1
      @reservation.startdate = Date.new( year, 1, 1)
      @reservation.enddate = Date.new( year, 12, 31)
      @today = false
      @yesterday = false
      @l_week = false
      @l_month = false
      @l_year = true
    else
    end
    debug "#{@reservation.startdate}, #{@reservation.enddate}"
    render :update do |page|
      page[:dates].replace_html :partial => 'report/shared/dates'
    end
  end
end
