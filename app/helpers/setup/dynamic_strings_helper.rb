module Setup::DynamicStringsHelper

  def show_image name
    parts = name.partition('.')
    case parts[2].downcase
    when 'jpg','png','gif'
      '<td><img src="/dynamic/' + name + '" height="20" /></td>'
    end
  end

end
