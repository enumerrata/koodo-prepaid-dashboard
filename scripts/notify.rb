#!/usr/bin/env ruby

require 'uri'
require 'erb'
require 'mail'
require 'yaml'
require 'json'
require 'net/http'
require 'highline'
require 'mechanize'
require 'action_view'
require 'active_record'
require 'active_support/core_ext/numeric/time'
require_relative '../models/usage_data_point'
require_relative '../models/koodo_transaction'

include ActionView::Helpers::DateHelper

ENVIRONMENT = ENV['RACK_ENV'] || 'development'
DBCONFIG = YAML.load(ERB.new(File.read(File.join('config', 'database.yml'))).result)

ActiveRecord::Base.establish_connection(DBCONFIG[ENVIRONMENT])

Mail.defaults do
  delivery_method :smtp, {
    :address => 'smtp.sendgrid.net',
    :port => '587',
    :domain => 'heroku.com',
    :user_name => ENV['SENDGRID_USERNAME'],
    :password => ENV['SENDGRID_PASSWORD'],
    :authentication => :plain,
    :enable_starttls_auto => true
  }
end

DATA_BOOSTER_VALUES = [1024, 512, 256]
DATA_BOOSTER_COSTS = [30, 20, 10]
TALK_BOOSTER_VALUES = [500, 200, 100]
TALK_BOOSTER_COSTS = [25, 10, 5]

# If numbers increase by any value less than this, don't assume a top-up happened.
ALLOWABLE_INACCURACY_PERCENTAGE = 0.01
ALLOWABLE_MB_INACCURACY = DATA_BOOSTER_VALUES.max.to_f * ALLOWABLE_INACCURACY_PERCENTAGE
ALLOWABLE_MINUTE_INACCURACY = TALK_BOOSTER_VALUES.max.to_f * ALLOWABLE_INACCURACY_PERCENTAGE

APPROXIMATE_COST_PER_MB = DATA_BOOSTER_COSTS.max.to_f / DATA_BOOSTER_VALUES.max.to_f
APPROXIMATE_COST_PER_MINUTE = TALK_BOOSTER_COSTS.max.to_f / TALK_BOOSTER_VALUES.max.to_f

# Usage rate over time, in $/second.
USUAL_USAGE_RATE = 30.0/30.days
FROM_ADDRESS = 'koodo-prepaid-dashboard@petersobot.com'

def calculate_metric_usage_ignoring_top_ups(a, b, top_up_values, inaccuracy=0)
  delta = a - b
  if delta < (-1 * inaccuracy)
    # we must have topped up, so round up to the nearest top-up value.
    top_up_value = top_up_values.find { |v| v > (-1 * delta) }

    # Offset the delta with the top-up value to account for the top-up.
    delta += top_up_value
  end

  delta
end

def calculate_approximate_usage(time_period=24.hours)
  points = UsageDataPoint.last(time_period).order(:created_at)

  mb_used = 0
  minutes_used = 0

  points.zip(points.drop(1))[0...-1].each do |a, b|
    minutes_used += calculate_metric_usage_ignoring_top_ups(
      a.minutes_remaining,
      b.minutes_remaining,
      TALK_BOOSTER_VALUES,
      ALLOWABLE_MINUTE_INACCURACY
    )
    mb_used += calculate_metric_usage_ignoring_top_ups(
      a.mb_remaining,
      b.mb_remaining,
      DATA_BOOSTER_VALUES,
      ALLOWABLE_MB_INACCURACY
    )
  end

  [minutes_used, mb_used]
end

def calculate_usage_rate(minutes_used, mb_used, period)
  (mb_used * APPROXIMATE_COST_PER_MB + minutes_used * APPROXIMATE_COST_PER_MINUTE) / period
end

def generate_subject_and_message(minutes_used, mb_used, period)
  subject = "#{format('$%.2f', mb_used * APPROXIMATE_COST_PER_MB + minutes_used * APPROXIMATE_COST_PER_MINUTE)} used in the past #{distance_of_time_in_words(period)}."

  usage_parts = []
  usage_parts << "#{format('%.2f', mb_used)} mb (#{format('$%.2f', mb_used * APPROXIMATE_COST_PER_MB)})" if mb_used > 0
  usage_parts << "#{minutes_used.ceil} minutes (#{format('$%.2f', minutes_used * APPROXIMATE_COST_PER_MINUTE)})" if minutes_used > 0
  usage = usage_parts.empty? ? 'no data or minutes' : usage_parts.join(' and ')

  message = "You've used #{usage} in the last #{distance_of_time_in_words(period)}."

  [subject, message]
end

def send_sms(target, body)
  data = JSON.generate({phone: [target], text: body})
  header = {'Content-Type' => 'text/json'}

  uri = URI.parse(ENV['TILL_URL'])
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  request = Net::HTTP::Post.new(uri.request_uri, header)
  request.body = data
  http.request(request)
end

def notify_daily
  period = 24.hours
  minutes_used, mb_used = calculate_approximate_usage(period)
  usage_rate = calculate_usage_rate(minutes_used, mb_used, period)
  subject, message = generate_subject_and_message(minutes_used, mb_used, period)

  sms_target = ENV['SMS_TARGET']
  email_target = ENV['EMAIL_TARGET']

  if usage_rate > USUAL_USAGE_RATE && sms_target.present?
    send_sms(sms_target, message)
  elsif email_target.present? && ENV['SENDGRID_USERNAME']
    Mail.deliver do
      to email_target
      from FROM_ADDRESS
      subject subject
      body message
    end
  end
end

def notify_weekly
  period = 1.week
  minutes_used, mb_used = calculate_approximate_usage(period)
  usage_rate = calculate_usage_rate(minutes_used, mb_used, period)
  subject, message = generate_subject_and_message(minutes_used, mb_used, period)

  email_target = ENV['EMAIL_TARGET']

  if email_target.present? && ENV['SENDGRID_USERNAME']
    Mail.deliver do
      to email_target
      from FROM_ADDRESS
      subject subject
      body message
    end
  end
end

if ARGV.include? '--daily'
  notify_daily
elsif ARGV.include?('--weekly') && ARGV.include?('--on-day') && Date::DAYNAMES.include?(ARGV.last.humanize)
  notify_weekly if Date::DAYNAMES[Date.today.wday] == ARGV.last.humanize
else
  raise 'Please specify --daily or (--weekly and --on-day <day name>).'
end
