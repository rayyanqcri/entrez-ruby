# coding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'entrez-ruby/version'

Gem::Specification.new do |spec|
  spec.name          = "entrez-ruby"
  spec.version       = Entrez::VERSION
  spec.authors       = ["Hossam Hammady"]
  spec.email         = ["github@hammady.net"]
  spec.description   = %q{Ruby library to consume the NCBI Entrez API used for PubMed. Currently It supports esearch, efetch and elink}
  spec.summary       = %q{Ruby library to consume the NCBI Entrez API}
  spec.homepage      = "https://github.com/rayyanqcri/entrez-ruby"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency 'rake', '~> 0'
  spec.add_development_dependency 'log4r', '~> 1.0'
  spec.add_development_dependency 'rspec', '~> 3.5'
  spec.add_development_dependency 'simplecov', '~> 0.14'
  spec.add_development_dependency 'coderay', '~> 1.1'

end
