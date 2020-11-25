class Setup::InitdbController < ApplicationController

  def initdemo
    require 'resolv'
    rem = request.remote_ip
    srv = Resolv::getaddress request.host
    if srv == rem
      # only do this from local machine
      # this is intended only for the demo system
      initdb
    else
      debug 'rejected... not same host'
      redirect_to :controller=> '/reservation', :action => 'list'
    end
  end

  def initdb
    debug 'in initdb..........................................'
    if Rails.env.production?
      # this is only designed for a demo or training system
      debug 'redirecting'
      redirect_to :controller=> '/reservation', :action => 'list' and return
    end
    debug 'reloading'
    ############################################
    # db reset replaces db from schema and seeds
    ############################################
    Rake::Task["db:reset"].execute
    debug 'reset done'
    Rake::Task["db:load_db_from_fixtures"].execute
    debug 'load done'
    # reread the options.
    @option = Option.first
    # get rid of the login info because everything 
    # may have changed
    session[:user_id] = nil
    # need to calculate charges on all reservations
    Reservation.all.each do |res|
      Charges.new( res.startdate,
		   res.enddate,
		   res.space.price.id,
		   res.discount.id,
		   res.id,
		   res.seasonal)
      charges = Charge.stay(res.id)
      total = 0.0
      charges.each { |c| total += c.amount - c.discount }
      total += calculate_extras(res.id)
      total -= res.onetime_discount
      tax_amount = Taxrate.calculate_tax(res.id, @option)
      debug "total #{total}, tax_amount #{tax_amount}, res_id #{res.id}"
      res.update_attributes :total => total, :tax_amount => tax_amount
    end
    redirect_to :controller=> '/reservation', :action => 'list'
  #rescue
    #logger.error "error in Initdb:initdemo"
    #flash[:error] = "Application error"
  end
end
