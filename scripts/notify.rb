#!/usr/bin/env ruby

require 'erb'
require 'yaml'
require 'easy-sms'
require 'highline'
require 'mechanize'
require 'active_record'
require 'active_support/core_ext/numeric/time'
require_relative '../models/usage_data_point'
require_relative '../models/koodo_transaction'

ENVIRONMENT = ENV['RACK_ENV'] || 'development'
DBCONFIG = YAML.load(ERB.new(File.read(File.join('config', 'database.yml'))).result)

ActiveRecord::Base.establish_connection(DBCONFIG[ENVIRONMENT])

DATA_BOOSTER_VALUES = [1024, 512, 256]
DATA_BOOSTER_COSTS = [30, 20, 10]
TALK_BOOSTER_VALUES = [500, 200, 100]
TALK_BOOSTER_COSTS = [25, 10, 5]

APPROXIMATE_COST_PER_MB = DATA_BOOSTER_COSTS.max.to_f / DATA_BOOSTER_VALUES.max.to_f
APPROXIMATE_COST_PER_MINUTE = TALK_BOOSTER_COSTS.max.to_f / TALK_BOOSTER_VALUES.max.to_f

# Usage rate over time, in $/second.
USUAL_USAGE_RATE = 30.0/30.days

def calculate_metric_usage_ignoring_top_ups(a, b, top_up_values)
  delta = a - b
  if delta < 0
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
      TALK_BOOSTER_VALUES
    )
    mb_used += calculate_metric_usage_ignoring_top_ups(
      a.mb_remaining,
      b.mb_remaining,
      DATA_BOOSTER_VALUES
    )
  end

  [minutes_used, mb_used]
end

def calculate_usage_rate(minutes_used, mb_used, period)
  (mb_used * APPROXIMATE_COST_PER_MB + minutes_used * APPROXIMATE_COST_PER_MINUTE) / period
end

def generate_subject_and_message(minutes_used, mb_used, period)
  subject = "#{format('$%.2f', mb_used * APPROXIMATE_COST_PER_MB + minutes_used * APPROXIMATE_COST_PER_MINUTE)} used yesterday."

  usage_parts = []
  usage_parts << "#{format('%.2f', mb_used)} mb (#{format('$%.2f', mb_used * APPROXIMATE_COST_PER_MB)})" if mb_used > 0
  usage_parts << "#{minutes_used.ceil} minutes (#{format('$%.2f', minutes_used * APPROXIMATE_COST_PER_MINUTE)})" if minutes_used > 0
  usage = usage_parts.empty? ? 'no data or minutes' : usage_parts.join(' and ')

  message = "You've used #{usage} in the last 24 hours."

  [subject, message]
end

def notify
  period = 24.hours
  minutes_used, mb_used = calculate_approximate_usage(period)
  usage_rate = calculate_usage_rate(minutes_used, mb_used, period)
  subject, message = generate_subject_and_message(minutes_used, mb_used, period)

  sms_target = ENV['SMS_TARGET']
  if usage_rate > USUAL_USAGE_RATE && sms_target.present?
    client = EasySMS::Client.new
    client.messages.create to: sms_target, body: message
  end
end

notify
