class Setup::EmailController < ApplicationController
  before_filter :login_from_cookie
  before_filter :check_login
  before_filter :authorize

#####################################################
# Email Configuration
#####################################################
  def list
    @page_title = 'Email configuration'
    @email = Email.first
    unless @email
      @email = Email.new
      @email.save
    end
  end

  def edit
    @page_title = 'Edit Email configuration'
    @email = Email.first
    unless @email
      @email = Email.new
      @email.save
    end
  end

  def update
    @email = Email.first
    if @email.update_attributes(params[:email])
      flash[:notice] = "Update successful"
      restart(false)
      redirect_to :action => :list and return
    else
      flash[:error] = "Error in update"
      redirect_to :action => :edit and return
    end
  end

  def send_test
    email = ResMailer.deliver_tst
  rescue => error
    flash[:error] = "email test failed: #{error.message}"
  ensure
    redirect_to :action => :list and return
  end

end
