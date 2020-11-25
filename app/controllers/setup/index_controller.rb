class Setup::IndexController < ApplicationController
  before_filter :cookies_required, :only => [:index ]
  before_filter :login_from_cookie
  before_filter :check_login
  before_filter :authorize

  def index
    @page_title = "Setup"
  end
end
