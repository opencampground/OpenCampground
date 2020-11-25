require 'test_helper'

class IntegrationTest < ActiveSupport::TestCase
  def test_strip
    int = Integration.new
    int.cc_merchant_id = ' 12345 '
    int.cc_api_username = ' testuser '
    int.cc_api_password = '  kaj;flkjurendf '
    int.save
    assert int.cc_merchant_id == '12345'
    assert int.cc_api_username == 'testuser'
    assert int.cc_api_password == 'kaj;flkjurendf'
  end
end
