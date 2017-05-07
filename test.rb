#!/usr/bin/env ruby

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'rayyan-scrapers'
require 'logger'

logger = Logger.new(STDOUT)
logger.level = Logger::INFO
RayyanFormats::Base.logger = logger

RayyanFormats::Base.plugins = [
  RayyanFormats::Plugins::PubmedXML
]

plugin = RayyanFormats::Base.get_export_plugin('csv')
%w(
  spec/support/entrez-contents/pubmed1.xml
  spec/support/stubbed/pubmed-100499.xml
).each do |filename|
  RayyanFormats::Base.import(RayyanFormats::Source.new(filename)) { |target, total|
    puts plugin.export(target)
  }
end
