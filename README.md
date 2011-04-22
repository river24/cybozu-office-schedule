Cybozu::Office::Schedule
========================

This is a ruby library for editing schedule of Cybozu Office.

Dependencies
------------

This library requires 'mechanize' and 'nokogiri'.

    gem install mechanize
    gem install nokogiri

Usage
-----

    require 'cybozu/office/schedule'
    cybozu = Cybozu::Office::Schedule.new(url, uid, gid, password)
    if !cybozu.login
      STDOUT .print "Login error...\n"
      exit
    end

