#!/usr/bin/env ruby

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'rayyan-scrapers'
require 'logger'

logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG

logger.warn "Test log line"