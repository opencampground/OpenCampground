class BogusController < ApplicationController

  def index
    str = ''
    params[:anything].each do |p|
      str += p + ' '
    end
    error 'from ' + request.remote_ip + ' params => /' +  str
    render :nothing => true
  end

end
