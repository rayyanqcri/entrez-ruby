# coding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rayyan-scrapers/version'

Gem::Specification.new do |spec|
  spec.name          = "rayyan-scrapers"
  spec.version       = RayyanScrapers::VERSION
  spec.authors       = ["Hossam Hammady"]
  spec.email         = ["github@hammady.net"]
  spec.description   = %q{Rayyan scrapers that fetch external references like PubMed}
  spec.summary       = %q{Rayyan scrapers that fetch external references}
  spec.homepage      = "https://github.com/rayyansys/rayyan-scrapers"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency 'rake', '~> 13'
  spec.add_development_dependency 'rspec', '~> 3.5'
  spec.add_development_dependency 'coderay', '~> 1.1'
  spec.add_development_dependency 'coveralls', '~> 0.8'

  spec.add_dependency 'nokogiri', '~> 1.6'
  spec.add_dependency 'typhoeus', '~> 1.1'
  spec.add_dependency 'rayyan-formats-core', "~> 0.2"
  spec.add_dependency 'moneta', "~> 1.0"
end
