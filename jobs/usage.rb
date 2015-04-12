require 'active_support/core_ext/numeric/time'
require_relative '../models/usage_data_point'
require_relative '../models/koodo_transaction'

def nonnegative_first_differences(points)
  points.zip(points.drop 1)[0..-2].map { |a, b| {x: b[:x], y: [a[:y] - b[:y], 0].max} }
end

def daily_sums(points)
  nonnegative_first_differences(points)
  .group_by { |p| p[:x].strftime('%Y-%m-%d') }
  .map do |date, local_points|
    s = local_points.map{ |p| p[:y] }.sum
    creation_dates = local_points.map { |p| p[:x] }
    [{x: creation_dates.min.to_i, y: s}, {x: creation_dates.max.to_i, y: s}]
  end.flatten.sort { |a, b| a[:x] <=> b[:x] }
end

def cost_breakdown(data_usage, minute_usage, base_plan_cost, mb_cost, minute_cost)
  data_cost = ((data_usage / (1024 * 1024)) * mb_cost)
  talk_cost = (minute_usage * minute_cost)
  [['Category', 'Cost'], ['Data', data_cost], ['Talk', talk_cost], ['Base Plan', base_plan_cost]]
end

def estimate_monthly_cost(data_usage, minute_usage, base_plan_cost, mb_cost, minute_cost)
  cost_breakdown(data_usage, minute_usage, base_plan_cost, mb_cost, minute_cost).drop(1).map{ |p| p[1] }.sum
end

SCHEDULER.every '1m', :allow_overlapping => false, :first_in => 0 do
  ActiveRecord::Base.connection_pool.with_connection do
    points = UsageDataPoint.last(30.days)
    previous_month_points = UsageDataPoint.last(30.days, ending: 1.month.ago)

    byte_points = points.map { |p| {x: p.created_at.to_i, y: p.mb_remaining * 1024 * 1024} }
    byte_usage = nonnegative_first_differences byte_points
    total_bytes_used = byte_usage.map{|p| p[:y]}.sum
    total_bytes_used_last_month = nonnegative_first_differences(previous_month_points.map { |p| {x: p.created_at.to_i, y: p.mb_remaining * 1024 * 1024} }).map{|p| p[:y]}.sum

    byte_usage_daily_points = daily_sums(points.map { |p| {x: p.created_at, y: p.mb_remaining * 1024 * 1024} })

    send_event('data_usage', { points: byte_usage_daily_points, displayedValue: (total_bytes_used / (1024 * 1024)).to_i })
    send_event('data_remaining', { points: byte_points, displayedValue: (byte_points.last[:y] / (1024 * 1024)).to_i })

    talk_points = points.map { |p| {x: p.created_at.to_i, y: p.minutes_remaining} }
    talk_usage = talk_points.zip(talk_points.drop 1)[0..-2].map { |a, b| {x: b[:x], y: [a[:y] - b[:y], 0].max} }
    total_minutes_used = talk_usage.map{|p| p[:y]}.sum
    total_minutes_used_last_month = nonnegative_first_differences(previous_month_points.map { |p| {x: p.created_at.to_i, y: p.minutes_remaining} }).map{|p| p[:y]}.sum

    talk_usage_daily_points = daily_sums(points.map { |p| {x: p.created_at, y: p.minutes_remaining} })

    send_event('talk_usage', { points: talk_usage_daily_points, displayedValue: total_minutes_used })
    send_event('talk_remaining', { points: talk_points, displayedValue: talk_points.last[:y] })

    send_event('cost_per_month', {
      current: sprintf('%.2f', KoodoTransaction.cost_per_month / 100),
      moreinfo: "per month, over the last #{(KoodoTransaction.account_age / 1.month.to_f).ceil} months",
    })

    base_plan_cost = 1500
    mb_cost = 3000 / 1000
    minute_cost = 2500 / 500

    send_event('estimated_monthly_cost', {
      current: sprintf('%.2f', estimate_monthly_cost(total_bytes_used, total_minutes_used, base_plan_cost, mb_cost, minute_cost) / 100),
      last: sprintf('%.2f', estimate_monthly_cost(total_bytes_used_last_month, total_minutes_used_last_month, base_plan_cost, mb_cost, minute_cost) / 100),
      moreinfo: "assuming $#{sprintf('%.2f', base_plan_cost / 100)} base plan cost",
    })

    send_event('cost_breakdown', {
      slices: cost_breakdown(total_bytes_used, total_minutes_used, base_plan_cost, mb_cost, minute_cost).map { |p| p[1].is_a?(String) ? p : [p[0], (p[1] / 100).round(2)] }
    })

    send_event('account_balance', {
      current: sprintf('%.2f', KoodoTransaction.account_balance / 100),
      last: sprintf('%.2f', KoodoTransaction.account_balance_ignoring_last_transaction / 100),
      moreinfo: "Last transaction: #{KoodoTransaction.last.english_description}",
    })
  end
  ActiveRecord::Base.connection_pool.release_connection
end
