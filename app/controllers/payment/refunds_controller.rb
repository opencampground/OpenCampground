class Payment::RefundsController < ApplicationController

  # GET /payment_refunds/1/edit
  def edit
    @page_title = 'Update Refund'
    @payment = Payment.find(params[:id])
    if @payment.refundable
      @card_transaction = CardTransaction.find_by_payment_id(@payment.id)
      @card_transaction.amount = Payment.total(@payment.reservation_id)
    else
      flash[:warning] = "payment not refundable"
      redirect_to payments_url # the list of payments
    end
  end

  # PUT /payment_refunds/1
  # PUT /payment_refunds/1.xml
  # need Card_transactions.id and .amount
  def update
    orig = CardTransaction.find(params[:id])
    debug 'orig loaded'
    trans = orig.clone
    debug 'orig cloned'
    trans.amount = params[:card_transaction][:amount]
    trans.save
    debug 'trans saved'
    debug "transaction: #{trans.inspect}"
    stat = do_refund(orig, trans)
    debug stat.inspect
    if transaction['respstat'] == 'A' && trans.receiptData?
      redirect_to payment_receipt_url(trans.id)
    else
      redirect_to payments_url # the list of payments
    end
  rescue
    redirect_to payments_url # the list of payments
  end

private

  def do_refund(original, transaction)
    debug 'do_refund'
    if original.amount == transaction.amount
      debug "original #{original.amount} == transaction #{transaction.amount} doing void/refund"
      stat = transaction.void_refund
    else
      # cannot do a partial void AFAIK
      debug "original #{original.amount} != transaction #{transaction.amount} doing refund only"
      stat = transaction.refund
    end
    if stat
      debug "respstat = #{transaction['respstat']}, authcode = #{transaction['authcode']}, amount = #{transaction.amount}"
      if transaction['respstat'] == 'A'
	debug "before: original amount is #{original.amount}, trans amount is #{transaction.amount}"
	if transaction.amount == 0.0
	  transaction.amount = -original.amount
	else
	  transaction.amount = -transaction.amount
	end
	debug "after:  original amount is #{original.amount}, trans amount is #{transaction.amount}"
	if transaction['authcode'] == 'REVERS'
	  debug 'void'
	  memo = "voided retref #{original.retref}"
	  refundable = false,
	  flash[:notice] = "Credit card transaction for reservation #{original.reservation_id} voided"
	  info "Credit card transaction for reservation #{original.reservation_id} voided"
	else
	  # refund
	  if -original.amount == transaction.amount
	    memo = "full refund of retref #{original.retref}"
	    debug "full refund: amount is #{transaction.amount}"
	  else
	    memo = "partial refund (#{number_2_currency(transaction.amount)}) of retref #{original.retref}"
	    debug "partial refund: amount is #{transaction.amount}"
	  end
	  flash[:notice] = "Credit card transaction for reservation #{original.reservation_id} refunded"
	  info "Credit card transaction for reservation #{original.reservation_id} refunded"
	end
	pmt = Payment.create(:reservation_id => transaction.reservation_id,
			     :credit_card_no => transaction.payment.credit_card_no,
			     :amount => transaction.amount,
			     :memo => memo,
			     :creditcard_id => transaction.payment.creditcard_id)
	payments = Payment.find_all_by_reservation_id transaction.reservation_id, :order => 'created_at'
	due = 0.0
	payments.each do |p| 
	  debug "payment = #{p.amount} due = #{due}"
	  due += p.amount
	end
	debug "payments left = #{due}"
	payments[0].update_attributes :refundable => false if due == 0.0 
	res = Reservation.find(transaction.reservation_id)
	res.add_log(memo)
	# keep a record of the void/refund
	transaction.payment_id = pmt.id
	# not saved unless successful
	transaction.save
	# the refunded payment is now not refundable
	pmt.update_attributes :refundable => false
      else
	flash[:error] = "credit card transaction not refunded: #{transaction['resptext']}(#{transaction['respcode']})"
	error "credit card transaction not refunded: #{transaction['resptext']}(#{transaction['respcode']})"
      end
      debug "refund/void: #{transaction.inspect}"
    else
      # communication failure details
      message = ''
      transaction.errors.each{|attr,msg| message += "#{attr} - #{msg}\n" }
      if message.empty?
	flash[:error] =  "communication error"
	error "communication error"
      else
	flash[:error] =  "communication error, credit card transaction not refunded: #{message}"
	error "communication error, credit card transaction not refunded: #{message }"
      end
    end
  end
end
