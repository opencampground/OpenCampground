class PaymentsController < ApplicationController
  before_filter :login_from_cookie
  before_filter :check_login
  before_filter :clear_session

  # GET /payments
  def index
    @page_title = 'Payments by Reservation'
    if params[:page]
      page = params[:page]
      session[:page] = page
    else
      page = session[:page]
    end
    if params[:id]
      @payments = Payment.paginate :page => 1, :conditions => ["reservation_id = ?", params[:id]], :order => "pmt_date ASC"
    else
      @payments = Payment.paginate(:page => page, :per_page => @option.disp_rows, :include => "creditcard", :order => "reservation_id desc, created_at")
    end
  end

  # GET /payment/1
  def show
    @page_title = 'Payments by Reservation'
    if params[:page]
      page = params[:page]
    else
      page = session[:page]
    end
    @payments = Payment.all :conditions => ["reservation_id = ?", params[:id]], :order => "pmt_date ASC"
  end

  # GET /payments/1/edit
  def edit
    @payment = Payment.find(params[:id].to_i)
    @page_title = "Edit Payment #{@payment.id} for Reservation #{@payment.reservation_id}"
  end

  # PUT /payments/1
  def update
    @payment = Payment.find(params[:id].to_i)

    if @payment.update_attributes(params[:payment])
      flash[:notice] = 'Payment updated'
      Reservation.find(@payment.reservation_id).add_log("payment #{@payment.id} updated")
      redirect_to(payments_url)
    else
      flash[:error] = 'Payment update failed'
      render :action => "edit"
    end
  end

  # DELETE /payments/1
  def destroy
    payment = Payment.find(params[:id].to_i)
    payment.destroy
    begin
      Reservation.find(payment.reservation_id).add_log("payment #{payment.id} record destroyed")
    rescue
    end
    redirect_to(payments_url)
  end

end
