class Setup::PaypalController < ApplicationController
  before_filter :login_from_cookie
  before_filter :check_login
  before_filter :authorize
  def list
    @page_title = 'Remote Reservation Configuration'
  end

  def edit
    @page_title = 'Edit Remote Reservation Configuration'
  end

  def update
    if @option.update_attributes(params[:option])
      flash[:notice] = "Update successful"
    else
      flash[:error] = "Update failed"
    end
    redirect_to :action => :list
  end

end
