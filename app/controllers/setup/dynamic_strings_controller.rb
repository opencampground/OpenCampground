class Setup::DynamicStringsController < ApplicationController
  before_filter :login_from_cookie
  before_filter :check_login, :except => [:index]
  before_filter :authorize, :except => [:index]

  # caches_page :index
  # serve dynamic stylesheet with name defined
  # by filename on incoming URL parameter :name
  def index
    # logger.debug "finding #{params[:name]}"
    filename = params[:name].to_s
    if @stylefile = DynamicString.find_by_name(filename.downcase)
      case File.extname(filename).downcase
      when '.css'
	# logger.debug "sending #{filename} as text/css"
	send_data(@stylefile.text, :type => "text/css", :disposition => 'inline')
      when '.jpg', '.jpeg'
	# logger.debug "sending #{filename} as image/jpeg"
	send_data(@stylefile.text, :type => "image/jpeg", :disposition => 'inline')
      when '.gif'
	# logger.debug "sending #{filename} as image/gif"
	send_data(@stylefile.text, :type => "image/gif", :disposition => 'inline')
      when '.png'
	# logger.debug "sending #{filename} as image/png"
	send_data(@stylefile.text, :type => "image/png", :disposition => 'inline')
      when '.bmp'
	# logger.debug "sending #{filename} as image/png"
	send_data(@stylefile.text, :type => "image/bmp", :disposition => 'inline')
      when '.js'
	# logger.debug "sending #{filename} as application/javascript"
	send_data(@stylefile.text, :type => "application/javascript", :disposition => 'inline')
      else
	# logger.debug "sending #{filename} as text/plain"
	send_data(@stylefile.text, :type => "text/plain", :disposition => 'inline')
      end
    else #no method/action specified
      render(:nothing => true, :status => 404)
    end #if @stylefile..
  end #index

  def list
    @file_list = DynamicString.all :conditions => ["name != ? and name != ?", 'Logo.jpg', 'Logo.png']
    @logo_file_list = DynamicString.all :conditions => ["name = ? or name = ?", 'Logo.jpg', 'Logo.png']
  end

  def uploadDynamicFile
    name = ''
    if params[:upload]
      name = File.basename params[:upload].original_filename
      logger.debug "file name is #{name}"
      # store data in db
      if (ds = DynamicString.find_by_name(name))
	ds.destroy
      end
      ds = DynamicString.create! :name => name, :text => params[:upload].read
    else
      flash[:error]= 'No file selected, Browse for a file'
    end
    case name
    when 'Logo.jpg'
      fn = Rails.root.join('public','images','Logo.jpg')
      f = File.new(fn, "w")
      f.syswrite(ds.text)
      f.close
      debug "created #{fn}"
      fn = Rails.root.join('public','images','Logo.png')
      File.delete fn if File.exists? fn
      if (ds = DynamicString.find_by_name('Logo.png'))
	debug "deleting #{fn}"
	ds.destroy
      end
    when 'Logo.png'
      fn = Rails.root.join('public','images','Logo.png')
      f = File.new(fn, "w")
      f.syswrite(ds.text)
      f.close
      debug "created #{fn}"
      fn = Rails.root.join('public','images','Logo.jpg')
      File.delete fn if File.exists? fn
      if (ds = DynamicString.find_by_name('Logo.jpg'))
	debug "deleting #{fn}"
	ds.destroy
      end
    end
    redirect_to :action => :list
  end

  def uploadLocalFile
    if params[:upload]
      @option.update_attribute :css, params[:upload].read
    else
      flash[:error]= 'No file selected, Browse for a file'
    end
    redirect_to :action => :list
  end

  def uploadRemoteFile
    if params[:upload]
      @option.update_attribute :remote_css, params[:upload].read
    else
      flash[:error]= 'No file selected, Browse for a file'
    end
    redirect_to :action => :list
  end

  def remove_remote
    # remove from options
    @option.update_attribute :remote_css, nil
    redirect_to :action => :list
  end

  def remove_local
    # remove from options
    @option.update_attribute :css, nil
    redirect_to :action => :list
  end

  def do_delete
    if params[:id]
      ds = DynamicString.find params[:id]
      if ds.name == 'Logo.jpg' or ds.name == 'Logo.png'
	fn = Rails.root.join('public','images',ds.name)
	File.delete fn if File.exists? fn
      end
      ds.destroy
    end
    redirect_to :action => :list
  end

end
