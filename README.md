## koodo-prepaid-dashboard

A tiny [Dashing](dashing.io) Ruby app to scrape [Koodo
Mobile](http://koodomobile.com)'s prepaid billing site, record information
over time, and display statistics and information about your account. Super
rough, lightweight, and brittle. Currently only fetches data about usage - how
many minutes and how many megabytes you have left on your mobile "Boosters" -
and transactions.

![image](https://cloud.githubusercontent.com/assets/213293/7109063/2c459bb2-e164-11e4-80b3-fdac94b4393f.png)

Runs well (and for free) on Heroku:

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy)

##Local installation

    git clone https://github.com/psobot/koodo-prepaid-dashboard.git
    cd koodo-prepaid-dashboard
    bundle install

To run the server locally:

    dashing start

To fetch a single data point from Koodo:

    bundle exec scripts/scrape.rb

##Configuration

Important variables - like the username and password you use to log into
Koodo's prepaid billing dashboard - need to be stored somewhere. What better
place than in environment variables?

  - `KOODO_USERNAME` stores the user name (i.e. email address) used to log
  	into your Koodo prepaid account.

  - `KOODO_PASSWORD` stores the password you use to log into your Koodo
  	prepaid account. (~~super secure~~)

##Heroku Setup
The one-click "Deploy to Heroku" button above should do almost everying required to
set this app up on Heroku, but there are still a couple steps that need doing.

 - Log into the [Heroku Scheduler Dashboard](https://scheduler.heroku.com/dashboard) and
   add a single recurring task that calls `bundle exec scripts/scrape.rb` every hour. (This
   task shouldn't take longer than 30 seconds to fetch a single data point from Koodo,
   which means that running the task hourly won't exceed your monthly free dyno allotment.)

##TODO

Tons of cool stuff could be done with this data. Scrape another page to find out
things like:

  - Is Prepaid still cheaper than Postpaid, given my usage patterns?

