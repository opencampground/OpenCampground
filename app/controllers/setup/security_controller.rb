class Setup::SecurityController < ApplicationController
  require 'digest'
  before_filter :login_from_cookie
  before_filter :check_login
  before_filter :authorize
  def list
    @page_title = 'Security Variables Configuration'
  end

  def edit
    @page_title = 'Edit Security Variables Configuration'
  end

  def generate
    cookie_token = Digest::SHA2.hexdigest Time.now.usec.to_s
    sleep 1.0
    session_token = Digest::SHA2.hexdigest Time.now.usec.to_s
    @option.update_attributes :cookie_token => cookie_token, :session_token => session_token
    redirect_to :action => :list
  end

  def update
    if @option.update_attributes(params[:option])
      flash[:notice] = "Update successful"
      redirect_to :action => :list
    else
      render :edit
    end
  end

end
