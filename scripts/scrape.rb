#!/usr/bin/env ruby

require 'erb'
require 'yaml'
require 'highline'
require 'mechanize'
require 'active_record'
require_relative '../models/usage_data_point'
require_relative '../models/koodo_transaction'

ENVIRONMENT = ENV['RACK_ENV'] || 'development'
DBCONFIG = YAML.load(ERB.new(File.read(File.join('config', 'database.yml'))).result)

ActiveRecord::Base.establish_connection(DBCONFIG[ENVIRONMENT])

class Scraper
  ROOT_URL = 'https://prepaidselfserve.koodomobile.com/Overview/'

  def initialize(username=ENV.fetch('KOODO_USERNAME', ARGV[1]), password=ENV.fetch('KOODO_PASSWORD', ARGV[2]))
    @username = username
    @password = password
    @password = HighLine.new.ask("Enter your password:") { |q| q.echo = false } if @password.nil?
    @browser = Mechanize.new
    @logged_in = false
    login unless @username.nil? || @password.nil?
  end

  def login(username=nil, password=nil)
    @username ||= username
    @password ||= password

    raise 'Missing credentials' if @username.nil? || @password.nil?

    @browser.get(ROOT_URL)
    form = @browser.page.forms.first

    form['ctl00$FullContent$ContentBottom$LoginControl$UserName'] = @username
    form['ctl00$FullContent$ContentBottom$LoginControl$Password'] = @password
    form.click_button

    raise 'LoginFailure' unless @browser.page.body.include?('Account Status Active')
    @logged_in = true
    self
  end

  def fetch_booster_usage
    raise 'Not logged in' unless @logged_in
    booster_url = "products-and-services/view-bundle-usage/"
    @browser.get(ROOT_URL + booster_url)

    dp = @browser.page.search('#FullContent_DashboardContent_ViewBundleUsagePanel').first
    return {
      mb_remaining: dp.search('#DataRemainingLiteral').map { |x| x.text.to_f }.sum,
      minutes_remaining: dp.search('#CrossServiceRemainingLiteral').map { |x| x.text.to_f }.sum
    }
  end

  TRANSACTION_ATTRIBUTE_MAP = {
    koodo_id: 'gvIDHeader',
    date: 'gvTransactionDateCol',
    description: 'gvTransactionTypeCol',
    credit: 'gvCreditCol',
    debit: 'gvDebitCol',
  }

  def fetch_most_recent_transactions
    transactions_url = 'billing/transaction-history/'
    @browser.get(ROOT_URL + transactions_url)
    form = @browser.page.forms.first

    form.radiobutton_with(:value => 'UseDropDownRadioButton').check

    #   Select the third item in the dropdown list, which is
    #   the search filter that returns the most results
    form['ctl00$ctl00$FullContent$DashboardContent$DateSelectDropDownList'] = ['3']

    form.click_button(form.button_with(name: 'ctl00$ctl00$FullContent$DashboardContent$ViewTransactionHistoryButton'))

    (@browser.page.search('tr.gvTransactionHistoryRow') + @browser.page.search('tr.gvTransactionHistoryAltRow')).map do |t|
      _parse_transaction_history_row(t)
    end
  end

  def _parse_transaction_history_row(row)
    Hash[TRANSACTION_ATTRIBUTE_MAP.map do |attribute, cssClass|
      value = row.search("td.#{cssClass}").text.strip

      #   Normalize dates to datetimes
      if attribute == :date
        value = DateTime.strptime(value, '%b %d, %Y')
        #   Convert dollar values to integer values of cents,
        #   assuming that the maximum dollar value is less than $1000
      elsif value.start_with?('$') && value.length <= '$999.99'.length
        value = value.gsub('$', '').gsub('.', '').to_i
      elsif attribute == :koodo_id
        value = value.to_i
      end

      #   Convert &nbsp rows to NULLs
      value = nil if value == "" || (value.is_a?(String) && value.start_with?('&nbsp'))
      [attribute, value]
    end]
  end
end

def scrape
  scraper = Scraper.new

  #   Fetch usage info re: booster usage.
  usage = scraper.fetch_booster_usage
  UsageDataPoint.create(usage) unless usage.values.all? { |v| v < 0.0001 }

  #   Fetch latest transactions and put these in the DB,
  #   but only if we don't already have them.
  scraper.fetch_most_recent_transactions.each do |transaction|
    existing = KoodoTransaction.find_by_koodo_id transaction[:koodo_id]
    KoodoTransaction.create(transaction) if existing.nil?
  end
end

scrape
