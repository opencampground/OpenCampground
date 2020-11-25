class ResMailer < ActionMailer::Base
  include MyLib

  def reservation_confirmation(reservation)
    email_setup(reservation)
    @subject = Email.first.confirm_subject
  end
  
  def reservation_update(reservation)
    email_setup(reservation)
    @subject = Email.first.update_subject
  end
  
  def reservation_feedback(reservation)
    email_setup(reservation)
    @subject = Email.first.feedback_subject
  end

  def reservation_cancel(reservation, reason)
    email_setup(reservation, reason)
    @subject = Email.first.reservation_cancel_subject
  end
  
  def remote_reservation_received(reservation)
    email_setup(reservation)
    @subject = Email.first.remote_res_subject
  end
  
  def remote_reservation_confirmation(reservation)
    email_setup(reservation)
    @subject = Email.first.remote_res_confirm_subject
  end
  
  def remote_reservation_reject(reservation)
    email_setup(reservation)
    @subject = Email.first.remote_res_reject_subject
  end
  
  def tst
    email = Email.first
    @from       = email.sender
    @recipients = email.reply
    @subject    = 'Mailer Test'
    @cc = email.cc unless email.cc.empty?
    @bcc = email.bcc unless email.bcc.empty?
    @reply_to = email.reply unless email.reply.empty?
    @sent_on    = currentTime
    @headers = {}
    @body       = {:email => email}
  end

  def render_message(method_name, body)
    mail_template = MailTemplate.find_by_name(method_name)
    template = Liquid::Template.parse(mail_template.body)
    template.render body
  end

private
  def email_setup(reservation, reason = '')
    option = Option.first
    email = Email.first
    @from = email.sender
    @recipients = reservation.camper.email
    @cc = email.cc unless email.cc.empty?
    @bcc = email.bcc unless email.bcc.empty?
    @reply_to = email.reply.empty? ? email.sender : email.reply
    @headers = {}
    @sent_on = currentTime
    payment = Payment.total(reservation.id)
    if option.use_override? and reservation.override_total > 0.0
      charges = reservation.override_total + reservation.tax_amount
    else
      charges = reservation.total + reservation.tax_amount
    end
    due = charges - payment
    @body = {"camper"     => reservation.camper.full_name,
             "start"      => DateFmt.format_date(reservation.startdate),
	     "departure"  => DateFmt.format_date(reservation.enddate),
	     "number"     => reservation.id.to_s,
	     "space_name" => reservation.space.name,
	     "charges"    => number_2_currency(charges),
	     "payment"    => number_2_currency(payment),
	     "deposit"    => number_2_currency(reservation.deposit),
	     "due"        => number_2_currency(due),
	     "reason"	  => reason,
	     "reply"      => email.reply
	     }
  end
end
