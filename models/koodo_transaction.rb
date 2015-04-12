require 'active_record'
require 'active_support/core_ext/numeric/time'

class KoodoTransaction < ActiveRecord::Base
  default_scope { order('date ASC') }

  def self.account_balance
    all.map { |e| (e.credit || 0) - (e.debit || 0) }.sum
  end

  def self.account_balance_ignoring_last_transaction
    order('date ASC').all[0..-2].map { |e| (e.credit || 0) - (e.debit || 0) }.sum
  end

  def self.total_paid
    all.map { |e| (e.credit || 0) }.sum
  end

  def self.total_used
    all.map { |e| (e.debit || 0) }.sum
  end

  def self.account_opened_on
    order('date ASC').first.date
  end

  def self.account_age
    Time.now - account_opened_on.to_time
  end

  def self.cost_per_month
    total_used / (account_age.to_f / 1.month.to_f)
  end

  def english_description
    parts = description.split('/')
    return parts[0...(parts.length / 2.0).ceil].join('/')
  end

  def french_description
    parts = description.split('/')
    return parts[(parts.length / 2.0).ceil...-1].join('/')
  end
end
