require 'active_record'

class UsageDataPoint < ActiveRecord::Base
  def self.last(time_period, options={})
    if options.has_key? :ending
      where('created_at > ? AND created_at < ?', options[:ending] - time_period, options[:ending]).order(:created_at)
    else
      where('created_at > ?', Time.now - time_period).order(:created_at)
    end
  end
end
