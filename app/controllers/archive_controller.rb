class ArchiveController < ApplicationController
  before_filter :login_from_cookie
  before_filter :check_login
  before_filter :clear_session

  def index
    @page_title = 'Archives'
    list
    render :action => 'list'
  end

# GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
#  verify :method => :post, :only => :destroy,
#         :redirect_to => { :action => :list }

  def list
    @page_title = 'Archives'
    session[:reservation_id] = nil
    if params[:page]
      session[:a_page] = params[:page]
      page = params[:page]
    elsif session[:a_page]
      page = session[:a_page]
    else 
      page = 1
      session[:a_page] = 1
    end
    @archives = Archive.paginate :order => @option.archive_list_sort, :page => page, :per_page => @option.disp_rows
  rescue
    @option.update_attributes :archive_list_sort => "startdate ASC"
    @archives = Archive.paginate :order => @option.archive_list_sort, :page => params[:page], :per_page => @option.disp_rows
  end

  def show
    session[:reservation_id] = nil
    @archive = Archive.find(params[:archive_id].to_i)
    @page_title = "Archived Reservation #{@archive.reservation_id}"
    @payments = @archive.payments
    @reservation = Reservation.find @archive.reservation_id
  rescue ActiveRecord::RecordNotFound
    @reservation = false
  end

  def destroy
    Archive.find(params[:archive_id].to_i).destroy
    redirect_to :action => 'list'
  end

  def sort_by_res
    @option.update_attributes :archive_list_sort => "reservation_id, id ASC"
    redirect_to :action => 'list'
  end

  def sort_by_name
    @option.update_attributes :archive_list_sort => "name ASC"
    redirect_to :action => 'list'
  end

  def sort_by_start
    @option.update_attributes :archive_list_sort => "startdate ASC"
    redirect_to :action => 'list'
  end

  def sort_by_end
    @option.update_attributes :archive_list_sort => "enddate ASC"
    redirect_to :action => 'list'
  end

  def sort_by_space
    @option.update_attributes :archive_list_sort => "space_name ASC"
    redirect_to :action => 'list'
  end

  def update_sel
    a = Archive.find(params[:archive_id].to_i)
    a.update_attribute :selected, !a.selected
    render(:nothing => true) 
  end

  def select_all
    Archive.all.each do |a|
      a.update_attribute :selected, true
    end
    redirect_to :action => 'list'
  end

  def clear_all
    Archive.all.each do |a|
      a.update_attribute :selected,  false
    end
    redirect_to :action => 'list'
  end

  def delete_selected
    Archive.find_all_by_selected(true).each do |a|
      debug "#{a.id} selected"
      a.destroy
    end
    redirect_to :action => 'list'
  end

  def download_selected
    csv_string = 'name,address,address2,city,state,mail_code,country,email,phone,phone_2, '
    csv_string << 'startdate, enddate, '
    csv_string << 'vehicle_license,vehicle_state,vehicle_license_2,vehicle_state_2,'
    csv_string << 'rigtype_name,slides,length,rig_age,'
    csv_string << 'adults,pets,kids,'
    csv_string << 'space_name,deposit,total_charge,tax_str,'
    csv_string << 'group_name,discount_name,special_request,close_reason,canceled,'
    csv_string << 'idnumber,log,recommender,seasonal'
    csv_string << "\n"

    #data
    Archive.find_all_by_selected(true).each do |a|
      debug "#{a.id} selected"
      csv_string << "\"#{a.name}\",\"#{a.address}\",\"#{a.address2}\",\"#{a.city}\",\"#{a.state}\",\"#{a.mail_code}\",\"#{a.country}\",\"#{a.email}\",\"#{a.phone}\",\"#{a.phone_2}\","
      csv_string << "\"#{a.startdate}\",\"#{a.enddate}\","
      csv_string << "\"#{a.vehicle_license}\",\"#{a.vehicle_state}\",\"#{a.vehicle_license_2}\",\"#{a.vehicle_state_2}\","
      csv_string << "\"#{a.rigtype_name}\",\"#{a.slides}\",\"#{a.length}\",\"#{a.rig_age}\","
      csv_string << "\"#{a.adults}\",\"#{a.pets}\",\"#{a.kids}\",\"#{a.space_name}\","
      csv_string << "\"#{a.deposit}\",\"#{a.total_charge}\",\"#{a.tax_str}\","
      csv_string << "\"#{a.group_name}\",\"#{a.discount_name}\",\"#{a.special_request}\",\"#{a.close_reason}\",\"#{a.canceled}\","
      csv_string << "\"#{a.idnumber}\",\"#{a.log}\",\"#{a.recommender}\",\"#{a.seasonal}\"\n"
    end

    send_data csv_string,
              :type => 'text/csv;charset=iso-8859-1;header=present',
              :disposition => 'attachment; filename=Archive.csv'
  end

end
