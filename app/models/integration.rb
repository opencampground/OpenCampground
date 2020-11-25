class Integration < ActiveRecord::Base
  before_save :remove_spaces

  def cc_gateway
    if Rails.env.production?
      'https://boltgw.cardconnect.com:8443'
    else
      'https://boltgw.cardconnect.com:6443'
    end
  end

  def self.first_or_create(attributes = nil, &block)
    first || create(attributes, &block)
  end

  def self.terminal?
    first.cc_bolt_api_key.size > 0
  end

  def self.no_terminal?
    first.cc_bolt_api_key.size == 0
  end

private

  def remove_spaces
    self.cc_merchant_id = cc_merchant_id.strip unless cc_merchant_id.empty?  if cc_merchant_id
    self.cc_api_username = cc_api_username.strip unless cc_api_username.empty? if cc_api_username
    self.cc_api_password = cc_api_password.strip unless cc_api_password.empty? if cc_api_password
  rescue
  end

end
