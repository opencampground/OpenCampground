class Setup::MapController < ApplicationController
  before_filter :login_from_cookie
  before_filter :check_login
  before_filter :authorize

#####################################################
# Maps
#####################################################
  def edit
    @page_title = 'Set Maps'
    @use_map = @option.use_map
    if @use_map
      @map = @option.map
    else
      @map = ''
    end
    debug 'map: ' + (@map ? @map : '')
    debug @use_map.to_s
    @use_remote_map = @option.use_remote_map
    if @use_remote_map
      @remote_map = @option.remote_map
    else
      @remote_map = ''
    end
    debug 'remote map: ' + (@remote_map ? @remote_map : '')
    debug @use_remote_map.to_s
  end
  
  def update
  end
  
  def delete
    
    if @option.map == @option.remote_map
      case params[:id]
      when 'local'
        @option.update_attributes :map => ''
      when 'remote'
        @option.update_attributes :remote_map => ''
      end
    else
      case params[:id]
      when 'local'
        begin
          filename = 'public/map/'+ @option.map
          debug 'filename: ' + filename
          if File::delete filename
            debug 'file delete succeeded: ' + filename
            @option.update_attributes :map => ''
          else
            flash[:error] = 'Error in file deletion'
            @option.update_attributes :map => '' unless File.exist?(filename)
            error 'Error deleting file: ' + filename 
          end
        rescue => err
          @option.update_attributes :map => '' unless File.exist?(filename)
          flash[:error] = 'Error in file deletion ' + err
          error 'Error deleting file ' + err
        end
      when 'remote'
        begin
          filename = 'public/map/'+ @option.remote_map
          debug 'filename: ' + filename
          if File::delete filename
            debug 'file delete succeeded: ' + filename
            @option.update_attributes :remote_map => ''
          else
            flash[:error] = 'Error in file deletion'
            @option.update_attributes :remote_map => '' unless File.exist?(filename)
            error 'Error deleting file: ' + filename 
          end
        rescue => err
          @option.update_attributes :remote_map => '' unless File.exist?(filename)
          flash[:error] = 'Error in file deletion ' + err
          error 'Error deleting file ' + err
        end
      else
        debug 'invalid map: ' + params[:id]
      end
    end
  rescue => err
    flash[:error] = 'Error in file deletion'
    error 'Error deleting file ' + err
  ensure
    redirect_to :action => :edit
  end
  
  def uploadRemoteMapFile
    unless params[:upload]
      flash[:error]= 'No Filename specified. Browse to find a map file'
      redirect_to :action => :edit and return
    end
    name = uploadFile params[:upload]
    debug name
    @option.update_attributes :remote_map => name
    redirect_to :action => :edit
  end
  
  def uploadMapFile 
    unless params[:upload]
      flash[:error]= 'No Filename specified. Browse to find a map file'
      redirect_to :action => :edit and return
    end
    name = uploadFile params[:upload]
    debug name
    @option.update_attributes :map => name
    redirect_to :action => :edit and return
  end

  private
  def uploadFile filename
    name =  filename.original_filename
    name = sanitize_filename name
    directory = "public/map"
    # create the file path
    path = File.join(directory, name)
    debug path
    if File::exist? path
      return name
    end
    # write the file
    if File.open(path, "wb") { |f| f.write(params[:upload].read) }
      flash[:notice] = "File upload succeeded"
    else
      flash[:error] = "File upload failed"
    end
    return name
  rescue => err
    flash[:error] = "File upload failed.  Did you select a file to upload?"
    error err.to_s
  end
  
end
