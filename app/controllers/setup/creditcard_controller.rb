class Setup::CreditcardController < ApplicationController
  before_filter :login_from_cookie
  before_filter :check_login
  before_filter :authorize

#####################################################
# Creditcards
#####################################################
  def list
    @page_title = 'List of credit cards'
    @creditcards = Creditcard.all
  end

  def sort
    @page_title = 'Update sort order of payment types'
    @creditcards = Creditcard.all
  end

  def resort
    pos = 1
    params[:creditcards].each do |id|
      Creditcard.update(id, :position => pos)
      pos += 1
    end
    redirect_to :action => :sort
  end
      
  def new
    @page_title = 'Define a new Credit Card'
    @creditcard = Creditcard.new
  end

  def create
    @creditcard = Creditcard.new(params[:creditcard])
    if @creditcard.save
      flash[:notice] = "Creditcard #{@creditcard.name} was successfully created."
    else
      flash[:error] = 'Creation of new creditcard failed. Make sure name is unique'
    end
    redirect_to :action => 'list'
  end

  def edit
    @page_title = 'Modify a current credit card'
    @creditcard = Creditcard.find(params[:id])
  end

  def update
    @creditcard = Creditcard.find(params[:id])
    if @creditcard.update_attributes(params[:creditcard])
      flash[:notice] = "Creditcard #{@creditcard.name} was successfully updated."
    else
      flash[:error] = 'Update of creditcard failed.'
    end
    redirect_to :action => 'list'
  end

  def destroy
    creditcard = Creditcard.find(params[:id])
    name = creditcard.name
    pmt = Payment.find_all_by_creditcard_id(creditcard.id)
    if pmt.size == 0
        if creditcard.destroy
	flash[:notice] = "Creditcard #{name} was successfully destroyed."
      else
	flash[:error] = 'Deletion of creditcard failed.'
      end
    else
      flash[:error] = "Creditcard #{name} in use by reservations: "
      pmt.each do |p|
        flash[:error] += p.reservation_id.to_s + ' '
      end
    end
    redirect_to :action => 'list'
  end
end
