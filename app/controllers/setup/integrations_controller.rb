class Setup::IntegrationsController < ApplicationController
  before_filter :login_from_cookie
  before_filter :check_login
  before_filter :authorize

  def edit
    @page_title = 'Edit Payment Gateway Configuration'
    @integration = Integration.first_or_create
  end

  def update
    debug
    @integration = Integration.first
    if params[:name]
      @integration.update_attributes :name => params[:name]
      render :update do |page|
	page.replace_html('integration', :partial => 'integrations')
      end
      return
    else
      debug "ENV['API_Key'] is #{ENV['API_Key']}"
      if @integration.name.include?('CardConnect')
	if Rails.env.production?
	  params[:integration].merge!({"cc_endpoint" =>"https://boltgw.cardconnect.com:8443","cc_bolt_endpoint" =>"https://bolt.cardpointe.com:443", "cc_bolt_api_key" => ENV['API_Key']})
	else
	  params[:integration].merge!({"cc_endpoint" =>"https://boltgw.cardconnect.com:6443","cc_bolt_endpoint" =>"https://bolt-uat.cardpointe.com:6443", "cc_bolt_api_key" => ENV['API_Key']})
	end
      end
      debug "params[:integration] are #{params[:integration].inspect}"
      if @integration.update_attributes(params[:integration])
	flash[:notice] = 'Update successful'
	debug 'update successful'
      else
	flash[:error] = 'Integration Update failed: ' + @integration.errors.full_messages[0]
	error 'Integration Update failed' + @integration.errors.full_messages[0]
      end
    end
    redirect_to edit_setup_integration_url(:id => 0)
  rescue => err
    error err
    redirect_to edit_setup_integration_url(:id => 0)
  end

end
