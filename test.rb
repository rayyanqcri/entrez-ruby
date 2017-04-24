#!/usr/bin/env ruby

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'entrez-ruby'
require 'log4r'

logger = Log4r::Logger.new('EntrezRuby')
logger.outputters = Log4r::Outputter.stdout
#Entrez::Base.logger = logger

# TODO
