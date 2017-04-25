#!/usr/bin/env ruby

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'rayyan-scrapers'
require 'log4r'

logger = Log4r::Logger.new('RayyanScrapers')
logger.outputters = Log4r::Outputter.stdout
#RayyanScrapers::Base.logger = logger

# TODO
